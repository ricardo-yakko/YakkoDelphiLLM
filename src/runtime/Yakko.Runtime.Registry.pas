unit Yakko.Runtime.Registry;

{ Explicit runtime registry layer for YakkoDelphiLLM.

  Architectural intent:
  - provide an explicit registry for runtime-capable items;
  - avoid large if/else dispatch blocks and scattered string-based factories;
  - prepare a safer multi-model, multi-provider and multi-template future;
  - keep registration synchronous, explicit and easy to trace.

  Registry vs DI container:
  - a registry stores explicit known items;
  - a DI container resolves object graphs and dependencies dynamically;
  - this unit intentionally stays at registry level only and does not resolve
    dependencies, scan RTTI or auto-discover implementations.

  This unit is intentionally simple and synchronous in this phase:
  no DI container, no plugin loading, no RTTI scanning, no singleton, no remote
  registry and no persistence yet. }

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Generics.Collections;

type
  TYakkoRegistryItemType =
  (
    ritModel,
    ritProvider,
    ritTemplate,
    ritPipeline,
    ritTool
  );

  TYakkoRegistryItemTypeHelper = record helper for TYakkoRegistryItemType
  public
    function ToString: string;
  end;

  TYakkoRegistryMetadata = TDictionary<string, string>;

  TYakkoRegistryItem = class
  private
    FName: string;
    FItemType: TYakkoRegistryItemType;
    FMetadata: TYakkoRegistryMetadata;
    FCreatedAt: TDateTime;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    function Clone: TYakkoRegistryItem;
    function ToDebugString: string;

    property Name: string read FName write FName;
    property ItemType: TYakkoRegistryItemType read FItemType write FItemType;
    property Metadata: TYakkoRegistryMetadata read FMetadata;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
  end;

  TYakkoRuntimeRegistry = class
  private
    FItems: TObjectList<TYakkoRegistryItem>;
  public
    constructor Create;
    destructor Destroy; override;

    procedure RegisterItem(AItem: TYakkoRegistryItem);
    function FindByName(const AName: string): TYakkoRegistryItem;
    function FindByType(AType: TYakkoRegistryItemType): TObjectList<TYakkoRegistryItem>;
    function Contains(const AName: string): Boolean;
  end;

implementation

procedure CloneStringDictionary(ASource, ADest: TYakkoRegistryMetadata);
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

{ TYakkoRegistryItemTypeHelper }

function TYakkoRegistryItemTypeHelper.ToString: string;
begin
  case Self of
    ritModel:
      Result := 'model';
    ritProvider:
      Result := 'provider';
    ritTemplate:
      Result := 'template';
    ritPipeline:
      Result := 'pipeline';
    ritTool:
      Result := 'tool';
  else
    Result := 'model';
  end;
end;

{ TYakkoRegistryItem }

constructor TYakkoRegistryItem.Create;
begin
  inherited Create;
  FName := '';
  FItemType := ritModel;
  FMetadata := TYakkoRegistryMetadata.Create;
  FCreatedAt := Now;
end;

destructor TYakkoRegistryItem.Destroy;
begin
  FreeAndNil(FMetadata);
  inherited;
end;

procedure TYakkoRegistryItem.Clear;
begin
  FName := '';
  FItemType := ritModel;
  FMetadata.Clear;
  FCreatedAt := Now;

  { TODO: add item snapshots for registry replay and migration auditing. }
  { TODO: add lazy-load metadata markers for future registry providers. }
  { TODO: add capability negotiation metadata for multi-model and multi-provider setups. }
end;

function TYakkoRegistryItem.Clone: TYakkoRegistryItem;
begin
  Result := TYakkoRegistryItem.Create;
  try
    Result.FName := FName;
    Result.FItemType := FItemType;
    Result.FCreatedAt := FCreatedAt;
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoRegistryItem.ToDebugString: string;
begin
  Result := Format(
    'TYakkoRegistryItem(Name=%s, ItemType=%s, CreatedAt=%s, Metadata=%d)',
    [
      FName,
      FItemType.ToString,
      DateTimeToStr(FCreatedAt),
      FMetadata.Count
    ]
  );
end;

{ TYakkoRuntimeRegistry }

constructor TYakkoRuntimeRegistry.Create;
begin
  inherited Create;
  FItems := TObjectList<TYakkoRegistryItem>.Create(False);

  { TODO: add specialized provider registry on top of the generic registry. }
  { TODO: add specialized model registry on top of the generic registry. }
  { TODO: add specialized template registry on top of the generic registry. }
  { TODO: add runtime snapshots for registry state restoration. }
end;

destructor TYakkoRuntimeRegistry.Destroy;
begin
  FreeAndNil(FItems);
  inherited;
end;

procedure TYakkoRuntimeRegistry.RegisterItem(AItem: TYakkoRegistryItem);
begin
  if not Assigned(AItem) then
    raise EArgumentNilException.Create('AItem must be assigned.');

  if Trim(AItem.Name) = '' then
    raise EArgumentException.Create('AItem.Name must not be empty.');

  if Contains(AItem.Name) then
    raise EInvalidOpException.CreateFmt('Registry item "%s" already exists.', [AItem.Name]);

  FItems.Add(AItem.Clone);

  { Explicit registration avoids hardcoded factories and string-based branching. }
  { TODO: add registry versioning and compatibility markers. }
  { TODO: add lazy loading hooks without turning this layer into auto-discovery. }
  { TODO: add distributed registry support only after local explicit registration is stable. }
end;

function TYakkoRuntimeRegistry.FindByName(const AName: string): TYakkoRegistryItem;
var
  LItem: TYakkoRegistryItem;
begin
  Result := nil;
  for LItem in FItems do
  begin
    if SameText(LItem.Name, AName) then
      Exit(LItem);
  end;
end;

function TYakkoRuntimeRegistry.FindByType(AType: TYakkoRegistryItemType): TObjectList<TYakkoRegistryItem>;
var
  LItem: TYakkoRegistryItem;
begin
  Result := TObjectList<TYakkoRegistryItem>.Create(False);
  for LItem in FItems do
  begin
    if LItem.ItemType = AType then
      Result.Add(LItem);
  end;
end;

function TYakkoRuntimeRegistry.Contains(const AName: string): Boolean;
begin
  Result := Assigned(FindByName(AName));
end;

end.
