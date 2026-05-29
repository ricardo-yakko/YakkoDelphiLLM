unit Yakko.Runtime.Policies;

{ Runtime policy architecture for governance and guardrails in YakkoDelphiLLM.

  Architectural intent:
  - keep governance concerns separate from extension concerns;
  - let hooks intercept flow while policies decide what is allowed;
  - centralize runtime guardrails without contaminating bridge/controller/pipeline;
  - prepare future moderation, safety and tool/reasoning governance evolution.

  Hooks vs Policies:
  - hooks are execution interception points;
  - policies are governance decisions (allow/deny/modify).

  This unit is intentionally local and synchronous in this first phase:
  no ACL/RBAC/auth/network/distributed policy engine yet. }

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TYakkoRuntimePolicyType =
  (
    rptPromptMutation,
    rptToolExecution,
    rptReasoningVisibility,
    rptRAGInjection,
    rptOutputMutation
  );

  TYakkoRuntimePolicyTypeHelper = record helper for TYakkoRuntimePolicyType
  public
    function ToString: string;
  end;

  TYakkoPolicyDecision =
  (
    pdUnknown,
    pdAllow,
    pdDeny,
    pdModify
  );

  TYakkoPolicyDecisionHelper = record helper for TYakkoPolicyDecision
  public
    function ToString: string;
  end;

  TYakkoRuntimePolicyMetadata = TDictionary<string, string>;

  TYakkoRuntimePolicyContext = class
  private
    FPolicyType: TYakkoRuntimePolicyType;
    FMetadata: TYakkoRuntimePolicyMetadata;
    FTimestamp: TDateTime;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    function Clone: TYakkoRuntimePolicyContext;
    function ToDebugString: string;

    property PolicyType: TYakkoRuntimePolicyType read FPolicyType write FPolicyType;
    property Metadata: TYakkoRuntimePolicyMetadata read FMetadata;
    property Timestamp: TDateTime read FTimestamp write FTimestamp;
  end;

  TYakkoPolicyResult = class
  private
    FDecision: TYakkoPolicyDecision;
    FReason: string;
    FMetadata: TYakkoRuntimePolicyMetadata;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    function Clone: TYakkoPolicyResult;
    function ToDebugString: string;

    property Decision: TYakkoPolicyDecision read FDecision write FDecision;
    property Reason: string read FReason write FReason;
    property Metadata: TYakkoRuntimePolicyMetadata read FMetadata;
  end;

  IYakkoRuntimePolicy = interface
    ['{56CD45F4-5169-4F66-8C9A-A57C1CB66A0E}']
    function PolicyType: TYakkoRuntimePolicyType;
    function Evaluate(AContext: TYakkoRuntimePolicyContext): TYakkoPolicyResult;
  end;

  TYakkoRuntimePolicyManager = class
  private
    FPolicies: TList<IYakkoRuntimePolicy>;
  public
    constructor Create;
    destructor Destroy; override;

    procedure RegisterPolicy(const APolicy: IYakkoRuntimePolicy);
    function EvaluatePolicies(
      APolicyType: TYakkoRuntimePolicyType;
      AContext: TYakkoRuntimePolicyContext
    ): TYakkoPolicyResult;
  end;

implementation

procedure CloneStringDictionary(ASource, ADest: TYakkoRuntimePolicyMetadata);
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

{ TYakkoRuntimePolicyTypeHelper }

function TYakkoRuntimePolicyTypeHelper.ToString: string;
begin
  case Self of
    rptPromptMutation:
      Result := 'prompt-mutation';
    rptToolExecution:
      Result := 'tool-execution';
    rptReasoningVisibility:
      Result := 'reasoning-visibility';
    rptRAGInjection:
      Result := 'rag-injection';
    rptOutputMutation:
      Result := 'output-mutation';
  else
    Result := 'prompt-mutation';
  end;
end;

{ TYakkoPolicyDecisionHelper }

function TYakkoPolicyDecisionHelper.ToString: string;
begin
  case Self of
    pdUnknown:
      Result := 'unknown';
    pdAllow:
      Result := 'allow';
    pdDeny:
      Result := 'deny';
    pdModify:
      Result := 'modify';
  else
    Result := 'unknown';
  end;
end;

{ TYakkoRuntimePolicyContext }

constructor TYakkoRuntimePolicyContext.Create;
begin
  inherited Create;
  FPolicyType := rptPromptMutation;
  FMetadata := TYakkoRuntimePolicyMetadata.Create;
  FTimestamp := Now;
