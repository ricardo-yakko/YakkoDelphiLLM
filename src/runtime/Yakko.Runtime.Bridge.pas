unit Yakko.Runtime.Bridge;

{ Controlled integration boundary between legacy procedural runtime and the modern
  architecture stack.

  Architectural role:
  - centralize legacy-to-modern adaptation in a single bridge layer;
  - isolate migration concerns from both legacy execution code and modern domain types;
  - support strangler migration by allowing incremental replacement over time;
  - prepare shadow execution and side-by-side diagnostics without scattering integration logic.

  The bridge intentionally keeps runtime behavior safe for gradual adoption:
  it can execute modern flow internally while legacy production flow remains authoritative
  until explicit cutover criteria are validated. }

interface

uses
  System.SysUtils,
  uYakkoLlamaTypes,
  Yakko.Message.LegacyAdapter,
  Yakko.ConversationState,
  Yakko.Prompt.Document,
  Yakko.Prompt.Builder,
  Yakko.Prompt.Diff,
  Yakko.Template.Provider,
  Yakko.Inference.Types,
  Yakko.Generation.Controller,
  Yakko.Runtime.Diagnostics;

type
  TYakkoRuntimeBridge = class
  private
    FPromptBuilder: TYakkoPromptBuilder;
    FTemplateProvider: IYakkoTemplateProvider;
    FGenerationController: TYakkoGenerationController;
    FDiagnostics: TYakkoRuntimeDiagnostics;
  public
    constructor Create;
    destructor Destroy; override;

    function ExecuteLegacyGeneration(
      const APromptSistema: string;
      const APromptUsuario: string;
      const AMessages: TArray<TLlamaMensagem>
    ): string;
  end;

implementation

constructor TYakkoRuntimeBridge.Create;
begin
  inherited Create;
  FPromptBuilder := TYakkoPromptBuilder.Create;
  FTemplateProvider := TYakkoTemplateProviderFactory.CreateDefault;
  FGenerationController := TYakkoGenerationController.Create;
  FDiagnostics := TYakkoRuntimeDiagnostics.Create;
end;

destructor TYakkoRuntimeBridge.Destroy;
begin
  FreeAndNil(FDiagnostics);
  FreeAndNil(FGenerationController);
  FTemplateProvider := nil;
  FreeAndNil(FPromptBuilder);
  inherited;
end;

function TYakkoRuntimeBridge.ExecuteLegacyGeneration(const APromptSistema,
  APromptUsuario: string; const AMessages: TArray<TLlamaMensagem>): string;
var
  LConversation: TYakkoConversationState;
  LBuildRequest: TYakkoPromptBuildRequest;
  LBuildResult: TYakkoPromptBuildResult;
  LInferenceRequest: TYakkoInferenceRequest;
  LSession: TYakkoGenerationSession;
  LLegacyPromptText: string;
  LLegacyDocument: TYakkoPromptDocument;
  LPromptBlock: TYakkoPromptBlock;
  LMessage: TLlamaMensagem;
  LPromptDiagnostics: TYakkoRuntimeComparisonResult;
  LOutputDiagnostics: TYakkoRuntimeComparisonResult;
  LPromptDiffDiagnostics: TYakkoPromptDiffResult;
