unit Yakko.Prompt.Builder;

{ Prompt construction pipeline for YakkoDelphiLLM runtime.
  Architectural intent:
  - move PromptBuilder from a procedural text renderer to a semantic assembler;
  - keep semantic block selection inside the builder;
  - keep text serialization inside template providers;
  - preserve temporary compatibility by still returning PromptText.

  New internal flow:
  ConversationState -> PromptBuilder -> PromptDocument -> TemplateProvider -> PromptText

  PromptDocument is the contract between semantic context engineering and model-
  specific rendering. This separation enables safer migration, multi-template
  support and future multimodal/reasoning extensions without changing runtime
  inference behavior today. }

interface

uses
  System.SysUtils,
  Yakko.ConversationState,
  Yakko.Message,
  Yakko.Prompt.Document,
  Yakko.Template.Provider;

type
  TYakkoPromptBuildRequest = class
  private
    FConversationState: TYakkoConversationState;
    FIncludeSystemPrompt: Boolean;
    FIncludeTools: Boolean;
    FIncludeRAG: Boolean;
    FIncludeReasoning: Boolean;
    FToolsContext: string;
    FRAGContext: string;
    FReasoningInstruction: string;
    FMaxHistoryMessages: Integer;
    FTemplateName: string;
  public
    constructor Create;
    procedure Assign(ASource: TYakkoPromptBuildRequest);

    property ConversationState: TYakkoConversationState read FConversationState write FConversationState;
    property IncludeSystemPrompt: Boolean read FIncludeSystemPrompt write FIncludeSystemPrompt;
    property IncludeTools: Boolean read FIncludeTools write FIncludeTools;
    property IncludeRAG: Boolean read FIncludeRAG write FIncludeRAG;
    property IncludeReasoning: Boolean read FIncludeReasoning write FIncludeReasoning;
    property ToolsContext: string read FToolsContext write FToolsContext;
    property RAGContext: string read FRAGContext write FRAGContext;
    property ReasoningInstruction: string read FReasoningInstruction write FReasoningInstruction;
    property MaxHistoryMessages: Integer read FMaxHistoryMessages write FMaxHistoryMessages;
    property TemplateName: string read FTemplateName write FTemplateName;
  end;

  TYakkoPromptBuildResult = class
  private
    FPromptText: string;
    FPromptDocument: TYakkoPromptDocument;
    FBuiltAt: TDateTime;
    FCharacterCount: Integer;
    FMessageCount: Integer;
    FSectionCount: Integer;
    FTemplateName: string;
    FSystemPromptIncluded: Boolean;
    FToolsIncluded: Boolean;
    FRAGIncluded: Boolean;
    FReasoningIncluded: Boolean;
    FContextLimitsApplied: Boolean;
    procedure SetPromptDocument(const Value: TYakkoPromptDocument);
  public
    constructor Create;
    destructor Destroy; override;
    function Clone: TYakkoPromptBuildResult;

    property PromptText: string read FPromptText write FPromptText;
    property PromptDocument: TYakkoPromptDocument read FPromptDocument write SetPromptDocument;
    property BuiltAt: TDateTime read FBuiltAt write FBuiltAt;
    property CharacterCount: Integer read FCharacterCount write FCharacterCount;
    property MessageCount: Integer read FMessageCount write FMessageCount;
    property SectionCount: Integer read FSectionCount write FSectionCount;
    property TemplateName: string read FTemplateName write FTemplateName;
    property SystemPromptIncluded: Boolean read FSystemPromptIncluded write FSystemPromptIncluded;
    property ToolsIncluded: Boolean read FToolsIncluded write FToolsIncluded;
    property RAGIncluded: Boolean read FRAGIncluded write FRAGIncluded;
    property ReasoningIncluded: Boolean read FReasoningIncluded write FReasoningIncluded;
    property ContextLimitsApplied: Boolean read FContextLimitsApplied write FContextLimitsApplied;
  end;

  TYakkoPromptBuilder = class
  private
    FRequest: TYakkoPromptBuildRequest;
    FResult: TYakkoPromptBuildResult;
    procedure ResetState;
    procedure AddSemanticBlock(
      ABlockType: TYakkoPromptBlockType;
      const AContent: string;
      AVisible: Boolean = True;
      const ARole: string = ''
    );
    procedure AppendSystemPrompt;
    procedure AppendConversation;
    procedure AppendTools;
    procedure AppendRAG;
    procedure AppendReasoning;
    procedure ApplyContextLimits;
    function BuildMessageText(AMessage: TYakkoMessage): string; deprecated 'Legacy helper kept temporarily while migration is in progress.';
  public
    constructor Create;
    destructor Destroy; override;

    function Build(ARequest: TYakkoPromptBuildRequest): TYakkoPromptBuildResult;
  end;

