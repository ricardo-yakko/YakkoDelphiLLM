unit Yakko.Runtime.Diagnostics;

{ Runtime diagnostics and parity validation layer for YakkoDelphiLLM migration.

  Architectural intent:
  - provide a controlled observability boundary between legacy and modern runtimes;
  - validate shadow execution parity without altering production behavior;
  - detect migration regressions early through explicit comparison artifacts;
  - increase migration confidence and rollback safety during strangler adoption.

  This unit is intentionally backend-agnostic and non-invasive:
  - no inference execution;
  - no tokenizer or llama.cpp coupling;
  - no async, no threads, no EventBus.

  RuntimeBridge is expected to be the primary consumer of this diagnostics layer
  during shadow-mode rollout, while legacy runtime remains production-authoritative. }

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Winapi.Windows;

type
  TYakkoComparisonStatus =
  (
    csUnknown,
    csEquivalent,
    csDifferent,
    csWarning,
    csError
  );

  TYakkoComparisonStatusHelper = record helper for TYakkoComparisonStatus
  public
    function ToString: string;
  end;

  TYakkoRuntimeComparisonMetadata = TDictionary<string, string>;

  TYakkoRuntimeMetricsComparison = class
  private
    FLegacyPromptLength: Integer;
    FModernPromptLength: Integer;
    FLegacyExecutionTimeMs: Int64;
    FModernExecutionTimeMs: Int64;
    FLegacyGeneratedLength: Integer;
    FModernGeneratedLength: Integer;
    FLegacyTokenCount: Integer;
    FModernTokenCount: Integer;
  public
    constructor Create;

    procedure Clear;
    function Clone: TYakkoRuntimeMetricsComparison;
    function ToDebugString: string;

    property LegacyPromptLength: Integer read FLegacyPromptLength write FLegacyPromptLength;
    property ModernPromptLength: Integer read FModernPromptLength write FModernPromptLength;
    property LegacyExecutionTimeMs: Int64 read FLegacyExecutionTimeMs write FLegacyExecutionTimeMs;
    property ModernExecutionTimeMs: Int64 read FModernExecutionTimeMs write FModernExecutionTimeMs;
    property LegacyGeneratedLength: Integer read FLegacyGeneratedLength write FLegacyGeneratedLength;
    property ModernGeneratedLength: Integer read FModernGeneratedLength write FModernGeneratedLength;
    property LegacyTokenCount: Integer read FLegacyTokenCount write FLegacyTokenCount;
    property ModernTokenCount: Integer read FModernTokenCount write FModernTokenCount;
  end;

  TYakkoRuntimeComparisonResult = class
  private
    FStatus: TYakkoComparisonStatus;
    FLegacyPrompt: string;
    FModernPrompt: string;
    FLegacyOutput: string;
    FModernOutput: string;
    FDifferences: TStringList;
    FMetrics: TYakkoRuntimeMetricsComparison;
    FCreatedAt: TDateTime;
    FMetadata: TYakkoRuntimeComparisonMetadata;
    procedure SetMetrics(const Value: TYakkoRuntimeMetricsComparison);
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    function Clone: TYakkoRuntimeComparisonResult;
    function ToDebugString: string;

    property Status: TYakkoComparisonStatus read FStatus write FStatus;
    property LegacyPrompt: string read FLegacyPrompt write FLegacyPrompt;
    property ModernPrompt: string read FModernPrompt write FModernPrompt;
    property LegacyOutput: string read FLegacyOutput write FLegacyOutput;
    property ModernOutput: string read FModernOutput write FModernOutput;
    property Differences: TStringList read FDifferences;
    property Metrics: TYakkoRuntimeMetricsComparison read FMetrics write SetMetrics;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
    property Metadata: TYakkoRuntimeComparisonMetadata read FMetadata;
  end;

  TYakkoRuntimeDiagnostics = class
  public
    function ComparePrompts(
      const ALegacyPrompt: string;
      const AModernPrompt: string
    ): TYakkoRuntimeComparisonResult;

    function CompareOutputs(
      const ALegacyOutput: string;
      const AModernOutput: string
    ): TYakkoRuntimeComparisonResult;

    procedure EmitDiagnostics(AResult: TYakkoRuntimeComparisonResult);
  end;

implementation

procedure CloneStringDictionary(ASource, ADest: TYakkoRuntimeComparisonMetadata);
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

procedure AddBasicDifference(ALines: TStringList; const AName: string; ALegacy, AModern: string);
begin
  if not Assigned(ALines) then
    Exit;

  if ALegacy = AModern then
    Exit;

  ALines.Add(Format('%s differs', [AName]));

  if Trim(ALegacy) = '' then
    ALines.Add(Format('%s legacy is empty', [AName]));
  if Trim(AModern) = '' then
    ALines.Add(Format('%s modern is empty', [AName]));
  if Length(ALegacy) <> Length(AModern) then
    ALines.Add(Format('%s length differs: legacy=%d modern=%d', [AName, Length(ALegacy), Length(AModern)]));
