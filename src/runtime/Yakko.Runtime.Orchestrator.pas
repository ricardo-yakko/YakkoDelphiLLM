unit Yakko.Runtime.Orchestrator;

{ Central runtime orchestration layer for YakkoDelphiLLM.

  Architectural intent:
  - centralize the order of execution for the modern runtime flow;
  - coordinate policies, hooks, diagnostics and generation control from one place;
  - keep the bridge thin and keep controller/pipeline/hook/policy units focused;
  - prepare future tracing, rollback and extensibility without coupling them now.

  Controller vs Orchestrator:
  - the controller owns generation lifecycle boundaries for a single execution;
  - the orchestrator owns the runtime-wide governance order around that lifecycle;
  - the orchestrator decides when policies, hooks and diagnostics are allowed to run.

  This unit is intentionally synchronous and backend-agnostic in this first phase:
  no async orchestration, no EventBus, no plugin loader, no distributed tracing,
  no retries, no rollback automation and no real inference integration here. }

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Generics.Collections,
  Yakko.Inference.Types,
  Yakko.Generation.Controller,
  Yakko.Runtime.Policies,
  Yakko.Runtime.Hooks,
  Yakko.Runtime.Diagnostics;

type
  TYakkoRuntimeOrchestrationStage =
  (
    rosInitialization,
    rosPolicyEvaluation,
    rosHookExecution,
    rosDiagnostics,
    rosGeneration,
    rosFinalization
  );

  TYakkoRuntimeOrchestrationStageHelper = record helper for TYakkoRuntimeOrchestrationStage
  public
    function ToString: string;
  end;

  TYakkoRuntimeOrchestrationMetadata = TDictionary<string, string>;

  TYakkoRuntimeOrchestrationContext = class
  private
    FCurrentStage: TYakkoRuntimeOrchestrationStage;
    FMetadata: TYakkoRuntimeOrchestrationMetadata;
    FCreatedAt: TDateTime;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    function Clone: TYakkoRuntimeOrchestrationContext;
    function ToDebugString: string;

    property CurrentStage: TYakkoRuntimeOrchestrationStage read FCurrentStage write FCurrentStage;
    property Metadata: TYakkoRuntimeOrchestrationMetadata read FMetadata;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
  end;

  TYakkoRuntimeOrchestrator = class
  private
    FPolicyManager: TYakkoRuntimePolicyManager;
    FHookManager: TYakkoRuntimeHookManager;
    FDiagnostics: TYakkoRuntimeDiagnostics;
    FGenerationController: TYakkoGenerationController;
    procedure SetStage(AContext: TYakkoRuntimeOrchestrationContext; AStage: TYakkoRuntimeOrchestrationStage);
    procedure TraceStage(const AStage: TYakkoRuntimeOrchestrationStage; const AMessage: string);
  public
    constructor Create;
    destructor Destroy; override;

    function Execute(ARequest: TYakkoInferenceRequest): TYakkoInferenceResult;
  end;

implementation

procedure CloneStringDictionary(ASource, ADest: TYakkoRuntimeOrchestrationMetadata);
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

{ TYakkoRuntimeOrchestrationStageHelper }

function TYakkoRuntimeOrchestrationStageHelper.ToString: string;
begin
  case Self of
    rosInitialization:
      Result := 'initialization';
    rosPolicyEvaluation:
      Result := 'policy-evaluation';
    rosHookExecution:
      Result := 'hook-execution';
    rosDiagnostics:
      Result := 'diagnostics';
    rosGeneration:
      Result := 'generation';
    rosFinalization:
      Result := 'finalization';
  else
    Result := 'initialization';
  end;
end;

{ TYakkoRuntimeOrchestrationContext }

constructor TYakkoRuntimeOrchestrationContext.Create;
begin
  inherited Create;
  FCurrentStage := rosInitialization;
  FMetadata := TYakkoRuntimeOrchestrationMetadata.Create;
  FCreatedAt := Now;
end;

destructor TYakkoRuntimeOrchestrationContext.Destroy;
begin
  FreeAndNil(FMetadata);
  inherited;
end;

procedure TYakkoRuntimeOrchestrationContext.Clear;
begin
  FCurrentStage := rosInitialization;
  FMetadata.Clear;
  FCreatedAt := Now;

  { TODO: add execution snapshots for replay-oriented orchestration debugging. }
  { TODO: add rollback markers for safe unwind orchestration. }
  { TODO: add tracing identifiers for distributed trace propagation. }
end;

function TYakkoRuntimeOrchestrationContext.Clone: TYakkoRuntimeOrchestrationContext;
begin
  Result := TYakkoRuntimeOrchestrationContext.Create;
  try
    Result.FCurrentStage := FCurrentStage;
    Result.FCreatedAt := FCreatedAt;
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoRuntimeOrchestrationContext.ToDebugString: string;
begin
  Result := Format(
    'TYakkoRuntimeOrchestrationContext(CurrentStage=%s, CreatedAt=%s, Metadata=%d)',
    [
      FCurrentStage.ToString,
      DateTimeToStr(FCreatedAt),
      FMetadata.Count
    ]
  );
