unit Yakko.Prompt.Diff;

{ Prompt diff engine for controlled runtime operationalization.

  Architectural intent:
  - compare legacy and modern prompts deterministically;
  - provide structural divergence metrics for shadow safety;
  - prepare semantic diff evolution without heuristics right now.

  This unit is synchronous and local only. }

interface

uses
  System.SysUtils,
  System.Classes,
  System.Math,
  System.Hash,
  System.Generics.Collections,
  Yakko.Prompt.Document;

type
  TYakkoPromptDiffMetadata = TDictionary<string, string>;

  TYakkoPromptDiffResult = class
  private
    FEquivalent: Boolean;
    FDivergenceScore: Double;
    FPromptHash: string;
    FStructuralHash: string;
    FSemanticHash: string;
    FBlockOrderDiff: Integer;
    FBlockTypeDiff: Integer;
    FBlockSizeDiff: Integer;
    FContentDiff: Integer;
    FMetadataDiff: Integer;
    FEstimatedTokenDiff: Integer;
    FDifferences: TStringList;
    FMetadata: TYakkoPromptDiffMetadata;
    FCreatedAt: TDateTime;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    function Clone: TYakkoPromptDiffResult;
    function ToDebugString: string;

    property Equivalent: Boolean read FEquivalent write FEquivalent;
    property DivergenceScore: Double read FDivergenceScore write FDivergenceScore;
    property PromptHash: string read FPromptHash write FPromptHash;
    property StructuralHash: string read FStructuralHash write FStructuralHash;
    property SemanticHash: string read FSemanticHash write FSemanticHash;
    property BlockOrderDiff: Integer read FBlockOrderDiff write FBlockOrderDiff;
    property BlockTypeDiff: Integer read FBlockTypeDiff write FBlockTypeDiff;
    property BlockSizeDiff: Integer read FBlockSizeDiff write FBlockSizeDiff;
    property ContentDiff: Integer read FContentDiff write FContentDiff;
    property MetadataDiff: Integer read FMetadataDiff write FMetadataDiff;
    property EstimatedTokenDiff: Integer read FEstimatedTokenDiff write FEstimatedTokenDiff;
    property Differences: TStringList read FDifferences;
    property Metadata: TYakkoPromptDiffMetadata read FMetadata;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
  end;

  TYakkoPromptDiffEngine = class
  private
    function ComputeDocumentStructuralSignature(ADocument: TYakkoPromptDocument): string;
    function ComputeDocumentPromptText(ADocument: TYakkoPromptDocument): string;
    function EstimateTokens(const AText: string): Integer;
  public
    function CompareDocuments(
      ALegacyPromptDocument: TYakkoPromptDocument;
      AModernPromptDocument: TYakkoPromptDocument
    ): TYakkoPromptDiffResult;

    function ComparePromptTexts(
      const ALegacyPrompt: string;
      const AModernPrompt: string
    ): TYakkoPromptDiffResult;
  end;

implementation

procedure CloneStringDictionary(ASource, ADest: TYakkoPromptDiffMetadata);
var
  LPair: TPair<string, string>;
begin
  if not Assigned(ADest) then
    raise EArgumentNilException.Create('ADest must be assigned.');

  ADest.Clear;
  if not Assigned(ASource) then
    Exit;

  for LPair in ASource do
    ADest.AddOrSetValue(LPair.Key, LPair.Value);
end;

{ TYakkoPromptDiffResult }

constructor TYakkoPromptDiffResult.Create;
begin
  inherited Create;
  FEquivalent := False;
  FDivergenceScore := 0;
  FPromptHash := '';
  FStructuralHash := '';
  FSemanticHash := '';
  FBlockOrderDiff := 0;
  FBlockTypeDiff := 0;
  FBlockSizeDiff := 0;
  FContentDiff := 0;
  FMetadataDiff := 0;
  FEstimatedTokenDiff := 0;
  FDifferences := TStringList.Create;
  FMetadata := TYakkoPromptDiffMetadata.Create;
  FCreatedAt := Now;
end;

destructor TYakkoPromptDiffResult.Destroy;
begin
  FreeAndNil(FMetadata);
  FreeAndNil(FDifferences);
  inherited;
end;

