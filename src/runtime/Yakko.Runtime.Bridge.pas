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
  Yakko.Prompt.Builder,
  Yakko.Template.Provider,
  Yakko.Inference.Types,
  Yakko.Generation.Controller;

type
  TYakkoRuntimeBridge = class
  private
    FPromptBuilder: TYakkoPromptBuilder;
    FTemplateProvider: IYakkoTemplateProvider;
    FGenerationController: TYakkoGenerationController;
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
end;

destructor TYakkoRuntimeBridge.Destroy;
begin
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
      { PromptDocument -> inference request contract. }
      LInferenceRequest.PromptDocument := LBuildResult.PromptDocument;
      LInferenceRequest.Stream := False;
      LInferenceRequest.Metadata.AddOrSetValue('bridge.mode', 'legacy-integration');
      LInferenceRequest.Metadata.AddOrSetValue('bridge.template', FTemplateProvider.ProviderName);

      { Controlled lifecycle execution through controller + pipeline. }
      LSession := FGenerationController.StartGeneration(LInferenceRequest);
      try
        Result := LSession.Result.GeneratedText;
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
