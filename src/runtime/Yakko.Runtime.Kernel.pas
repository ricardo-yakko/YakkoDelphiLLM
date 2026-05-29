unit Yakko.Runtime.Kernel;

{ Central runtime kernel for YakkoDelphiLLM.

  Architectural intent:
  - own the top-level runtime lifecycle and ownership graph;
  - centralize orchestrator, bridge and future registries/providers;
  - avoid singleton chaos and fragmented ownership across managers;
  - prepare the runtime for multi-model and multi-runtime evolution.

  Kernel vs Orchestrator:
  - the kernel owns the global lifecycle and ownership boundaries;
  - the orchestrator owns the ordered execution of one runtime flow;
  - the kernel decides when the orchestrator may exist, run or shut down.

  This unit is intentionally synchronous and lightweight in this phase:
  no DI container, no service locator, no singleton, no plugin loading,
  no EventBus, no async startup and no real inference integration here. }

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Generics.Collections,
  Yakko.Runtime.Bridge,
  Yakko.Runtime.Orchestrator;

type
  TYakkoRuntimeKernelState =
  (
    rksCreated,
    rksInitialized,
    rksRunning,
    rksShuttingDown,
    rksStopped
  );

  TYakkoRuntimeKernelStateHelper = record helper for TYakkoRuntimeKernelState
  public
    function ToString: string;
  end;

  TYakkoRuntimeKernelMetadata = TDictionary<string, string>;

  TYakkoRuntimeKernelContext = class
  private
    FKernelId: string;
    FState: TYakkoRuntimeKernelState;
    FCreatedAt: TDateTime;
    FMetadata: TYakkoRuntimeKernelMetadata;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    function Clone: TYakkoRuntimeKernelContext;
    function ToDebugString: string;

    property KernelId: string read FKernelId write FKernelId;
    property State: TYakkoRuntimeKernelState read FState write FState;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
    property Metadata: TYakkoRuntimeKernelMetadata read FMetadata;
  end;

  TYakkoRuntimeKernel = class
  private
    FContext: TYakkoRuntimeKernelContext;
    FOrchestrator: TYakkoRuntimeOrchestrator;
    FBridge: TYakkoRuntimeBridge;
    procedure UpdateState(AState: TYakkoRuntimeKernelState);
    procedure TraceState(const AMessage: string);
  public
    constructor Create;
    destructor Destroy; override;

    procedure Initialize;
    procedure Shutdown;
    function IsRunning: Boolean;

    property Context: TYakkoRuntimeKernelContext read FContext;
    property Orchestrator: TYakkoRuntimeOrchestrator read FOrchestrator;
    property Bridge: TYakkoRuntimeBridge read FBridge;
  end;

implementation

procedure CloneStringDictionary(ASource, ADest: TYakkoRuntimeKernelMetadata);
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

{ TYakkoRuntimeKernelStateHelper }

function TYakkoRuntimeKernelStateHelper.ToString: string;
begin
  case Self of
    rksCreated:
      Result := 'created';
    rksInitialized:
      Result := 'initialized';
    rksRunning:
      Result := 'running';
    rksShuttingDown:
      Result := 'shutting-down';
    rksStopped:
      Result := 'stopped';
  else
    Result := 'created';
  end;
end;

{ TYakkoRuntimeKernelContext }

constructor TYakkoRuntimeKernelContext.Create;
begin
  inherited Create;
  FKernelId := '';
  FState := rksCreated;
  FCreatedAt := Now;
  FMetadata := TYakkoRuntimeKernelMetadata.Create;
end;

destructor TYakkoRuntimeKernelContext.Destroy;
begin
  FreeAndNil(FMetadata);
  inherited;
end;

procedure TYakkoRuntimeKernelContext.Clear;
begin
  FKernelId := '';
  FState := rksCreated;
  FCreatedAt := Now;
  FMetadata.Clear;

  { TODO: add runtime snapshot references for future replay support. }
  { TODO: add graceful cancellation markers for orderly shutdown. }
  { TODO: add multi-runtime instance metadata for cluster-style orchestration. }
