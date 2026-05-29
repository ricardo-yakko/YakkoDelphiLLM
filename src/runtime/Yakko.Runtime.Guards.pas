unit Yakko.Runtime.Guards;

{ Runtime architectural guards for YakkoDelphiLLM.

  Architectural intent:
  - detect invalid runtime couplings early;
  - validate deterministic lifecycle expectations;
  - prevent hidden dependency regressions during runtime evolution.

  This unit intentionally performs local synchronous structural validation only. }

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Yakko.Runtime.Kernel,
  Yakko.Runtime.Composition,
  Yakko.Runtime.Registry,
  Yakko.Runtime.Capabilities,
  Yakko.TokenBudget,
  Yakko.ContextWindow;

type
  TYakkoArchitectureValidationMetadata = TDictionary<string, string>;

  TYakkoArchitectureValidationResult = class
  private
    FIsValid: Boolean;
    FReason: string;
    FViolations: TStringList;
    FMetadata: TYakkoArchitectureValidationMetadata;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    function Clone: TYakkoArchitectureValidationResult;
    function ToDebugString: string;

    property IsValid: Boolean read FIsValid write FIsValid;
    property Reason: string read FReason write FReason;
    property Violations: TStringList read FViolations;
    property Metadata: TYakkoArchitectureValidationMetadata read FMetadata;
  end;

  TYakkoRuntimeArchitectureGuards = class
  public
    class function ValidateArchitecture(AKernel: TYakkoRuntimeKernel): TYakkoArchitectureValidationResult; static;
    class function ValidateLifecycle(AKernel: TYakkoRuntimeKernel): TYakkoArchitectureValidationResult; static;
    class function ValidateComposition(AKernel: TYakkoRuntimeKernel): TYakkoArchitectureValidationResult; static;
    class function ValidateTokenBudget(ABudget: TYakkoTokenBudget): TYakkoArchitectureValidationResult; static;
    class function ValidateContextOverflow(AWindow: TYakkoContextWindow): TYakkoArchitectureValidationResult; static;
    class function ValidateMissingTemplate(AKernel: TYakkoRuntimeKernel; const ATemplateName: string): TYakkoArchitectureValidationResult; static;
    class function ValidateInvalidComposition(ACompositionResult: TYakkoRuntimeCompositionResult): TYakkoArchitectureValidationResult; static;
    class function ValidateMissingCapability(AItem: TYakkoRegistryItem; ACapability: TYakkoRuntimeCapability): TYakkoArchitectureValidationResult; static;
    class function ValidateLifecycleTransition(AFromState, AToState: TYakkoRuntimeKernelState): TYakkoArchitectureValidationResult; static;
  end;

implementation

procedure CloneStringDictionary(ASource, ADest: TYakkoArchitectureValidationMetadata);
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

procedure AddViolation(
  AResult: TYakkoArchitectureValidationResult;
  const AViolation: string
);
begin
  AResult.Violations.Add(AViolation);
  AResult.IsValid := False;
end;

procedure FinalizeResult(AResult: TYakkoArchitectureValidationResult; const ACategory: string);
begin
  if AResult.IsValid then
    AResult.Reason := ACategory + ' validation passed.'
  else
    AResult.Reason := ACategory + ' validation failed.';

  AResult.Metadata.AddOrSetValue('category', ACategory);
  AResult.Metadata.AddOrSetValue('is_valid', BoolToStr(AResult.IsValid, True));
  AResult.Metadata.AddOrSetValue('violations', IntToStr(AResult.Violations.Count));
end;

{ TYakkoArchitectureValidationResult }

constructor TYakkoArchitectureValidationResult.Create;
begin
  inherited Create;
  FIsValid := True;
  FReason := '';
  FViolations := TStringList.Create;
  FMetadata := TYakkoArchitectureValidationMetadata.Create;
end;

destructor TYakkoArchitectureValidationResult.Destroy;
begin
  FreeAndNil(FMetadata);
  FreeAndNil(FViolations);
  inherited;
end;

procedure TYakkoArchitectureValidationResult.Clear;
begin
  FIsValid := True;
  FReason := '';
  FViolations.Clear;
  FMetadata.Clear;

  { TODO: add severity levels and categories for richer architectural diagnostics. }
end;

function TYakkoArchitectureValidationResult.Clone: TYakkoArchitectureValidationResult;
begin
  Result := TYakkoArchitectureValidationResult.Create;
  try
    Result.FIsValid := FIsValid;
    Result.FReason := FReason;
    Result.FViolations.Assign(FViolations);
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoArchitectureValidationResult.ToDebugString: string;
begin
  Result := Format(
    'TYakkoArchitectureValidationResult(IsValid=%s, Reason=%s, Violations=%d, Metadata=%d)',
    [
      BoolToStr(FIsValid, True),
      FReason,
      FViolations.Count,
      FMetadata.Count
    ]
  );