procedure TYakkoPromptDiffResult.Clear;
begin
  FEquivalent := False;
  FDivergenceScore := 0;
  FPromptHash := '';
  FStructuralHash := '';
  FSemanticHash := '';
  FBlockOrderDiff := 0;
  FBlockTypeDiff := 0;
  FBlockSizeDiff := 0;
  FContentDiff := 0;
  FMetadataDiff := 0;
  FEstimatedTokenDiff := 0;
  FDifferences.Clear;
  FMetadata.Clear;
  FCreatedAt := Now;

  { TODO: add semantic embedding-based similarity when semantic mode is approved. }
end;

function TYakkoPromptDiffResult.Clone: TYakkoPromptDiffResult;
begin
  Result := TYakkoPromptDiffResult.Create;
  try
    Result.FEquivalent := FEquivalent;
    Result.FDivergenceScore := FDivergenceScore;
    Result.FPromptHash := FPromptHash;
    Result.FStructuralHash := FStructuralHash;
    Result.FSemanticHash := FSemanticHash;
    Result.FBlockOrderDiff := FBlockOrderDiff;
    Result.FBlockTypeDiff := FBlockTypeDiff;
    Result.FBlockSizeDiff := FBlockSizeDiff;
    Result.FContentDiff := FContentDiff;
    Result.FMetadataDiff := FMetadataDiff;
    Result.FEstimatedTokenDiff := FEstimatedTokenDiff;
    Result.FDifferences.Assign(FDifferences);
    Result.FCreatedAt := FCreatedAt;
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoPromptDiffResult.ToDebugString: string;
begin
  Result := Format(
    'TYakkoPromptDiffResult(Equivalent=%s, Divergence=%.4f, PromptHash=%s, StructuralHash=%s, SemanticHash=%s, BlockOrderDiff=%d, BlockTypeDiff=%d, BlockSizeDiff=%d, ContentDiff=%d, MetadataDiff=%d, EstimatedTokenDiff=%d, Differences=%d)',
    [
      BoolToStr(FEquivalent, True),
      FDivergenceScore,
      FPromptHash,
      FStructuralHash,
      FSemanticHash,
      FBlockOrderDiff,
      FBlockTypeDiff,
      FBlockSizeDiff,
      FContentDiff,
      FMetadataDiff,
      FEstimatedTokenDiff,
      FDifferences.Count
    ]
  );
end;

{ TYakkoPromptDiffEngine }

function TYakkoPromptDiffEngine.ComputeDocumentPromptText(
  ADocument: TYakkoPromptDocument): string;
var
  LBuilder: TStringBuilder;
  LBlock: TYakkoPromptBlock;
begin
  if not Assigned(ADocument) then
    Exit('');

  LBuilder := TStringBuilder.Create;
  try
    for LBlock in ADocument.Blocks do
    begin
      if not LBlock.Visible then
        Continue;
      if LBuilder.Length > 0 then
        LBuilder.AppendLine;
      LBuilder.Append(LBlock.BlockType.ToString).Append(':').Append(LBlock.Content);
    end;
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

function TYakkoPromptDiffEngine.ComputeDocumentStructuralSignature(
  ADocument: TYakkoPromptDocument): string;
var
  LBuilder: TStringBuilder;
  LBlock: TYakkoPromptBlock;
begin
  if not Assigned(ADocument) then
    Exit('');

  LBuilder := TStringBuilder.Create;
  try
    for LBlock in ADocument.Blocks do
    begin
      LBuilder.Append(LBlock.BlockType.ToString).Append('|');
      LBuilder.Append(Length(LBlock.Content)).Append('|');
      LBuilder.Append(BoolToStr(LBlock.Visible, True)).Append('|');
      LBuilder.Append(LBlock.Metadata.Count).Append(';');
    end;
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

function TYakkoPromptDiffEngine.EstimateTokens(const AText: string): Integer;
begin
  if Trim(AText) = '' then
    Exit(0);
  Result := Max(1, Length(AText) div 4);
end;

function TYakkoPromptDiffEngine.CompareDocuments(
  ALegacyPromptDocument, AModernPromptDocument: TYakkoPromptDocument): TYakkoPromptDiffResult;
var
  LLegacyText: string;
  LModernText: string;
  LLegacySignature: string;
  LModernSignature: string;
  LIndex: Integer;
  LLegacyBlock, LModernBlock: TYakkoPromptBlock;
