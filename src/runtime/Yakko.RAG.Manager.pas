unit Yakko.RAG.Manager;

{ Deterministic RAG manager for first runtime integration layer.

  Responsibilities:
  - receive TYakkoRAGQuery;
  - query chat, knowledge and inventory memories;
  - consolidate structured TYakkoRAGResult;
  - prepare deterministic context text.

  Non-goals in this phase:
  - prompt assembly;
  - model inference;
  - semantic ranking;
  - async orchestration. }

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Yakko.RAG.Types,
  Yakko.RAG.KnowledgeMemory,
  Yakko.RAG.InventoryMemory,
  Yakko.RAG.ChatMemory;

type
  TYakkoRAGManager = class
  private
    FKnowledgeMemory: TYakkoKnowledgeMemory;
    FInventoryMemory: TYakkoInventoryMemory;
    FChatMemory: TYakkoChatMemory;
    FOwnsKnowledgeMemory: Boolean;
    FOwnsInventoryMemory: Boolean;
    FOwnsChatMemory: Boolean;

    class function Normalize(const AValue: string): string; static;
    class function TrimEdgePunctuation(const AValue: string): string; static;
    class function ExtractCandidateTerms(const AText: string): TArray<string>; static;

    procedure AddUniqueDocuments(
      ATarget: TYakkoRAGResult;
      ASource: TYakkoKnowledgeDocumentList;
      ASeen: TDictionary<string, Boolean>;
      AMaxResults: Integer
    );
    procedure AddUniqueChunks(
      ATarget: TYakkoRAGResult;
      ASource: TYakkoKnowledgeChunkList;
      ASeen: TDictionary<string, Boolean>;
      AMaxResults: Integer
    );
    procedure AddUniqueEntities(
      ATarget: TYakkoRAGResult;
      ASource: TYakkoInventoryEntityList;
      ASeen: TDictionary<string, Boolean>;
      AMaxResults: Integer
    );

    class function NormalizeMaxResults(AValue: Integer): Integer; static;
    procedure AppendCompatibilityDiagnostics(AResult: TYakkoRAGResult);

    procedure MergeKnowledgeDocuments(
      ATarget: TYakkoRAGResult;
      ASource: TYakkoKnowledgeDocumentList;
      ASeen: TDictionary<string, Boolean>;
      AMaxResults: Integer
    );
    procedure MergeKnowledgeChunks(
      ATarget: TYakkoRAGResult;
      ASource: TYakkoKnowledgeChunkList;
      ASeen: TDictionary<string, Boolean>;
      AMaxResults: Integer
    );
    procedure MergeInventoryEntities(
      ATarget: TYakkoRAGResult;
      ASource: TYakkoInventoryEntityList;
      ASeen: TDictionary<string, Boolean>;
      AMaxResults: Integer
    );
  public
    constructor Create; overload;
    constructor CreateWithMemories(
      AKnowledgeMemory: TYakkoKnowledgeMemory;
      AInventoryMemory: TYakkoInventoryMemory;
      AChatMemory: TYakkoChatMemory;
      AOwnsKnowledgeMemory: Boolean = False;
      AOwnsInventoryMemory: Boolean = False;
      AOwnsChatMemory: Boolean = False
    ); overload;
    destructor Destroy; override;

    function ExecuteQuery(AQuery: TYakkoRAGQuery): TYakkoRAGResult;
    function PrepareContextText(AResult: TYakkoRAGResult): string;
    function ToDebugString: string;

    property KnowledgeMemory: TYakkoKnowledgeMemory read FKnowledgeMemory;
    property InventoryMemory: TYakkoInventoryMemory read FInventoryMemory;
    property ChatMemory: TYakkoChatMemory read FChatMemory;
  end;

implementation

constructor TYakkoRAGManager.Create;
begin
  inherited Create;

  FKnowledgeMemory := TYakkoKnowledgeMemory.Create;
  FInventoryMemory := TYakkoInventoryMemory.Create;
  FChatMemory := TYakkoChatMemory.Create;
  FOwnsKnowledgeMemory := True;
  FOwnsInventoryMemory := True;
  FOwnsChatMemory := True;
end;