end;

{ TYakkoRuntimeArchitectureGuards }

class function TYakkoRuntimeArchitectureGuards.ValidateArchitecture(
  AKernel: TYakkoRuntimeKernel): TYakkoArchitectureValidationResult;
begin
  Result := TYakkoArchitectureValidationResult.Create;

  if not Assigned(AKernel) then
  begin
    AddViolation(Result, 'Kernel must be assigned.');
    FinalizeResult(Result, 'architecture');
    Exit;
  end;

  if Assigned(AKernel.Orchestrator) and not Assigned(AKernel.GenerationController) then
    AddViolation(Result, 'Orchestrator depends on generation controller.');

  if Assigned(AKernel.CompositionManager) and not Assigned(AKernel.CompatibilityManager) then
    AddViolation(Result, 'Composition depends on compatibility manager.');

  if Assigned(AKernel.Resolver) and not Assigned(AKernel.RuntimeRegistry) then
    AddViolation(Result, 'Resolver depends on runtime registry.');

  if Assigned(AKernel.ModelRegistry) and (AKernel.ModelRegistry.RuntimeRegistry <> AKernel.RuntimeRegistry) then
    AddViolation(Result, 'Model registry must depend on kernel runtime registry.');

  if Assigned(AKernel.ProviderRegistry) and (AKernel.ProviderRegistry.RuntimeRegistry <> AKernel.RuntimeRegistry) then
    AddViolation(Result, 'Provider registry must depend on kernel runtime registry.');

  if Assigned(AKernel.TemplateRegistry) and (AKernel.TemplateRegistry.RuntimeRegistry <> AKernel.RuntimeRegistry) then
    AddViolation(Result, 'Template registry must depend on kernel runtime registry.');

  if Assigned(AKernel.PipelineRegistry) and (AKernel.PipelineRegistry.RuntimeRegistry <> AKernel.RuntimeRegistry) then
    AddViolation(Result, 'Pipeline registry must depend on kernel runtime registry.');

  FinalizeResult(Result, 'architecture');
end;

class function TYakkoRuntimeArchitectureGuards.ValidateLifecycle(
  AKernel: TYakkoRuntimeKernel): TYakkoArchitectureValidationResult;
begin
  Result := TYakkoArchitectureValidationResult.Create;

  if not Assigned(AKernel) then
  begin
    AddViolation(Result, 'Kernel must be assigned.');
    FinalizeResult(Result, 'lifecycle');
    Exit;
  end;

  if (AKernel.Context.State = ksReady) and (not AKernel.IsReady) then
    AddViolation(Result, 'Kernel state is ready but IsReady returned false.');

  if AKernel.IsReady then
  begin
    if not Assigned(AKernel.RuntimeRegistry) then
      AddViolation(Result, 'Ready kernel must own runtime registry.');
    if not Assigned(AKernel.Orchestrator) then
      AddViolation(Result, 'Ready kernel must own orchestrator.');
    if not Assigned(AKernel.Bridge) then
      AddViolation(Result, 'Ready kernel must own bridge.');
  end;

  if AKernel.Context.State = ksDestroyed then
  begin
    if Assigned(AKernel.RuntimeRegistry) then
      AddViolation(Result, 'Destroyed kernel must not keep runtime registry.');
    if Assigned(AKernel.CompositionManager) then
      AddViolation(Result, 'Destroyed kernel must not keep composition manager.');
  end;

  FinalizeResult(Result, 'lifecycle');
end;

class function TYakkoRuntimeArchitectureGuards.ValidateComposition(
  AKernel: TYakkoRuntimeKernel): TYakkoArchitectureValidationResult;
begin
  Result := TYakkoArchitectureValidationResult.Create;

  if not Assigned(AKernel) then
  begin
    AddViolation(Result, 'Kernel must be assigned.');
    FinalizeResult(Result, 'composition');
    Exit;
  end;

  if not Assigned(AKernel.CompositionManager) then
    AddViolation(Result, 'Composition manager must exist before composition validation.');

  if not Assigned(AKernel.CompatibilityManager) then
    AddViolation(Result, 'Compatibility manager must exist before composition validation.');

  if not Assigned(AKernel.ModelRegistry) then
    AddViolation(Result, 'Model registry is required for composition.');

  if not Assigned(AKernel.ProviderRegistry) then
    AddViolation(Result, 'Provider registry is required for composition.');

  if not Assigned(AKernel.TemplateRegistry) then
    AddViolation(Result, 'Template registry is required for composition.');

  if not Assigned(AKernel.PipelineRegistry) then
    AddViolation(Result, 'Pipeline registry is required for composition.');

  FinalizeResult(Result, 'composition');
end;

class function TYakkoRuntimeArchitectureGuards.ValidateTokenBudget(
  ABudget: TYakkoTokenBudget): TYakkoArchitectureValidationResult;