begin
  if not Assigned(ALegacyPromptDocument) then
    raise EArgumentNilException.Create('ALegacyPromptDocument must be assigned.');
  if not Assigned(AModernPromptDocument) then
    raise EArgumentNilException.Create('AModernPromptDocument must be assigned.');

  Result := TYakkoPromptDiffResult.Create;

  LLegacyText := ComputeDocumentPromptText(ALegacyPromptDocument);
  LModernText := ComputeDocumentPromptText(AModernPromptDocument);
  LLegacySignature := ComputeDocumentStructuralSignature(ALegacyPromptDocument);
  LModernSignature := ComputeDocumentStructuralSignature(AModernPromptDocument);

  Result.PromptHash := THashSHA2.GetHashString(LLegacyText + '||' + LModernText);
  Result.StructuralHash := THashSHA2.GetHashString(LLegacySignature + '||' + LModernSignature);
  Result.SemanticHash := 'semantic-hash-placeholder';

  if ALegacyPromptDocument.BlockCount <> AModernPromptDocument.BlockCount then
    Result.BlockOrderDiff := Abs(ALegacyPromptDocument.BlockCount - AModernPromptDocument.BlockCount);

  for LIndex := 0 to Min(ALegacyPromptDocument.BlockCount, AModernPromptDocument.BlockCount) - 1 do
  begin
    LLegacyBlock := ALegacyPromptDocument.Blocks[LIndex];
    LModernBlock := AModernPromptDocument.Blocks[LIndex];

    if LLegacyBlock.BlockType <> LModernBlock.BlockType then
      Inc(Result.FBlockTypeDiff);

    if Length(LLegacyBlock.Content) <> Length(LModernBlock.Content) then
      Inc(Result.FBlockSizeDiff);

    if not SameText(Trim(LLegacyBlock.Content), Trim(LModernBlock.Content)) then
      Inc(Result.FContentDiff);

    if LLegacyBlock.Metadata.Count <> LModernBlock.Metadata.Count then
      Inc(Result.FMetadataDiff);
  end;

  Result.EstimatedTokenDiff := Abs(EstimateTokens(LLegacyText) - EstimateTokens(LModernText));
  Result.DivergenceScore :=
    Result.BlockOrderDiff +
    Result.BlockTypeDiff +
    Result.BlockSizeDiff +
    Result.ContentDiff +
    Result.MetadataDiff +
    Result.EstimatedTokenDiff;

  Result.Equivalent := Result.DivergenceScore = 0;

  if not Result.Equivalent then
  begin
    Result.Differences.Add(Format('block-order-diff=%d', [Result.BlockOrderDiff]));
    Result.Differences.Add(Format('block-type-diff=%d', [Result.BlockTypeDiff]));
    Result.Differences.Add(Format('block-size-diff=%d', [Result.BlockSizeDiff]));
    Result.Differences.Add(Format('content-diff=%d', [Result.ContentDiff]));
    Result.Differences.Add(Format('metadata-diff=%d', [Result.MetadataDiff]));
    Result.Differences.Add(Format('estimated-token-diff=%d', [Result.EstimatedTokenDiff]));
  end;

  Result.Metadata.AddOrSetValue('legacy.blocks', IntToStr(ALegacyPromptDocument.BlockCount));
  Result.Metadata.AddOrSetValue('modern.blocks', IntToStr(AModernPromptDocument.BlockCount));
  Result.Metadata.AddOrSetValue('legacy.tokens.estimated', IntToStr(EstimateTokens(LLegacyText)));
  Result.Metadata.AddOrSetValue('modern.tokens.estimated', IntToStr(EstimateTokens(LModernText)));
  Result.Metadata.AddOrSetValue('mode', 'structural-deterministic');
end;

function TYakkoPromptDiffEngine.ComparePromptTexts(
  const ALegacyPrompt, AModernPrompt: string): TYakkoPromptDiffResult;
begin
  Result := TYakkoPromptDiffResult.Create;
  Result.PromptHash := THashSHA2.GetHashString(ALegacyPrompt + '||' + AModernPrompt);
  Result.StructuralHash := THashSHA2.GetHashString(IntToStr(Length(ALegacyPrompt)) + '|' + IntToStr(Length(AModernPrompt)));
  Result.SemanticHash := 'semantic-hash-placeholder';
  Result.ContentDiff := Ord(not SameText(Trim(ALegacyPrompt), Trim(AModernPrompt)));
  Result.EstimatedTokenDiff := Abs(EstimateTokens(ALegacyPrompt) - EstimateTokens(AModernPrompt));
  Result.DivergenceScore := Result.ContentDiff + Result.EstimatedTokenDiff;
  Result.Equivalent := Result.DivergenceScore = 0;
  if not Result.Equivalent then
    Result.Differences.Add('prompt-text-divergence');
end;

end.