end;

{ TYakkoRuntimeOrchestrator }

constructor TYakkoRuntimeOrchestrator.Create;
begin
  inherited Create;
  FPolicyManager := TYakkoRuntimePolicyManager.Create;
  FHookManager := TYakkoRuntimeHookManager.Create;
  FDiagnostics := TYakkoRuntimeDiagnostics.Create;
  FGenerationController := TYakkoGenerationController.Create;

  { TODO: add a lightweight orchestration registry for future execution modes. }
  { TODO: add central observability provider abstraction when tracing is introduced. }
end;

destructor TYakkoRuntimeOrchestrator.Destroy;
begin
  FreeAndNil(FGenerationController);
  FreeAndNil(FDiagnostics);
  FreeAndNil(FHookManager);
  FreeAndNil(FPolicyManager);
  inherited;
end;

procedure TYakkoRuntimeOrchestrator.SetStage(
  AContext: TYakkoRuntimeOrchestrationContext; AStage: TYakkoRuntimeOrchestrationStage);
begin
  if not Assigned(AContext) then
    raise EArgumentNilException.Create('AContext must be assigned.');

  AContext.CurrentStage := AStage;
  AContext.Metadata.AddOrSetValue('orchestrator.stage', AStage.ToString);
  AContext.Metadata.AddOrSetValue('orchestrator.stage.timestamp', DateTimeToStr(Now));
  TraceStage(AStage, 'stage-transition');
end;

procedure TYakkoRuntimeOrchestrator.TraceStage(
  const AStage: TYakkoRuntimeOrchestrationStage; const AMessage: string);
begin
  OutputDebugString(PChar(Format('[YakkoRuntimeOrchestrator] %s=%s', [AMessage, AStage.ToString])));
end;

function TYakkoRuntimeOrchestrator.Execute(
  ARequest: TYakkoInferenceRequest): TYakkoInferenceResult;
var
  LContext: TYakkoRuntimeOrchestrationContext;
  LRequest: TYakkoInferenceRequest;
  LPolicyContext: TYakkoRuntimePolicyContext;
  LPolicyResult: TYakkoPolicyResult;
  LHookContext: TYakkoRuntimeHookContext;
  LPromptDiagnostics: TYakkoRuntimeComparisonResult;
  LOutputDiagnostics: TYakkoRuntimeComparisonResult;
  LSession: TYakkoGenerationSession;
  LPolicyType: TYakkoRuntimePolicyType;
  LDenied: Boolean;
  LPolicyTypes: array[0..4] of TYakkoRuntimePolicyType;

  procedure AddOrchestrationMetadata(const AKey, AValue: string);
  begin
    LContext.Metadata.AddOrSetValue(AKey, AValue);
  end;

  procedure EvaluatePolicy(const APolicyType: TYakkoRuntimePolicyType);
  begin
    LPolicyResult := FPolicyManager.EvaluatePolicies(APolicyType, LPolicyContext);
    try
      AddOrchestrationMetadata('policy.' + APolicyType.ToString + '.decision', LPolicyResult.Decision.ToString);
      AddOrchestrationMetadata('policy.' + APolicyType.ToString + '.reason', LPolicyResult.Reason);

      if LPolicyResult.Decision = pdDeny then
      begin
        LDenied := True;
        AddOrchestrationMetadata('orchestrator.blocked', '1');
        AddOrchestrationMetadata('orchestrator.block.reason', LPolicyResult.Reason);
      end;
    finally
      LPolicyResult.Free;
    end;
  end;

