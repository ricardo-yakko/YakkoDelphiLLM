unit Yakko.Runtime.Bootstrap;

{ Runtime bootstrap layer for YakkoDelphiLLM.

  Architectural intent:
  - centralize deterministic runtime startup sequence;
  - register default runtime items explicitly (no scanning/discovery);
  - configure baseline policies and hooks explicitly;
  - compose a default runtime configuration through composition manager.

  This unit intentionally avoids reflection, auto-discovery, plugin loading,
  dynamic routing and adaptive negotiation. }

interface

uses
  System.SysUtils,
  Yakko.Runtime.Kernel,
  Yakko.Runtime.Registry,
  Yakko.Runtime.Capabilities,
  Yakko.Runtime.Resolver,
  Yakko.Runtime.Composition,
  Yakko.Runtime.Policies,
  Yakko.Runtime.Hooks,
  Yakko.Runtime.Metadata;

type
  TYakkoRuntimeBootstrap = class
  private
    FKernel: TYakkoRuntimeKernel;
    FLastComposition: TYakkoRuntimeCompositionResult;

    procedure RegisterDefaultModels;
    procedure RegisterDefaultProviders;
    function BuildDefaultCompositionRequest: TYakkoRuntimeCompositionRequest;
  public
    constructor Create(AKernel: TYakkoRuntimeKernel);
    destructor Destroy; override;

    procedure RegisterDefaultTemplates;
    procedure RegisterDefaultPipelines;
    procedure RegisterDefaultPolicies;
    procedure RegisterDefaultHooks;

    function BootstrapDefaultRuntime: TYakkoRuntimeCompositionResult;

    property Kernel: TYakkoRuntimeKernel read FKernel;
    property LastComposition: TYakkoRuntimeCompositionResult read FLastComposition;
  end;

implementation

type
  TYakkoDefaultAllowPolicy = class(TInterfacedObject, IYakkoRuntimePolicy)
  private
    FPolicyType: TYakkoRuntimePolicyType;
  public
    constructor Create(APolicyType: TYakkoRuntimePolicyType);
    function PolicyType: TYakkoRuntimePolicyType;
    function Evaluate(AContext: TYakkoRuntimePolicyContext): TYakkoPolicyResult;
  end;

  TYakkoNoopHook = class(TInterfacedObject, IYakkoRuntimeHook)
  private
    FHookType: TYakkoRuntimeHookType;
  public
    constructor Create(AHookType: TYakkoRuntimeHookType);
    function HookType: TYakkoRuntimeHookType;
    procedure Execute(AContext: TYakkoRuntimeHookContext);
  end;

function CreateRegistryItem(const AName: string; AItemType: TYakkoRegistryItemType): TYakkoRegistryItem;
begin
  Result := TYakkoRegistryItem.Create;
  Result.Name := AName;
  Result.ItemType := AItemType;
  Result.Metadata.AddOrSetValue(TYakkoRuntimeMetadataKeys.Capabilities, 'chat-completion,streaming');
end;

{ TYakkoDefaultAllowPolicy }

constructor TYakkoDefaultAllowPolicy.Create(APolicyType: TYakkoRuntimePolicyType);
begin
  inherited Create;
  FPolicyType := APolicyType;
end;

function TYakkoDefaultAllowPolicy.PolicyType: TYakkoRuntimePolicyType;
begin
  Result := FPolicyType;
end;

function TYakkoDefaultAllowPolicy.Evaluate(
  AContext: TYakkoRuntimePolicyContext): TYakkoPolicyResult;
begin
  Result := TYakkoPolicyResult.Create;
  Result.Decision := pdAllow;
  Result.Reason := 'default-policy-allow';
  if Assigned(AContext) then
    Result.Metadata.AddOrSetValue('policy_context', AContext.ToDebugString);
end;

{ TYakkoNoopHook }

constructor TYakkoNoopHook.Create(AHookType: TYakkoRuntimeHookType);
begin
  inherited Create;
  FHookType := AHookType;
end;

function TYakkoNoopHook.HookType: TYakkoRuntimeHookType;
begin
  Result := FHookType;
end;

procedure TYakkoNoopHook.Execute(AContext: TYakkoRuntimeHookContext);
begin
  if Assigned(AContext) then
    AContext.Metadata.AddOrSetValue('hook.default', 'noop');
end;

{ TYakkoRuntimeBootstrap }

constructor TYakkoRuntimeBootstrap.Create(AKernel: TYakkoRuntimeKernel);
begin
  inherited Create;
  if not Assigned(AKernel) then
    raise EArgumentNilException.Create('AKernel must be assigned.');

  FKernel := AKernel;
  FLastComposition := nil;
