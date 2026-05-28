unit Yakko.Generation.Controller;

{ Generation lifecycle controller for YakkoDelphiLLM runtime.
  Architectural intent:
  - separate lifecycle coordination from inference stage execution;
  - keep pipeline focused on stage orchestration, while controller manages
    global execution status and active session tracking;
  - centralize generation session ownership, status transitions and high-level
    observability metadata;
  - prepare future runtime evolution for async execution, cancellation,
    streaming callbacks, tools and reasoning lifecycle control.

  Pipeline vs Controller:
  - Pipeline executes ordered technical stages.
  - Controller governs lifecycle boundaries and session state.

  This unit intentionally does not perform direct backend inference and does not
  integrate with llama.cpp, tokenizer or real streaming yet. }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Yakko.Inference.Types,
  Yakko.Inference.Pipeline;

type
  TYakkoGenerationStatus =
  (
    gsIdle,
    gsPreparing,
    gsRunning,
    gsStreaming,
    gsCompleted,
    gsCancelled,
    gsError
  );

  TYakkoGenerationStatusHelper = record helper for TYakkoGenerationStatus
  public
    function ToString: string;
  end;

  TYakkoGenerationMetadata = TDictionary<string, string>;

  TYakkoGenerationSession = class
  private
    FSessionId: string;
    FStatus: TYakkoGenerationStatus;
    FRequest: TYakkoInferenceRequest;
    FResult: TYakkoInferenceResult;
    FStartedAt: TDateTime;
    FFinishedAt: TDateTime;
    FMetadata: TYakkoGenerationMetadata;
    procedure SetRequest(const Value: TYakkoInferenceRequest);
    procedure SetResult(const Value: TYakkoInferenceResult);
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    function Clone: TYakkoGenerationSession;
    function ToDebugString: string;

    property SessionId: string read FSessionId write FSessionId;
    property Status: TYakkoGenerationStatus read FStatus write FStatus;
    property Request: TYakkoInferenceRequest read FRequest write SetRequest;
    property Result: TYakkoInferenceResult read FResult write SetResult;
    property StartedAt: TDateTime read FStartedAt write FStartedAt;
    property FinishedAt: TDateTime read FFinishedAt write FFinishedAt;
    property Metadata: TYakkoGenerationMetadata read FMetadata;
  end;

  TYakkoGenerationController = class
  private
    FPipeline: TYakkoInferencePipeline;
    FCurrentSession: TYakkoGenerationSession;
    function CreateSessionId: string;
    function MapInferenceStateToStatus(AState: TYakkoInferenceState): TYakkoGenerationStatus;
  public
    constructor Create;
    destructor Destroy; override;

    function StartGeneration(ARequest: TYakkoInferenceRequest): TYakkoGenerationSession;
    procedure CancelGeneration;
    function IsGenerating: Boolean;

    property Pipeline: TYakkoInferencePipeline read FPipeline;
    property CurrentSession: TYakkoGenerationSession read FCurrentSession;
  end;

implementation

procedure CloneStringDictionary(ASource, ADest: TYakkoGenerationMetadata);
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

{ TYakkoGenerationStatusHelper }

function TYakkoGenerationStatusHelper.ToString: string;
begin
  case Self of
    gsIdle:
      Result := 'idle';
    gsPreparing:
      Result := 'preparing';
    gsRunning:
      Result := 'running';
    gsStreaming:
      Result := 'streaming';
    gsCompleted:
      Result := 'completed';
    gsCancelled:
      Result := 'cancelled';
    gsError:
      Result := 'error';
  else
    Result := 'idle';
  end;
end;

{ TYakkoGenerationSession }

constructor TYakkoGenerationSession.Create;
begin
  inherited Create;
  FSessionId := '';
  FStatus := gsIdle;
  FRequest := TYakkoInferenceRequest.Create;
  FResult := TYakkoInferenceResult.Create;
  FStartedAt := 0;
  FFinishedAt := 0;
  FMetadata := TYakkoGenerationMetadata.Create;
end;

destructor TYakkoGenerationSession.Destroy;
begin
  FreeAndNil(FMetadata);
  FreeAndNil(FResult);
  FreeAndNil(FRequest);
  inherited;
end;

procedure TYakkoGenerationSession.SetRequest(const Value: TYakkoInferenceRequest);
begin
  if Value = FRequest then
    Exit;

  FreeAndNil(FRequest);
  if Assigned(Value) then
    FRequest := Value.Clone
  else
    FRequest := TYakkoInferenceRequest.Create;
end;

procedure TYakkoGenerationSession.SetResult(const Value: TYakkoInferenceResult);
begin
  if Value = FResult then
    Exit;

  FreeAndNil(FResult);
  if Assigned(Value) then
    FResult := Value.Clone
  else
    FResult := TYakkoInferenceResult.Create;
end;

procedure TYakkoGenerationSession.Clear;
begin
  FRequest.Free;
  FResult.Free;
  FRequest := TYakkoInferenceRequest.Create;
  FResult := TYakkoInferenceResult.Create;
  FSessionId := '';
  FStatus := gsIdle;
  FStartedAt := 0;
  FFinishedAt := 0;
  FMetadata.Clear;

  { TODO: preserve retry attempt metadata once retry policies become available. }
  { TODO: preserve cancellation state timeline once cancellation tokens are added. }
  { TODO: preserve streaming chunk diagnostics when streaming lifecycle is implemented. }