implementation

{ TYakkoPromptBuildRequest }

constructor TYakkoPromptBuildRequest.Create;
begin
  inherited Create;
  FConversationState := nil;
  FIncludeSystemPrompt := True;
  FIncludeTools := False;
  FIncludeRAG := False;
  FIncludeReasoning := False;
  FToolsContext := '';
  FRAGContext := '';
  FReasoningInstruction := '';
  FMaxHistoryMessages := 0;
  FTemplateName := 'default';
end;

procedure TYakkoPromptBuildRequest.Assign(ASource: TYakkoPromptBuildRequest);
begin
  if not Assigned(ASource) then
    raise EArgumentNilException.Create('ASource must be assigned.');

  FConversationState := ASource.FConversationState;
  FIncludeSystemPrompt := ASource.FIncludeSystemPrompt;
  FIncludeTools := ASource.FIncludeTools;
  FIncludeRAG := ASource.FIncludeRAG;
  FIncludeReasoning := ASource.FIncludeReasoning;
  FToolsContext := ASource.FToolsContext;
  FRAGContext := ASource.FRAGContext;
  FReasoningInstruction := ASource.FReasoningInstruction;
  FMaxHistoryMessages := ASource.FMaxHistoryMessages;
  FTemplateName := ASource.FTemplateName;
end;

{ TYakkoPromptBuildResult }

constructor TYakkoPromptBuildResult.Create;
begin
  inherited Create;
  FPromptText := '';
  FPromptDocument := TYakkoPromptDocument.Create;
  FBuiltAt := 0;
  FCharacterCount := 0;
  FMessageCount := 0;
  FSectionCount := 0;
  FTemplateName := 'default';
  FSystemPromptIncluded := False;
  FToolsIncluded := False;
  FRAGIncluded := False;
  FReasoningIncluded := False;
  FContextLimitsApplied := False;
end;

destructor TYakkoPromptBuildResult.Destroy;
begin
  FreeAndNil(FPromptDocument);
  inherited;
end;

procedure TYakkoPromptBuildResult.SetPromptDocument(
  const Value: TYakkoPromptDocument);
begin
  if Value = FPromptDocument then
    Exit;

  FreeAndNil(FPromptDocument);
  if Assigned(Value) then
    FPromptDocument := Value.Clone
  else
    FPromptDocument := TYakkoPromptDocument.Create;
end;

function TYakkoPromptBuildResult.Clone: TYakkoPromptBuildResult;
begin
  Result := TYakkoPromptBuildResult.Create;
  Result.FPromptText := FPromptText;
  Result.SetPromptDocument(FPromptDocument);
  Result.FBuiltAt := FBuiltAt;
  Result.FCharacterCount := FCharacterCount;
  Result.FMessageCount := FMessageCount;
  Result.FSectionCount := FSectionCount;
  Result.FTemplateName := FTemplateName;
  Result.FSystemPromptIncluded := FSystemPromptIncluded;
  Result.FToolsIncluded := FToolsIncluded;
  Result.FRAGIncluded := FRAGIncluded;
  Result.FReasoningIncluded := FReasoningIncluded;
  Result.FContextLimitsApplied := FContextLimitsApplied;
end;

{ TYakkoPromptBuilder }

constructor TYakkoPromptBuilder.Create;
begin
  inherited Create;
  FRequest := TYakkoPromptBuildRequest.Create;
  FResult := TYakkoPromptBuildResult.Create;
end;

destructor TYakkoPromptBuilder.Destroy;
begin
  FreeAndNil(FResult);
  FreeAndNil(FRequest);
  inherited;
end;

procedure TYakkoPromptBuilder.ResetState;
begin
  FreeAndNil(FResult);
  FResult := TYakkoPromptBuildResult.Create;
end;

procedure TYakkoPromptBuilder.AddSemanticBlock(ABlockType: TYakkoPromptBlockType;
  const AContent: string; AVisible: Boolean; const ARole: string);
var
  LBlock: TYakkoPromptBlock;
  LNormalizedContent: string;
begin
  LNormalizedContent := Trim(AContent);
  if LNormalizedContent = '' then
    Exit;

  LBlock := TYakkoPromptBlock.Create;
  try
    LBlock.BlockType := ABlockType;
    LBlock.Content := LNormalizedContent;
    LBlock.Visible := AVisible;

    if ARole <> '' then
      LBlock.Metadata.AddOrSetValue('role', ARole);

    FResult.PromptDocument.AddBlock(LBlock);
  except
    LBlock.Free;
    raise;
  end;
end;