end;

destructor TYakkoRuntimeBootstrap.Destroy;
begin
  FreeAndNil(FLastComposition);
  inherited;
end;

procedure TYakkoRuntimeBootstrap.RegisterDefaultModels;
var
  LItem: TYakkoRegistryItem;
  LExisting: TYakkoRegistryItem;
begin
  LExisting := FKernel.ModelRegistry.FindByName('default-model');
  try
    if Assigned(LExisting) then
      Exit;
  finally
    LExisting.Free;
  end;

  LItem := CreateRegistryItem('default-model', ritModel);
  try
    LItem.Metadata.AddOrSetValue(TYakkoRuntimeMetadataKeys.SupportedProviders, 'default-provider');
    LItem.Metadata.AddOrSetValue(TYakkoRuntimeMetadataKeys.SupportedTemplates, 'default-template');
    LItem.Metadata.AddOrSetValue(TYakkoRuntimeMetadataKeys.RequiresProviderCapabilities, 'chat-completion');
    LItem.Metadata.AddOrSetValue(TYakkoRuntimeMetadataKeys.RequiresTemplateCapabilities, 'chat-completion');
    FKernel.ModelRegistry.RegisterModel(LItem);
  finally
    LItem.Free;
  end;
end;

procedure TYakkoRuntimeBootstrap.RegisterDefaultProviders;
var
  LItem: TYakkoRegistryItem;
  LExisting: TYakkoRegistryItem;
begin
  LExisting := FKernel.ProviderRegistry.FindByName('default-provider');
  try
    if Assigned(LExisting) then
      Exit;
  finally
    LExisting.Free;
  end;

  LItem := CreateRegistryItem('default-provider', ritProvider);
  try
    LItem.Metadata.AddOrSetValue(TYakkoRuntimeMetadataKeys.SupportedModels, 'default-model');
    LItem.Metadata.AddOrSetValue(TYakkoRuntimeMetadataKeys.SupportedPipelines, 'default-pipeline');
    LItem.Metadata.AddOrSetValue(TYakkoRuntimeMetadataKeys.RequiresModelCapabilities, 'chat-completion');
    LItem.Metadata.AddOrSetValue(TYakkoRuntimeMetadataKeys.RequiresPipelineCapabilities, 'chat-completion');
    FKernel.ProviderRegistry.RegisterProvider(LItem);
  finally
    LItem.Free;
  end;
end;

procedure TYakkoRuntimeBootstrap.RegisterDefaultTemplates;
var
  LItem: TYakkoRegistryItem;
  LExisting: TYakkoRegistryItem;
begin
  LExisting := FKernel.TemplateRegistry.FindByName('default-template');
  try
    if Assigned(LExisting) then
      Exit;
  finally
    LExisting.Free;
  end;

  LItem := CreateRegistryItem('default-template', ritTemplate);
  try
    LItem.Metadata.AddOrSetValue(TYakkoRuntimeMetadataKeys.SupportedModels, 'default-model');
    LItem.Metadata.AddOrSetValue(TYakkoRuntimeMetadataKeys.SupportedPipelines, 'default-pipeline');
    LItem.Metadata.AddOrSetValue(TYakkoRuntimeMetadataKeys.RequiresModelCapabilities, 'chat-completion');
    LItem.Metadata.AddOrSetValue(TYakkoRuntimeMetadataKeys.RequiresPipelineCapabilities, 'chat-completion');
    FKernel.TemplateRegistry.RegisterTemplate(LItem);
  finally
    LItem.Free;
  end;
end;

procedure TYakkoRuntimeBootstrap.RegisterDefaultPipelines;
var
  LItem: TYakkoRegistryItem;
  LExisting: TYakkoRegistryItem;
begin
  LExisting := FKernel.PipelineRegistry.FindByName('default-pipeline');
  try
    if Assigned(LExisting) then
      Exit;
  finally
    LExisting.Free;
  end;

  LItem := CreateRegistryItem('default-pipeline', ritPipeline);
  try
    LItem.Metadata.AddOrSetValue(TYakkoRuntimeMetadataKeys.SupportedProviders, 'default-provider');
    LItem.Metadata.AddOrSetValue(TYakkoRuntimeMetadataKeys.SupportedTemplates, 'default-template');
    LItem.Metadata.AddOrSetValue(TYakkoRuntimeMetadataKeys.RequiresProviderCapabilities, 'chat-completion');
    LItem.Metadata.AddOrSetValue(TYakkoRuntimeMetadataKeys.RequiresTemplateCapabilities, 'chat-completion');
    FKernel.PipelineRegistry.RegisterPipeline(LItem);
  finally
    LItem.Free;
  end;
