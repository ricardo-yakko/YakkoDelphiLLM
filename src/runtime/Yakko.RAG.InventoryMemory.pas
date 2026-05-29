unit Yakko.RAG.InventoryMemory;

{ Deterministic inventory memory for first RAG layer.

  Responsibilities:
  - register structured inventory entities;
  - resolve aliases;
  - search by category, brand and simple text;
  - expose compatibility and equivalence queries.

  This unit intentionally does not use probabilistic matching. }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Yakko.RAG.Types;

type
  TYakkoInventoryMemory = class
  private
    FEntities: TYakkoInventoryEntityList;
    FAliases: TYakkoStringMap;
    FEquivalences: TDictionary<string, TYakkoStringList>;
    function FindEntityByIdInternal(const AEntityId: string): TYakkoInventoryEntity;
    function ResolveEntityId(const AEntityOrAlias: string): string;
    class function Normalize(const AValue: string): string; static;
    class function TextContains(const AText, ATerm: string): Boolean; static;
    class function ListContainsText(AList: TYakkoStringList; const AValue: string): Boolean; static;
    procedure AddEquivalenceOneWay(const AEntityId, AEquivalentId: string);
  public
    constructor Create;
    destructor Destroy; override;

    procedure RegisterEntity(AEntity: TYakkoInventoryEntity);
    procedure RegisterAlias(const AAlias, AEntityId: string);
    procedure RegisterEquivalence(const AEntityId, AEquivalentEntityId: string);

    function SearchByCategory(const ACategory: string): TYakkoInventoryEntityList;
    function SearchByBrand(const ABrand: string): TYakkoInventoryEntityList;
    function SearchByAlias(const AAlias: string): TYakkoInventoryEntityList;
    function SearchByName(const AName: string): TYakkoInventoryEntityList;
    function SearchByText(const AText: string): TYakkoInventoryEntityList;
    function SearchCompatibleWith(const AEntityOrAlias: string): TYakkoInventoryEntityList;
    function SearchEquivalentTo(const AEntityOrAlias: string): TYakkoInventoryEntityList;
    function AreCompatible(const ALeftEntityOrAlias, ARightEntityOrAlias: string): Boolean;

    function EntityCount: Integer;
    function AliasCount: Integer;
    function ToDebugString: string;
  end;

implementation

constructor TYakkoInventoryMemory.Create;
begin
  inherited Create;
  FEntities := TYakkoInventoryEntityList.Create(True);
  FAliases := TYakkoStringMap.Create;
  FEquivalences := TDictionary<string, TYakkoStringList>.Create;
end;

destructor TYakkoInventoryMemory.Destroy;
var
  LList: TYakkoStringList;
begin
  for LList in FEquivalences.Values do
    LList.Free;

  FreeAndNil(FEquivalences);
  FreeAndNil(FAliases);
  FreeAndNil(FEntities);
  inherited;
end;

class function TYakkoInventoryMemory.Normalize(const AValue: string): string;
begin
  Result := Trim(LowerCase(AValue));
end;

class function TYakkoInventoryMemory.TextContains(const AText, ATerm: string): Boolean;
begin
  Result := Pos(Normalize(ATerm), Normalize(AText)) > 0;
end;

class function TYakkoInventoryMemory.ListContainsText(AList: TYakkoStringList;
  const AValue: string): Boolean;
var
  LItem: string;
begin
  Result := False;
  if not Assigned(AList) then
    Exit;

  for LItem in AList do
  begin
    if SameText(Trim(LItem), Trim(AValue)) then
      Exit(True);
  end;
end;

function TYakkoInventoryMemory.FindEntityByIdInternal(
  const AEntityId: string): TYakkoInventoryEntity;
var
  LEntity: TYakkoInventoryEntity;
begin
  Result := nil;
  for LEntity in FEntities do
  begin
    if SameText(Trim(LEntity.Id), Trim(AEntityId)) then
      Exit(LEntity);
  end;
end;

function TYakkoInventoryMemory.ResolveEntityId(const AEntityOrAlias: string): string;
var
  LEntity: TYakkoInventoryEntity;
begin
  Result := '';
  if Trim(AEntityOrAlias) = '' then
    Exit;

  if FAliases.TryGetValue(Normalize(AEntityOrAlias), Result) then
    Exit;

  for LEntity in FEntities do
  begin
    if SameText(Trim(LEntity.Id), Trim(AEntityOrAlias))
      or SameText(Trim(LEntity.Name), Trim(AEntityOrAlias))
      or ListContainsText(LEntity.Aliases, AEntityOrAlias)
    then
      Exit(LEntity.Id);
  end;
