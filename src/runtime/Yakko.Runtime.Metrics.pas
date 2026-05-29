unit Yakko.Runtime.Metrics;

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TYakkoRuntimeMetricsMetadata = TDictionary<string, string>;

  TYakkoRuntimeMetricsSnapshot = class
  private
    FPromptBuildTimeMs: Int64;
    FSerializationTimeMs: Int64;
    FCompositionTimeMs: Int64;
    FCompatibilityValidationTimeMs: Int64;
    FPipelineStageDurationMs: Int64;
    FTokenThroughput: Double;
    FGenerationThroughput: Double;
    FMemoryEstimationMb: Double;
    FCreatedAt: TDateTime;
    FMetadata: TYakkoRuntimeMetricsMetadata;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    function Clone: TYakkoRuntimeMetricsSnapshot;
    function ToDebugString: string;

    property PromptBuildTimeMs: Int64 read FPromptBuildTimeMs write FPromptBuildTimeMs;
    property SerializationTimeMs: Int64 read FSerializationTimeMs write FSerializationTimeMs;
    property CompositionTimeMs: Int64 read FCompositionTimeMs write FCompositionTimeMs;
    property CompatibilityValidationTimeMs: Int64 read FCompatibilityValidationTimeMs write FCompatibilityValidationTimeMs;
    property PipelineStageDurationMs: Int64 read FPipelineStageDurationMs write FPipelineStageDurationMs;
    property TokenThroughput: Double read FTokenThroughput write FTokenThroughput;
    property GenerationThroughput: Double read FGenerationThroughput write FGenerationThroughput;
    property MemoryEstimationMb: Double read FMemoryEstimationMb write FMemoryEstimationMb;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
    property Metadata: TYakkoRuntimeMetricsMetadata read FMetadata;
  end;

  TYakkoMetricsCollector = class
  private
    FCurrent: TYakkoRuntimeMetricsSnapshot;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Reset;
    procedure MarkPromptBuildTime(AMilliseconds: Int64);
    procedure MarkSerializationTime(AMilliseconds: Int64);
    procedure MarkCompositionTime(AMilliseconds: Int64);
    procedure MarkCompatibilityValidationTime(AMilliseconds: Int64);
    procedure MarkPipelineStageDuration(AMilliseconds: Int64);
    procedure MarkTokenThroughput(AValue: Double);
    procedure MarkGenerationThroughput(AValue: Double);
    procedure MarkMemoryEstimation(AValueMb: Double);

    function Snapshot: TYakkoRuntimeMetricsSnapshot;
    function ToDebugString: string;
  end;

implementation

procedure CloneStringDictionary(ASource, ADest: TYakkoRuntimeMetricsMetadata);
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

{ TYakkoRuntimeMetricsSnapshot }

constructor TYakkoRuntimeMetricsSnapshot.Create;
begin
  inherited Create;
  FMetadata := TYakkoRuntimeMetricsMetadata.Create;
  Clear;
end;

destructor TYakkoRuntimeMetricsSnapshot.Destroy;
begin
  FreeAndNil(FMetadata);
  inherited;
end;

procedure TYakkoRuntimeMetricsSnapshot.Clear;
begin
  FPromptBuildTimeMs := 0;
  FSerializationTimeMs := 0;
  FCompositionTimeMs := 0;
  FCompatibilityValidationTimeMs := 0;
  FPipelineStageDurationMs := 0;
  FTokenThroughput := 0;
  FGenerationThroughput := 0;
  FMemoryEstimationMb := 0;
  FCreatedAt := Now;
  FMetadata.Clear;

  { TODO: add percentile summaries when enough operational data exists. }
end;

function TYakkoRuntimeMetricsSnapshot.Clone: TYakkoRuntimeMetricsSnapshot;
begin
  Result := TYakkoRuntimeMetricsSnapshot.Create;
  try
    Result.FPromptBuildTimeMs := FPromptBuildTimeMs;
    Result.FSerializationTimeMs := FSerializationTimeMs;
    Result.FCompositionTimeMs := FCompositionTimeMs;
    Result.FCompatibilityValidationTimeMs := FCompatibilityValidationTimeMs;
    Result.FPipelineStageDurationMs := FPipelineStageDurationMs;
    Result.FTokenThroughput := FTokenThroughput;
    Result.FGenerationThroughput := FGenerationThroughput;
    Result.FMemoryEstimationMb := FMemoryEstimationMb;
    Result.FCreatedAt := FCreatedAt;
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoRuntimeMetricsSnapshot.ToDebugString: string;
begin
  Result := Format(
    'TYakkoRuntimeMetricsSnapshot(PromptBuild=%d, Serialization=%d, Composition=%d, Compatibility=%d, Stage=%d, TokenThroughput=%.4f, GenerationThroughput=%.4f, MemoryEstimationMb=%.2f, Metadata=%d)',
    [
      FPromptBuildTimeMs,
      FSerializationTimeMs,
      FCompositionTimeMs,
      FCompatibilityValidationTimeMs,
      FPipelineStageDurationMs,
      FTokenThroughput,
      FGenerationThroughput,
      FMemoryEstimationMb,
      FMetadata.Count
    ]
  );
end;

{ TYakkoMetricsCollector }

constructor TYakkoMetricsCollector.Create;
begin
  inherited Create;
  FCurrent := TYakkoRuntimeMetricsSnapshot.Create;
end;

destructor TYakkoMetricsCollector.Destroy;
begin
  FreeAndNil(FCurrent);
  inherited;
end;

procedure TYakkoMetricsCollector.Reset;
begin
  FCurrent.Clear;
end;

procedure TYakkoMetricsCollector.MarkPromptBuildTime(AMilliseconds: Int64);
begin
  FCurrent.PromptBuildTimeMs := AMilliseconds;
end;

procedure TYakkoMetricsCollector.MarkSerializationTime(AMilliseconds: Int64);
begin
  FCurrent.SerializationTimeMs := AMilliseconds;
end;

procedure TYakkoMetricsCollector.MarkCompositionTime(AMilliseconds: Int64);
begin
  FCurrent.CompositionTimeMs := AMilliseconds;
end;

procedure TYakkoMetricsCollector.MarkCompatibilityValidationTime(AMilliseconds: Int64);
begin
  FCurrent.CompatibilityValidationTimeMs := AMilliseconds;
end;

procedure TYakkoMetricsCollector.MarkPipelineStageDuration(AMilliseconds: Int64);
begin
  FCurrent.PipelineStageDurationMs := AMilliseconds;
end;

procedure TYakkoMetricsCollector.MarkTokenThroughput(AValue: Double);
begin
  FCurrent.TokenThroughput := AValue;
end;

procedure TYakkoMetricsCollector.MarkGenerationThroughput(AValue: Double);
begin
  FCurrent.GenerationThroughput := AValue;
end;

procedure TYakkoMetricsCollector.MarkMemoryEstimation(AValueMb: Double);
begin
  FCurrent.MemoryEstimationMb := AValueMb;
end;

function TYakkoMetricsCollector.Snapshot: TYakkoRuntimeMetricsSnapshot;
begin
  Result := FCurrent.Clone;
end;

function TYakkoMetricsCollector.ToDebugString: string;
begin
  Result := FCurrent.ToDebugString;
end;

end.
