unit Yakko.RAG.Types;

{ Deterministic RAG domain types for YakkoDelphiLLM runtime.

  Architectural intent:
  - provide explicit and auditable RAG data structures;
  - keep ownership boundaries clear and predictable;
  - prepare future semantic retrieval without changing current behavior.

  This unit intentionally avoids embeddings, async execution, reflection and
  external framework dependencies. }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Yakko.ConversationState;

type
  TYakkoStringList = TList<string>;
  TYakkoStringMap = TDictionary<string, string>;

  TYakkoKnowledgeDocument = class
  private
    FId: string;
    FSource: string;
    FTitle: string;
    FContent: string;
    FCategory: string;
    FTags: TYakkoStringList;
    FMetadata: TYakkoStringMap;
    FCreatedAt: TDateTime;
    FUpdatedAt: TDateTime;
  public
    constructor Create;
    destructor Destroy; override;

    function Clone: TYakkoKnowledgeDocument;
    function ToDebugString: string;

    property Id: string read FId write FId;
    property Source: string read FSource write FSource;
    property Title: string read FTitle write FTitle;
    property Content: string read FContent write FContent;
    property Category: string read FCategory write FCategory;
    property Tags: TYakkoStringList read FTags;
    property Metadata: TYakkoStringMap read FMetadata;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
    property UpdatedAt: TDateTime read FUpdatedAt write FUpdatedAt;
  end;

  TYakkoKnowledgeChunk = class
  private
    FChunkId: string;
    FDocumentId: string;
    FText: string;
    FChunkIndex: Integer;
    FMetadata: TYakkoStringMap;
    FTags: TYakkoStringList;
  public
    constructor Create;
    destructor Destroy; override;

    function Clone: TYakkoKnowledgeChunk;
    function ToDebugString: string;

    property ChunkId: string read FChunkId write FChunkId;
    property DocumentId: string read FDocumentId write FDocumentId;
    property Text: string read FText write FText;
    property ChunkIndex: Integer read FChunkIndex write FChunkIndex;
    property Metadata: TYakkoStringMap read FMetadata;
    property Tags: TYakkoStringList read FTags;
  end;

  TYakkoInventoryEntity = class
  private
    FId: string;
    FName: string;
    FBrand: string;
    FCategory: string;
    FDescription: string;
    FSpecifications: TYakkoStringMap;
    FCompatibleWith: TYakkoStringList;
    FAliases: TYakkoStringList;
    FMetadata: TYakkoStringMap;
  public
    constructor Create;
    destructor Destroy; override;

    function Clone: TYakkoInventoryEntity;
    function ToDebugString: string;

    property Id: string read FId write FId;
    property Name: string read FName write FName;
    property Brand: string read FBrand write FBrand;
    property Category: string read FCategory write FCategory;
    property Description: string read FDescription write FDescription;
    property Specifications: TYakkoStringMap read FSpecifications;
    property CompatibleWith: TYakkoStringList read FCompatibleWith;
    property Aliases: TYakkoStringList read FAliases;
    property Metadata: TYakkoStringMap read FMetadata;
  end;

  TYakkoKnowledgeDocumentList = TObjectList<TYakkoKnowledgeDocument>;
  TYakkoKnowledgeChunkList = TObjectList<TYakkoKnowledgeChunk>;
  TYakkoInventoryEntityList = TObjectList<TYakkoInventoryEntity>;

  TYakkoRAGQuery = class
  private
    FQueryText: string;
    FConversationState: TYakkoConversationState;
    FMetadata: TYakkoStringMap;
    FMaxResults: Integer;
    FCategories: TYakkoStringList;
    FTags: TYakkoStringList;
    procedure SetConversationState(const Value: TYakkoConversationState);
  public
    constructor Create;
    destructor Destroy; override;

    function Clone: TYakkoRAGQuery;
    function ToDebugString: string;

    property QueryText: string read FQueryText write FQueryText;
    property ConversationState: TYakkoConversationState read FConversationState write SetConversationState;
    property Metadata: TYakkoStringMap read FMetadata;
    property MaxResults: Integer read FMaxResults write FMaxResults;
    property Categories: TYakkoStringList read FCategories;
    property Tags: TYakkoStringList read FTags;
  end;

  TYakkoRAGResult = class
  private
    FRetrievedDocuments: TYakkoKnowledgeDocumentList;
    FRetrievedChunks: TYakkoKnowledgeChunkList;
    FRetrievedEntities: TYakkoInventoryEntityList;
    FDiagnostics: TYakkoStringMap;
    FMetadata: TYakkoStringMap;
  public
    constructor Create;
    destructor Destroy; override;

    procedure AddRetrievedDocument(ADocument: TYakkoKnowledgeDocument);
    procedure AddRetrievedChunk(AChunk: TYakkoKnowledgeChunk);
    procedure AddRetrievedEntity(AEntity: TYakkoInventoryEntity);

    function Clone: TYakkoRAGResult;
    function ToDebugString: string;

    property RetrievedDocuments: TYakkoKnowledgeDocumentList read FRetrievedDocuments;
    property RetrievedChunks: TYakkoKnowledgeChunkList read FRetrievedChunks;
    property RetrievedEntities: TYakkoInventoryEntityList read FRetrievedEntities;
    property Diagnostics: TYakkoStringMap read FDiagnostics;
    property Metadata: TYakkoStringMap read FMetadata;
  end;