end;

{ TYakkoComparisonStatusHelper }

function TYakkoComparisonStatusHelper.ToString: string;
begin
  case Self of
    csUnknown:
      Result := 'unknown';
    csEquivalent:
      Result := 'equivalent';
    csDifferent:
      Result := 'different';
    csWarning:
      Result := 'warning';
    csError:
      Result := 'error';
  else
    Result := 'unknown';
  end;
end;

{ TYakkoRuntimeMetricsComparison }

constructor TYakkoRuntimeMetricsComparison.Create;
begin
  inherited Create;
  Clear;
end;

procedure TYakkoRuntimeMetricsComparison.Clear;
begin
  FLegacyPromptLength := 0;
  FModernPromptLength := 0;
  FLegacyExecutionTimeMs := 0;
  FModernExecutionTimeMs := 0;
  FLegacyGeneratedLength := 0;
  FModernGeneratedLength := 0;
  FLegacyTokenCount := 0;
  FModernTokenCount := 0;
end;

function TYakkoRuntimeMetricsComparison.Clone: TYakkoRuntimeMetricsComparison;
begin
  Result := TYakkoRuntimeMetricsComparison.Create;
  Result.FLegacyPromptLength := FLegacyPromptLength;
  Result.FModernPromptLength := FModernPromptLength;
  Result.FLegacyExecutionTimeMs := FLegacyExecutionTimeMs;
  Result.FModernExecutionTimeMs := FModernExecutionTimeMs;
  Result.FLegacyGeneratedLength := FLegacyGeneratedLength;
  Result.FModernGeneratedLength := FModernGeneratedLength;
  Result.FLegacyTokenCount := FLegacyTokenCount;
  Result.FModernTokenCount := FModernTokenCount;
end;

function TYakkoRuntimeMetricsComparison.ToDebugString: string;
begin
  Result := Format(
    'TYakkoRuntimeMetricsComparison(LegacyPromptLength=%d, ModernPromptLength=%d, LegacyExecutionTimeMs=%d, ModernExecutionTimeMs=%d, LegacyGeneratedLength=%d, ModernGeneratedLength=%d, LegacyTokenCount=%d, ModernTokenCount=%d)',
    [
      FLegacyPromptLength,
      FModernPromptLength,
      FLegacyExecutionTimeMs,
      FModernExecutionTimeMs,
      FLegacyGeneratedLength,
      FModernGeneratedLength,
      FLegacyTokenCount,
      FModernTokenCount
    ]
  );
end;

{ TYakkoRuntimeComparisonResult }

constructor TYakkoRuntimeComparisonResult.Create;
begin
  inherited Create;
  FStatus := csUnknown;
  FLegacyPrompt := '';
  FModernPrompt := '';
  FLegacyOutput := '';
  FModernOutput := '';
  FDifferences := TStringList.Create;
  FMetrics := TYakkoRuntimeMetricsComparison.Create;
  FCreatedAt := Now;
  FMetadata := TYakkoRuntimeComparisonMetadata.Create;
end;

destructor TYakkoRuntimeComparisonResult.Destroy;
begin
  FreeAndNil(FMetadata);
  FreeAndNil(FMetrics);
  FreeAndNil(FDifferences);
  inherited;
end;

procedure TYakkoRuntimeComparisonResult.SetMetrics(
  const Value: TYakkoRuntimeMetricsComparison);
begin
  if Value = FMetrics then
    Exit;

  FreeAndNil(FMetrics);
  if Assigned(Value) then
    FMetrics := Value.Clone
  else
    FMetrics := TYakkoRuntimeMetricsComparison.Create;
end;

procedure TYakkoRuntimeComparisonResult.Clear;
begin
  FStatus := csUnknown;
  FLegacyPrompt := '';
  FModernPrompt := '';
  FLegacyOutput := '';
  FModernOutput := '';
  FDifferences.Clear;
  FMetrics.Clear;
  FCreatedAt := Now;
  FMetadata.Clear;

  { TODO: preserve regression snapshots for longitudinal migration confidence. }
  { TODO: preserve execution replay payload references for reproducible diagnostics. }
end;

function TYakkoRuntimeComparisonResult.Clone: TYakkoRuntimeComparisonResult;
begin
  Result := TYakkoRuntimeComparisonResult.Create;
  try
    Result.FStatus := FStatus;
    Result.FLegacyPrompt := FLegacyPrompt;
    Result.FModernPrompt := FModernPrompt;
    Result.FLegacyOutput := FLegacyOutput;
    Result.FModernOutput := FModernOutput;
    Result.FDifferences.Assign(FDifferences);
    Result.SetMetrics(FMetrics);
    Result.FCreatedAt := FCreatedAt;
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoRuntimeComparisonResult.ToDebugString: string;
begin
  Result := Format(
    'TYakkoRuntimeComparisonResult(Status=%s, LegacyPromptLength=%d, ModernPromptLength=%d, LegacyOutputLength=%d, ModernOutputLength=%d, Differences=%d, CreatedAt=%s)',
    [
      FStatus.ToString,
      Length(FLegacyPrompt),
      Length(FModernPrompt),
      Length(FLegacyOutput),
      Length(FModernOutput),
      FDifferences.Count,
      DateTimeToStr(FCreatedAt)
    ]
  );