end;

procedure TYakkoInventoryMemory.RegisterEntity(AEntity: TYakkoInventoryEntity);
var
  LAlias: string;
begin
  if not Assigned(AEntity) then
    raise EArgumentNilException.Create('AEntity must be assigned.');

  if Trim(AEntity.Id) = '' then
    raise EArgumentException.Create('AEntity.Id must not be empty.');

  if Assigned(FindEntityByIdInternal(AEntity.Id)) then
    raise EInvalidOpException.CreateFmt('Inventory entity "%s" already exists.', [AEntity.Id]);

  { Ownership is transferred to TYakkoInventoryMemory once the entity is added. }
  FEntities.Add(AEntity);

  for LAlias in AEntity.Aliases do
    RegisterAlias(LAlias, AEntity.Id);
end;

procedure TYakkoInventoryMemory.RegisterAlias(const AAlias, AEntityId: string);
begin
  if Trim(AAlias) = '' then
    raise EArgumentException.Create('AAlias must not be empty.');

  if Trim(AEntityId) = '' then
    raise EArgumentException.Create('AEntityId must not be empty.');

  if not Assigned(FindEntityByIdInternal(AEntityId)) then
    raise EInvalidOpException.CreateFmt('Entity "%s" not found for alias "%s".', [AEntityId, AAlias]);

  FAliases.AddOrSetValue(Normalize(AAlias), Trim(AEntityId));
end;

procedure TYakkoInventoryMemory.AddEquivalenceOneWay(const AEntityId,
  AEquivalentId: string);
var
  LList: TYakkoStringList;
begin
  if not FEquivalences.TryGetValue(Trim(AEntityId), LList) then
  begin
    LList := TYakkoStringList.Create;
    FEquivalences.Add(Trim(AEntityId), LList);
  end;

  if not ListContainsText(LList, AEquivalentId) then
    LList.Add(Trim(AEquivalentId));
end;

procedure TYakkoInventoryMemory.RegisterEquivalence(const AEntityId,
  AEquivalentEntityId: string);
begin
  if Trim(AEntityId) = '' then
    raise EArgumentException.Create('AEntityId must not be empty.');

  if Trim(AEquivalentEntityId) = '' then
    raise EArgumentException.Create('AEquivalentEntityId must not be empty.');

  if not Assigned(FindEntityByIdInternal(AEntityId)) then
    raise EInvalidOpException.CreateFmt('Entity "%s" not found.', [AEntityId]);

  if not Assigned(FindEntityByIdInternal(AEquivalentEntityId)) then
    raise EInvalidOpException.CreateFmt('Entity "%s" not found.', [AEquivalentEntityId]);

  AddEquivalenceOneWay(AEntityId, AEquivalentEntityId);
  AddEquivalenceOneWay(AEquivalentEntityId, AEntityId);
end;

function TYakkoInventoryMemory.SearchByCategory(
  const ACategory: string): TYakkoInventoryEntityList;
var
  LEntity: TYakkoInventoryEntity;
begin
  Result := TYakkoInventoryEntityList.Create(True);
  try
    if Trim(ACategory) = '' then
      Exit;

    for LEntity in FEntities do
    begin
      if SameText(Trim(LEntity.Category), Trim(ACategory)) then
        Result.Add(LEntity.Clone);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoInventoryMemory.SearchByBrand(
  const ABrand: string): TYakkoInventoryEntityList;
var
  LEntity: TYakkoInventoryEntity;
begin
  Result := TYakkoInventoryEntityList.Create(True);
  try
    if Trim(ABrand) = '' then
      Exit;

    for LEntity in FEntities do
    begin
      if SameText(Trim(LEntity.Brand), Trim(ABrand)) then
        Result.Add(LEntity.Clone);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoInventoryMemory.SearchByAlias(
  const AAlias: string): TYakkoInventoryEntityList;
var
  LEntityId: string;
  LEntity: TYakkoInventoryEntity;
begin
  Result := TYakkoInventoryEntityList.Create(True);
  try
    if Trim(AAlias) = '' then
      Exit;

    if FAliases.TryGetValue(Normalize(AAlias), LEntityId) then
    begin
      LEntity := FindEntityByIdInternal(LEntityId);
      if Assigned(LEntity) then
        Result.Add(LEntity.Clone);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoInventoryMemory.SearchByName(
  const AName: string): TYakkoInventoryEntityList;