implementation

procedure CloneStringMap(ASource, ADest: TYakkoStringMap);
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

procedure CloneStringList(ASource, ADest: TYakkoStringList);
var
  LValue: string;
begin
  if not Assigned(ADest) then
    raise EArgumentNilException.Create('ADest must be assigned.');

  ADest.Clear;
  if not Assigned(ASource) then
    Exit;

  for LValue in ASource do
    ADest.Add(LValue);
end;

{ TYakkoKnowledgeDocument }

constructor TYakkoKnowledgeDocument.Create;
begin
  inherited Create;
  FId := '';
  FSource := '';
  FTitle := '';
  FContent := '';
  FCategory := '';
  FTags := TYakkoStringList.Create;
  FMetadata := TYakkoStringMap.Create;
  FCreatedAt := Now;
  FUpdatedAt := FCreatedAt;
end;

destructor TYakkoKnowledgeDocument.Destroy;
begin
  FreeAndNil(FMetadata);
  FreeAndNil(FTags);
  inherited;
end;

function TYakkoKnowledgeDocument.Clone: TYakkoKnowledgeDocument;
begin
  Result := TYakkoKnowledgeDocument.Create;
  try
    Result.FId := FId;
    Result.FSource := FSource;
    Result.FTitle := FTitle;
    Result.FContent := FContent;
    Result.FCategory := FCategory;
    Result.FCreatedAt := FCreatedAt;
    Result.FUpdatedAt := FUpdatedAt;
    CloneStringList(FTags, Result.FTags);
    CloneStringMap(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoKnowledgeDocument.ToDebugString: string;
begin
  Result := Format(
    'TYakkoKnowledgeDocument(Id=%s, Source=%s, Title=%s, Category=%s, Tags=%d, Metadata=%d, CreatedAt=%s, UpdatedAt=%s, ContentLength=%d)',
    [
      FId,
      FSource,
      FTitle,
      FCategory,
      FTags.Count,
      FMetadata.Count,
      DateTimeToStr(FCreatedAt),
      DateTimeToStr(FUpdatedAt),
      Length(FContent)
    ]
  );
end;

{ TYakkoKnowledgeChunk }

constructor TYakkoKnowledgeChunk.Create;
begin
  inherited Create;
  FChunkId := '';
  FDocumentId := '';
  FText := '';
  FChunkIndex := 0;
  FMetadata := TYakkoStringMap.Create;
  FTags := TYakkoStringList.Create;
end;

destructor TYakkoKnowledgeChunk.Destroy;
begin
  FreeAndNil(FTags);
  FreeAndNil(FMetadata);
  inherited;
end;

function TYakkoKnowledgeChunk.Clone: TYakkoKnowledgeChunk;
begin
  Result := TYakkoKnowledgeChunk.Create;
  try
    Result.FChunkId := FChunkId;
    Result.FDocumentId := FDocumentId;
    Result.FText := FText;
    Result.FChunkIndex := FChunkIndex;
    CloneStringMap(FMetadata, Result.FMetadata);
    CloneStringList(FTags, Result.FTags);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoKnowledgeChunk.ToDebugString: string;
begin
  Result := Format(
    'TYakkoKnowledgeChunk(ChunkId=%s, DocumentId=%s, ChunkIndex=%d, Tags=%d, Metadata=%d, TextLength=%d)',
    [FChunkId, FDocumentId, FChunkIndex, FTags.Count, FMetadata.Count, Length(FText)]
  );
end;

{ TYakkoInventoryEntity }

constructor TYakkoInventoryEntity.Create;
begin
  inherited Create;
  FId := '';
  FName := '';
  FBrand := '';
  FCategory := '';
  FDescription := '';
  FSpecifications := TYakkoStringMap.Create;
  FCompatibleWith := TYakkoStringList.Create;
  FAliases := TYakkoStringList.Create;
  FMetadata := TYakkoStringMap.Create;
end;

destructor TYakkoInventoryEntity.Destroy;
begin
  FreeAndNil(FMetadata);
  FreeAndNil(FAliases);
  FreeAndNil(FCompatibleWith);
  FreeAndNil(FSpecifications);
  inherited;
end;

function TYakkoInventoryEntity.Clone: TYakkoInventoryEntity;
begin
  Result := TYakkoInventoryEntity.Create;
  try
    Result.FId := FId;
    Result.FName := FName;
    Result.FBrand := FBrand;
    Result.FCategory := FCategory;
    Result.FDescription := FDescription;
    CloneStringMap(FSpecifications, Result.FSpecifications);
    CloneStringList(FCompatibleWith, Result.FCompatibleWith);
    CloneStringList(FAliases, Result.FAliases);
    CloneStringMap(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoInventoryEntity.ToDebugString: string;
begin
  Result := Format(
    'TYakkoInventoryEntity(Id=%s, Name=%s, Brand=%s, Category=%s, Specs=%d, CompatibleWith=%d, Aliases=%d, Metadata=%d, DescriptionLength=%d)',
    [
      FId,
      FName,
      FBrand,
      FCategory,
      FSpecifications.Count,
      FCompatibleWith.Count,
      FAliases.Count,
      FMetadata.Count,
      Length(FDescription)
    ]
  );
end;

{ TYakkoRAGQuery }

constructor TYakkoRAGQuery.Create;
begin
  inherited Create;
  FQueryText := '';
  FConversationState := nil;
  FMetadata := TYakkoStringMap.Create;
  FMaxResults := 10;
  FCategories := TYakkoStringList.Create;
  FTags := TYakkoStringList.Create;
end;

destructor TYakkoRAGQuery.Destroy;
begin
  FreeAndNil(FTags);
  FreeAndNil(FCategories);
  FreeAndNil(FMetadata);
  FreeAndNil(FConversationState);
  inherited;
end;

procedure TYakkoRAGQuery.SetConversationState(
  const Value: TYakkoConversationState);
begin
  FreeAndNil(FConversationState);
  if Assigned(Value) then
    FConversationState := Value.Clone;
end;

function TYakkoRAGQuery.Clone: TYakkoRAGQuery;
begin
  Result := TYakkoRAGQuery.Create;
  try
    Result.FQueryText := FQueryText;
    if Assigned(FConversationState) then
      Result.FConversationState := FConversationState.Clone;
    CloneStringMap(FMetadata, Result.FMetadata);
    Result.FMaxResults := FMaxResults;
    CloneStringList(FCategories, Result.FCategories);
    CloneStringList(FTags, Result.FTags);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoRAGQuery.ToDebugString: string;
begin
  Result := Format(
    'TYakkoRAGQuery(QueryLength=%d, HasConversationState=%s, Metadata=%d, MaxResults=%d, Categories=%d, Tags=%d)',
    [
      Length(FQueryText),
      BoolToStr(Assigned(FConversationState), True),
      FMetadata.Count,
      FMaxResults,
      FCategories.Count,
      FTags.Count
    ]
  );
end;

{ TYakkoRAGResult }

constructor TYakkoRAGResult.Create;
begin
  inherited Create;
  FRetrievedDocuments := TYakkoKnowledgeDocumentList.Create(True);
  FRetrievedChunks := TYakkoKnowledgeChunkList.Create(True);
  FRetrievedEntities := TYakkoInventoryEntityList.Create(True);
  FDiagnostics := TYakkoStringMap.Create;
  FMetadata := TYakkoStringMap.Create;
end;

destructor TYakkoRAGResult.Destroy;
begin
  FreeAndNil(FMetadata);
  FreeAndNil(FDiagnostics);
  FreeAndNil(FRetrievedEntities);
  FreeAndNil(FRetrievedChunks);
  FreeAndNil(FRetrievedDocuments);
  inherited;
end;

procedure TYakkoRAGResult.AddRetrievedDocument(ADocument: TYakkoKnowledgeDocument);
begin
  if not Assigned(ADocument) then
    raise EArgumentNilException.Create('ADocument must be assigned.');

  { Ownership is transferred to TYakkoRAGResult once the document is added. }
  FRetrievedDocuments.Add(ADocument);
end;

procedure TYakkoRAGResult.AddRetrievedChunk(AChunk: TYakkoKnowledgeChunk);
begin
  if not Assigned(AChunk) then
    raise EArgumentNilException.Create('AChunk must be assigned.');

  { Ownership is transferred to TYakkoRAGResult once the chunk is added. }
  FRetrievedChunks.Add(AChunk);
end;

procedure TYakkoRAGResult.AddRetrievedEntity(AEntity: TYakkoInventoryEntity);
begin
  if not Assigned(AEntity) then
    raise EArgumentNilException.Create('AEntity must be assigned.');

  { Ownership is transferred to TYakkoRAGResult once the entity is added. }
  FRetrievedEntities.Add(AEntity);
end;

function TYakkoRAGResult.Clone: TYakkoRAGResult;
var
  LDocument: TYakkoKnowledgeDocument;
  LChunk: TYakkoKnowledgeChunk;
  LEntity: TYakkoInventoryEntity;
begin
  Result := TYakkoRAGResult.Create;
  try
    for LDocument in FRetrievedDocuments do
      Result.FRetrievedDocuments.Add(LDocument.Clone);

    for LChunk in FRetrievedChunks do
      Result.FRetrievedChunks.Add(LChunk.Clone);

    for LEntity in FRetrievedEntities do
      Result.FRetrievedEntities.Add(LEntity.Clone);

    CloneStringMap(FDiagnostics, Result.FDiagnostics);
    CloneStringMap(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoRAGResult.ToDebugString: string;
begin
  Result := Format(
    'TYakkoRAGResult(Documents=%d, Chunks=%d, Entities=%d, Diagnostics=%d, Metadata=%d)',
    [
      FRetrievedDocuments.Count,
      FRetrievedChunks.Count,
      FRetrievedEntities.Count,
      FDiagnostics.Count,
      FMetadata.Count
    ]
  );
end;

end.