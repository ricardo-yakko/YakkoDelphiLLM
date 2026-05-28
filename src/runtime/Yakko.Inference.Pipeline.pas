unit Yakko.Inference.Pipeline;

{ Modern inference pipeline architecture for YakkoDelphiLLM runtime.
  Architectural intent:
  - separate monolithic procedural execution into explicit, evolvable stages;
  - isolate pipeline coordination from backend-specific generation code;
  - make execution flow observable and testable through context snapshots;
  - prepare the runtime for modern capabilities such as tools, reasoning,
    streaming, cancellation and advanced decoding strategies.

  This unit intentionally does not perform real inference yet. It introduces the
  orchestration structure only, preserving runtime behavior while creating a safe
  migration path away from procedural execution. }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Yakko.Inference.Types;

type
  TYakkoInferenceStage =
  (
    ipsPreparation,
    ipsTokenization,
    ipsGeneration,
    ipsSampling,
    ipsStreaming,
    ipsFinalization
  );

  TYakkoInferenceStageHelper = record helper for TYakkoInferenceStage
  public
    function ToString: string;
  end;

  TYakkoInferencePipelineMetadata = TDictionary<string, string>;

  TYakkoInferencePipelineContext = class
  private
    FRequest: TYakkoInferenceRequest;
    FResult: TYakkoInferenceResult;
    FCurrentStage: TYakkoInferenceStage;
    FMetadata: TYakkoInferencePipelineMetadata;
    procedure SetRequest(const Value: TYakkoInferenceRequest);
    procedure SetResult(const Value: TYakkoInferenceResult);
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    function Clone: TYakkoInferencePipelineContext;
    function ToDebugString: string;

    property Request: TYakkoInferenceRequest read FRequest write SetRequest;
    property Result: TYakkoInferenceResult read FResult write SetResult;
    property CurrentStage: TYakkoInferenceStage read FCurrentStage write FCurrentStage;
    property Metadata: TYakkoInferencePipelineMetadata read FMetadata;
  end;

  { Stage contract for inference orchestration.
    Each stage is responsible for one isolated execution concern and can be
    evolved independently. This stage boundary prepares the pipeline for future
    hooks, tracing points and replacement of concrete implementations. }
  IYakkoInferenceStage = interface
    ['{A8BB6AF3-A47D-475F-B236-E6A96EC864EA}']
    function StageType: TYakkoInferenceStage;
    procedure Execute(AContext: TYakkoInferencePipelineContext);
  end;

  TYakkoBaseInferenceStage = class abstract(TInterfacedObject, IYakkoInferenceStage)
  protected
    procedure UpdateStage(AContext: TYakkoInferencePipelineContext; AStage: TYakkoInferenceStage);
  public
    function StageType: TYakkoInferenceStage; virtual; abstract;
    procedure Execute(AContext: TYakkoInferencePipelineContext); virtual; abstract;
  end;

  TYakkoPreparationStage = class(TYakkoBaseInferenceStage)
  public
    function StageType: TYakkoInferenceStage; override;
    procedure Execute(AContext: TYakkoInferencePipelineContext); override;
  end;

  TYakkoTokenizationStage = class(TYakkoBaseInferenceStage)
  public
    function StageType: TYakkoInferenceStage; override;
    procedure Execute(AContext: TYakkoInferencePipelineContext); override;
  end;

  TYakkoGenerationStage = class(TYakkoBaseInferenceStage)
  public
    function StageType: TYakkoInferenceStage; override;
    procedure Execute(AContext: TYakkoInferencePipelineContext); override;
  end;

  TYakkoSamplingStage = class(TYakkoBaseInferenceStage)
  public
    function StageType: TYakkoInferenceStage; override;
    procedure Execute(AContext: TYakkoInferencePipelineContext); override;
  end;

  TYakkoStreamingStage = class(TYakkoBaseInferenceStage)
  public
    function StageType: TYakkoInferenceStage; override;
    procedure Execute(AContext: TYakkoInferencePipelineContext); override;
  end;

  TYakkoFinalizationStage = class(TYakkoBaseInferenceStage)
  public
    function StageType: TYakkoInferenceStage; override;
    procedure Execute(AContext: TYakkoInferencePipelineContext); override;
  end;

  TYakkoInferencePipeline = class
  private
    FStages: TList<IYakkoInferenceStage>;
  public
    constructor Create;
    destructor Destroy; override;

    procedure AddStage(const AStage: IYakkoInferenceStage);
    function Execute(ARequest: TYakkoInferenceRequest): TYakkoInferenceResult;
  end;

