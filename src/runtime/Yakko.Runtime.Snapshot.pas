unit Yakko.Runtime.Snapshot;

{ Runtime snapshot foundation for YakkoDelphiLLM.

  Architectural intent:
  - capture deterministic in-memory snapshots of runtime architecture state;
  - support diagnostics and future persistence planning;
  - keep snapshot collection explicit and side-effect free.

  This unit intentionally avoids serialization and persistence implementations. }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Yakko.Runtime.Kernel,
  Yakko.Runtime.Registry,
  Yakko.Runtime.Capabilities,
  Yakko.Runtime.Composition;

type
  TYakkoRuntimeSnapshotMetadata = TDictionary<string, string>;

  TYakkoRuntimeSnapshot = class
  private
    FCreatedAt: TDateTime;
    FKernelState: TYakkoRuntimeKernelState;
    FRegistryItems: TObjectList<TYakkoRegistryItem>;
    FCapabilities: TYakkoRuntimeCapabilities;
    FCurrentComposition: TYakkoRuntimeCompositionResult;
    FMetadata: TYakkoRuntimeSnapshotMetadata;

    procedure SetCurrentComposition(const Value: TYakkoRuntimeCompositionResult);
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    procedure CaptureFromKernel(
      AKernel: TYakkoRuntimeKernel;
      ACurrentComposition: TYakkoRuntimeCompositionResult = nil
    );

    function Clone: TYakkoRuntimeSnapshot;
    function ToDebugString: string;

    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
    property KernelState: TYakkoRuntimeKernelState read FKernelState write FKernelState;
    property RegistryItems: TObjectList<TYakkoRegistryItem> read FRegistryItems;
    property Capabilities: TYakkoRuntimeCapabilities read FCapabilities;
    property CurrentComposition: TYakkoRuntimeCompositionResult read FCurrentComposition write SetCurrentComposition;
    property Metadata: TYakkoRuntimeSnapshotMetadata read FMetadata;
  end;

implementation

procedure CloneStringDictionary(ASource, ADest: TYakkoRuntimeSnapshotMetadata);
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

procedure CopyCapabilities(ASource, ADest: TYakkoRuntimeCapabilities);
var
  LCapability: TYakkoRuntimeCapability;
begin
  if not Assigned(ADest) then
    raise EArgumentNilException.Create('ADest must be assigned.');

  if not Assigned(ASource) then
    Exit;

  for LCapability in ASource.ToArray do
    ADest.Add(LCapability);
end;

procedure CaptureRegistryTypeItems(
  ARegistry: TYakkoRuntimeRegistry;
  AItemType: TYakkoRegistryItemType;
  ADestination: TObjectList<TYakkoRegistryItem>
);
var
  LItems: TObjectList<TYakkoRegistryItem>;
  LItem: TYakkoRegistryItem;
begin
  if not Assigned(ARegistry) or not Assigned(ADestination) then
    Exit;

  LItems := ARegistry.FindByType(AItemType);
  try
    for LItem in LItems do
      ADestination.Add(LItem.Clone);
  finally
    LItems.Free;
  end;
end;

{ TYakkoRuntimeSnapshot }

constructor TYakkoRuntimeSnapshot.Create;
begin
  inherited Create;
  FCreatedAt := Now;
  FKernelState := ksCreated;
  FRegistryItems := TObjectList<TYakkoRegistryItem>.Create(True);
  FCapabilities := TYakkoRuntimeCapabilities.Create;
  FCurrentComposition := nil;
  FMetadata := TYakkoRuntimeSnapshotMetadata.Create;
end;

destructor TYakkoRuntimeSnapshot.Destroy;
begin
  FreeAndNil(FMetadata);
  FreeAndNil(FCurrentComposition);
  FreeAndNil(FCapabilities);
  FreeAndNil(FRegistryItems);
  inherited;
end;