begin
  LConversation := TYakkoConversationState.Create;
  LBuildRequest := TYakkoPromptBuildRequest.Create;
  LInferenceRequest := TYakkoInferenceRequest.Create;
  try
    { Legacy -> modern domain adaptation boundary. }
    LConversation.SystemPrompt := APromptSistema;
    TYakkoLegacyMessageAdapter.ConvertListToYakko(AMessages, LConversation.GetMessages);
    if Trim(APromptUsuario) <> '' then
      LConversation.AddUserMessage(APromptUsuario);

    { Semantic prompt assembly. The builder no longer owns template details. }
    LBuildRequest.ConversationState := LConversation;
    LBuildRequest.IncludeSystemPrompt := True;
    LBuildRequest.IncludeTools := False;
    LBuildRequest.IncludeRAG := False;
    LBuildRequest.IncludeReasoning := False;
    LBuildRequest.TemplateName := FTemplateProvider.ProviderName;

    LBuildResult := FPromptBuilder.Build(LBuildRequest);
    try
      LLegacyDocument := TYakkoPromptDocument.Create;
      try
        if Trim(APromptSistema) <> '' then
        begin
          LPromptBlock := TYakkoPromptBlock.Create;
          LPromptBlock.BlockType := pbtSystem;
          LPromptBlock.Content := APromptSistema;
          LLegacyDocument.AddBlock(LPromptBlock);
        end;

        for LMessage in AMessages do
        begin
          LPromptBlock := TYakkoPromptBlock.Create;
          LPromptBlock.BlockType := pbtConversation;
          LPromptBlock.Content := LMessage.Conteudo;
          case LMessage.Role of
            mrSystem:
              LPromptBlock.Metadata.AddOrSetValue('role', 'system');
            mrUser:
              LPromptBlock.Metadata.AddOrSetValue('role', 'user');
          else
            LPromptBlock.Metadata.AddOrSetValue('role', 'assistant');
          end;
          LLegacyDocument.AddBlock(LPromptBlock);
        end;

        if Trim(APromptUsuario) <> '' then
        begin
          LPromptBlock := TYakkoPromptBlock.Create;
          LPromptBlock.BlockType := pbtConversation;
          LPromptBlock.Content := APromptUsuario;
          LPromptBlock.Metadata.AddOrSetValue('role', 'user');
          LLegacyDocument.AddBlock(LPromptBlock);
        end;

        LLegacyPromptText := FTemplateProvider.BuildPromptDocument(LLegacyDocument);

        LPromptDiagnostics := FDiagnostics.ComparePrompts(LLegacyPromptText, LBuildResult.PromptText);
        try
          LPromptDiffDiagnostics := FDiagnostics.ComparePromptDocuments(LLegacyDocument, LBuildResult.PromptDocument);
          try
            LInferenceRequest.Metadata.AddOrSetValue('shadow.prompt.equivalent', BoolToStr(LPromptDiagnostics.Status = csEquivalent, True));
            LInferenceRequest.Metadata.AddOrSetValue('shadow.prompt.divergence', FloatToStr(LPromptDiffDiagnostics.DivergenceScore));
            LInferenceRequest.Metadata.AddOrSetValue('shadow.prompt.hash', LPromptDiffDiagnostics.PromptHash);
            LInferenceRequest.Metadata.AddOrSetValue('shadow.prompt.structural_hash', LPromptDiffDiagnostics.StructuralHash);
          finally
            LPromptDiffDiagnostics.Free;
          end;
        finally
          FDiagnostics.EmitDiagnostics(LPromptDiagnostics);
          LPromptDiagnostics.Free;
        end;
      finally
        LLegacyDocument.Free;
      end;

      { PromptDocument -> inference request contract. }
      LInferenceRequest.PromptDocument := LBuildResult.PromptDocument;
      LInferenceRequest.Stream := False;
      LInferenceRequest.Metadata.AddOrSetValue('bridge.mode', 'legacy-integration');
      LInferenceRequest.Metadata.AddOrSetValue('bridge.template', FTemplateProvider.ProviderName);

      { Controlled lifecycle execution through controller + pipeline. }
      LSession := FGenerationController.StartGeneration(LInferenceRequest);
      try
        Result := LSession.Result.GeneratedText;

        LOutputDiagnostics := FDiagnostics.CompareOutputs(Result, Result);
        try
          LOutputDiagnostics.Metadata.AddOrSetValue('shadow.output.mode', 'placeholder-equality');
          FDiagnostics.EmitDiagnostics(LOutputDiagnostics);
        finally
          LOutputDiagnostics.Free;
        end;
      finally
        LSession.Free;
      end;
    finally
      LBuildResult.Free;
    end;
  finally
    LInferenceRequest.Free;
    LBuildRequest.Free;
    LConversation.Free;
  end;

  { Shadow migration notes:
    - This bridge prepares side-by-side execution between legacy and modern flows.
    - Current production output must remain legacy-authoritative until parity is proven.
    TODO: add output comparison between legacy and modern generated text.
    TODO: add metrics comparison and drift diagnostics by request/session.
    TODO: add tracing envelope for bridge, builder, controller and pipeline spans.
    TODO: add explicit shadow execution flags and staged rollout controls.
    TODO: add rollback strategy metadata for safe migration cutovers.
    TODO: add async orchestration without changing synchronous legacy contracts.
    TODO: add streaming integration bridge when incremental output is introduced.
    TODO: add tool execution bridge between legacy tools and modern tool lifecycle.
    TODO: add reasoning bridge for hidden/public reasoning policy transitions. }
end;

end.
