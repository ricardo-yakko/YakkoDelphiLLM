unit InventoryLab.AliasResolver;

{ Deterministic alias resolver for canonical inventory entities. }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  InventoryLab.Models,
  Yakko.RAG.Types;

type
  TInventoryLabAliasResolver = class
  private
    FAliasToEntityId: TInventoryLabStringMap;
    function Normalize(const AValue: string): string;
  public
    constructor Create;
    destructor Destroy; override;

    procedure RegisterEntityAliases(AEntity: TYakkoInventoryEntity);
    function ResolveExact(const AValue: string): string;
    function ExtractMentions(const AText: string): TInventoryLabStringList;

    function AliasCount: Integer;
    function ToDebugString: string;
  end;

implementation

constructor TInventoryLabAliasResolver.Create;
begin
  inherited Create;
  FAliasToEntityId := TInventoryLabStringMap.Create;
end;

destructor TInventoryLabAliasResolver.Destroy;
begin
  FreeAndNil(FAliasToEntityId);
  inherited;
end;

function TInventoryLabAliasResolver.Normalize(const AValue: string): string;
begin
  Result := Trim(LowerCase(AValue));
end;

procedure TInventoryLabAliasResolver.RegisterEntityAliases(
  AEntity: TYakkoInventoryEntity);
var
  LAlias: string;
begin
  if not Assigned(AEntity) then
    raise EArgumentNilException.Create('AEntity must be assigned.');

  if Trim(AEntity.Id) = '' then
    raise EArgumentException.Create('AEntity.Id must not be empty.');

  FAliasToEntityId.AddOrSetValue(Normalize(AEntity.Id), AEntity.Id);
  FAliasToEntityId.AddOrSetValue(Normalize(AEntity.Name), AEntity.Id);

  for LAlias in AEntity.Aliases do
  begin
    if Trim(LAlias) <> '' then
      FAliasToEntityId.AddOrSetValue(Normalize(LAlias), AEntity.Id);
  end;
end;

function TInventoryLabAliasResolver.ResolveExact(const AValue: string): string;
begin
  Result := '';
  FAliasToEntityId.TryGetValue(Normalize(AValue), Result);
end;

function TInventoryLabAliasResolver.ExtractMentions(
  const AText: string): TInventoryLabStringList;
var
  LAliases: TList<string>;
  LAlias: string;
  LNormalizedText: string;
  LEntityId: string;
  LAdded: TDictionary<string, Boolean>;
begin
  Result := TInventoryLabStringList.Create;
  LAdded := TDictionary<string, Boolean>.Create;
  try
    LAliases := TList<string>.Create;
    try
      for LAlias in FAliasToEntityId.Keys do
        LAliases.Add(LAlias);

      { Longest alias first reduces accidental partial matches. }
      LAliases.Sort(TComparer<string>.Construct(
        function(const Left, Right: string): Integer
        begin
          Result := Length(Right) - Length(Left);
        end
      ));

      LNormalizedText := Normalize(AText);
      for LAlias in LAliases do
      begin
        if (LAlias = '') or (Length(LAlias) < 2) then
          Continue;

        if Pos(LAlias, LNormalizedText) > 0 then
        begin
          LEntityId := FAliasToEntityId[LAlias];
          if not LAdded.ContainsKey(LEntityId) then
          begin
            LAdded.Add(LEntityId, True);
            Result.Add(LEntityId);
          end;
        end;
      end;
    finally
      LAliases.Free;
    end;
  finally
    LAdded.Free;
  end;
end;

function TInventoryLabAliasResolver.AliasCount: Integer;
begin
  Result := FAliasToEntityId.Count;
end;

function TInventoryLabAliasResolver.ToDebugString: string;
begin
  Result := Format('TInventoryLabAliasResolver(Aliases=%d)', [FAliasToEntityId.Count]);
end;

end.
