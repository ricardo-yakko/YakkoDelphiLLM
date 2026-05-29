unit Yakko.Runtime.Telemetry;

{ Runtime telemetry foundation for YakkoDelphiLLM.

  Architectural intent:
  - provide structured in-memory telemetry events;
  - keep telemetry synchronous and deterministic;
  - prepare future exporters without coupling current runtime flow.

  This unit intentionally avoids OpenTelemetry exporters, async pipelines and
  distributed telemetry transports. }

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections;

type
  TYakkoRuntimeTelemetryMetadata = TDictionary<string, string>;

  TYakkoRuntimeTelemetryEventNames = class
  public
    const RuntimeInitialized = 'runtime initialized';
    const RuntimeShutdown = 'runtime shutdown';
    const CompositionStarted = 'composition started';
    const CompositionFinished = 'composition finished';
    const GenerationStarted = 'generation started';
    const GenerationFinished = 'generation finished';
    const PipelineStageChanged = 'pipeline stage changed';
    const CompatibilityValidation = 'compatibility validation';
    const ResolverSelection = 'resolver selection';
  end;

  TYakkoRuntimeTelemetryEvent = class
  private
    FEventName: string;
    FTimestamp: TDateTime;
    FComponent: string;
    FAction: string;
    FState: string;
    FDurationMs: Int64;
    FMetricValue: Double;
    FMetadata: TYakkoRuntimeTelemetryMetadata;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    function Clone: TYakkoRuntimeTelemetryEvent;
    function ToDebugString: string;

    property EventName: string read FEventName write FEventName;
    property Timestamp: TDateTime read FTimestamp write FTimestamp;
    property Component: string read FComponent write FComponent;
    property Action: string read FAction write FAction;
    property State: string read FState write FState;
    property DurationMs: Int64 read FDurationMs write FDurationMs;
    property MetricValue: Double read FMetricValue write FMetricValue;
    property Metadata: TYakkoRuntimeTelemetryMetadata read FMetadata;
  end;

  TYakkoRuntimeTelemetryManager = class
  private
    FEvents: TObjectList<TYakkoRuntimeTelemetryEvent>;
  public
    constructor Create;
    destructor Destroy; override;

    procedure RecordEvent(AEvent: TYakkoRuntimeTelemetryEvent);
    procedure RecordSimpleEvent(
      const AEventName, AComponent, AAction, AState: string;
      AMetadata: TYakkoRuntimeTelemetryMetadata = nil
    );

    function SnapshotEvents: TObjectList<TYakkoRuntimeTelemetryEvent>;
    procedure Clear;
    function ToDebugString: string;
  end;

implementation

procedure CloneStringDictionary(ASource, ADest: TYakkoRuntimeTelemetryMetadata);
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

{ TYakkoRuntimeTelemetryEvent }

constructor TYakkoRuntimeTelemetryEvent.Create;
begin
  inherited Create;
  FEventName := '';
  FTimestamp := Now;
  FComponent := '';
  FAction := '';
  FState := '';
  FDurationMs := 0;
  FMetricValue := 0;
  FMetadata := TYakkoRuntimeTelemetryMetadata.Create;
end;

destructor TYakkoRuntimeTelemetryEvent.Destroy;
begin
  FreeAndNil(FMetadata);
  inherited;
end;

procedure TYakkoRuntimeTelemetryEvent.Clear;
begin
  FEventName := '';
  FTimestamp := Now;
  FComponent := '';
  FAction := '';
  FState := '';
  FDurationMs := 0;
  FMetricValue := 0;
  FMetadata.Clear;

  { TODO: add correlation fields for future cross-component telemetry stitching. }
  { TODO: add telemetry severity and category levels for richer diagnostics. }
end;

function TYakkoRuntimeTelemetryEvent.Clone: TYakkoRuntimeTelemetryEvent;
begin
  Result := TYakkoRuntimeTelemetryEvent.Create;
  try
    Result.FEventName := FEventName;
    Result.FTimestamp := FTimestamp;
    Result.FComponent := FComponent;
    Result.FAction := FAction;
    Result.FState := FState;
    Result.FDurationMs := FDurationMs;
    Result.FMetricValue := FMetricValue;
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoRuntimeTelemetryEvent.ToDebugString: string;
begin
  Result := Format(
    'TYakkoRuntimeTelemetryEvent(Event=%s, Component=%s, Action=%s, State=%s, DurationMs=%d, MetricValue=%.4f, Timestamp=%s, Metadata=%d)',
    [
      FEventName,
      FComponent,
      FAction,
      FState,
      FDurationMs,
      FMetricValue,
      DateTimeToStr(FTimestamp),
      FMetadata.Count
    ]
  );
end;

{ TYakkoRuntimeTelemetryManager }

constructor TYakkoRuntimeTelemetryManager.Create;
begin
  inherited Create;
  FEvents := TObjectList<TYakkoRuntimeTelemetryEvent>.Create(True);
end;

destructor TYakkoRuntimeTelemetryManager.Destroy;
begin
  FreeAndNil(FEvents);
  inherited;
end;

procedure TYakkoRuntimeTelemetryManager.RecordEvent(AEvent: TYakkoRuntimeTelemetryEvent);
begin
  if not Assigned(AEvent) then
    raise EArgumentNilException.Create('AEvent must be assigned.');

  FEvents.Add(AEvent.Clone);
end;

procedure TYakkoRuntimeTelemetryManager.RecordSimpleEvent(
  const AEventName, AComponent, AAction, AState: string;
  AMetadata: TYakkoRuntimeTelemetryMetadata);
var
  LEvent: TYakkoRuntimeTelemetryEvent;
begin
  LEvent := TYakkoRuntimeTelemetryEvent.Create;
  try
    LEvent.EventName := AEventName;
    LEvent.Timestamp := Now;
    LEvent.Component := AComponent;
    LEvent.Action := AAction;
    LEvent.State := AState;
    CloneStringDictionary(AMetadata, LEvent.Metadata);
    RecordEvent(LEvent);
  finally
    LEvent.Free;
  end;
end;

function TYakkoRuntimeTelemetryManager.SnapshotEvents: TObjectList<TYakkoRuntimeTelemetryEvent>;
var
  LEvent: TYakkoRuntimeTelemetryEvent;
begin
  Result := TObjectList<TYakkoRuntimeTelemetryEvent>.Create(True);
  for LEvent in FEvents do
    Result.Add(LEvent.Clone);
end;

procedure TYakkoRuntimeTelemetryManager.Clear;
begin
  FEvents.Clear;
end;

function TYakkoRuntimeTelemetryManager.ToDebugString: string;
begin
  Result := Format('TYakkoRuntimeTelemetryManager(Events=%d)', [FEvents.Count]);
end;

end.