implementation

procedure CloneStringDictionary(ASource, ADest: TYakkoInferencePipelineMetadata);
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

function MapStageToInferenceState(AStage: TYakkoInferenceStage): TYakkoInferenceState;
begin
  case AStage of
    ipsPreparation:
      Result := isPreparing;
    ipsTokenization:
      Result := isTokenizing;
    ipsGeneration:
      Result := isGenerating;
    ipsSampling:
      Result := isGenerating;
    ipsStreaming:
      Result := isStreaming;
    ipsFinalization:
      Result := isCompleted;
  else
    Result := isIdle;
  end;
end;

{ TYakkoInferenceStageHelper }

function TYakkoInferenceStageHelper.ToString: string;
begin
  case Self of
    ipsPreparation:
      Result := 'preparation';
    ipsTokenization:
      Result := 'tokenization';
    ipsGeneration:
      Result := 'generation';
    ipsSampling:
      Result := 'sampling';
    ipsStreaming:
      Result := 'streaming';
    ipsFinalization:
      Result := 'finalization';
  else
    Result := 'preparation';
  end;
end;

{ TYakkoInferencePipelineContext }

constructor TYakkoInferencePipelineContext.Create;
begin
  inherited Create;
  FRequest := TYakkoInferenceRequest.Create;
  FResult := TYakkoInferenceResult.Create;
  FCurrentStage := ipsPreparation;
  FMetadata := TYakkoInferencePipelineMetadata.Create;
end;

destructor TYakkoInferencePipelineContext.Destroy;
begin
  FreeAndNil(FMetadata);
  FreeAndNil(FResult);
  FreeAndNil(FRequest);
  inherited;
end;

procedure TYakkoInferencePipelineContext.SetRequest(
  const Value: TYakkoInferenceRequest);
begin
  if Value = FRequest then
    Exit;

  FreeAndNil(FRequest);
  if Assigned(Value) then
    FRequest := Value.Clone
  else
    FRequest := TYakkoInferenceRequest.Create;
end;

procedure TYakkoInferencePipelineContext.SetResult(
  const Value: TYakkoInferenceResult);
begin
  if Value = FResult then
    Exit;

  FreeAndNil(FResult);
  if Assigned(Value) then
    FResult := Value.Clone
  else
    FResult := TYakkoInferenceResult.Create;
end;

procedure TYakkoInferencePipelineContext.Clear;
begin
  FRequest.Free;
  FResult.Free;
  FRequest := TYakkoInferenceRequest.Create;
  FResult := TYakkoInferenceResult.Create;
  FCurrentStage := ipsPreparation;
  FMetadata.Clear;

  { TODO: preserve stage metrics snapshots when per-stage telemetry is introduced. }
  { TODO: preserve cancellation state once cancellation tokens become part of context. }
end;

function TYakkoInferencePipelineContext.Clone: TYakkoInferencePipelineContext;
begin
  Result := TYakkoInferencePipelineContext.Create;
  try
    Result.SetRequest(FRequest);
    Result.SetResult(FResult);
    Result.FCurrentStage := FCurrentStage;
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoInferencePipelineContext.ToDebugString: string;
begin
  Result := Format(
    'TYakkoInferencePipelineContext(CurrentStage=%s, Request=%s, Result=%s, Metadata=%d)',
    [
      FCurrentStage.ToString,
      FRequest.ToDebugString,
      FResult.ToDebugString,
      FMetadata.Count
    ]
  );
end;

{ TYakkoBaseInferenceStage }

procedure TYakkoBaseInferenceStage.UpdateStage(
  AContext: TYakkoInferencePipelineContext; AStage: TYakkoInferenceStage);
begin
  if not Assigned(AContext) then
    raise EArgumentNilException.Create('AContext must be assigned.');

  AContext.CurrentStage := AStage;
  AContext.Result.State := MapStageToInferenceState(AStage);
  AContext.Metadata.AddOrSetValue('stage.current', AStage.ToString);

  { TODO: add execution hooks and trace spans per stage transition. }
  { TODO: add stage metrics timing start/stop fields for observability. }
end;

{ TYakkoPreparationStage }

function TYakkoPreparationStage.StageType: TYakkoInferenceStage;
begin
  Result := ipsPreparation;
end;

procedure TYakkoPreparationStage.Execute(AContext: TYakkoInferencePipelineContext);
begin
  UpdateStage(AContext, StageType);

  { TODO: validate request constraints and normalize execution parameters. }
  { TODO: prepare retry policy metadata and execution hook envelopes. }
  { TODO: prepare cancellation integration once tokens are introduced. }
