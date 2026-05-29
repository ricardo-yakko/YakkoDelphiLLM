unit Yakko.Runtime.Trace;

{ Runtime execution trace foundation for YakkoDelphiLLM.

  Architectural intent:
  - provide local structured execution traces for diagnostics;
  - keep trace capture deterministic and lightweight;
  - prepare future replay and persistence without implementing them now.

  This unit intentionally avoids persistence, distributed tracing and replay
  execution. }

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TYakkoExecutionTraceMetadata = TDictionary<string, string>;

  TYakkoExecutionTraceStep = class
  private
    FTimestamp: TDateTime;
    FComponent: string;
    FAction: string;
    FState: string;
    FMetadata: TYakkoExecutionTraceMetadata;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    function Clone: TYakkoExecutionTraceStep;
    function ToDebugString: string;

    property Timestamp: TDateTime read FTimestamp write FTimestamp;
    property Component: string read FComponent write FComponent;
    property Action: string read FAction write FAction;
    property State: string read FState write FState;
    property Metadata: TYakkoExecutionTraceMetadata read FMetadata;
  end;

  TYakkoExecutionTrace = class
  private
    FTraceId: string;
    FCreatedAt: TDateTime;
    FSteps: TObjectList<TYakkoExecutionTraceStep>;
    FMetadata: TYakkoExecutionTraceMetadata;
  public
    constructor Create;
    destructor Destroy; override;

    procedure AddStep(AStep: TYakkoExecutionTraceStep);
    procedure AddSimpleStep(
      const AComponent, AAction, AState: string;
      AMetadata: TYakkoExecutionTraceMetadata = nil
    );

    procedure Clear;
    function Clone: TYakkoExecutionTrace;
    function ToDebugString: string;

    property TraceId: string read FTraceId write FTraceId;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
    property Steps: TObjectList<TYakkoExecutionTraceStep> read FSteps;
    property Metadata: TYakkoExecutionTraceMetadata read FMetadata;
  end;

implementation

procedure CloneStringDictionary(ASource, ADest: TYakkoExecutionTraceMetadata);
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

{ TYakkoExecutionTraceStep }

constructor TYakkoExecutionTraceStep.Create;
begin
  inherited Create;
  FTimestamp := Now;
  FComponent := '';
  FAction := '';
  FState := '';
  FMetadata := TYakkoExecutionTraceMetadata.Create;
end;

destructor TYakkoExecutionTraceStep.Destroy;
begin
  FreeAndNil(FMetadata);
  inherited;
end;

procedure TYakkoExecutionTraceStep.Clear;
begin
  FTimestamp := Now;
  FComponent := '';
  FAction := '';
  FState := '';
  FMetadata.Clear;

  { TODO: add deterministic stage ordering indexes for replay planning. }
end;

function TYakkoExecutionTraceStep.Clone: TYakkoExecutionTraceStep;
begin
  Result := TYakkoExecutionTraceStep.Create;
  try
    Result.FTimestamp := FTimestamp;
    Result.FComponent := FComponent;
    Result.FAction := FAction;
    Result.FState := FState;
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoExecutionTraceStep.ToDebugString: string;
begin
  Result := Format(
    'TYakkoExecutionTraceStep(Component=%s, Action=%s, State=%s, Timestamp=%s, Metadata=%d)',
    [
      FComponent,
      FAction,
      FState,
      DateTimeToStr(FTimestamp),
      FMetadata.Count
    ]
  );
end;

{ TYakkoExecutionTrace }

constructor TYakkoExecutionTrace.Create;
begin
  inherited Create;
  FTraceId := GuidToString(TGuid.NewGuid);
  FCreatedAt := Now;
  FSteps := TObjectList<TYakkoExecutionTraceStep>.Create(True);
  FMetadata := TYakkoExecutionTraceMetadata.Create;
end;

destructor TYakkoExecutionTrace.Destroy;
begin
  FreeAndNil(FMetadata);
  FreeAndNil(FSteps);
  inherited;
end;

procedure TYakkoExecutionTrace.AddStep(AStep: TYakkoExecutionTraceStep);
begin
  if not Assigned(AStep) then
    raise EArgumentNilException.Create('AStep must be assigned.');

  FSteps.Add(AStep.Clone);
end;

procedure TYakkoExecutionTrace.AddSimpleStep(
  const AComponent, AAction, AState: string;
  AMetadata: TYakkoExecutionTraceMetadata);
var
  LStep: TYakkoExecutionTraceStep;
begin
  LStep := TYakkoExecutionTraceStep.Create;
  try
    LStep.Timestamp := Now;
    LStep.Component := AComponent;
    LStep.Action := AAction;
    LStep.State := AState;
    CloneStringDictionary(AMetadata, LStep.Metadata);
    AddStep(LStep);
  finally
    LStep.Free;
  end;
end;

procedure TYakkoExecutionTrace.Clear;
begin
  FTraceId := GuidToString(TGuid.NewGuid);
  FCreatedAt := Now;
  FSteps.Clear;
  FMetadata.Clear;

  { TODO: add trace snapshots for future in-memory replay diagnostics. }
  { TODO: add optional bounded trace history for long-running sessions. }
end;

function TYakkoExecutionTrace.Clone: TYakkoExecutionTrace;
var
  LStep: TYakkoExecutionTraceStep;
begin
  Result := TYakkoExecutionTrace.Create;
  try
    Result.FTraceId := FTraceId;
    Result.FCreatedAt := FCreatedAt;
    for LStep in FSteps do
      Result.FSteps.Add(LStep.Clone);
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoExecutionTrace.ToDebugString: string;
begin
  Result := Format(
    'TYakkoExecutionTrace(TraceId=%s, CreatedAt=%s, Steps=%d, Metadata=%d)',
    [
      FTraceId,
      DateTimeToStr(FCreatedAt),
      FSteps.Count,
      FMetadata.Count
    ]
  );
end;

end.