constructor TYakkoRAGManager.CreateWithMemories(
  AKnowledgeMemory: TYakkoKnowledgeMemory;
  AInventoryMemory: TYakkoInventoryMemory;
  AChatMemory: TYakkoChatMemory;
  AOwnsKnowledgeMemory, AOwnsInventoryMemory, AOwnsChatMemory: Boolean);
begin
  inherited Create;

  if not Assigned(AKnowledgeMemory) then
    raise EArgumentNilException.Create('AKnowledgeMemory must be assigned.');

  if not Assigned(AInventoryMemory) then
    raise EArgumentNilException.Create('AInventoryMemory must be assigned.');

  if not Assigned(AChatMemory) then
    raise EArgumentNilException.Create('AChatMemory must be assigned.');

  FKnowledgeMemory := AKnowledgeMemory;
  FInventoryMemory := AInventoryMemory;
  FChatMemory := AChatMemory;
  FOwnsKnowledgeMemory := AOwnsKnowledgeMemory;
  FOwnsInventoryMemory := AOwnsInventoryMemory;
  FOwnsChatMemory := AOwnsChatMemory;
end;

destructor TYakkoRAGManager.Destroy;
begin
  if FOwnsChatMemory then
    FreeAndNil(FChatMemory)
  else
    FChatMemory := nil;

  if FOwnsInventoryMemory then
    FreeAndNil(FInventoryMemory)
  else
    FInventoryMemory := nil;

  if FOwnsKnowledgeMemory then
    FreeAndNil(FKnowledgeMemory)
  else
    FKnowledgeMemory := nil;

  inherited;
end;

class function TYakkoRAGManager.Normalize(const AValue: string): string;
begin
  Result := Trim(LowerCase(AValue));
end;

class function TYakkoRAGManager.TrimEdgePunctuation(const AValue: string): string;
const
  CEdgeChars = ' .,;:!?()[]{}<>"''`';
begin
  Result := Trim(AValue);
  while (Result <> '') and (Pos(Result[1], CEdgeChars) > 0) do
    Delete(Result, 1, 1);
  while (Result <> '') and (Pos(Result[Length(Result)], CEdgeChars) > 0) do
    Delete(Result, Length(Result), 1);
end;

class function TYakkoRAGManager.ExtractCandidateTerms(
  const AText: string): TArray<string>;
var
  LTerms: TStringList;
  LRawParts: TArray<string>;
  LPart: string;
  LNormalized: string;
  LIndex: Integer;
