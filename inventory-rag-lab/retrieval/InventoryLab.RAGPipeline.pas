unit InventoryLab.RAGPipeline;

{ Deterministic RAG query pipeline for the inventory lab. }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  InventoryLab.Models,
  InventoryLab.EntityMemory,
  InventoryLab.KnowledgeMemory,
  InventoryLab.RelationshipGraph,
  InventoryLab.ContextAssembler,
  Yakko.RAG.Types,
  Yakko.RAG.ChatMemory,
  Yakko.RAG.Manager;

type
  TInventoryLabRAGPipeline = class
  private
    FEntityMemory: TInventoryLabEntityMemory;
    FKnowledgeMemory: TInventoryLabKnowledgeMemory;
    FRelationshipGraph: TInventoryLabRelationshipGraph;
    FContextAssembler: TInventoryLabContextAssembler;
    FRAGManager: TYakkoRAGManager;

    class function Normalize(const AValue: string): string; static;
    class function ExtractQueryTerms(const AQueryText: string): TArray<string>; static;
    class function QueryHasCategoryHint(const AQueryText, ACategory: string): Boolean; static;
    function ComputeEntityScore(const AQueryText: string;
      AEntity: TYakkoInventoryEntity): Integer;
    procedure ReorderEntitiesByScore(AResult: TYakkoRAGResult;
      const AQueryText: string; AScoreMap: TInventoryLabStringMap);
    procedure ExpandRelationships(AResult: TYakkoRAGResult;
      const AQueryText: string);
    procedure ExpandByQueryTerms(AResult: TYakkoRAGResult;
      const AQueryText: string);
  public
    constructor Create(AEntityMemory: TInventoryLabEntityMemory;
      AKnowledgeMemory: TInventoryLabKnowledgeMemory;
      ARelationshipGraph: TInventoryLabRelationshipGraph);
    destructor Destroy; override;

    function ExecuteQuery(const AQueryText: string;
      AMaxResults: Integer = 12): TInventoryLabPipelineResult;
  end;

implementation

constructor TInventoryLabRAGPipeline.Create(AEntityMemory: TInventoryLabEntityMemory;
  AKnowledgeMemory: TInventoryLabKnowledgeMemory;
  ARelationshipGraph: TInventoryLabRelationshipGraph);
begin
  inherited Create;
  if not Assigned(AEntityMemory) then
    raise EArgumentNilException.Create('AEntityMemory must be assigned.');
  if not Assigned(AKnowledgeMemory) then
    raise EArgumentNilException.Create('AKnowledgeMemory must be assigned.');
  if not Assigned(ARelationshipGraph) then
    raise EArgumentNilException.Create('ARelationshipGraph must be assigned.');

  FEntityMemory := AEntityMemory;
  FKnowledgeMemory := AKnowledgeMemory;
  FRelationshipGraph := ARelationshipGraph;
  FContextAssembler := TInventoryLabContextAssembler.Create;
  FRAGManager := TYakkoRAGManager.CreateWithMemories(
    FKnowledgeMemory.KnowledgeMemory,
    FEntityMemory.InventoryMemory,
    TYakkoChatMemory.Create,
    False,
    False,
    True
  );
end;

destructor TInventoryLabRAGPipeline.Destroy;
begin
  FreeAndNil(FRAGManager);
  FreeAndNil(FContextAssembler);
  inherited;
end;

class function TInventoryLabRAGPipeline.Normalize(const AValue: string): string;
begin
  Result := Trim(LowerCase(AValue));
end;

class function TInventoryLabRAGPipeline.ExtractQueryTerms(
  const AQueryText: string): TArray<string>;
var
  LRawTerms: TArray<string>;
  LTerm: string;
  LClean: string;
  LTerms: TDictionary<string, Boolean>;
  LList: TList<string>;
  LIndex: Integer;

  function CleanTerm(const AValue: string): string;
  const
    CTrimChars = ' .,;:!?()[]{}<>"''`';
  begin
    Result := Trim(AValue);
    while (Result <> '') and (Pos(Result[1], CTrimChars) > 0) do
      Delete(Result, 1, 1);
    while (Result <> '') and (Pos(Result[Length(Result)], CTrimChars) > 0) do
      Delete(Result, Length(Result), 1);
    Result := Normalize(Result);
  end;

  function IsStopWord(const AValue: string): Boolean;
  begin
    Result :=
      (AValue = 'de') or (AValue = 'da') or (AValue = 'do') or
      (AValue = 'das') or (AValue = 'dos') or (AValue = 'a') or
      (AValue = 'o') or (AValue = 'e') or (AValue = 'em') or
      (AValue = 'na') or (AValue = 'no') or (AValue = 'nas') or
      (AValue = 'nos') or (AValue = 'para') or (AValue = 'com') or
        (AValue = 'que') or (AValue = 'essa') or (AValue = 'esse') or
        (AValue = 'funciona') or (AValue = 'funcionar') or (AValue = 'serve');
  end;