end;

destructor TYakkoRuntimePolicyContext.Destroy;
begin
  FreeAndNil(FMetadata);
  inherited;
end;

procedure TYakkoRuntimePolicyContext.Clear;
begin
  FMetadata.Clear;
  FTimestamp := Now;

  { TODO: add prompt payload references for sanitization policies. }
  { TODO: add output payload references for filtering policies. }
end;

function TYakkoRuntimePolicyContext.Clone: TYakkoRuntimePolicyContext;
begin
  Result := TYakkoRuntimePolicyContext.Create;
  try
    Result.FPolicyType := FPolicyType;
    Result.FTimestamp := FTimestamp;
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoRuntimePolicyContext.ToDebugString: string;
begin
  Result := Format(
    'TYakkoRuntimePolicyContext(PolicyType=%s, Timestamp=%s, Metadata=%d)',
    [
      FPolicyType.ToString,
      DateTimeToStr(FTimestamp),
      FMetadata.Count
    ]
  );
end;

{ TYakkoPolicyResult }

constructor TYakkoPolicyResult.Create;
begin
  inherited Create;
  FDecision := pdUnknown;
  FReason := '';
  FMetadata := TYakkoRuntimePolicyMetadata.Create;
end;

destructor TYakkoPolicyResult.Destroy;
begin
  FreeAndNil(FMetadata);
  inherited;
end;

procedure TYakkoPolicyResult.Clear;
begin
  FDecision := pdUnknown;
  FReason := '';
  FMetadata.Clear;
end;

function TYakkoPolicyResult.Clone: TYakkoPolicyResult;
begin
  Result := TYakkoPolicyResult.Create;
  try
    Result.FDecision := FDecision;
    Result.FReason := FReason;
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoPolicyResult.ToDebugString: string;
begin
  Result := Format(
    'TYakkoPolicyResult(Decision=%s, Reason=%s, Metadata=%d)',
    [
      FDecision.ToString,
      FReason,
      FMetadata.Count
    ]
  );
end;

{ TYakkoRuntimePolicyManager }

constructor TYakkoRuntimePolicyManager.Create;
begin
  inherited Create;
  FPolicies := TList<IYakkoRuntimePolicy>.Create;
end;

destructor TYakkoRuntimePolicyManager.Destroy;
begin
  FreeAndNil(FPolicies);
  inherited;
end;

procedure TYakkoRuntimePolicyManager.RegisterPolicy(
  const APolicy: IYakkoRuntimePolicy);
begin
  if not Assigned(APolicy) then
    raise EArgumentNilException.Create('APolicy must be assigned.');

  FPolicies.Add(APolicy);

  { TODO: add policy priorities and deterministic resolution order. }
  { TODO: add distributed policy source and provider registry. }
end;

function TYakkoRuntimePolicyManager.EvaluatePolicies(
  APolicyType: TYakkoRuntimePolicyType;
  AContext: TYakkoRuntimePolicyContext): TYakkoPolicyResult;
var
  LPolicy: IYakkoRuntimePolicy;
  LEvaluation: TYakkoPolicyResult;
begin
  if not Assigned(AContext) then
    raise EArgumentNilException.Create('AContext must be assigned.');

  Result := TYakkoPolicyResult.Create;
  Result.Decision := pdAllow;
  Result.Reason := 'default-allow';

  AContext.PolicyType := APolicyType;
  AContext.Timestamp := Now;

  for LPolicy in FPolicies do
  begin
    if LPolicy.PolicyType <> APolicyType then
      Continue;

    LEvaluation := LPolicy.Evaluate(AContext);
    try
      if not Assigned(LEvaluation) then
        Continue;

      if LEvaluation.Decision = pdDeny then
      begin
        Result.Free;
        Result := LEvaluation.Clone;
        Exit;
      end;

      if LEvaluation.Decision = pdModify then
      begin
        Result.Free;
        Result := LEvaluation.Clone;
      end;
    finally
      LEvaluation.Free;
    end;
  end;

  { TODO: add async policy evaluation and cancellation-aware policy flow. }
  { TODO: add moderation and safety policy groups. }
  { TODO: add tool sandboxing policy decisions. }
  { TODO: add reasoning visibility rule evaluation. }
  { TODO: add prompt sanitization and output filtering policies. }
  { TODO: add policy tracing and telemetry providers (including OpenTelemetry). }
end;

end.
