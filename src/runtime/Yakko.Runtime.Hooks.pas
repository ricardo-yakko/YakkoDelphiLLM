unit Yakko.Runtime.Hooks;

{ Runtime hook architecture for controlled extensibility in YakkoDelphiLLM.

  Architectural intent:
  - provide explicit interception points without contaminating core runtime layers;
  - keep pipeline/controller/bridge/builder focused on execution concerns;
  - enable observability and instrumentation through controlled hooks;
  - prepare future tool/RAG/reasoning injections via stable extension boundaries.

  Hooks are not an EventBus:
  - hooks are deterministic interception points in a known flow;
  - EventBus is broader publish/subscribe propagation across domains.

  This unit keeps the core runtime isolated while enabling gradual extensibility.
  It intentionally does not include plugin loading, async execution or telemetry
  providers yet. }

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TYakkoRuntimeHookType =
  (
    rhtBeforePromptBuild,
    rhtAfterPromptBuild,

    rhtBeforeInference,
    rhtAfterInference,

    rhtBeforeStage,
    rhtAfterStage,

    rhtBeforeOutput,
    rhtAfterOutput
  );

  TYakkoRuntimeHookTypeHelper = record helper for TYakkoRuntimeHookType
  public
    function ToString: string;
  end;

  TYakkoRuntimeHookMetadata = TDictionary<string, string>;

  TYakkoRuntimeHookContext = class
  private
    FHookType: TYakkoRuntimeHookType;
    FMetadata: TYakkoRuntimeHookMetadata;
    FTimestamp: TDateTime;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    function Clone: TYakkoRuntimeHookContext;
    function ToDebugString: string;

    property HookType: TYakkoRuntimeHookType read FHookType write FHookType;
    property Metadata: TYakkoRuntimeHookMetadata read FMetadata;
    property Timestamp: TDateTime read FTimestamp write FTimestamp;
  end;

  IYakkoRuntimeHook = interface
    ['{C6622094-C8E2-4436-B938-B18F2AD82F8A}']
    function HookType: TYakkoRuntimeHookType;
    procedure Execute(AContext: TYakkoRuntimeHookContext);
  end;

  TYakkoRuntimeHookManager = class
  private
    FHooks: TList<IYakkoRuntimeHook>;
  public
    constructor Create;
    destructor Destroy; override;

    procedure RegisterHook(const AHook: IYakkoRuntimeHook);
    procedure ExecuteHooks(AHookType: TYakkoRuntimeHookType; AContext: TYakkoRuntimeHookContext);
  end;

implementation

procedure CloneStringDictionary(ASource, ADest: TYakkoRuntimeHookMetadata);
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

{ TYakkoRuntimeHookTypeHelper }

function TYakkoRuntimeHookTypeHelper.ToString: string;
begin
  case Self of
    rhtBeforePromptBuild:
      Result := 'before-prompt-build';
    rhtAfterPromptBuild:
      Result := 'after-prompt-build';
    rhtBeforeInference:
      Result := 'before-inference';
    rhtAfterInference:
      Result := 'after-inference';
    rhtBeforeStage:
      Result := 'before-stage';
    rhtAfterStage:
      Result := 'after-stage';
    rhtBeforeOutput:
      Result := 'before-output';
    rhtAfterOutput:
      Result := 'after-output';
  else
    Result := 'before-stage';
  end;
end;

{ TYakkoRuntimeHookContext }

constructor TYakkoRuntimeHookContext.Create;
begin
  inherited Create;
  FHookType := rhtBeforeStage;
  FMetadata := TYakkoRuntimeHookMetadata.Create;
  FTimestamp := Now;
end;

destructor TYakkoRuntimeHookContext.Destroy;
begin
  FreeAndNil(FMetadata);
  inherited;
end;

procedure TYakkoRuntimeHookContext.Clear;
begin
  FMetadata.Clear;
  FTimestamp := Now;

  { TODO: add structured payload slots for tool and RAG injection contexts. }
  { TODO: add reasoning-policy payload fields for policy hook execution. }
end;

function TYakkoRuntimeHookContext.Clone: TYakkoRuntimeHookContext;
begin
  Result := TYakkoRuntimeHookContext.Create;
  try
    Result.FHookType := FHookType;
    Result.FTimestamp := FTimestamp;
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoRuntimeHookContext.ToDebugString: string;
begin
  Result := Format(
    'TYakkoRuntimeHookContext(HookType=%s, Timestamp=%s, Metadata=%d)',
    [
      FHookType.ToString,
      DateTimeToStr(FTimestamp),
      FMetadata.Count
    ]
  );
end;

{ TYakkoRuntimeHookManager }

constructor TYakkoRuntimeHookManager.Create;
begin
  inherited Create;
  FHooks := TList<IYakkoRuntimeHook>.Create;
end;

destructor TYakkoRuntimeHookManager.Destroy;
begin
  FreeAndNil(FHooks);
  inherited;
end;

procedure TYakkoRuntimeHookManager.RegisterHook(
  const AHook: IYakkoRuntimeHook);
begin
  if not Assigned(AHook) then
    raise EArgumentNilException.Create('AHook must be assigned.');

  FHooks.Add(AHook);

  { TODO: add hook priorities and deterministic ordering policies. }
  { TODO: add plugin discovery and runtime hook registration sources. }
end;

procedure TYakkoRuntimeHookManager.ExecuteHooks(
  AHookType: TYakkoRuntimeHookType; AContext: TYakkoRuntimeHookContext);
var
  LHook: IYakkoRuntimeHook;
begin
  if not Assigned(AContext) then
    raise EArgumentNilException.Create('AContext must be assigned.');

  AContext.HookType := AHookType;
  AContext.Timestamp := Now;

  for LHook in FHooks do
  begin
    if LHook.HookType <> AHookType then
      Continue;

    { Current execution is intentionally simple and synchronous.
      Future revisions can isolate failures per hook with policy controls. }
    LHook.Execute(AContext);
  end;

  { TODO: add async hooks and cancellation-aware execution paths. }
  { TODO: add distributed tracing and OpenTelemetry exporters. }
  { TODO: add telemetry providers and metrics sinks without coupling core runtime. }
  { TODO: add policy hooks for runtime behavior governance. }
  { TODO: add tool injection and RAG injection hooks. }
  { TODO: add reasoning policy hooks and post-reasoning sanitization interceptors. }
end;

end.
