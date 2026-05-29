unit InventoryLab.RelationshipBuilder;

{ Deterministic relationship extraction from real JSON-derived records. }

interface

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  InventoryLab.Models,
  InventoryLab.AliasResolver,
  InventoryLab.RelationshipGraph,
  InventoryLab.EntityMemory,
  Yakko.RAG.Types;

type
  TInventoryLabRelationshipBuilder = class
  private
    FAliasResolver: TInventoryLabAliasResolver;
    FEntityMemory: TInventoryLabEntityMemory;
    class function Normalize(const AValue: string): string; static;
    class function DetectRelationType(const AKey, AValue: string;
      out AType: TInventoryLabRelationType): Boolean; static;
    procedure AddRelationsFromText(const ASourceEntityId, AKey, AValue: string;
      AGraph: TInventoryLabRelationshipGraph);
    procedure AddInferredSameSpecRelations(AGraph: TInventoryLabRelationshipGraph);
  public
    constructor Create(AAliasResolver: TInventoryLabAliasResolver;
      AEntityMemory: TInventoryLabEntityMemory);

    procedure BuildFromRawRecords(ARawRecords: TInventoryLabRawRecordList;
      AGraph: TInventoryLabRelationshipGraph);
  end;

implementation

constructor TInventoryLabRelationshipBuilder.Create(
  AAliasResolver: TInventoryLabAliasResolver;
  AEntityMemory: TInventoryLabEntityMemory);
begin
  inherited Create;
  if not Assigned(AAliasResolver) then
    raise EArgumentNilException.Create('AAliasResolver must be assigned.');
  if not Assigned(AEntityMemory) then
    raise EArgumentNilException.Create('AEntityMemory must be assigned.');

  FAliasResolver := AAliasResolver;
  FEntityMemory := AEntityMemory;
end;

class function TInventoryLabRelationshipBuilder.Normalize(const AValue: string): string;
begin
  Result := Trim(LowerCase(AValue));
end;

class function TInventoryLabRelationshipBuilder.DetectRelationType(
  const AKey, AValue: string; out AType: TInventoryLabRelationType): Boolean;
var
  LKey: string;
  LValue: string;
begin
  Result := True;
  LKey := Normalize(AKey);
  LValue := Normalize(AValue);

  if ContainsText(LKey, 'incompat') or ContainsText(LValue, 'incompativel') then
    AType := lrtIncompatibleWith
  else if ContainsText(LKey, 'equival') then
    AType := lrtEquivalentTo
  else if ContainsText(LKey, 'upgrade') then
    AType := lrtUpgradeOf
  else if ContainsText(LKey, 'require') or ContainsText(LKey, 'requer')
    or ContainsText(LValue, 'requer')
  then
    AType := lrtRequires
  else if ContainsText(LKey, 'socket') then
    AType := lrtSameSocket
  else if ContainsText(LKey, 'chipset') then
    AType := lrtSameChipset
  else if ContainsText(LKey, 'platform') or ContainsText(LKey, 'plataforma') then
    AType := lrtSamePlatform
  else if ContainsText(LKey, 'compat') then
    AType := lrtCompatibleWith
  else
    Result := False;
end;

procedure TInventoryLabRelationshipBuilder.AddRelationsFromText(
  const ASourceEntityId, AKey, AValue: string; AGraph: TInventoryLabRelationshipGraph);
var
  LType: TInventoryLabRelationType;
  LMentions: TInventoryLabStringList;
  LTargetId: string;
begin
  if not DetectRelationType(AKey, AValue, LType) then
    Exit;

  LMentions := FAliasResolver.ExtractMentions(AValue);
  try
    for LTargetId in LMentions do
    begin
      if SameText(LTargetId, ASourceEntityId) then
        Continue;

      AGraph.AddRelation(ASourceEntityId, LTargetId, LType, AKey + '=' + AValue);
    end;
  finally
    LMentions.Free;
  end;
end;

procedure TInventoryLabRelationshipBuilder.AddInferredSameSpecRelations(
  AGraph: TInventoryLabRelationshipGraph);
var
  LByText: TYakkoInventoryEntityList;
  LCategoryEntities: TYakkoInventoryEntityList;
  I: Integer;
  J: Integer;
  LA: TYakkoInventoryEntity;
  LB: TYakkoInventoryEntity;
  LSocketA: string;
  LSocketB: string;
  LChipsetA: string;
  LChipsetB: string;
  LPlatformA: string;
  LPlatformB: string;

  function FindSpec(AEntity: TYakkoInventoryEntity; const AContainsKey: string): string;
  var
    LPair: TPair<string, string>;
  begin
    Result := '';
    for LPair in AEntity.Specifications do
    begin
      if ContainsText(LowerCase(LPair.Key), LowerCase(AContainsKey)) then
        Exit(Trim(LPair.Value));
    end;
  end;