end;

function TYakkoRuntimeKernelContext.Clone: TYakkoRuntimeKernelContext;
begin
  Result := TYakkoRuntimeKernelContext.Create;
  try
    Result.FKernelId := FKernelId;
    Result.FState := FState;
    Result.FCreatedAt := FCreatedAt;
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoRuntimeKernelContext.ToDebugString: string;
begin
  Result := Format(
    'TYakkoRuntimeKernelContext(KernelId=%s, State=%s, CreatedAt=%s, Metadata=%d)',
    [
      FKernelId,
      FState.ToString,
      DateTimeToStr(FCreatedAt),
      FMetadata.Count
    ]
  );
end;

{ TYakkoRuntimeKernel }

constructor TYakkoRuntimeKernel.Create;
begin
  inherited Create;
  FContext := TYakkoRuntimeKernelContext.Create;
  FOrchestrator := TYakkoRuntimeOrchestrator.Create;
  FBridge := TYakkoRuntimeBridge.Create;

  { TODO: add kernel-level registry ownership for services, models and providers. }
  { TODO: add runtime pool management once multi-runtime execution is introduced. }
  { TODO: add hot reload coordination without turning the kernel into a service locator. }
end;

destructor TYakkoRuntimeKernel.Destroy;
begin
  Shutdown;
  FreeAndNil(FBridge);
  FreeAndNil(FOrchestrator);
  FreeAndNil(FContext);
  inherited;
end;

procedure TYakkoRuntimeKernel.UpdateState(AState: TYakkoRuntimeKernelState);
begin
  FContext.State := AState;
  FContext.Metadata.AddOrSetValue('kernel.state', AState.ToString);
  FContext.Metadata.AddOrSetValue('kernel.state.timestamp', DateTimeToStr(Now));
  TraceState('state-transition');
end;

procedure TYakkoRuntimeKernel.TraceState(const AMessage: string);
begin
  OutputDebugString(PChar(Format('[YakkoRuntimeKernel] %s=%s', [AMessage, FContext.State.ToString])));
end;

procedure TYakkoRuntimeKernel.Initialize;
begin
  if FContext.State in [rksInitialized, rksRunning] then
    Exit;

  FContext.KernelId := GuidToString(TGuid.NewGuid);
  FContext.CreatedAt := Now;
  FContext.Metadata.AddOrSetValue('kernel.kind', 'runtime-kernel');
  FContext.Metadata.AddOrSetValue('kernel.lifecycle', 'managed');
  FContext.Metadata.AddOrSetValue('kernel.orchestrator', FOrchestrator.ClassName);
  FContext.Metadata.AddOrSetValue('kernel.bridge', FBridge.ClassName);

  UpdateState(rksInitialized);
  UpdateState(rksRunning);

  { The kernel owns the global runtime lifecycle; the orchestrator remains the
    ordered execution coordinator underneath it. }
  { TODO: add provider registry bootstrap here once providers become first-class. }
  { TODO: add model registry bootstrap here once multi-model runtime is introduced. }
  { TODO: add service registry bootstrap here once runtime services are externalized. }
  { TODO: add graceful shutdown hooks and drain coordination. }
end;

procedure TYakkoRuntimeKernel.Shutdown;
begin
  if FContext.State in [rksStopped, rksShuttingDown, rksCreated] then
    Exit;

  UpdateState(rksShuttingDown);

  { Shutdown is intentionally simple for now: release ownership in a controlled
    order and prepare the lifecycle for a future graceful drain phase. }
  { TODO: add runtime pool draining. }
  { TODO: add hot reload handoff. }
  { TODO: add distributed runtime node shutdown coordination. }

  UpdateState(rksStopped);
end;

function TYakkoRuntimeKernel.IsRunning: Boolean;
begin
  Result := FContext.State = rksRunning;
end;

end.