begin
  LTerms := TStringList.Create;
  try
    LTerms.Sorted := True;
    LTerms.Duplicates := dupIgnore;

    LRawParts := AText.Split([' ', #9, #10, #13], TStringSplitOptions.ExcludeEmpty);
    for LPart in LRawParts do
    begin
      LNormalized := Normalize(TrimEdgePunctuation(LPart));

      { Keep tokenization deterministic by splitting only on whitespace and
        trimming edge punctuation. Do not split on '.' or '/'. }
      if Length(LNormalized) < 2 then
        Continue;

      LTerms.Add(LNormalized);
    end;

    SetLength(Result, LTerms.Count);
    for LIndex := 0 to LTerms.Count - 1 do
      Result[LIndex] := LTerms[LIndex];
  finally
    LTerms.Free;
  end;
end;

procedure TYakkoRAGManager.AddUniqueDocuments(ATarget: TYakkoRAGResult;
  ASource: TYakkoKnowledgeDocumentList; ASeen: TDictionary<string, Boolean>;
  AMaxResults: Integer);
var
  LDocument: TYakkoKnowledgeDocument;
  LKey: string;
begin
  if not Assigned(ATarget) or not Assigned(ASource) then
    Exit;

  for LDocument in ASource do
  begin
    if ATarget.RetrievedDocuments.Count >= AMaxResults then
      Break;

    LKey := Normalize(LDocument.Id);
    if LKey = '' then
      LKey := Normalize(LDocument.Title + '|' + LDocument.Source);

    if ASeen.ContainsKey(LKey) then
      Continue;

    ASeen.AddOrSetValue(LKey, True);
    ATarget.AddRetrievedDocument(LDocument.Clone);
  end;
end;

procedure TYakkoRAGManager.AddUniqueChunks(ATarget: TYakkoRAGResult;
  ASource: TYakkoKnowledgeChunkList; ASeen: TDictionary<string, Boolean>;
  AMaxResults: Integer);
var
  LChunk: TYakkoKnowledgeChunk;
  LKey: string;
begin
  if not Assigned(ATarget) or not Assigned(ASource) then
    Exit;

  for LChunk in ASource do
  begin
    if ATarget.RetrievedChunks.Count >= AMaxResults then
      Break;

    LKey := Normalize(LChunk.ChunkId);
    if LKey = '' then
      LKey := Normalize(LChunk.DocumentId + '|' + IntToStr(LChunk.ChunkIndex));

    if ASeen.ContainsKey(LKey) then
      Continue;

    ASeen.AddOrSetValue(LKey, True);
    ATarget.AddRetrievedChunk(LChunk.Clone);
  end;
end;

procedure TYakkoRAGManager.AddUniqueEntities(ATarget: TYakkoRAGResult;
  ASource: TYakkoInventoryEntityList; ASeen: TDictionary<string, Boolean>;
  AMaxResults: Integer);
var
  LEntity: TYakkoInventoryEntity;
  LKey: string;
begin
  if not Assigned(ATarget) or not Assigned(ASource) then
    Exit;

  for LEntity in ASource do
  begin
    if ATarget.RetrievedEntities.Count >= AMaxResults then
      Break;

    LKey := Normalize(LEntity.Id);
    if LKey = '' then
      LKey := Normalize(LEntity.Name + '|' + LEntity.Brand + '|' + LEntity.Category);

    if ASeen.ContainsKey(LKey) then
      Continue;

    ASeen.AddOrSetValue(LKey, True);
    ATarget.AddRetrievedEntity(LEntity.Clone);
  end;
end;

class function TYakkoRAGManager.NormalizeMaxResults(AValue: Integer): Integer;
begin
  Result := AValue;
  if Result <= 0 then
    Result := 10;
  if Result > 100 then
    Result := 100;
end;

procedure TYakkoRAGManager.AppendCompatibilityDiagnostics(AResult: TYakkoRAGResult);
var
  I: Integer;
  J: Integer;
  LLeft: TYakkoInventoryEntity;
  LRight: TYakkoInventoryEntity;
  LKey: string;
begin
  if not Assigned(AResult) then
    Exit;

  for I := 0 to AResult.RetrievedEntities.Count - 1 do
  begin
    for J := I + 1 to AResult.RetrievedEntities.Count - 1 do
    begin
      LLeft := AResult.RetrievedEntities[I];
      LRight := AResult.RetrievedEntities[J];
      LKey := Format('compatibility.%s.%s', [LLeft.Id, LRight.Id]);

      if InventoryMemory.AreCompatible(LLeft.Id, LRight.Id) then
        AResult.Diagnostics.AddOrSetValue(LKey, 'true')
      else
        AResult.Diagnostics.AddOrSetValue(LKey, 'false');
    end;
  end;
end;

procedure TYakkoRAGManager.MergeKnowledgeDocuments(ATarget: TYakkoRAGResult;
  ASource: TYakkoKnowledgeDocumentList; ASeen: TDictionary<string, Boolean>;
  AMaxResults: Integer);
begin
  try
    AddUniqueDocuments(ATarget, ASource, ASeen, AMaxResults);
  finally
    ASource.Free;
  end;
end;

procedure TYakkoRAGManager.MergeKnowledgeChunks(ATarget: TYakkoRAGResult;
  ASource: TYakkoKnowledgeChunkList; ASeen: TDictionary<string, Boolean>;
  AMaxResults: Integer);
begin
  try
    AddUniqueChunks(ATarget, ASource, ASeen, AMaxResults);
  finally
    ASource.Free;
  end;
end;

procedure TYakkoRAGManager.MergeInventoryEntities(ATarget: TYakkoRAGResult;
  ASource: TYakkoInventoryEntityList; ASeen: TDictionary<string, Boolean>;
  AMaxResults: Integer);
begin
  try
    AddUniqueEntities(ATarget, ASource, ASeen, AMaxResults);
  finally
    ASource.Free;
  end;
end;

function TYakkoRAGManager.ExecuteQuery(AQuery: TYakkoRAGQuery): TYakkoRAGResult;
var
  LMaxResults: Integer;
  LSeenDocs: TDictionary<string, Boolean>;
  LSeenChunks: TDictionary<string, Boolean>;
  LSeenEntities: TDictionary<string, Boolean>;
  LCategories: TArray<string>;
  LTags: TArray<string>;
  LCategory: string;
  LBrand: string;
  LTerm: string;
  LTerms: TArray<string>;
begin
  if not Assigned(AQuery) then
    raise EArgumentNilException.Create('AQuery must be assigned.');

  if (Trim(AQuery.QueryText) = '') and (AQuery.Categories.Count = 0) and (AQuery.Tags.Count = 0) then
    raise EArgumentException.Create('RAG query must have QueryText, Categories or Tags.');

  Result := TYakkoRAGResult.Create;
  LSeenDocs := TDictionary<string, Boolean>.Create;
  LSeenChunks := TDictionary<string, Boolean>.Create;
  LSeenEntities := TDictionary<string, Boolean>.Create;
  try
    try
      LMaxResults := NormalizeMaxResults(AQuery.MaxResults);

      if Trim(AQuery.QueryText) <> '' then
      begin
        MergeKnowledgeDocuments(Result, FKnowledgeMemory.SearchDocumentsByAlias(AQuery.QueryText), LSeenDocs, LMaxResults);
        MergeKnowledgeDocuments(Result, FKnowledgeMemory.SearchDocumentsByName(AQuery.QueryText), LSeenDocs, LMaxResults);
        MergeKnowledgeDocuments(Result, FKnowledgeMemory.SearchDocumentsByText(AQuery.QueryText), LSeenDocs, LMaxResults);
        MergeKnowledgeChunks(Result, FKnowledgeMemory.SearchChunksByText(AQuery.QueryText), LSeenChunks, LMaxResults);

        MergeInventoryEntities(Result, FInventoryMemory.SearchByAlias(AQuery.QueryText), LSeenEntities, LMaxResults);
        MergeInventoryEntities(Result, FInventoryMemory.SearchByName(AQuery.QueryText), LSeenEntities, LMaxResults);
        MergeInventoryEntities(Result, FInventoryMemory.SearchByText(AQuery.QueryText), LSeenEntities, LMaxResults);
      end;

      LCategories := AQuery.Categories.ToArray;
      for LCategory in LCategories do
      begin
        MergeKnowledgeDocuments(Result, FKnowledgeMemory.SearchDocumentsByCategory(LCategory), LSeenDocs, LMaxResults);
        MergeInventoryEntities(Result, FInventoryMemory.SearchByCategory(LCategory), LSeenEntities, LMaxResults);
      end;

      LTags := AQuery.Tags.ToArray;
      if Length(LTags) > 0 then
        MergeKnowledgeDocuments(Result, FKnowledgeMemory.SearchDocumentsByTags(LTags, False), LSeenDocs, LMaxResults);

      LTerms := ExtractCandidateTerms(AQuery.QueryText);
      for LTerm in LTerms do
      begin
        MergeKnowledgeDocuments(Result, FKnowledgeMemory.SearchDocumentsByAlias(LTerm), LSeenDocs, LMaxResults);
        MergeInventoryEntities(Result, FInventoryMemory.SearchByAlias(LTerm), LSeenEntities, LMaxResults);
        MergeInventoryEntities(Result, FInventoryMemory.SearchCompatibleWith(LTerm), LSeenEntities, LMaxResults);
        MergeInventoryEntities(Result, FInventoryMemory.SearchEquivalentTo(LTerm), LSeenEntities, LMaxResults);

        { Brand lookup is deterministic and explicit: try each normalized term. }
        LBrand := LTerm;
        MergeInventoryEntities(Result, FInventoryMemory.SearchByBrand(LBrand), LSeenEntities, LMaxResults);
      end;

      Result.Diagnostics.AddOrSetValue('knowledge.documents', IntToStr(Result.RetrievedDocuments.Count));
      Result.Diagnostics.AddOrSetValue('knowledge.chunks', IntToStr(Result.RetrievedChunks.Count));
      Result.Diagnostics.AddOrSetValue('inventory.entities', IntToStr(Result.RetrievedEntities.Count));
      Result.Diagnostics.AddOrSetValue('query.max_results', IntToStr(LMaxResults));

      Result.Metadata.AddOrSetValue('chat.relevant_context', FChatMemory.BuildRelevantContextText);
      Result.Metadata.AddOrSetValue('chat.persistent_context', FChatMemory.BuildPersistentContextText);

      AppendCompatibilityDiagnostics(Result);
    except
      Result.Free;
      raise;
    end;
  finally
    LSeenEntities.Free;
    LSeenChunks.Free;
    LSeenDocs.Free;
  end;
end;

function TYakkoRAGManager.PrepareContextText(AResult: TYakkoRAGResult): string;
var
  LBuilder: TStringBuilder;
  LDocument: TYakkoKnowledgeDocument;
  LChunk: TYakkoKnowledgeChunk;
  LEntity: TYakkoInventoryEntity;
  LSpec: TPair<string, string>;
  LRelevantContext: string;
  LPersistentContext: string;
begin
  if not Assigned(AResult) then
    raise EArgumentNilException.Create('AResult must be assigned.');

  LBuilder := TStringBuilder.Create;
  try
    LBuilder.AppendLine('[RAG-CONTEXT]');

    LBuilder.AppendLine('[KNOWLEDGE-DOCUMENTS]');
    for LDocument in AResult.RetrievedDocuments do
    begin
      LBuilder.AppendLine(Format('id=%s; title=%s; category=%s; source=%s',
        [LDocument.Id, LDocument.Title, LDocument.Category, LDocument.Source]));
      if Trim(LDocument.Content) <> '' then
        LBuilder.AppendLine('content=' + LDocument.Content);
      LBuilder.AppendLine('');
    end;

    LBuilder.AppendLine('[KNOWLEDGE-CHUNKS]');
    for LChunk in AResult.RetrievedChunks do
    begin
      LBuilder.AppendLine(Format('chunk_id=%s; document_id=%s; chunk_index=%d',
        [LChunk.ChunkId, LChunk.DocumentId, LChunk.ChunkIndex]));
      if Trim(LChunk.Text) <> '' then
        LBuilder.AppendLine('text=' + LChunk.Text);
      LBuilder.AppendLine('');
    end;

    LBuilder.AppendLine('[INVENTORY-ENTITIES]');
    for LEntity in AResult.RetrievedEntities do
    begin
      LBuilder.AppendLine(Format('id=%s; name=%s; brand=%s; category=%s',
        [LEntity.Id, LEntity.Name, LEntity.Brand, LEntity.Category]));
      if Trim(LEntity.Description) <> '' then
        LBuilder.AppendLine('description=' + LEntity.Description);

      for LSpec in LEntity.Specifications do
        LBuilder.AppendLine(Format('spec.%s=%s', [LSpec.Key, LSpec.Value]));

      if LEntity.CompatibleWith.Count > 0 then
        LBuilder.AppendLine('compatible_with=' + String.Join(', ', LEntity.CompatibleWith.ToArray));

      if LEntity.Aliases.Count > 0 then
        LBuilder.AppendLine('aliases=' + String.Join(', ', LEntity.Aliases.ToArray));

      LBuilder.AppendLine('');
    end;

    LBuilder.AppendLine('[CHAT-CONTEXT]');

    LRelevantContext := '';
    if AResult.Metadata.ContainsKey('chat.relevant_context') then
      LRelevantContext := Trim(AResult.Metadata['chat.relevant_context']);

    LPersistentContext := '';
    if AResult.Metadata.ContainsKey('chat.persistent_context') then
      LPersistentContext := Trim(AResult.Metadata['chat.persistent_context']);

    if LRelevantContext <> '' then
    begin
      LBuilder.AppendLine('relevant:');
      LBuilder.AppendLine(LRelevantContext);
    end;

    if LPersistentContext <> '' then
    begin
      LBuilder.AppendLine('persistent:');
      LBuilder.AppendLine(LPersistentContext);
    end;

    Result := Trim(LBuilder.ToString);
  finally
    LBuilder.Free;
  end;
end;

function TYakkoRAGManager.ToDebugString: string;
begin
  Result := Format(
    'TYakkoRAGManager(Knowledge=%s, Inventory=%s, Chat=%s, OwnsKnowledge=%s, OwnsInventory=%s, OwnsChat=%s)',
    [
      FKnowledgeMemory.ToDebugString,
      FInventoryMemory.ToDebugString,
      FChatMemory.ToDebugString,
      BoolToStr(FOwnsKnowledgeMemory, True),
      BoolToStr(FOwnsInventoryMemory, True),
      BoolToStr(FOwnsChatMemory, True)
    ]
  );
end;

end.
