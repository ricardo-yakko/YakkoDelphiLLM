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
  Yakko.Generation.Controller,
  Yakko.Runtime.Bridge,
  Yakko.Runtime.Orchestrator,
  Yakko.Runtime.Registry,
  Yakko.Runtime.Capabilities,
  Yakko.Runtime.Resolver,
  Yakko.Runtime.SpecializedRegistries,
  Yakko.Runtime.Compatibility,
  Yakko.Runtime.Composition,
  Yakko.Runtime.Hooks,
  Yakko.Runtime.Policies,
  Yakko.Runtime.Diagnostics;

type
  TYakkoRuntimeKernelState =
  (
    ksCreated,
    ksInitializing,
    ksReady,
    ksShuttingDown,
    ksDestroyed
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
    FInitializedAt: TDateTime;
    FReadyAt: TDateTime;
    FShutdownAt: TDateTime;
    FDestroyedAt: TDateTime;
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
    property InitializedAt: TDateTime read FInitializedAt write FInitializedAt;
    property ReadyAt: TDateTime read FReadyAt write FReadyAt;
    property ShutdownAt: TDateTime read FShutdownAt write FShutdownAt;
    property DestroyedAt: TDateTime read FDestroyedAt write FDestroyedAt;
    property Metadata: TYakkoRuntimeKernelMetadata read FMetadata;
  end;

  TYakkoRuntimeKernel = class
  private
    FContext: TYakkoRuntimeKernelContext;

    FRuntimeRegistry: TYakkoRuntimeRegistry;
    FCapabilities: TYakkoRuntimeCapabilities;

    FModelRegistry: TYakkoModelRegistry;
    FProviderRegistry: TYakkoProviderRegistry;
    FTemplateRegistry: TYakkoTemplateRegistry;
    FPipelineRegistry: TYakkoPipelineRegistry;

    FResolver: TYakkoRuntimeResolver;
    FCompatibilityManager: TYakkoRuntimeCompatibilityManager;
    FCompositionManager: TYakkoRuntimeCompositionManager;

    FHookManager: TYakkoRuntimeHookManager;
    FPolicyManager: TYakkoRuntimePolicyManager;
    FDiagnostics: TYakkoRuntimeDiagnostics;

    FOrchestrator: TYakkoRuntimeOrchestrator;
    FBridge: TYakkoRuntimeBridge;
    FGenerationController: TYakkoGenerationController;

    procedure BuildOwnershipGraph;
    procedure ReleaseOwnershipGraph;
    procedure UpdateState(AState: TYakkoRuntimeKernelState);
    procedure TraceState(const AMessage: string);
  public
    constructor Create;
    destructor Destroy; override;

    procedure Initialize;
    procedure Shutdown;
    procedure Reset;
    function IsReady: Boolean;
    function ToDebugString: string;

    property Context: TYakkoRuntimeKernelContext read FContext;
    property RuntimeRegistry: TYakkoRuntimeRegistry read FRuntimeRegistry;
    property Capabilities: TYakkoRuntimeCapabilities read FCapabilities;
    property ModelRegistry: TYakkoModelRegistry read FModelRegistry;
    property ProviderRegistry: TYakkoProviderRegistry read FProviderRegistry;
    property TemplateRegistry: TYakkoTemplateRegistry read FTemplateRegistry;
    property PipelineRegistry: TYakkoPipelineRegistry read FPipelineRegistry;
    property Resolver: TYakkoRuntimeResolver read FResolver;
    property CompatibilityManager: TYakkoRuntimeCompatibilityManager read FCompatibilityManager;
    property CompositionManager: TYakkoRuntimeCompositionManager read FCompositionManager;
    property HookManager: TYakkoRuntimeHookManager read FHookManager;
    property PolicyManager: TYakkoRuntimePolicyManager read FPolicyManager;
    property Diagnostics: TYakkoRuntimeDiagnostics read FDiagnostics;
    property Orchestrator: TYakkoRuntimeOrchestrator read FOrchestrator;
    property Bridge: TYakkoRuntimeBridge read FBridge;
    property GenerationController: TYakkoGenerationController read FGenerationController;
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
    ksCreated:
      Result := 'created';
    ksInitializing:
      Result := 'initializing';
    ksReady:
      Result := 'ready';
    ksShuttingDown:
      Result := 'shutting-down';
    ksDestroyed:
      Result := 'destroyed';
  else
    Result := 'created';
  end;
end;

{ TYakkoRuntimeKernelContext }

constructor TYakkoRuntimeKernelContext.Create;
begin
  inherited Create;
  FKernelId := '';
  FState := ksCreated;
  FCreatedAt := Now;
  FInitializedAt := 0;
  FReadyAt := 0;
  FShutdownAt := 0;
  FDestroyedAt := 0;
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
  FState := ksCreated;
  FCreatedAt := Now;
  FInitializedAt := 0;
  FReadyAt := 0;
  FShutdownAt := 0;
  FDestroyedAt := 0;
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
    Result.FInitializedAt := FInitializedAt;
    Result.FReadyAt := FReadyAt;
    Result.FShutdownAt := FShutdownAt;
    Result.FDestroyedAt := FDestroyedAt;
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoRuntimeKernelContext.ToDebugString: string;
begin
  Result := Format(
    'TYakkoRuntimeKernelContext(KernelId=%s, State=%s, CreatedAt=%s, InitializedAt=%s, ReadyAt=%s, ShutdownAt=%s, DestroyedAt=%s, Metadata=%d)',
    [
      FKernelId,
      FState.ToString,
      DateTimeToStr(FCreatedAt),
      DateTimeToStr(FInitializedAt),
      DateTimeToStr(FReadyAt),
      DateTimeToStr(FShutdownAt),
      DateTimeToStr(FDestroyedAt),
      FMetadata.Count
    ]
  );
end;

{ TYakkoRuntimeKernel }

constructor TYakkoRuntimeKernel.Create;
begin
  inherited Create;
  FContext := TYakkoRuntimeKernelContext.Create;
  FContext.KernelId := GuidToString(TGuid.NewGuid);
  FContext.Metadata.AddOrSetValue('kernel.kind', 'runtime-kernel');
  FContext.Metadata.AddOrSetValue('kernel.lifecycle', 'explicit');
  FContext.Metadata.AddOrSetValue('kernel.ownership', 'centralized');

  { TODO: add kernel-wide rollback orchestration once deterministic rollback contracts exist. }
  { TODO: add runtime health probes for multi-node readiness validation. }
  { TODO: add lifecycle audit snapshots for long-term replay diagnostics. }
end;

destructor TYakkoRuntimeKernel.Destroy;
begin
  Shutdown;
  if FContext.State <> ksDestroyed then
  begin
    FContext.DestroyedAt := Now;
    UpdateState(ksDestroyed);
  end;
  FreeAndNil(FContext);
  inherited;
end;

procedure TYakkoRuntimeKernel.BuildOwnershipGraph;
begin
  if Assigned(FRuntimeRegistry) then
    Exit;

  FRuntimeRegistry := TYakkoRuntimeRegistry.Create;
  FCapabilities := TYakkoRuntimeCapabilities.Create;

  FModelRegistry := TYakkoModelRegistry.Create(FRuntimeRegistry);
  FProviderRegistry := TYakkoProviderRegistry.Create(FRuntimeRegistry);
  FTemplateRegistry := TYakkoTemplateRegistry.Create(FRuntimeRegistry);
  FPipelineRegistry := TYakkoPipelineRegistry.Create(FRuntimeRegistry);

  FResolver := TYakkoRuntimeResolver.Create(FRuntimeRegistry);
  FCompatibilityManager := TYakkoRuntimeCompatibilityManager.Create;
  FCompositionManager := TYakkoRuntimeCompositionManager.Create(
    FModelRegistry,
    FProviderRegistry,
    FTemplateRegistry,
    FPipelineRegistry
  );

  FHookManager := TYakkoRuntimeHookManager.Create;
  FPolicyManager := TYakkoRuntimePolicyManager.Create;
  FDiagnostics := TYakkoRuntimeDiagnostics.Create;

  FBridge := TYakkoRuntimeBridge.Create;
  FOrchestrator := TYakkoRuntimeOrchestrator.Create;
  FGenerationController := TYakkoGenerationController.Create;

  FContext.Metadata.AddOrSetValue('kernel.components.registry', FRuntimeRegistry.ClassName);
  FContext.Metadata.AddOrSetValue('kernel.components.resolver', FResolver.ClassName);
  FContext.Metadata.AddOrSetValue('kernel.components.compatibility', FCompatibilityManager.ClassName);
  FContext.Metadata.AddOrSetValue('kernel.components.composition', FCompositionManager.ClassName);
  FContext.Metadata.AddOrSetValue('kernel.components.hooks', FHookManager.ClassName);
  FContext.Metadata.AddOrSetValue('kernel.components.policies', FPolicyManager.ClassName);
  FContext.Metadata.AddOrSetValue('kernel.components.diagnostics', FDiagnostics.ClassName);
  FContext.Metadata.AddOrSetValue('kernel.components.bridge', FBridge.ClassName);
  FContext.Metadata.AddOrSetValue('kernel.components.orchestrator', FOrchestrator.ClassName);
  FContext.Metadata.AddOrSetValue('kernel.components.controller', FGenerationController.ClassName);
end;

procedure TYakkoRuntimeKernel.ReleaseOwnershipGraph;
begin
  FreeAndNil(FGenerationController);
  FreeAndNil(FOrchestrator);
  FreeAndNil(FBridge);

  FreeAndNil(FDiagnostics);
  FreeAndNil(FPolicyManager);
  FreeAndNil(FHookManager);

  FreeAndNil(FCompositionManager);
  FreeAndNil(FCompatibilityManager);
  FreeAndNil(FResolver);

  FreeAndNil(FPipelineRegistry);
  FreeAndNil(FTemplateRegistry);
  FreeAndNil(FProviderRegistry);
  FreeAndNil(FModelRegistry);

  FreeAndNil(FCapabilities);
  FreeAndNil(FRuntimeRegistry);
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
  if FContext.State = ksReady then
    Exit;

  if FContext.State = ksShuttingDown then
    raise EInvalidOpException.Create('Kernel cannot initialize while shutting down.');

  UpdateState(ksInitializing);
  FContext.InitializedAt := Now;

  BuildOwnershipGraph;

  FContext.ReadyAt := Now;
  UpdateState(ksReady);

  { The kernel centralizes ownership and lifecycle boundaries.
    Bootstrap logic is intentionally externalized to Yakko.Runtime.Bootstrap. }
end;

procedure TYakkoRuntimeKernel.Shutdown;
begin
  if FContext.State in [ksShuttingDown, ksDestroyed, ksCreated] then
    Exit;

  UpdateState(ksShuttingDown);
  FContext.ShutdownAt := Now;

  ReleaseOwnershipGraph;

  UpdateState(ksDestroyed);
end;

procedure TYakkoRuntimeKernel.Reset;
begin
  Shutdown;
  FContext.Clear;
  FContext.KernelId := GuidToString(TGuid.NewGuid);
  FContext.CreatedAt := Now;
  Initialize;
end;

function TYakkoRuntimeKernel.IsReady: Boolean;
begin
  Result := FContext.State = ksReady;
end;

function TYakkoRuntimeKernel.ToDebugString: string;
begin
  Result := Format(
    'TYakkoRuntimeKernel(State=%s, IsReady=%s, Registry=%s, SpecializedRegistries=%s, Resolver=%s, Compatibility=%s, Composition=%s, Hooks=%s, Policies=%s, Diagnostics=%s, Bridge=%s, Orchestrator=%s, GenerationController=%s)',
    [
      FContext.State.ToString,
      BoolToStr(IsReady, True),
      BoolToStr(Assigned(FRuntimeRegistry), True),
      BoolToStr(Assigned(FModelRegistry) and Assigned(FProviderRegistry) and Assigned(FTemplateRegistry) and Assigned(FPipelineRegistry), True),
      BoolToStr(Assigned(FResolver), True),
      BoolToStr(Assigned(FCompatibilityManager), True),
      BoolToStr(Assigned(FCompositionManager), True),
      BoolToStr(Assigned(FHookManager), True),
      BoolToStr(Assigned(FPolicyManager), True),
      BoolToStr(Assigned(FDiagnostics), True),
      BoolToStr(Assigned(FBridge), True),
      BoolToStr(Assigned(FOrchestrator), True),
      BoolToStr(Assigned(FGenerationController), True)
    ]
  );
end;

end.