procedure TYakkoPromptBuilder.AppendSystemPrompt;
begin
  if not FRequest.IncludeSystemPrompt then
    Exit;
  if not Assigned(FRequest.ConversationState) then
    Exit;

  AddSemanticBlock(pbtSystem, FRequest.ConversationState.SystemPrompt, True);
  FResult.SystemPromptIncluded := FResult.PromptDocument.BlockCount > 0;
end;

procedure TYakkoPromptBuilder.AppendConversation;
var
  LMessages: TYakkoMessageList;
  LStartIndex: Integer;
  LIndex: Integer;
begin
  if not Assigned(FRequest.ConversationState) then
    Exit;

  LMessages := FRequest.ConversationState.GetMessages;
  if LMessages.Count = 0 then
    Exit;

  if FRequest.MaxHistoryMessages > 0 then
    LStartIndex := LMessages.Count - FRequest.MaxHistoryMessages
  else
    LStartIndex := 0;

  if LStartIndex < 0 then
    LStartIndex := 0;

  for LIndex := LStartIndex to LMessages.Count - 1 do
  begin
    if (LMessages[LIndex].IsReasoning) and (not FRequest.IncludeReasoning) then
      Continue;

    AddSemanticBlock(
      pbtConversation,
      LMessages[LIndex].Content,
      True,
      LMessages[LIndex].Role.ToString
    );
    FResult.MessageCount := FResult.MessageCount + 1;
  end;
end;

procedure TYakkoPromptBuilder.AppendTools;
begin
  if not FRequest.IncludeTools then
    Exit;

  AddSemanticBlock(pbtTool, FRequest.ToolsContext, True);
  FResult.ToolsIncluded := Trim(FRequest.ToolsContext) <> '';

  { TODO: tool serialization details belong to template providers, not the builder. }
end;

procedure TYakkoPromptBuilder.AppendRAG;
begin
  if not FRequest.IncludeRAG then
    Exit;

  AddSemanticBlock(pbtRAG, FRequest.RAGContext, True);
  FResult.RAGIncluded := Trim(FRequest.RAGContext) <> '';

  { TODO: support structured RAG documents and citation-aware block metadata. }
end;

procedure TYakkoPromptBuilder.AppendReasoning;
var
  LInstruction: string;
begin
  if not FRequest.IncludeReasoning then
    Exit;

  LInstruction := Trim(FRequest.ReasoningInstruction);
  if LInstruction = '' then
    LInstruction := 'Use internal reasoning to improve answer quality, then respond with the final answer only.';

  AddSemanticBlock(pbtReasoning, LInstruction, True);
  FResult.ReasoningIncluded := True;

  { TODO: hidden reasoning visibility and redaction policies should be block metadata. }
end;

procedure TYakkoPromptBuilder.ApplyContextLimits;
begin
  FResult.ContextLimitsApplied := False;

  { TODO: implement multimodal blocks and attachment references in PromptDocument. }
  { TODO: implement tool serialization hints for providers via semantic metadata. }
  { TODO: implement XML prompt tree support with nested semantic blocks. }
  { TODO: implement structured outputs and JSON schema prompt constraints. }
  { TODO: implement semantic compression and summary replacement strategies. }
  { TODO: implement token attribution once tokenizer-level tracing is introduced. }
end;

function TYakkoPromptBuilder.BuildMessageText(AMessage: TYakkoMessage): string;
begin
  if not Assigned(AMessage) then
    Exit('');

  Result := Trim(AMessage.Content);

  { TODO: remove this legacy helper after all callers migrate to PromptDocument. }
end;

function TYakkoPromptBuilder.Build(ARequest: TYakkoPromptBuildRequest): TYakkoPromptBuildResult;
var
  LTemplateProvider: IYakkoTemplateProvider;
begin
  if not Assigned(ARequest) then
    raise EArgumentNilException.Create('ARequest must be assigned.');
  if not Assigned(ARequest.ConversationState) then
    raise EArgumentNilException.Create('ARequest.ConversationState must be assigned.');

  ResetState;
  FRequest.Assign(ARequest);
  FResult.TemplateName := FRequest.TemplateName;

  { The builder now assembles semantic intent first. }
  AppendSystemPrompt;
  AppendConversation;
  AppendTools;
  AppendRAG;
  AppendReasoning;
  ApplyContextLimits;

  FResult.SectionCount := FResult.PromptDocument.BlockCount;

  { Temporary compatibility stage:
    serialize PromptDocument back to PromptText through a template strategy,
    while external runtime flow still consumes PromptText. }
  LTemplateProvider := TYakkoTemplateProviderFactory.CreateDefault;
  FResult.PromptText := LTemplateProvider.BuildPromptDocument(FResult.PromptDocument);
  FResult.CharacterCount := Length(FResult.PromptText);
  FResult.BuiltAt := Now;

  Result := FResult.Clone;
end;

end.