end;

{ TYakkoTokenizationStage }

function TYakkoTokenizationStage.StageType: TYakkoInferenceStage;
begin
  Result := ipsTokenization;
end;

procedure TYakkoTokenizationStage.Execute(AContext: TYakkoInferencePipelineContext);
begin
  UpdateStage(AContext, StageType);

  { TODO: integrate tokenizer abstraction without binding to concrete backend yet. }
  { TODO: add token attribution data collection for prompt/response accounting. }
  { TODO: support grammar constraints and JSON schema constrained decoding setup. }
end;

{ TYakkoGenerationStage }

function TYakkoGenerationStage.StageType: TYakkoInferenceStage;
begin
  Result := ipsGeneration;
end;

procedure TYakkoGenerationStage.Execute(AContext: TYakkoInferencePipelineContext);
begin
  UpdateStage(AContext, StageType);

  { TODO: connect to concrete backend generation adapter (llama.cpp or other). }
  { TODO: add speculative decoding scaffolding and draft-model coordination. }
  { TODO: support KV cache reuse strategy negotiation. }
end;

{ TYakkoSamplingStage }

function TYakkoSamplingStage.StageType: TYakkoInferenceStage;
begin
  Result := ipsSampling;
end;

procedure TYakkoSamplingStage.Execute(AContext: TYakkoInferencePipelineContext);
begin
  UpdateStage(AContext, StageType);

  { TODO: apply sampling policies in a dedicated pluggable sampling component. }
  { TODO: add batching-aware sampling orchestration for grouped requests. }
  { TODO: add retry policies for recoverable sampling failures. }
end;

{ TYakkoStreamingStage }

function TYakkoStreamingStage.StageType: TYakkoInferenceStage;
begin
  Result := ipsStreaming;
end;

procedure TYakkoStreamingStage.Execute(AContext: TYakkoInferencePipelineContext);
begin
  UpdateStage(AContext, StageType);

  { TODO: add streaming callbacks and incremental chunk delivery adapters. }
  { TODO: add observable tracing events for token/chunk flow. }
  { TODO: support tool/reasoning event channels once stage hooks exist. }
end;

{ TYakkoFinalizationStage }

function TYakkoFinalizationStage.StageType: TYakkoInferenceStage;
begin
  Result := ipsFinalization;
end;

procedure TYakkoFinalizationStage.Execute(AContext: TYakkoInferencePipelineContext);
begin
  UpdateStage(AContext, StageType);

  if AContext.Result.State <> isError then
    AContext.Result.State := isCompleted;

  { TODO: finalize metrics aggregation and stage timing consolidation. }
  { TODO: finalize cancellation status handling once cancellation tokens exist. }
end;

{ TYakkoInferencePipeline }

constructor TYakkoInferencePipeline.Create;
begin
  inherited Create;
  FStages := TList<IYakkoInferenceStage>.Create;

  { Default stage order keeps execution explicit and observable.
    Stages are placeholders only in this first architecture cut. }
  AddStage(TYakkoPreparationStage.Create);
  AddStage(TYakkoTokenizationStage.Create);
  AddStage(TYakkoGenerationStage.Create);
  AddStage(TYakkoSamplingStage.Create);
  AddStage(TYakkoStreamingStage.Create);
  AddStage(TYakkoFinalizationStage.Create);
end;

destructor TYakkoInferencePipeline.Destroy;
begin
  FreeAndNil(FStages);
  inherited;
end;

procedure TYakkoInferencePipeline.AddStage(const AStage: IYakkoInferenceStage);
begin
  if not Assigned(AStage) then
    raise EArgumentNilException.Create('AStage must be assigned.');

  FStages.Add(AStage);
end;

function TYakkoInferencePipeline.Execute(
  ARequest: TYakkoInferenceRequest): TYakkoInferenceResult;
var
  LContext: TYakkoInferencePipelineContext;
  LStage: IYakkoInferenceStage;
begin
  if not Assigned(ARequest) then
    raise EArgumentNilException.Create('ARequest must be assigned.');

  LContext := TYakkoInferencePipelineContext.Create;
  try
    LContext.Request := ARequest;
    LContext.Result.State := isPreparing;
    LContext.Metadata.AddOrSetValue('pipeline.mode', 'placeholder');

    for LStage in FStages do
      LStage.Execute(LContext);

    Result := LContext.Result.Clone;
  finally
    LContext.Free;
  end;

  { TODO: add cancellation token checks before/after each stage execution. }
  { TODO: add execution hooks for before-stage and after-stage interception. }
end;

end.