begin
  LTerms := TDictionary<string, Boolean>.Create;
  LList := TList<string>.Create;
  try
    LRawTerms := AQueryText.Split([' ', #9, #10, #13], TStringSplitOptions.ExcludeEmpty);
    for LTerm in LRawTerms do
    begin
      LClean := CleanTerm(LTerm);
      if Length(LClean) < 3 then
        Continue;
      if IsStopWord(LClean) then
        Continue;
      LTerms.AddOrSetValue(LClean, True);
    end;

    for LTerm in LTerms.Keys do
      LList.Add(LTerm);

    LList.Sort;
    SetLength(Result, LList.Count);
    for LIndex := 0 to LList.Count - 1 do
      Result[LIndex] := LList[LIndex];
  finally
    LList.Free;
    LTerms.Free;
  end;
end;

class function TInventoryLabRAGPipeline.QueryHasCategoryHint(const AQueryText,
  ACategory: string): Boolean;
var
  LQuery: string;
  LCategory: string;
begin
  LQuery := Normalize(AQueryText);
  LCategory := Normalize(ACategory);

  Result := (LCategory <> '') and
    ((Pos(LCategory, LQuery) > 0)
    or ((LCategory = 'cpu') and (Pos('ryzen', LQuery) > 0))
    or ((LCategory = 'gpu') and ((Pos('rtx', LQuery) > 0) or (Pos('placa de video', LQuery) > 0)))
    or ((LCategory = 'motherboard') and (Pos('b450', LQuery) > 0))
    or ((LCategory = 'psu') and ((Pos('fonte', LQuery) > 0) or (Pos('watt', LQuery) > 0)))
    or ((LCategory = 'ram') and (Pos('memoria', LQuery) > 0)));
end;

function TInventoryLabRAGPipeline.ComputeEntityScore(const AQueryText: string;
  AEntity: TYakkoInventoryEntity): Integer;
var
  LQuery: string;
  LAlias: string;
  LEdges: TInventoryLabRelationEdgeList;
begin
  Result := 0;
  LQuery := Normalize(AQueryText);

  if (Pos(Normalize(AEntity.Id), LQuery) > 0) or (Pos(Normalize(AEntity.Name), LQuery) > 0) then
    Inc(Result, 1000);

  for LAlias in AEntity.Aliases do
  begin
    if Pos(Normalize(LAlias), LQuery) > 0 then
    begin
      Inc(Result, 900);
      Break;
    end;
  end;

  if QueryHasCategoryHint(AQueryText, AEntity.Category) then
    Inc(Result, 300);

  LEdges := FRelationshipGraph.GetOutgoing(AEntity.Id);
  try
    if LEdges.Count > 0 then
      Inc(Result, 200);

    if FRelationshipGraph.GetByType(AEntity.Id, lrtCompatibleWith).Count > 0 then
      Inc(Result, 500);
  finally
    LEdges.Free;
  end;

  Inc(Result, 100);
end;

procedure TInventoryLabRAGPipeline.ReorderEntitiesByScore(AResult: TYakkoRAGResult;
  const AQueryText: string; AScoreMap: TInventoryLabStringMap);
var
  LSorted: TList<TYakkoInventoryEntity>;
  LEntity: TYakkoInventoryEntity;
  LScore: Integer;
begin
  LSorted := TList<TYakkoInventoryEntity>.Create;
  try
    for LEntity in AResult.RetrievedEntities do
    begin
      LSorted.Add(LEntity.Clone);
      LScore := ComputeEntityScore(AQueryText, LEntity);
      AScoreMap.AddOrSetValue(LEntity.Id, IntToStr(LScore));
    end;

    LSorted.Sort(TComparer<TYakkoInventoryEntity>.Construct(
      function(const Left, Right: TYakkoInventoryEntity): Integer
      var
        LScoreLeft: Integer;
        LScoreRight: Integer;
      begin
        LScoreLeft := StrToIntDef(AScoreMap[Left.Id], 0);
        LScoreRight := StrToIntDef(AScoreMap[Right.Id], 0);
        Result := LScoreRight - LScoreLeft;
      end
    ));

    AResult.RetrievedEntities.Clear;
    for LEntity in LSorted do
      AResult.RetrievedEntities.Add(LEntity.Clone);
  finally
    for LEntity in LSorted do
      LEntity.Free;
    LSorted.Free;
  end;
end;

procedure TInventoryLabRAGPipeline.ExpandRelationships(AResult: TYakkoRAGResult;
  const AQueryText: string);
var
  LMentions: TInventoryLabStringList;
  LMentionId: string;
  LEdges: TInventoryLabRelationEdgeList;
  LEdge: TInventoryLabRelationEdge;
  LEntity: TYakkoInventoryEntity;
  LSeen: TDictionary<string, Boolean>;
begin
  LMentions := FEntityMemory.AliasResolver.ExtractMentions(AQueryText);
  LSeen := TDictionary<string, Boolean>.Create;
  try
    for LEntity in AResult.RetrievedEntities do
      LSeen.AddOrSetValue(LowerCase(LEntity.Id), True);

    for LMentionId in LMentions do
    begin
      LEdges := FRelationshipGraph.GetOutgoing(LMentionId);
      try
        for LEdge in LEdges do
        begin
          if LSeen.ContainsKey(LowerCase(LEdge.TargetEntityId)) then
            Continue;

          LEntity := FEntityMemory.FindById(LEdge.TargetEntityId);
          if Assigned(LEntity) then
          begin
            AResult.RetrievedEntities.Add(LEntity);
            LSeen.AddOrSetValue(LowerCase(LEdge.TargetEntityId), True);
            AResult.Diagnostics.AddOrSetValue(
              'relationship.expand.' + LEdge.TargetEntityId,
              LEdge.RelationType.ToKey
            );
          end;
        end;
      finally
        LEdges.Free;
      end;
    end;
  finally
    LSeen.Free;
    LMentions.Free;
  end;
end;

procedure TInventoryLabRAGPipeline.ExpandByQueryTerms(AResult: TYakkoRAGResult;
  const AQueryText: string);
var
  LTerms: TArray<string>;
  LTerm: string;
  LMatches: TYakkoInventoryEntityList;
  LEntity: TYakkoInventoryEntity;
  LSeen: TDictionary<string, Boolean>;
begin
  LSeen := TDictionary<string, Boolean>.Create;
  try
    for LEntity in AResult.RetrievedEntities do
      LSeen.AddOrSetValue(LowerCase(LEntity.Id), True);

    LTerms := ExtractQueryTerms(AQueryText);
    for LTerm in LTerms do
    begin
      LMatches := FEntityMemory.SearchByText(LTerm);
      try
        for LEntity in LMatches do
        begin
          if LSeen.ContainsKey(LowerCase(LEntity.Id)) then
            Continue;

          AResult.RetrievedEntities.Add(LEntity.Clone);
          LSeen.AddOrSetValue(LowerCase(LEntity.Id), True);
          AResult.Diagnostics.AddOrSetValue('term.expand.' + LTerm, 'entity:' + LEntity.Id);
        end;
      finally
        LMatches.Free;
      end;
    end;
  finally
    LSeen.Free;
  end;
end;

function TInventoryLabRAGPipeline.ExecuteQuery(const AQueryText: string;
  AMaxResults: Integer): TInventoryLabPipelineResult;
var
  LRagQuery: TYakkoRAGQuery;
  LRagResult: TYakkoRAGResult;
begin
  Result := TInventoryLabPipelineResult.Create;
  LRagQuery := TYakkoRAGQuery.Create;
  try
    LRagQuery.QueryText := AQueryText;
    LRagQuery.MaxResults := AMaxResults;

    LRagResult := FRAGManager.ExecuteQuery(LRagQuery);
    try
      ExpandByQueryTerms(LRagResult, AQueryText);
      ExpandRelationships(LRagResult, AQueryText);
      ReorderEntitiesByScore(LRagResult, AQueryText, Result.EntityScores);

      Result.RAGResult := LRagResult;
      Result.ContextText := FContextAssembler.BuildContext(Result, FRelationshipGraph);
      Result.Diagnostics.AddOrSetValue('pipeline.query_text', AQueryText);
      Result.Diagnostics.AddOrSetValue('pipeline.entities',
        IntToStr(Result.RAGResult.RetrievedEntities.Count));
      Result.Diagnostics.AddOrSetValue('pipeline.documents',
        IntToStr(Result.RAGResult.RetrievedDocuments.Count));
      Result.Diagnostics.AddOrSetValue('pipeline.chunks',
        IntToStr(Result.RAGResult.RetrievedChunks.Count));
    finally
      LRagResult.Free;
    end;
  finally
    LRagQuery.Free;
  end;
end;

end.