begin
  LByText := FEntityMemory.SearchByText('');
  try
    { The inventory search by empty text returns empty in current memory;
      use explicit lookups per known categories as deterministic fallback. }
    LByText.Free;
    LByText := TYakkoInventoryEntityList.Create(True);

    LCategoryEntities := FEntityMemory.SearchByCategory('cpu');
    try
      for I := 0 to LCategoryEntities.Count - 1 do
        LByText.Add(LCategoryEntities[I].Clone);
    finally
      LCategoryEntities.Free;
    end;

    LCategoryEntities := FEntityMemory.SearchByCategory('motherboard');
    try
      for I := 0 to LCategoryEntities.Count - 1 do
        LByText.Add(LCategoryEntities[I].Clone);
    finally
      LCategoryEntities.Free;
    end;

    LCategoryEntities := FEntityMemory.SearchByCategory('gpu');
    try
      for I := 0 to LCategoryEntities.Count - 1 do
        LByText.Add(LCategoryEntities[I].Clone);
    finally
      LCategoryEntities.Free;
    end;

    LCategoryEntities := FEntityMemory.SearchByCategory('psu');
    try
      for I := 0 to LCategoryEntities.Count - 1 do
        LByText.Add(LCategoryEntities[I].Clone);
    finally
      LCategoryEntities.Free;
    end;

    for I := 0 to LByText.Count - 1 do
    begin
      LA := LByText[I];
      LSocketA := FindSpec(LA, 'socket');
      LChipsetA := FindSpec(LA, 'chipset');
      LPlatformA := FindSpec(LA, 'platform');

      for J := I + 1 to LByText.Count - 1 do
      begin
        LB := LByText[J];
        LSocketB := FindSpec(LB, 'socket');
        LChipsetB := FindSpec(LB, 'chipset');
        LPlatformB := FindSpec(LB, 'platform');

        if (LSocketA <> '') and SameText(LSocketA, LSocketB) then
        begin
          AGraph.AddRelation(LA.Id, LB.Id, lrtSameSocket, 'inferred:socket=' + LSocketA);
          AGraph.AddRelation(LB.Id, LA.Id, lrtSameSocket, 'inferred:socket=' + LSocketA);
        end;

        if (LChipsetA <> '') and SameText(LChipsetA, LChipsetB) then
        begin
          AGraph.AddRelation(LA.Id, LB.Id, lrtSameChipset, 'inferred:chipset=' + LChipsetA);
          AGraph.AddRelation(LB.Id, LA.Id, lrtSameChipset, 'inferred:chipset=' + LChipsetA);
        end;

        if (LPlatformA <> '') and SameText(LPlatformA, LPlatformB) then
        begin
          AGraph.AddRelation(LA.Id, LB.Id, lrtSamePlatform, 'inferred:platform=' + LPlatformA);
          AGraph.AddRelation(LB.Id, LA.Id, lrtSamePlatform, 'inferred:platform=' + LPlatformA);
        end;
      end;
    end;
  finally
    LByText.Free;
  end;
end;

procedure TInventoryLabRelationshipBuilder.BuildFromRawRecords(
  ARawRecords: TInventoryLabRawRecordList; AGraph: TInventoryLabRelationshipGraph);
var
  LRaw: TInventoryLabRawRecord;
  LPair: TPair<string, string>;
  LLine: string;
  LSourceId: string;
  LEqPos: Integer;
  LKey: string;
  LValue: string;
begin
  if not Assigned(ARawRecords) then
    raise EArgumentNilException.Create('ARawRecords must be assigned.');
  if not Assigned(AGraph) then
    raise EArgumentNilException.Create('AGraph must be assigned.');

  for LRaw in ARawRecords do
  begin
    LSourceId := FAliasResolver.ResolveExact(LRaw.PartNumber);
    if LSourceId = '' then
      LSourceId := FAliasResolver.ResolveExact(LRaw.DisplayName);
    if LSourceId = '' then
      Continue;

    for LPair in LRaw.FlatScalars do
      AddRelationsFromText(LSourceId, LPair.Key, LPair.Value, AGraph);

    for LLine in LRaw.ArrayLines do
    begin
      LEqPos := Pos('=', LLine);
      if LEqPos <= 0 then
        Continue;

      LKey := Copy(LLine, 1, LEqPos - 1);
      LValue := Copy(LLine, LEqPos + 1, MaxInt);
      AddRelationsFromText(LSourceId, LKey, LValue, AGraph);
    end;
  end;

  AddInferredSameSpecRelations(AGraph);
end;

end.
