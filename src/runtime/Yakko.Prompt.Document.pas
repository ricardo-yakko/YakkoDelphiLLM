unit Yakko.Prompt.Document;

{ Semantic prompt document model for YakkoDelphiLLM runtime.
  Architectural intent:
  - separate semantic prompt construction from model-specific text serialization;
  - provide a stable intermediate representation between PromptBuilder and
    TemplateProvider;
  - preserve conversational and contextual intent without leaking template tokens,
    BOS/EOS markers or model delimiters into the semantic layer;
  - prepare the runtime for modern context engineering, where prompt blocks,
    hidden reasoning, multimodal content and retrieval context evolve independently.

  PromptDocument exists because PromptBuilder and TemplateProvider solve different
  problems. PromptBuilder should decide what the prompt means and which semantic
  blocks belong to it. TemplateProvider should decide how those blocks are turned
  into text for a specific model family.

  This intermediate layer prepares the runtime for multiple templates, richer
  reasoning policies, future multimodal inputs and structured prompt trees without
  coupling those concerns to the legacy prompt formatter. }

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TYakkoPromptBlockType =
  (
    pbtSystem,
    pbtConversation,
    pbtTool,
    pbtRAG,
    pbtReasoning,
    pbtAssistantPrefix,
    pbtMetadata
  );

  TYakkoPromptBlockTypeHelper = record helper for TYakkoPromptBlockType
  public
    function ToString: string;
  end;

  TYakkoPromptBlockMetadata = TDictionary<string, string>;

  TYakkoPromptBlock = class
  private
    FBlockType: TYakkoPromptBlockType;
    FContent: string;
    FVisible: Boolean;
    FMetadata: TYakkoPromptBlockMetadata;
  public
    constructor Create;
    destructor Destroy; override;

    function Clone: TYakkoPromptBlock;
    function ToDebugString: string;

    property BlockType: TYakkoPromptBlockType read FBlockType write FBlockType;
    property Content: string read FContent write FContent;
    property Visible: Boolean read FVisible write FVisible;
    property Metadata: TYakkoPromptBlockMetadata read FMetadata;
  end;

  TYakkoPromptBlockList = TObjectList<TYakkoPromptBlock>;
  TYakkoPromptDocumentMetadata = TDictionary<string, string>;

  TYakkoPromptDocument = class
  private
    FBlocks: TYakkoPromptBlockList;
    FCreatedAt: TDateTime;
    FMetadata: TYakkoPromptDocumentMetadata;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    procedure AddBlock(ABlock: TYakkoPromptBlock);

    function BlockCount: Integer;
    function Clone: TYakkoPromptDocument;
    function ToDebugString: string;

    property Blocks: TYakkoPromptBlockList read FBlocks;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
    property Metadata: TYakkoPromptDocumentMetadata read FMetadata;
  end;

implementation

{ TYakkoPromptBlockTypeHelper }

function TYakkoPromptBlockTypeHelper.ToString: string;
begin
  case Self of
    pbtSystem:
      Result := 'system';
    pbtConversation:
      Result := 'conversation';
    pbtTool:
      Result := 'tool';
    pbtRAG:
      Result := 'rag';
    pbtReasoning:
      Result := 'reasoning';
    pbtAssistantPrefix:
      Result := 'assistant-prefix';
    pbtMetadata:
      Result := 'metadata';
  else
    Result := 'metadata';
  end;
end;

{ TYakkoPromptBlock }

constructor TYakkoPromptBlock.Create;
begin
  inherited Create;
  FBlockType := pbtConversation;
  FContent := '';
  FVisible := True;
  FMetadata := TYakkoPromptBlockMetadata.Create;
end;

destructor TYakkoPromptBlock.Destroy;
begin
  FreeAndNil(FMetadata);
  inherited;
end;

function TYakkoPromptBlock.Clone: TYakkoPromptBlock;
var
  LPair: TPair<string, string>;
begin
  Result := TYakkoPromptBlock.Create;
  try
    Result.FBlockType := FBlockType;
    Result.FContent := FContent;
    Result.FVisible := FVisible;

    Result.FMetadata.Clear;
    for LPair in FMetadata do
      Result.FMetadata.AddOrSetValue(LPair.Key, LPair.Value);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoPromptBlock.ToDebugString: string;
begin
  Result := Format(
    'TYakkoPromptBlock(Type=%s, Visible=%s, ContentLength=%d, Metadata=%d)',
    [
      FBlockType.ToString,
      BoolToStr(FVisible, True),
      Length(FContent),
      FMetadata.Count
    ]
  );
end;

{ TYakkoPromptDocument }

constructor TYakkoPromptDocument.Create;
begin
  inherited Create;
  FBlocks := TYakkoPromptBlockList.Create(True);
  FCreatedAt := Now;
  FMetadata := TYakkoPromptDocumentMetadata.Create;
end;

destructor TYakkoPromptDocument.Destroy;
begin
  FreeAndNil(FMetadata);
  FreeAndNil(FBlocks);
  inherited;
end;

procedure TYakkoPromptDocument.Clear;
begin
  FBlocks.Clear;
  FMetadata.Clear;

  { TODO: preserve semantic compression summaries when document compaction exists. }
  { TODO: preserve token attribution once prompt tracing becomes available. }
  { TODO: preserve hidden reasoning visibility state when reasoning policies mature. }
end;

procedure TYakkoPromptDocument.AddBlock(ABlock: TYakkoPromptBlock);
begin
  if not Assigned(ABlock) then
    raise EArgumentNilException.Create('ABlock must be assigned.');

  { Ownership is transferred to TYakkoPromptDocument once a block is added. }
  FBlocks.Add(ABlock);

  { TODO: support multimodal blocks with typed payload references. }
  { TODO: support citations and structured retrieval provenance. }
  { TODO: support XML prompt trees and nested semantic block composition. }
  { TODO: support JSON schema prompting and structured output contracts. }
end;

function TYakkoPromptDocument.BlockCount: Integer;
begin
  Result := FBlocks.Count;
end;

function TYakkoPromptDocument.Clone: TYakkoPromptDocument;
var
  LBlock: TYakkoPromptBlock;
  LPair: TPair<string, string>;
begin
  Result := TYakkoPromptDocument.Create;
  try
    Result.FCreatedAt := FCreatedAt;

    Result.FMetadata.Clear;
    for LPair in FMetadata do
      Result.FMetadata.AddOrSetValue(LPair.Key, LPair.Value);

    for LBlock in FBlocks do
      Result.FBlocks.Add(LBlock.Clone);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoPromptDocument.ToDebugString: string;
begin
  Result := Format(
    'TYakkoPromptDocument(CreatedAt=%s, BlockCount=%d, Metadata=%d)',
    [
      DateTimeToStr(FCreatedAt),
      FBlocks.Count,
      FMetadata.Count
    ]
  );
end;

end.