procedure TYakkoRuntimeSnapshot.SetCurrentComposition(
  const Value: TYakkoRuntimeCompositionResult);
begin
  FreeAndNil(FCurrentComposition);
  if Assigned(Value) then
    FCurrentComposition := Value.Clone;
end;

procedure TYakkoRuntimeSnapshot.Clear;
begin
  FCreatedAt := Now;
  FKernelState := ksCreated;
  FRegistryItems.Clear;
  FreeAndNil(FCapabilities);
  FCapabilities := TYakkoRuntimeCapabilities.Create;
  FreeAndNil(FCurrentComposition);
  FMetadata.Clear;

  { TODO: add selective snapshot modes for lightweight diagnostics capture. }
  { TODO: add snapshot diff support for lifecycle transition analysis. }
end;

procedure TYakkoRuntimeSnapshot.CaptureFromKernel(
  AKernel: TYakkoRuntimeKernel;
  ACurrentComposition: TYakkoRuntimeCompositionResult);
begin
  Clear;

  if not Assigned(AKernel) then
    raise EArgumentNilException.Create('AKernel must be assigned.');

  FCreatedAt := Now;
  FKernelState := AKernel.Context.State;

  CaptureRegistryTypeItems(AKernel.RuntimeRegistry, ritModel, FRegistryItems);
  CaptureRegistryTypeItems(AKernel.RuntimeRegistry, ritProvider, FRegistryItems);
  CaptureRegistryTypeItems(AKernel.RuntimeRegistry, ritTemplate, FRegistryItems);
  CaptureRegistryTypeItems(AKernel.RuntimeRegistry, ritPipeline, FRegistryItems);
  CaptureRegistryTypeItems(AKernel.RuntimeRegistry, ritTool, FRegistryItems);

  CopyCapabilities(AKernel.Capabilities, FCapabilities);
  SetCurrentComposition(ACurrentComposition);

  FMetadata.AddOrSetValue('kernel.state', AKernel.Context.State.ToString);
  FMetadata.AddOrSetValue('kernel.debug', AKernel.ToDebugString);
  FMetadata.AddOrSetValue('registry.items', IntToStr(FRegistryItems.Count));
  FMetadata.AddOrSetValue('capabilities.count', IntToStr(Length(FCapabilities.ToArray)));
  FMetadata.AddOrSetValue('composition.available', BoolToStr(Assigned(FCurrentComposition), True));
  FMetadata.AddOrSetValue('policies.available', BoolToStr(Assigned(AKernel.PolicyManager), True));
  FMetadata.AddOrSetValue('hooks.available', BoolToStr(Assigned(AKernel.HookManager), True));

  { TODO: add policy snapshot structures when policy state becomes explicitly queryable. }
  { TODO: add hook snapshot structures when hook state becomes explicitly queryable. }
  { TODO: add composition timeline references for replay diagnostics. }
end;

function TYakkoRuntimeSnapshot.Clone: TYakkoRuntimeSnapshot;
var
  LItem: TYakkoRegistryItem;
begin
  Result := TYakkoRuntimeSnapshot.Create;
  try
    Result.FCreatedAt := FCreatedAt;
    Result.FKernelState := FKernelState;
    for LItem in FRegistryItems do
      Result.FRegistryItems.Add(LItem.Clone);
    CopyCapabilities(FCapabilities, Result.FCapabilities);
    Result.SetCurrentComposition(FCurrentComposition);
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoRuntimeSnapshot.ToDebugString: string;
begin
  Result := Format(
    'TYakkoRuntimeSnapshot(CreatedAt=%s, KernelState=%s, RegistryItems=%d, Capabilities=%d, HasComposition=%s, Metadata=%d)',
    [
      DateTimeToStr(FCreatedAt),
      FKernelState.ToString,
      FRegistryItems.Count,
      Length(FCapabilities.ToArray),
      BoolToStr(Assigned(FCurrentComposition), True),
      FMetadata.Count
    ]
  );
end;

end.