end;

procedure TYakkoRuntimeBootstrap.RegisterDefaultPolicies;
begin
  FKernel.PolicyManager.RegisterPolicy(TYakkoDefaultAllowPolicy.Create(rptPromptMutation));
  FKernel.PolicyManager.RegisterPolicy(TYakkoDefaultAllowPolicy.Create(rptToolExecution));
  FKernel.PolicyManager.RegisterPolicy(TYakkoDefaultAllowPolicy.Create(rptReasoningVisibility));
  FKernel.PolicyManager.RegisterPolicy(TYakkoDefaultAllowPolicy.Create(rptRAGInjection));
  FKernel.PolicyManager.RegisterPolicy(TYakkoDefaultAllowPolicy.Create(rptOutputMutation));

  FKernel.Context.Metadata.AddOrSetValue('bootstrap.default.policies', 'registered');
end;

procedure TYakkoRuntimeBootstrap.RegisterDefaultHooks;
begin
  FKernel.HookManager.RegisterHook(TYakkoNoopHook.Create(rhtBeforePromptBuild));
  FKernel.HookManager.RegisterHook(TYakkoNoopHook.Create(rhtAfterPromptBuild));
  FKernel.HookManager.RegisterHook(TYakkoNoopHook.Create(rhtBeforeInference));
  FKernel.HookManager.RegisterHook(TYakkoNoopHook.Create(rhtAfterInference));
  FKernel.HookManager.RegisterHook(TYakkoNoopHook.Create(rhtBeforeStage));
  FKernel.HookManager.RegisterHook(TYakkoNoopHook.Create(rhtAfterStage));
  FKernel.HookManager.RegisterHook(TYakkoNoopHook.Create(rhtBeforeOutput));
  FKernel.HookManager.RegisterHook(TYakkoNoopHook.Create(rhtAfterOutput));

  FKernel.Context.Metadata.AddOrSetValue('bootstrap.default.hooks', 'registered');
end;

function TYakkoRuntimeBootstrap.BuildDefaultCompositionRequest: TYakkoRuntimeCompositionRequest;
begin
  Result := TYakkoRuntimeCompositionRequest.Create;
  Result.RequiredCapabilities.Add(rcChatCompletion);
  Result.Metadata.AddOrSetValue(TYakkoRuntimeMetadataKeys.ModelName, 'default-model');
  Result.Metadata.AddOrSetValue(TYakkoRuntimeMetadataKeys.ProviderName, 'default-provider');
  Result.Metadata.AddOrSetValue(TYakkoRuntimeMetadataKeys.TemplateName, 'default-template');
  Result.Metadata.AddOrSetValue(TYakkoRuntimeMetadataKeys.PipelineName, 'default-pipeline');
end;

function TYakkoRuntimeBootstrap.BootstrapDefaultRuntime: TYakkoRuntimeCompositionResult;
var
  LRequest: TYakkoRuntimeCompositionRequest;
begin
  if not FKernel.IsReady then
    FKernel.Initialize;

  RegisterDefaultModels;
  RegisterDefaultProviders;
  RegisterDefaultTemplates;
  RegisterDefaultPipelines;

  FKernel.Capabilities.Add(rcChatCompletion);
  FKernel.Capabilities.Add(rcStreaming);

  RegisterDefaultPolicies;
  RegisterDefaultHooks;

  LRequest := BuildDefaultCompositionRequest;
  try
    FreeAndNil(FLastComposition);
    FLastComposition := FKernel.CompositionManager.Compose(LRequest);
  finally
    LRequest.Free;
  end;

  FKernel.Context.Metadata.AddOrSetValue('bootstrap.default.runtime', FLastComposition.Status.ToString);
  FKernel.Context.Metadata.AddOrSetValue('bootstrap.default.runtime.reason', FLastComposition.Reason);

  Result := FLastComposition.Clone;

  { TODO: add deterministic fallback chains after explicit fallback contracts are approved. }
  { TODO: add negotiation engine hook points after deterministic composition baseline is stable. }
  { TODO: add orchestration graphs once composition and compatibility contracts are frozen. }
  { TODO: add execution planning only after policy and compatibility rules are stabilized. }
  { TODO: add provider federation once local deterministic multi-provider flow is validated. }
end;

end.
