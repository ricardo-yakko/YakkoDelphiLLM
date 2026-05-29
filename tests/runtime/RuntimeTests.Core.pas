unit RuntimeTests.Core;

interface

procedure RunAllRuntimeTests;

implementation

uses
  System.SysUtils,
  Yakko.Message,
  Yakko.ConversationState,
  Yakko.Prompt.Builder,
  Yakko.Template.Provider,
  Yakko.Inference.Types,
  Yakko.Inference.Pipeline,
  Yakko.Runtime.Registry,
  Yakko.Runtime.Capabilities,
  Yakko.Runtime.Resolver,
  Yakko.Runtime.Compatibility,
  Yakko.Runtime.SpecializedRegistries,
  Yakko.Runtime.Composition,
  Yakko.Runtime.Kernel,
  Yakko.Runtime.Snapshot,
  Yakko.Runtime.Guards,
  Yakko.Runtime.Metadata,
  Yakko.TokenBudget,
  Yakko.ContextWindow;

procedure AssertTrue(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('Test failed: ' + AMessage);
end;

function CreateBaseItem(const AName: string; AType: TYakkoRegistryItemType): TYakkoRegistryItem;
begin
  Result := TYakkoRegistryItem.Create;
  Result.Name := AName;
  Result.ItemType := AType;
  Result.Metadata.AddOrSetValue('capabilities', 'chat-completion,streaming');
end;

procedure TestResolverAndComposition;
var
  LRegistry: TYakkoRuntimeRegistry;
  LModelRegistry: TYakkoModelRegistry;
  LProviderRegistry: TYakkoProviderRegistry;
  LTemplateRegistry: TYakkoTemplateRegistry;
  LPipelineRegistry: TYakkoPipelineRegistry;
  LModel, LProvider, LTemplate, LPipeline: TYakkoRegistryItem;
  LResolver: TYakkoRuntimeResolver;
  LResolveRequest: TYakkoResolutionRequest;
  LResolveResult: TYakkoResolutionResult;
  LCompositionManager: TYakkoRuntimeCompositionManager;
  LCompositionRequest: TYakkoRuntimeCompositionRequest;
  LCompositionResult: TYakkoRuntimeCompositionResult;
begin
  LRegistry := TYakkoRuntimeRegistry.Create;
  LModelRegistry := TYakkoModelRegistry.Create(LRegistry);
  LProviderRegistry := TYakkoProviderRegistry.Create(LRegistry);
  LTemplateRegistry := TYakkoTemplateRegistry.Create(LRegistry);
  LPipelineRegistry := TYakkoPipelineRegistry.Create(LRegistry);
  LResolver := TYakkoRuntimeResolver.Create(LRegistry);
  LCompositionManager := TYakkoRuntimeCompositionManager.Create(
    LModelRegistry, LProviderRegistry, LTemplateRegistry, LPipelineRegistry);
  try
    LModel := CreateBaseItem('m1', ritModel);
    LProvider := CreateBaseItem('p1', ritProvider);
    LTemplate := CreateBaseItem('t1', ritTemplate);
    LPipeline := CreateBaseItem('pl1', ritPipeline);
    try
      LModel.Metadata.AddOrSetValue('supported_providers', 'p1');
      LModel.Metadata.AddOrSetValue('supported_templates', 't1');
      LModel.Metadata.AddOrSetValue('requires_provider_capabilities', 'chat-completion');
      LModel.Metadata.AddOrSetValue('requires_template_capabilities', 'chat-completion');

      LProvider.Metadata.AddOrSetValue('supported_models', 'm1');
      LProvider.Metadata.AddOrSetValue('supported_pipelines', 'pl1');
      LProvider.Metadata.AddOrSetValue('requires_model_capabilities', 'chat-completion');
      LProvider.Metadata.AddOrSetValue('requires_pipeline_capabilities', 'chat-completion');

      LTemplate.Metadata.AddOrSetValue('supported_models', 'm1');
      LTemplate.Metadata.AddOrSetValue('supported_pipelines', 'pl1');
      LTemplate.Metadata.AddOrSetValue('requires_model_capabilities', 'chat-completion');
      LTemplate.Metadata.AddOrSetValue('requires_pipeline_capabilities', 'chat-completion');

      LPipeline.Metadata.AddOrSetValue('supported_providers', 'p1');
      LPipeline.Metadata.AddOrSetValue('supported_templates', 't1');
      LPipeline.Metadata.AddOrSetValue('requires_provider_capabilities', 'chat-completion');
      LPipeline.Metadata.AddOrSetValue('requires_template_capabilities', 'chat-completion');

      LModelRegistry.RegisterModel(LModel);
      LProviderRegistry.RegisterProvider(LProvider);
      LTemplateRegistry.RegisterTemplate(LTemplate);
      LPipelineRegistry.RegisterPipeline(LPipeline);
    finally
      LModel.Free;
      LProvider.Free;
      LTemplate.Free;
      LPipeline.Free;
    end;

    LResolveRequest := TYakkoResolutionRequest.Create;
    try
      LResolveRequest.Target := rtModel;
      LResolveRequest.Metadata.AddOrSetValue('name', 'm1');
      LResolveRequest.RequiredCapabilities.Add(rcChatCompletion);
      LResolveResult := LResolver.Resolve(LResolveRequest);
      try
        AssertTrue(LResolveResult.Success, 'Resolver should resolve model m1');
      finally
        LResolveResult.Free;
      end;
    finally
      LResolveRequest.Free;
    end;

    LCompositionRequest := TYakkoRuntimeCompositionRequest.Create;
    try
      LCompositionRequest.RequiredCapabilities.Add(rcChatCompletion);
      LCompositionRequest.Metadata.AddOrSetValue('model_name', 'm1');
      LCompositionRequest.Metadata.AddOrSetValue('provider_name', 'p1');
      LCompositionRequest.Metadata.AddOrSetValue('template_name', 't1');
      LCompositionRequest.Metadata.AddOrSetValue('pipeline_name', 'pl1');
      LCompositionResult := LCompositionManager.Compose(LCompositionRequest);
      try
        AssertTrue(LCompositionResult.Status = csSuccess, 'Composition must be success');
      finally
        LCompositionResult.Free;
      end;
    finally
      LCompositionRequest.Free;
    end;
  finally
    LCompositionManager.Free;
    LResolver.Free;
    LPipelineRegistry.Free;
    LTemplateRegistry.Free;
    LProviderRegistry.Free;
    LModelRegistry.Free;
    LRegistry.Free;
  end;
end;

procedure TestCompatibility;
var
  LRequest: TYakkoCompatibilityRequest;
  LManager: TYakkoRuntimeCompatibilityManager;
  LResult: TYakkoCompatibilityResult;
  LModel, LProvider: TYakkoRegistryItem;
begin
  LManager := TYakkoRuntimeCompatibilityManager.Create;
  LRequest := TYakkoCompatibilityRequest.Create;
  try
    LModel := CreateBaseItem('m2', ritModel);
    LProvider := CreateBaseItem('p2', ritProvider);
    try
      LModel.Metadata.AddOrSetValue('supported_providers', 'p2');
      LProvider.Metadata.AddOrSetValue('supported_models', 'm2');
      LRequest.Target := ctModelProvider;
      LRequest.Model := LModel;
      LRequest.Provider := LProvider;
      LResult := LManager.Validate(LRequest);
      try
        AssertTrue(LResult.Compatible, 'Compatibility should pass for aligned model/provider');
      finally
        LResult.Free;
      end;
    finally
      LModel.Free;
      LProvider.Free;
    end;
  finally
    LRequest.Free;
    LManager.Free;
  end;
end;

procedure TestPromptBuilderAndTemplateProvider;
var
  LConversation: TYakkoConversationState;
  LBuildRequest: TYakkoPromptBuildRequest;
  LBuilder: TYakkoPromptBuilder;
  LResult: TYakkoPromptBuildResult;
  LProvider: IYakkoTemplateProvider;
  LPromptText: string;
begin
  LConversation := TYakkoConversationState.Create;
  LBuildRequest := TYakkoPromptBuildRequest.Create;
  LBuilder := TYakkoPromptBuilder.Create;
  try
    LConversation.SystemPrompt := 'system';
    LConversation.AddUserMessage('hello');

    LBuildRequest.ConversationState := LConversation;
    LBuildRequest.IncludeSystemPrompt := True;

    LResult := LBuilder.Build(LBuildRequest);
    try
      AssertTrue(LResult.PromptDocument.BlockCount > 0, 'PromptDocument must have blocks');
      LProvider := TYakkoTemplateProviderFactory.CreateDefault;
      LPromptText := LProvider.BuildPromptDocument(LResult.PromptDocument);
      AssertTrue(Trim(LPromptText) <> '', 'Template provider should serialize prompt document');
    finally
      LResult.Free;
    end;
  finally
    LBuilder.Free;
    LBuildRequest.Free;
    LConversation.Free;
  end;
end;

procedure TestPipelineLifecycle;
var
  LPipeline: TYakkoInferencePipeline;
  LRequest: TYakkoInferenceRequest;
  LResult: TYakkoInferenceResult;
begin
  LPipeline := TYakkoInferencePipeline.Create;
  LRequest := TYakkoInferenceRequest.Create;
  try
    LResult := LPipeline.Execute(LRequest);
    try
      AssertTrue(LResult.State = isCompleted, 'Pipeline should end in completed state');
      AssertTrue(LResult.Metadata.Count = 0, 'Pipeline result metadata is currently empty by contract');
    finally
      LResult.Free;
    end;
  finally
    LRequest.Free;
    LPipeline.Free;
  end;
end;

procedure TestSnapshotCloneIntegrity;
var
  LKernel: TYakkoRuntimeKernel;
  LSnapshot: TYakkoRuntimeSnapshot;
  LClone: TYakkoRuntimeSnapshot;
begin
  LKernel := TYakkoRuntimeKernel.Create;
  try
    LKernel.Initialize;
    LSnapshot := TYakkoRuntimeSnapshot.Create;
    try
      LSnapshot.CaptureFromKernel(LKernel);
      LClone := LSnapshot.Clone;
      try
        AssertTrue(LClone.RegistryItems.Count = LSnapshot.RegistryItems.Count, 'Snapshot clone should preserve item count');
        AssertTrue(LClone.KernelState = LSnapshot.KernelState, 'Snapshot clone should preserve kernel state');
      finally
        LClone.Free;
      end;
    finally
      LSnapshot.Free;
    end;
    LKernel.Shutdown;
  finally
    LKernel.Free;
  end;
end;

procedure TestMetadataConsistency;
begin
  AssertTrue(TYakkoRuntimeMetadataKeys.Capabilities = 'capabilities', 'Metadata key capabilities must remain stable');
  AssertTrue(TYakkoRuntimeMetadataKeys.RequiresPipelineCapabilities = 'requires_pipeline_capabilities', 'Metadata key requires_pipeline_capabilities must remain stable');
end;

procedure TestGuards;
var
  LKernel: TYakkoRuntimeKernel;
  LResult: TYakkoArchitectureValidationResult;
  LBudget: TYakkoTokenBudget;
  LWindow: TYakkoContextWindow;
begin
  LKernel := TYakkoRuntimeKernel.Create;
  LBudget := TYakkoTokenBudget.Create;
  LWindow := TYakkoContextWindow.Create;
  try
    LKernel.Initialize;
    LResult := TYakkoRuntimeArchitectureGuards.ValidateArchitecture(LKernel);
    try
      AssertTrue(LResult.IsValid, 'Architecture guard should pass for initialized kernel');
    finally
      LResult.Free;
    end;

    LResult := TYakkoRuntimeArchitectureGuards.ValidateTokenBudget(LBudget);
    try
      AssertTrue(LResult.IsValid, 'Token budget guard should pass for default budget');
    finally
      LResult.Free;
    end;

    LResult := TYakkoRuntimeArchitectureGuards.ValidateContextOverflow(LWindow);
    try
      AssertTrue(LResult.IsValid, 'Context overflow guard should pass for empty window');
    finally
      LResult.Free;
    end;

    LKernel.Shutdown;
  finally
    LWindow.Free;
    LBudget.Free;
    LKernel.Free;
  end;
end;

procedure RunAllRuntimeTests;
begin
  TestResolverAndComposition;
  TestCompatibility;
  TestPromptBuilderAndTemplateProvider;
  TestPipelineLifecycle;
  TestSnapshotCloneIntegrity;
  TestMetadataConsistency;
  TestGuards;
end;

end.