end;

{ TYakkoRuntimeDiagnostics }

function TYakkoRuntimeDiagnostics.ComparePrompts(const ALegacyPrompt,
  AModernPrompt: string): TYakkoRuntimeComparisonResult;
begin
  Result := TYakkoRuntimeComparisonResult.Create;
  try
    Result.LegacyPrompt := ALegacyPrompt;
    Result.ModernPrompt := AModernPrompt;
    Result.Metrics.LegacyPromptLength := Length(ALegacyPrompt);
    Result.Metrics.ModernPromptLength := Length(AModernPrompt);
    Result.Metadata.AddOrSetValue('comparison.type', 'prompt');
    Result.Metadata.AddOrSetValue('mode', 'shadow');

    AddBasicDifference(Result.Differences, 'prompt', ALegacyPrompt, AModernPrompt);

    if Result.Differences.Count = 0 then
      Result.Status := csEquivalent
    else if (Trim(ALegacyPrompt) = '') or (Trim(AModernPrompt) = '') then
      Result.Status := csWarning
    else
      Result.Status := csDifferent;

    { TODO: implement semantic diff and structured comparison for prompts. }
    { TODO: implement token diff and prompt AST comparison. }
    { TODO: implement embedding similarity diagnostics for near-equivalent prompts. }
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoRuntimeDiagnostics.CompareOutputs(const ALegacyOutput,
  AModernOutput: string): TYakkoRuntimeComparisonResult;
begin
  Result := TYakkoRuntimeComparisonResult.Create;
  try
    Result.LegacyOutput := ALegacyOutput;
    Result.ModernOutput := AModernOutput;
    Result.Metrics.LegacyGeneratedLength := Length(ALegacyOutput);
    Result.Metrics.ModernGeneratedLength := Length(AModernOutput);
    Result.Metadata.AddOrSetValue('comparison.type', 'output');
    Result.Metadata.AddOrSetValue('mode', 'shadow');

    AddBasicDifference(Result.Differences, 'output', ALegacyOutput, AModernOutput);

    if Result.Differences.Count = 0 then
      Result.Status := csEquivalent
    else if (Trim(ALegacyOutput) = '') or (Trim(AModernOutput) = '') then
      Result.Status := csWarning
    else
      Result.Status := csDifferent;

    { TODO: implement structured output comparison for JSON/schema responses. }
    { TODO: implement streaming diff once chunked modern execution is enabled. }
    { TODO: implement regression snapshots and replay support for output drift. }
  except
    Result.Free;
    raise;
  end;
end;

procedure TYakkoRuntimeDiagnostics.EmitDiagnostics(
  AResult: TYakkoRuntimeComparisonResult);
var
  LBuilder: TStringBuilder;
  LDiff: string;
begin
  if not Assigned(AResult) then
    Exit;

  LBuilder := TStringBuilder.Create;
  try
    LBuilder.Append('[YakkoRuntimeDiagnostics] ');
    LBuilder.Append('Status=').Append(AResult.Status.ToString).Append('; ');
    LBuilder.Append('CreatedAt=').Append(DateTimeToStr(AResult.CreatedAt)).Append('; ');
    LBuilder.Append('LegacyPromptLength=').Append(AResult.Metrics.LegacyPromptLength).Append('; ');
    LBuilder.Append('ModernPromptLength=').Append(AResult.Metrics.ModernPromptLength).Append('; ');
    LBuilder.Append('LegacyOutputLength=').Append(AResult.Metrics.LegacyGeneratedLength).Append('; ');
    LBuilder.Append('ModernOutputLength=').Append(AResult.Metrics.ModernGeneratedLength).Append('; ');
    LBuilder.Append('Differences=').Append(AResult.Differences.Count);

    if AResult.Differences.Count > 0 then
    begin
      LBuilder.Append('; DifferenceList=');
      for LDiff in AResult.Differences do
        LBuilder.Append('[').Append(LDiff).Append(']');
    end;

    OutputDebugString(PChar(LBuilder.ToString));
  finally
    LBuilder.Free;
  end;

  { TODO: integrate telemetry providers and structured metrics sinks. }
  { TODO: integrate OpenTelemetry traces when distributed tracing is adopted. }
  { TODO: expose observability provider abstraction without coupling diagnostics core. }
end;

end.