begin
  if not Assigned(ARequest) then
    raise EArgumentNilException.Create('ARequest must be assigned.');

  LContext := TYakkoRuntimeOrchestrationContext.Create;
  LRequest := ARequest.Clone;
  LPolicyContext := TYakkoRuntimePolicyContext.Create;
  LHookContext := TYakkoRuntimeHookContext.Create;
  try
    SetStage(LContext, rosInitialization);
    AddOrchestrationMetadata('orchestrator.mode', 'sync');
    AddOrchestrationMetadata('orchestrator.controller', 'generation-controller');
    AddOrchestrationMetadata('orchestrator.pipeline', 'inference-pipeline');
    AddOrchestrationMetadata('request.max_tokens', IntToStr(LRequest.MaxTokens));
    AddOrchestrationMetadata('request.stream', BoolToStr(LRequest.Stream, True));
    AddOrchestrationMetadata('request.prompt_blocks', IntToStr(LRequest.PromptDocument.BlockCount));
    AddOrchestrationMetadata('request.metadata', IntToStr(LRequest.Metadata.Count));
    AddOrchestrationMetadata('orchestrator.context.created_at', DateTimeToStr(LContext.CreatedAt));

    LPolicyContext.Metadata.AddOrSetValue('orchestrator.context', LContext.ToDebugString);
    LPolicyContext.Metadata.AddOrSetValue('request.snapshot', LRequest.ToDebugString);

    { Policies are evaluated first so the runtime can refuse or annotate work
      before any hook, diagnostic or generation step runs. }
    SetStage(LContext, rosPolicyEvaluation);
    LDenied := False;
    LPolicyTypes[0] := rptPromptMutation;
    LPolicyTypes[1] := rptToolExecution;
    LPolicyTypes[2] := rptReasoningVisibility;
    LPolicyTypes[3] := rptRAGInjection;
    LPolicyTypes[4] := rptOutputMutation;

    for LPolicyType in LPolicyTypes do
    begin
      EvaluatePolicy(LPolicyType);
      if LDenied then
        Break;
    end;

    if LDenied then
    begin
      SetStage(LContext, rosFinalization);
      Result := TYakkoInferenceResult.Create;
      Result.State := isError;
      Result.FinishReason := 'policy-denied';
      Result.Metadata.AddOrSetValue('orchestrator.blocked', '1');
      Result.Metadata.AddOrSetValue('orchestrator.context', LContext.ToDebugString);

      LPromptDiagnostics := FDiagnostics.ComparePrompts(
        ARequest.PromptDocument.ToDebugString,
        LRequest.PromptDocument.ToDebugString);
      try
        FDiagnostics.EmitDiagnostics(LPromptDiagnostics);
      finally
        LPromptDiagnostics.Free;
      end;

      LOutputDiagnostics := FDiagnostics.CompareOutputs('', '');
      try
        FDiagnostics.EmitDiagnostics(LOutputDiagnostics);
      finally
        LOutputDiagnostics.Free;
      end;

      Exit;
    end;

    { Hooks execute after policies because hooks should observe an already-guarded flow.
      This keeps interception separate from governance and avoids cross-cutting leakage. }
    SetStage(LContext, rosHookExecution);
    LHookContext.Metadata.AddOrSetValue('orchestrator.context', LContext.ToDebugString);
    LHookContext.Metadata.AddOrSetValue('hook.phase', 'before-generation');
    FHookManager.ExecuteHooks(rhtBeforeInference, LHookContext);

    { Diagnostics run before the controller so the orchestrator can snapshot the
      request state before lifecycle ownership moves into generation control. }
    SetStage(LContext, rosDiagnostics);
    LPromptDiagnostics := FDiagnostics.ComparePrompts(
      ARequest.PromptDocument.ToDebugString,
      LRequest.PromptDocument.ToDebugString);
    try
      FDiagnostics.EmitDiagnostics(LPromptDiagnostics);
    finally
      LPromptDiagnostics.Free;
    end;

    { The controller owns the single-run generation lifecycle, while the
      orchestrator remains responsible for the runtime-wide order and guardrails. }
    SetStage(LContext, rosGeneration);
    LSession := FGenerationController.StartGeneration(LRequest);
    try
      Result := LSession.Result.Clone;
      Result.Metadata.AddOrSetValue('orchestrator.context', LContext.ToDebugString);
      Result.Metadata.AddOrSetValue('orchestrator.session', LSession.ToDebugString);
    finally
      LSession.Free;
    end;

    SetStage(LContext, rosHookExecution);
    LHookContext.Metadata.AddOrSetValue('hook.phase', 'after-generation');
    FHookManager.ExecuteHooks(rhtAfterInference, LHookContext);

    SetStage(LContext, rosDiagnostics);
    LOutputDiagnostics := FDiagnostics.CompareOutputs('', Result.GeneratedText);
    try
      FDiagnostics.EmitDiagnostics(LOutputDiagnostics);
    finally
      LOutputDiagnostics.Free;
    end;

    SetStage(LContext, rosFinalization);
    Result.Metadata.AddOrSetValue('orchestrator.final.stage', LContext.CurrentStage.ToString);
    Result.Metadata.AddOrSetValue('orchestrator.final.context', LContext.ToDebugString);
    Result.FinishReason := Result.FinishReason;

    { TODO: async orchestration. }
    { TODO: execution replay. }
    { TODO: rollback orchestration. }
    { TODO: distributed tracing. }
    { TODO: OpenTelemetry. }
    { TODO: execution snapshots. }
    { TODO: streaming orchestration. }
    { TODO: tool orchestration. }
    { TODO: reasoning orchestration. }
    { TODO: multimodal orchestration. }
  finally
    LHookContext.Free;
    LPolicyContext.Free;
    LRequest.Free;
    LContext.Free;
  end;
end;

end.
