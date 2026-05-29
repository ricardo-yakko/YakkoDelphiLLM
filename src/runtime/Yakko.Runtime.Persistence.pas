unit Yakko.Runtime.Persistence;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Yakko.Runtime.Snapshot,
  Yakko.Runtime.Trace,
  Yakko.Runtime.Metrics,
  Yakko.Prompt.Diff;

type
  TYakkoRuntimePersistenceMetadata = TDictionary<string, string>;

  TYakkoPersistenceSnapshot = class
  private
    FCreatedAt: TDateTime;
    FRuntimeSnapshot: TYakkoRuntimeSnapshot;
    FExecutionTrace: TYakkoExecutionTrace;
    FMetricsSnapshot: TYakkoRuntimeMetricsSnapshot;
    FPromptDiffSnapshot: TYakkoPromptDiffResult;
    FMetadata: TYakkoRuntimePersistenceMetadata;

    procedure SetRuntimeSnapshot(const Value: TYakkoRuntimeSnapshot);
    procedure SetExecutionTrace(const Value: TYakkoExecutionTrace);
    procedure SetMetricsSnapshot(const Value: TYakkoRuntimeMetricsSnapshot);
    procedure SetPromptDiffSnapshot(const Value: TYakkoPromptDiffResult);
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    function Clone: TYakkoPersistenceSnapshot;
    function ToDebugString: string;

    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
    property RuntimeSnapshot: TYakkoRuntimeSnapshot read FRuntimeSnapshot write SetRuntimeSnapshot;
    property ExecutionTrace: TYakkoExecutionTrace read FExecutionTrace write SetExecutionTrace;
    property MetricsSnapshot: TYakkoRuntimeMetricsSnapshot read FMetricsSnapshot write SetMetricsSnapshot;
    property PromptDiffSnapshot: TYakkoPromptDiffResult read FPromptDiffSnapshot write SetPromptDiffSnapshot;
    property Metadata: TYakkoRuntimePersistenceMetadata read FMetadata;
  end;

  TYakkoRuntimePersistenceManager = class
  private
    FSnapshots: TObjectList<TYakkoPersistenceSnapshot>;
  public
    constructor Create;
    destructor Destroy; override;

    procedure SaveSnapshot(ASnapshot: TYakkoPersistenceSnapshot);
    function SnapshotCount: Integer;
    function SnapshotAt(AIndex: Integer): TYakkoPersistenceSnapshot;
    procedure Clear;
    function ToDebugString: string;
  end;

implementation

procedure CloneStringDictionary(ASource, ADest: TYakkoRuntimePersistenceMetadata);
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

{ TYakkoPersistenceSnapshot }

constructor TYakkoPersistenceSnapshot.Create;
begin
  inherited Create;
  FCreatedAt := Now;
  FRuntimeSnapshot := nil;
  FExecutionTrace := nil;
  FMetricsSnapshot := nil;
  FPromptDiffSnapshot := nil;
  FMetadata := TYakkoRuntimePersistenceMetadata.Create;
end;

destructor TYakkoPersistenceSnapshot.Destroy;
begin
  FreeAndNil(FMetadata);
  FreeAndNil(FPromptDiffSnapshot);
  FreeAndNil(FMetricsSnapshot);
  FreeAndNil(FExecutionTrace);
  FreeAndNil(FRuntimeSnapshot);
  inherited;
end;

procedure TYakkoPersistenceSnapshot.SetRuntimeSnapshot(
  const Value: TYakkoRuntimeSnapshot);
begin
  FreeAndNil(FRuntimeSnapshot);
  if Assigned(Value) then
    FRuntimeSnapshot := Value.Clone;
end;

procedure TYakkoPersistenceSnapshot.SetExecutionTrace(
  const Value: TYakkoExecutionTrace);
begin
  FreeAndNil(FExecutionTrace);
  if Assigned(Value) then
    FExecutionTrace := Value.Clone;
end;

procedure TYakkoPersistenceSnapshot.SetMetricsSnapshot(
  const Value: TYakkoRuntimeMetricsSnapshot);
begin
  FreeAndNil(FMetricsSnapshot);
  if Assigned(Value) then
    FMetricsSnapshot := Value.Clone;
end;

procedure TYakkoPersistenceSnapshot.SetPromptDiffSnapshot(
  const Value: TYakkoPromptDiffResult);
begin
  FreeAndNil(FPromptDiffSnapshot);
  if Assigned(Value) then
    FPromptDiffSnapshot := Value.Clone;
end;

procedure TYakkoPersistenceSnapshot.Clear;
begin
  FCreatedAt := Now;
  FreeAndNil(FRuntimeSnapshot);
  FreeAndNil(FExecutionTrace);
  FreeAndNil(FMetricsSnapshot);
  FreeAndNil(FPromptDiffSnapshot);
  FMetadata.Clear;

  { TODO: add snapshot versioning once persistence schema evolves. }
end;

function TYakkoPersistenceSnapshot.Clone: TYakkoPersistenceSnapshot;
begin
  Result := TYakkoPersistenceSnapshot.Create;
  try
    Result.FCreatedAt := FCreatedAt;
    Result.SetRuntimeSnapshot(FRuntimeSnapshot);
    Result.SetExecutionTrace(FExecutionTrace);
    Result.SetMetricsSnapshot(FMetricsSnapshot);
    Result.SetPromptDiffSnapshot(FPromptDiffSnapshot);
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoPersistenceSnapshot.ToDebugString: string;
begin
  Result := Format(
    'TYakkoPersistenceSnapshot(CreatedAt=%s, RuntimeSnapshot=%s, ExecutionTrace=%s, Metrics=%s, PromptDiff=%s, Metadata=%d)',
    [
      DateTimeToStr(FCreatedAt),
      BoolToStr(Assigned(FRuntimeSnapshot), True),
      BoolToStr(Assigned(FExecutionTrace), True),
      BoolToStr(Assigned(FMetricsSnapshot), True),
      BoolToStr(Assigned(FPromptDiffSnapshot), True),
      FMetadata.Count
    ]
  );
end;

{ TYakkoRuntimePersistenceManager }

constructor TYakkoRuntimePersistenceManager.Create;
begin
  inherited Create;
  FSnapshots := TObjectList<TYakkoPersistenceSnapshot>.Create(True);
end;

destructor TYakkoRuntimePersistenceManager.Destroy;
begin
  FreeAndNil(FSnapshots);
  inherited;
end;

procedure TYakkoRuntimePersistenceManager.SaveSnapshot(
  ASnapshot: TYakkoPersistenceSnapshot);
begin
  if not Assigned(ASnapshot) then
    raise EArgumentNilException.Create('ASnapshot must be assigned.');

  FSnapshots.Add(ASnapshot.Clone);
end;

function TYakkoRuntimePersistenceManager.SnapshotCount: Integer;
begin
  Result := FSnapshots.Count;
end;

function TYakkoRuntimePersistenceManager.SnapshotAt(
  AIndex: Integer): TYakkoPersistenceSnapshot;
begin
  if (AIndex < 0) or (AIndex >= FSnapshots.Count) then
    raise EArgumentOutOfRangeException.Create('Snapshot index out of range.');

  Result := FSnapshots[AIndex].Clone;
end;

procedure TYakkoRuntimePersistenceManager.Clear;
begin
  FSnapshots.Clear;
end;

function TYakkoRuntimePersistenceManager.ToDebugString: string;
begin
  Result := Format('TYakkoRuntimePersistenceManager(Snapshots=%d)', [FSnapshots.Count]);
end;

end.