var
  LEntity: TYakkoInventoryEntity;
begin
  Result := TYakkoInventoryEntityList.Create(True);
  try
    if Trim(AName) = '' then
      Exit;

    for LEntity in FEntities do
    begin
      if TextContains(LEntity.Name, AName)
        or SameText(Trim(LEntity.Id), Trim(AName))
      then
        Result.Add(LEntity.Clone);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoInventoryMemory.SearchByText(
  const AText: string): TYakkoInventoryEntityList;
var
  LEntity: TYakkoInventoryEntity;
  LSpec: TPair<string, string>;
begin
  Result := TYakkoInventoryEntityList.Create(True);
  try
    if Trim(AText) = '' then
      Exit;

    for LEntity in FEntities do
    begin
      if TextContains(LEntity.Name, AText)
        or TextContains(LEntity.Brand, AText)
        or TextContains(LEntity.Category, AText)
        or TextContains(LEntity.Description, AText)
      then
      begin
        Result.Add(LEntity.Clone);
        Continue;
      end;

      for LSpec in LEntity.Specifications do
      begin
        if TextContains(LSpec.Key, AText) or TextContains(LSpec.Value, AText) then
        begin
          Result.Add(LEntity.Clone);
          Break;
        end;
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoInventoryMemory.SearchCompatibleWith(
  const AEntityOrAlias: string): TYakkoInventoryEntityList;
var
  LTargetId: string;
  LEntity: TYakkoInventoryEntity;
begin
  Result := TYakkoInventoryEntityList.Create(True);
  try
    LTargetId := ResolveEntityId(AEntityOrAlias);
    if LTargetId = '' then
      Exit;

    for LEntity in FEntities do
    begin
      if SameText(Trim(LEntity.Id), LTargetId) then
        Continue;

      if ListContainsText(LEntity.CompatibleWith, LTargetId)
        or ListContainsText(LEntity.CompatibleWith, AEntityOrAlias)
      then
        Result.Add(LEntity.Clone);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoInventoryMemory.SearchEquivalentTo(
  const AEntityOrAlias: string): TYakkoInventoryEntityList;
var
  LTargetId: string;
  LEquivalentIds: TYakkoStringList;
  LEquivalentId: string;
  LEntity: TYakkoInventoryEntity;
begin
  Result := TYakkoInventoryEntityList.Create(True);
  try
    LTargetId := ResolveEntityId(AEntityOrAlias);
    if LTargetId = '' then
      Exit;

    if not FEquivalences.TryGetValue(LTargetId, LEquivalentIds) then
      Exit;

    for LEquivalentId in LEquivalentIds do
    begin
      LEntity := FindEntityByIdInternal(LEquivalentId);
      if Assigned(LEntity) then
        Result.Add(LEntity.Clone);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoInventoryMemory.AreCompatible(const ALeftEntityOrAlias,
  ARightEntityOrAlias: string): Boolean;
var
  LLeftId: string;
  LRightId: string;
  LLeftEntity: TYakkoInventoryEntity;
  LRightEntity: TYakkoInventoryEntity;
begin
  Result := False;

  LLeftId := ResolveEntityId(ALeftEntityOrAlias);
  LRightId := ResolveEntityId(ARightEntityOrAlias);
  if (LLeftId = '') or (LRightId = '') then
    Exit;

  LLeftEntity := FindEntityByIdInternal(LLeftId);
  LRightEntity := FindEntityByIdInternal(LRightId);
  if (not Assigned(LLeftEntity)) or (not Assigned(LRightEntity)) then
    Exit;

  Result :=
    ListContainsText(LLeftEntity.CompatibleWith, LRightId)
    or ListContainsText(LRightEntity.CompatibleWith, LLeftId)
    or ListContainsText(LLeftEntity.CompatibleWith, ARightEntityOrAlias)
    or ListContainsText(LRightEntity.CompatibleWith, ALeftEntityOrAlias);
end;

function TYakkoInventoryMemory.EntityCount: Integer;
begin
  Result := FEntities.Count;
end;

function TYakkoInventoryMemory.AliasCount: Integer;
begin
  Result := FAliases.Count;
end;

function TYakkoInventoryMemory.ToDebugString: string;
begin
  Result := Format(
    'TYakkoInventoryMemory(Entities=%d, Aliases=%d, EquivalenceRoots=%d)',
    [FEntities.Count, FAliases.Count, FEquivalences.Count]
  );
end;

end.