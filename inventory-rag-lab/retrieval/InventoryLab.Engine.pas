unit InventoryLab.Engine;

{ End-to-end deterministic lab engine for structured inventory RAG. }

interface

uses
  System.SysUtils,
  InventoryLab.Models,
  InventoryLab.JsonLoader,
  InventoryLab.EntityNormalizer,
  InventoryLab.EntityMemory,
  InventoryLab.KnowledgeMemory,
  InventoryLab.RelationshipGraph,
  InventoryLab.RelationshipBuilder,
  InventoryLab.RAGPipeline,
  Yakko.RAG.Types;

type
  TInventoryLabEngine = class
  private
    FEntityMemory: TInventoryLabEntityMemory;
    FKnowledgeMemory: TInventoryLabKnowledgeMemory;
    FRelationshipGraph: TInventoryLabRelationshipGraph;
    FPipeline: TInventoryLabRAGPipeline;
    FRawRecords: TInventoryLabRawRecordList;
    FDiagnostics: TInventoryLabStringMap;
  public
    constructor Create;
    destructor Destroy; override;

    procedure LoadFromDirectory(const ADirectory: string);
    function Query(const AText: string; AMaxResults: Integer = 12): TInventoryLabPipelineResult;

    function ToDebugString: string;

    property Diagnostics: TInventoryLabStringMap read FDiagnostics;
    property EntityMemory: TInventoryLabEntityMemory read FEntityMemory;
    property KnowledgeMemory: TInventoryLabKnowledgeMemory read FKnowledgeMemory;
    property RelationshipGraph: TInventoryLabRelationshipGraph read FRelationshipGraph;
  end;

implementation

constructor TInventoryLabEngine.Create;
begin
  inherited Create;
  FEntityMemory := TInventoryLabEntityMemory.Create;
  FKnowledgeMemory := TInventoryLabKnowledgeMemory.Create;
  FRelationshipGraph := TInventoryLabRelationshipGraph.Create;
  FPipeline := TInventoryLabRAGPipeline.Create(FEntityMemory, FKnowledgeMemory, FRelationshipGraph);
  FRawRecords := TInventoryLabRawRecordList.Create(True);
  FDiagnostics := TInventoryLabStringMap.Create;
end;

destructor TInventoryLabEngine.Destroy;
begin
  FreeAndNil(FDiagnostics);
  FreeAndNil(FRawRecords);
  FreeAndNil(FPipeline);
  FreeAndNil(FRelationshipGraph);
  FreeAndNil(FKnowledgeMemory);
  FreeAndNil(FEntityMemory);
  inherited;
end;

procedure TInventoryLabEngine.LoadFromDirectory(const ADirectory: string);
var
  LRawLoaded: TInventoryLabRawRecordList;
  LRaw: TInventoryLabRawRecord;
  LEntity: TYakkoInventoryEntity;
  LAliases: TInventoryLabStringList;
  LAlias: string;
  LRelationshipBuilder: TInventoryLabRelationshipBuilder;
  LBaseId: string;
  LSuffix: Integer;
  LExistingEntity: TYakkoInventoryEntity;
begin
  FRawRecords.Clear;

  LRawLoaded := TInventoryLabJsonLoader.LoadFromDirectory(ADirectory, FDiagnostics);
  try
    for LRaw in LRawLoaded do
      FRawRecords.Add(LRaw.Clone);
  finally
    LRawLoaded.Free;
  end;

  for LRaw in FRawRecords do
  begin
    LEntity := TInventoryLabEntityNormalizer.NormalizeToEntity(LRaw);
    LAliases := TInventoryLabStringList.Create;
    try
      LBaseId := LEntity.Id;
      LSuffix := 1;
      while True do
      begin
        LExistingEntity := FEntityMemory.FindById(LEntity.Id);
        if not Assigned(LExistingEntity) then
          Break;

        LExistingEntity.Free;
        Inc(LSuffix);
        LEntity.Id := Format('%s_%d', [LBaseId, LSuffix]);
      end;

      if not SameText(LBaseId, LEntity.Id) then
        LEntity.Metadata.AddOrSetValue('canonical_id_base', LBaseId);

      TInventoryLabEntityNormalizer.CollectAliases(LRaw, LEntity, LAliases);
      FEntityMemory.RegisterEntity(LEntity);
      for LAlias in LAliases do
      begin
        if Trim(LAlias) <> '' then
          FEntityMemory.RegisterAlias(LAlias, LEntity.Id);
      end;

      FKnowledgeMemory.RegisterRawRecord(LRaw);
    finally
      LAliases.Free;
      LEntity.Free;
    end;
  end;

  LRelationshipBuilder := TInventoryLabRelationshipBuilder.Create(
    FEntityMemory.AliasResolver,
    FEntityMemory
  );
  try
    LRelationshipBuilder.BuildFromRawRecords(FRawRecords, FRelationshipGraph);
  finally
    LRelationshipBuilder.Free;
  end;

  FDiagnostics.AddOrSetValue('engine.entities', IntToStr(FEntityMemory.EntityCount));
  FDiagnostics.AddOrSetValue('engine.aliases', IntToStr(FEntityMemory.AliasCount));
  FDiagnostics.AddOrSetValue('engine.relationship_edges', IntToStr(FRelationshipGraph.EdgeCount));
end;

function TInventoryLabEngine.Query(const AText: string;
  AMaxResults: Integer): TInventoryLabPipelineResult;
begin
  Result := FPipeline.ExecuteQuery(AText, AMaxResults);
end;

function TInventoryLabEngine.ToDebugString: string;
begin
  Result := Format(
    'TInventoryLabEngine(EntityMemory=%s, KnowledgeMemory=%s, RelationshipGraph=%s)',
    [
      FEntityMemory.ToDebugString,
      FKnowledgeMemory.ToDebugString,
      FRelationshipGraph.ToDebugString
    ]
  );
end;

end.