end;

function TYakkoGenerationSession.Clone: TYakkoGenerationSession;
begin
  Result := TYakkoGenerationSession.Create;
  try
    Result.FSessionId := FSessionId;
    Result.FStatus := FStatus;
    Result.SetRequest(FRequest);
    Result.SetResult(FResult);
    Result.FStartedAt := FStartedAt;
    Result.FFinishedAt := FFinishedAt;
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoGenerationSession.ToDebugString: string;
begin
  Result := Format(
    'TYakkoGenerationSession(Id=%s, Status=%s, StartedAt=%s, FinishedAt=%s, Metadata=%d, ResultState=%d)',
    [
      FSessionId,
      FStatus.ToString,
      DateTimeToStr(FStartedAt),
      DateTimeToStr(FFinishedAt),
      FMetadata.Count,
      Ord(FResult.State)
    ]
  );
end;

{ TYakkoGenerationController }

constructor TYakkoGenerationController.Create;
begin
  inherited Create;
  FPipeline := TYakkoInferencePipeline.Create;
  FCurrentSession := TYakkoGenerationSession.Create;

  { TODO: add tracing bootstrapping for observable runtime lifecycles. }
  { TODO: add metrics aggregation state for global controller-level dashboards. }
end;

destructor TYakkoGenerationController.Destroy;
begin
  FreeAndNil(FCurrentSession);
  FreeAndNil(FPipeline);
  inherited;
end;

function TYakkoGenerationController.CreateSessionId: string;
var
  LGuid: TGuid;
begin
  if CreateGuid(LGuid) = 0 then
    Result := GuidToString(LGuid)
  else
    Result := FormatDateTime('yyyymmddhhnnsszzz', Now);
end;

function TYakkoGenerationController.MapInferenceStateToStatus(
  AState: TYakkoInferenceState): TYakkoGenerationStatus;
begin
  case AState of
    TYakkoInferenceState.isIdle:
      Result := gsIdle;
    TYakkoInferenceState.isPreparing:
      Result := gsPreparing;
    TYakkoInferenceState.isTokenizing:
      Result := gsPreparing;
    TYakkoInferenceState.isGenerating:
      Result := gsRunning;
    TYakkoInferenceState.isStreaming:
      Result := gsStreaming;
    TYakkoInferenceState.isCompleted:
      Result := gsCompleted;
    TYakkoInferenceState.isCancelled:
      Result := gsCancelled;
    TYakkoInferenceState.isError:
      Result := gsError;
  else
    Result := gsError;
  end;
end;

function TYakkoGenerationController.StartGeneration(
  ARequest: TYakkoInferenceRequest): TYakkoGenerationSession;
var
  LPipelineResult: TYakkoInferenceResult;
begin
  if not Assigned(ARequest) then
    raise EArgumentNilException.Create('ARequest must be assigned.');

  if IsGenerating then
    raise EInvalidOpException.Create('Generation already in progress.');

  FCurrentSession.Clear;
  FCurrentSession.SessionId := CreateSessionId;
  FCurrentSession.Status := gsPreparing;
  FCurrentSession.StartedAt := Now;
  FCurrentSession.Metadata.AddOrSetValue('controller.mode', 'sync-placeholder');
  FCurrentSession.Metadata.AddOrSetValue('controller.lifecycle', 'managed');
  FCurrentSession.Request := ARequest;

  try
    FCurrentSession.Status := gsRunning;

    LPipelineResult := FPipeline.Execute(ARequest);
    try
      FCurrentSession.Result := LPipelineResult;
      FCurrentSession.Status := MapInferenceStateToStatus(LPipelineResult.State);
      if FCurrentSession.Status = gsIdle then
        FCurrentSession.Status := gsCompleted;
    finally
      LPipelineResult.Free;
    end;
  except
    on E: Exception do
    begin
      FCurrentSession.Status := gsError;
      FCurrentSession.Metadata.AddOrSetValue('controller.error.class', E.ClassName);
      FCurrentSession.Metadata.AddOrSetValue('controller.error.message', E.Message);
      FCurrentSession.Result.State := isError;
      FCurrentSession.Result.FinishReason := 'controller-exception';
      raise;
    end;
  end;

  FCurrentSession.FinishedAt := Now;
  Result := FCurrentSession.Clone;

  { TODO: add async execution entrypoint for non-blocking generation lifecycle. }
  { TODO: add execution hooks before and after pipeline execution. }
  { TODO: add retry policy orchestration at controller level. }
  { TODO: add concurrency control policy for multiple generation sessions. }
  { TODO: add tool lifecycle and reasoning lifecycle coordination boundaries. }
end;

procedure TYakkoGenerationController.CancelGeneration;
begin
  if not IsGenerating then
    Exit;

  FCurrentSession.Status := gsCancelled;
  FCurrentSession.FinishedAt := Now;
  FCurrentSession.Result.State := isCancelled;
  FCurrentSession.Result.FinishReason := 'cancel-requested';
  FCurrentSession.Metadata.AddOrSetValue('controller.cancel.requested', '1');

  { TODO: connect cancellation tokens once cooperative cancellation is implemented. }
  { TODO: connect streaming callbacks for graceful mid-stream interruption. }
end;

function TYakkoGenerationController.IsGenerating: Boolean;
begin
  Result := FCurrentSession.Status in [gsPreparing, gsRunning, gsStreaming];
end;

end.