begin
  Result := TYakkoArchitectureValidationResult.Create;

  if not Assigned(ABudget) then
    AddViolation(Result, 'Token budget must be assigned.')
  else
  begin
    if ABudget.MaxContextTokens <= 0 then
      AddViolation(Result, 'Token budget max context tokens must be positive.');
    if ABudget.MaxResponseTokens <= 0 then
      AddViolation(Result, 'Token budget max response tokens must be positive.');
    if ABudget.Allocation.TotalAllocated > (ABudget.MaxContextTokens + ABudget.MaxResponseTokens) then
      AddViolation(Result, 'Token budget allocation exceeds allowed limit.');
  end;

  FinalizeResult(Result, 'token-budget');
end;

class function TYakkoRuntimeArchitectureGuards.ValidateContextOverflow(
  AWindow: TYakkoContextWindow): TYakkoArchitectureValidationResult;
begin
  Result := TYakkoArchitectureValidationResult.Create;

  if not Assigned(AWindow) then
    AddViolation(Result, 'Context window must be assigned.')
  else
  begin
    if AWindow.MaxMessages <= 0 then
      AddViolation(Result, 'Context window max messages must be positive.');
    if AWindow.RecentMessages.Count > AWindow.MaxMessages then
      AddViolation(Result, 'Context window overflow detected.');
  end;

  FinalizeResult(Result, 'context-window');
end;

class function TYakkoRuntimeArchitectureGuards.ValidateMissingTemplate(
  AKernel: TYakkoRuntimeKernel; const ATemplateName: string): TYakkoArchitectureValidationResult;
var
  LTemplate: TYakkoRegistryItem;
begin
  Result := TYakkoArchitectureValidationResult.Create;

  if not Assigned(AKernel) then
    AddViolation(Result, 'Kernel must be assigned.')
  else if not Assigned(AKernel.TemplateRegistry) then
    AddViolation(Result, 'Template registry must be assigned.')
  else
  begin
    LTemplate := AKernel.TemplateRegistry.FindByName(ATemplateName);
    try
      if not Assigned(LTemplate) then
        AddViolation(Result, Format('Template "%s" is missing.', [ATemplateName]));
    finally
      LTemplate.Free;
    end;
  end;

  FinalizeResult(Result, 'missing-template');
end;

class function TYakkoRuntimeArchitectureGuards.ValidateInvalidComposition(
  ACompositionResult: TYakkoRuntimeCompositionResult): TYakkoArchitectureValidationResult;
begin
  Result := TYakkoArchitectureValidationResult.Create;

  if not Assigned(ACompositionResult) then
    AddViolation(Result, 'Composition result must be assigned.')
  else if ACompositionResult.Status <> csSuccess then
    AddViolation(Result, 'Composition result status is not success.');

  FinalizeResult(Result, 'composition-result');
end;

class function TYakkoRuntimeArchitectureGuards.ValidateMissingCapability(
  AItem: TYakkoRegistryItem; ACapability: TYakkoRuntimeCapability): TYakkoArchitectureValidationResult;
var
  LCaps: string;
begin
  Result := TYakkoArchitectureValidationResult.Create;

  if not Assigned(AItem) then
    AddViolation(Result, 'Registry item must be assigned.')
  else
  begin
    LCaps := '';
    if Assigned(AItem.Metadata) and AItem.Metadata.ContainsKey('capabilities') then
      LCaps := LowerCase(AItem.Metadata['capabilities']);

    if Pos(LowerCase(ACapability.ToString), LCaps) = 0 then
      AddViolation(Result, Format('Item "%s" is missing capability "%s".', [AItem.Name, ACapability.ToString]));
  end;

  FinalizeResult(Result, 'missing-capability');
end;

class function TYakkoRuntimeArchitectureGuards.ValidateLifecycleTransition(
  AFromState, AToState: TYakkoRuntimeKernelState): TYakkoArchitectureValidationResult;

  function IsAllowedTransition(AFrom, ATo: TYakkoRuntimeKernelState): Boolean;
  begin
    case AFrom of
      ksCreated:
        Result := ATo in [ksInitializing, ksDestroyed];
      ksInitializing:
        Result := ATo in [ksReady, ksShuttingDown, ksDestroyed];
      ksReady:
        Result := ATo in [ksShuttingDown, ksDestroyed];
      ksShuttingDown:
        Result := ATo = ksDestroyed;
      ksDestroyed:
        Result := False;
    else
      Result := False;
    end;
  end;

begin
  Result := TYakkoArchitectureValidationResult.Create;

  if not IsAllowedTransition(AFromState, AToState) then
    AddViolation(Result, Format('Invalid lifecycle transition: %s -> %s', [AFromState.ToString, AToState.ToString]));

  FinalizeResult(Result, 'lifecycle-transition');
end;

end.
