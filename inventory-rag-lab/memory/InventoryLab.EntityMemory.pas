unit InventoryLab.EntityMemory;

{ Entity memory facade around TYakkoInventoryMemory for lab usage. }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  InventoryLab.Models,
  InventoryLab.AliasResolver,
  Yakko.RAG.Types,
  Yakko.RAG.InventoryMemory;

type
  TInventoryLabEntityMemory = class
  private
    FInventoryMemory: TYakkoInventoryMemory;
    FAliasResolver: TInventoryLabAliasResolver;
    FEntitiesById: TObjectDictionary<string, TYakkoInventoryEntity>;
  public
    constructor Create;
    destructor Destroy; override;

    procedure RegisterEntity(AEntity: TYakkoInventoryEntity);
    procedure RegisterAlias(const AAlias, AEntityId: string);

    function FindById(const AEntityId: string): TYakkoInventoryEntity;
    function ResolveEntityId(const AEntityOrAlias: string): string;
    function SearchByText(const AText: string): TYakkoInventoryEntityList;
    function SearchByCategory(const ACategory: string): TYakkoInventoryEntityList;
    function SearchByBrand(const ABrand: string): TYakkoInventoryEntityList;

    function EntityCount: Integer;
    function AliasCount: Integer;
    function ToDebugString: string;

    property InventoryMemory: TYakkoInventoryMemory read FInventoryMemory;
    property AliasResolver: TInventoryLabAliasResolver read FAliasResolver;
  end;

implementation

constructor TInventoryLabEntityMemory.Create;
begin
  inherited Create;
  FInventoryMemory := TYakkoInventoryMemory.Create;
  FAliasResolver := TInventoryLabAliasResolver.Create;
  FEntitiesById := TObjectDictionary<string, TYakkoInventoryEntity>.Create([doOwnsValues]);
end;

destructor TInventoryLabEntityMemory.Destroy;
begin
  FreeAndNil(FEntitiesById);
  FreeAndNil(FAliasResolver);
  FreeAndNil(FInventoryMemory);
  inherited;
end;

procedure TInventoryLabEntityMemory.RegisterEntity(AEntity: TYakkoInventoryEntity);
begin
  if not Assigned(AEntity) then
    raise EArgumentNilException.Create('AEntity must be assigned.');

  if Trim(AEntity.Id) = '' then
    raise EArgumentException.Create('AEntity.Id must not be empty.');

  FInventoryMemory.RegisterEntity(AEntity.Clone);
  FAliasResolver.RegisterEntityAliases(AEntity);
  FEntitiesById.AddOrSetValue(AEntity.Id, AEntity.Clone);
end;

procedure TInventoryLabEntityMemory.RegisterAlias(const AAlias, AEntityId: string);
begin
  FInventoryMemory.RegisterAlias(AAlias, AEntityId);
end;

function TInventoryLabEntityMemory.FindById(
  const AEntityId: string): TYakkoInventoryEntity;
begin
  Result := nil;
  if FEntitiesById.ContainsKey(AEntityId) then
    Result := FEntitiesById[AEntityId].Clone;
end;

function TInventoryLabEntityMemory.ResolveEntityId(
  const AEntityOrAlias: string): string;
begin
  Result := FAliasResolver.ResolveExact(AEntityOrAlias);
  if Result = '' then
    Result := AEntityOrAlias;
end;

function TInventoryLabEntityMemory.SearchByText(
  const AText: string): TYakkoInventoryEntityList;
begin
  Result := FInventoryMemory.SearchByText(AText);
end;

function TInventoryLabEntityMemory.SearchByCategory(
  const ACategory: string): TYakkoInventoryEntityList;
begin
  Result := FInventoryMemory.SearchByCategory(ACategory);
end;

function TInventoryLabEntityMemory.SearchByBrand(
  const ABrand: string): TYakkoInventoryEntityList;
begin
  Result := FInventoryMemory.SearchByBrand(ABrand);
end;

function TInventoryLabEntityMemory.EntityCount: Integer;
begin
  Result := FInventoryMemory.EntityCount;
end;

function TInventoryLabEntityMemory.AliasCount: Integer;
begin
  Result := FAliasResolver.AliasCount;
end;

function TInventoryLabEntityMemory.ToDebugString: string;
begin
  Result := Format('TInventoryLabEntityMemory(Inventory=%s, AliasResolver=%s)',
    [FInventoryMemory.ToDebugString, FAliasResolver.ToDebugString]);
end;

end.
