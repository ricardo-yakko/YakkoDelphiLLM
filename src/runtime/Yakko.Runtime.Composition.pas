unit Yakko.Runtime.Composition;

{ Explicit runtime composition layer for YakkoDelphiLLM.

  Architectural intent:
  - compose a full deterministic runtime set (model, provider, template, pipeline);
  - centralize runtime composition to avoid orchestration branching chaos;
  - use explicit requirements, explicit capabilities and explicit compatibility validation;
  - prepare fallback, negotiation and orchestration evolution without enabling them now.

  Resolver vs CompatibilityLayer vs CompositionLayer:
  - Resolver selects a concrete component candidate for each target;
  - CompatibilityLayer validates if selected components can work together;
  - CompositionLayer coordinates deterministic end-to-end composition flow.

  Why explicit composition:
  - keeps runtime assembly predictable and auditable;
  - avoids scattered branching in callers;
  - supports future multi-provider and orchestration expansion with clear boundaries.

  This unit intentionally avoids:
  - AI planning;
  - adaptive orchestration;
  - probabilistic scoring;
  - distributed orchestration;
  - inference behavior changes. }

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Generics.Collections,
  Yakko.Runtime.Registry,
  Yakko.Runtime.Capabilities,
  Yakko.Runtime.Resolver,
  Yakko.Runtime.Compatibility,
  Yakko.Runtime.SpecializedRegistries;

type
  TYakkoCompositionStatus =
  (
    csSuccess,
    csPartial,
    csFailed
  );

  TYakkoCompositionStatusHelper = record helper for TYakkoCompositionStatus
  public
    function ToString: string;
  end;

  TYakkoRuntimeCompositionMetadata = TDictionary<string, string>;

  TYakkoRuntimeCompositionRequest = class
  private
    FRequiredCapabilities: TYakkoRuntimeCapabilities;
    FMetadata: TYakkoRuntimeCompositionMetadata;
    FCreatedAt: TDateTime;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    function Clone: TYakkoRuntimeCompositionRequest;
    function ToDebugString: string;

    property RequiredCapabilities: TYakkoRuntimeCapabilities read FRequiredCapabilities;
    property Metadata: TYakkoRuntimeCompositionMetadata read FMetadata;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
  end;

  TYakkoRuntimeCompositionResult = class
  private
    FStatus: TYakkoCompositionStatus;
    FModel: TYakkoRegistryItem;
    FProvider: TYakkoRegistryItem;
    FTemplate: TYakkoRegistryItem;
    FPipeline: TYakkoRegistryItem;
    FCompatibilityResult: TYakkoCompatibilityResult;
    FReason: string;
    FMetadata: TYakkoRuntimeCompositionMetadata;

    procedure SetModel(const Value: TYakkoRegistryItem);
    procedure SetProvider(const Value: TYakkoRegistryItem);
    procedure SetTemplate(const Value: TYakkoRegistryItem);
    procedure SetPipeline(const Value: TYakkoRegistryItem);
    procedure SetCompatibilityResult(const Value: TYakkoCompatibilityResult);
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    function Clone: TYakkoRuntimeCompositionResult;
    function ToDebugString: string;

    property Status: TYakkoCompositionStatus read FStatus write FStatus;
    property Model: TYakkoRegistryItem read FModel write SetModel;
    property Provider: TYakkoRegistryItem read FProvider write SetProvider;
    property Template: TYakkoRegistryItem read FTemplate write SetTemplate;
    property Pipeline: TYakkoRegistryItem read FPipeline write SetPipeline;
    property CompatibilityResult: TYakkoCompatibilityResult read FCompatibilityResult write SetCompatibilityResult;
    property Reason: string read FReason write FReason;
    property Metadata: TYakkoRuntimeCompositionMetadata read FMetadata;
  end;

  TYakkoRuntimeCompositionManager = class
  private
    FModelRegistry: TYakkoModelRegistry;
    FProviderRegistry: TYakkoProviderRegistry;
    FTemplateRegistry: TYakkoTemplateRegistry;
    FPipelineRegistry: TYakkoPipelineRegistry;
    FCompatibilityManager: TYakkoRuntimeCompatibilityManager;

    function BuildResolutionRequest(
      ARequest: TYakkoRuntimeCompositionRequest;
      const ANameMetadataKey: string
    ): TYakkoResolutionRequest;

    function ResolveModel(
      ARequest: TYakkoRuntimeCompositionRequest;
      AResult: TYakkoRuntimeCompositionResult
    ): Boolean;

    function ResolveProvider(
      ARequest: TYakkoRuntimeCompositionRequest;
      AResult: TYakkoRuntimeCompositionResult
    ): Boolean;

    function ResolveTemplate(
      ARequest: TYakkoRuntimeCompositionRequest;
      AResult: TYakkoRuntimeCompositionResult
    ): Boolean;

    function ResolvePipeline(
      ARequest: TYakkoRuntimeCompositionRequest;
      AResult: TYakkoRuntimeCompositionResult
    ): Boolean;

    function ValidateComposedRuntime(AResult: TYakkoRuntimeCompositionResult): Boolean;

    function HasAnyResolvedItem(AResult: TYakkoRuntimeCompositionResult): Boolean;

    procedure ApplyResolutionFailure(
      AResult: TYakkoRuntimeCompositionResult;
      const AStepName: string;
      AResolutionResult: TYakkoResolutionResult
    );
  public
    constructor Create(
      AModelRegistry: TYakkoModelRegistry;
      AProviderRegistry: TYakkoProviderRegistry;
      ATemplateRegistry: TYakkoTemplateRegistry;
      APipelineRegistry: TYakkoPipelineRegistry
    );
    destructor Destroy; override;

    function Compose(ARequest: TYakkoRuntimeCompositionRequest): TYakkoRuntimeCompositionResult;
  end;

implementation

const
  CModelNameMetadataKey = 'model_name';
  CProviderNameMetadataKey = 'provider_name';
  CTemplateNameMetadataKey = 'template_name';
  CPipelineNameMetadataKey = 'pipeline_name';

procedure CloneStringDictionary(ASource, ADest: TYakkoRuntimeCompositionMetadata);
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

function GetDictionaryValueOrEmpty(ADictionary: TYakkoRuntimeCompositionMetadata; const AKey: string): string;
begin
  Result := '';
  if Assigned(ADictionary) and ADictionary.ContainsKey(AKey) then
    Result := Trim(ADictionary[AKey]);
end;

procedure CopyCapabilities(ASource, ADest: TYakkoRuntimeCapabilities);
var
  LCapability: TYakkoRuntimeCapability;
begin
  if not Assigned(ADest) then
    raise EArgumentNilException.Create('ADest must be assigned.');

  if not Assigned(ASource) then
    Exit;

  for LCapability in ASource.ToArray do
    ADest.Add(LCapability);
end;

{ TYakkoCompositionStatusHelper }

function TYakkoCompositionStatusHelper.ToString: string;
begin
  case Self of
    csSuccess:
      Result := 'success';
    csPartial:
      Result := 'partial';
    csFailed:
      Result := 'failed';
  else
    Result := 'failed';
  end;
end;

{ TYakkoRuntimeCompositionRequest }

constructor TYakkoRuntimeCompositionRequest.Create;
begin
  inherited Create;
  FRequiredCapabilities := TYakkoRuntimeCapabilities.Create;
  FMetadata := TYakkoRuntimeCompositionMetadata.Create;
  FCreatedAt := Now;
end;

destructor TYakkoRuntimeCompositionRequest.Destroy;
begin
  FreeAndNil(FRequiredCapabilities);
  FreeAndNil(FMetadata);
  inherited;
end;

procedure TYakkoRuntimeCompositionRequest.Clear;
begin
  FreeAndNil(FRequiredCapabilities);
  FRequiredCapabilities := TYakkoRuntimeCapabilities.Create;
  FMetadata.Clear;
  FCreatedAt := Now;
end;

function TYakkoRuntimeCompositionRequest.Clone: TYakkoRuntimeCompositionRequest;
begin
  Result := TYakkoRuntimeCompositionRequest.Create;
  try
    Result.FCreatedAt := FCreatedAt;
    CopyCapabilities(FRequiredCapabilities, Result.FRequiredCapabilities);
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoRuntimeCompositionRequest.ToDebugString: string;
begin
  Result := Format(
    'TYakkoRuntimeCompositionRequest(RequiredCapabilities=%s, Metadata=%d, CreatedAt=%s)',
    [
      FRequiredCapabilities.ToDebugString,
      FMetadata.Count,
      DateTimeToStr(FCreatedAt)
    ]
  );
end;

{ TYakkoRuntimeCompositionResult }

constructor TYakkoRuntimeCompositionResult.Create;
begin
  inherited Create;
  FStatus := csFailed;
  FModel := nil;
  FProvider := nil;
  FTemplate := nil;
  FPipeline := nil;
  FCompatibilityResult := nil;
  FReason := '';
  FMetadata := TYakkoRuntimeCompositionMetadata.Create;
end;

destructor TYakkoRuntimeCompositionResult.Destroy;
begin
  FreeAndNil(FModel);
  FreeAndNil(FProvider);
  FreeAndNil(FTemplate);
  FreeAndNil(FPipeline);
  FreeAndNil(FCompatibilityResult);
  FreeAndNil(FMetadata);
  inherited;
end;

procedure TYakkoRuntimeCompositionResult.SetModel(const Value: TYakkoRegistryItem);
begin
  FreeAndNil(FModel);
  if Assigned(Value) then
    FModel := Value.Clone;
end;

procedure TYakkoRuntimeCompositionResult.SetProvider(const Value: TYakkoRegistryItem);
begin
  FreeAndNil(FProvider);
  if Assigned(Value) then
    FProvider := Value.Clone;
end;

procedure TYakkoRuntimeCompositionResult.SetTemplate(const Value: TYakkoRegistryItem);
begin
  FreeAndNil(FTemplate);
  if Assigned(Value) then
    FTemplate := Value.Clone;
end;

procedure TYakkoRuntimeCompositionResult.SetPipeline(const Value: TYakkoRegistryItem);
begin
  FreeAndNil(FPipeline);
  if Assigned(Value) then
    FPipeline := Value.Clone;
end;

procedure TYakkoRuntimeCompositionResult.SetCompatibilityResult(const Value: TYakkoCompatibilityResult);
begin
  FreeAndNil(FCompatibilityResult);
  if Assigned(Value) then
    FCompatibilityResult := Value.Clone;
end;

procedure TYakkoRuntimeCompositionResult.Clear;
begin
  FStatus := csFailed;
  FreeAndNil(FModel);
  FreeAndNil(FProvider);
  FreeAndNil(FTemplate);
  FreeAndNil(FPipeline);
  FreeAndNil(FCompatibilityResult);
  FReason := '';
  FMetadata.Clear;
end;

function TYakkoRuntimeCompositionResult.Clone: TYakkoRuntimeCompositionResult;
begin
  Result := TYakkoRuntimeCompositionResult.Create;
  try
    Result.FStatus := FStatus;
    Result.Model := FModel;
    Result.Provider := FProvider;
    Result.Template := FTemplate;
    Result.Pipeline := FPipeline;
    Result.CompatibilityResult := FCompatibilityResult;
    Result.FReason := FReason;
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoRuntimeCompositionResult.ToDebugString: string;
var
  LCompatibilityText: string;
begin
  if Assigned(FCompatibilityResult) then
    LCompatibilityText := FCompatibilityResult.ToDebugString
  else
    LCompatibilityText := '<nil>';

  Result := Format(
    'TYakkoRuntimeCompositionResult(Status=%s, Model=%s, Provider=%s, Template=%s, Pipeline=%s, Compatibility=%s, Reason=%s, Metadata=%d)',
    [
      FStatus.ToString,
      BoolToStr(Assigned(FModel), True),
      BoolToStr(Assigned(FProvider), True),
      BoolToStr(Assigned(FTemplate), True),
      BoolToStr(Assigned(FPipeline), True),
      LCompatibilityText,
      FReason,
      FMetadata.Count
    ]
  );
end;

{ TYakkoRuntimeCompositionManager }

constructor TYakkoRuntimeCompositionManager.Create(
  AModelRegistry: TYakkoModelRegistry;
  AProviderRegistry: TYakkoProviderRegistry;
  ATemplateRegistry: TYakkoTemplateRegistry;
  APipelineRegistry: TYakkoPipelineRegistry
);
begin
  inherited Create;

  if not Assigned(AModelRegistry) then
    raise EArgumentNilException.Create('AModelRegistry must be assigned.');
  if not Assigned(AProviderRegistry) then
    raise EArgumentNilException.Create('AProviderRegistry must be assigned.');
  if not Assigned(ATemplateRegistry) then
    raise EArgumentNilException.Create('ATemplateRegistry must be assigned.');
  if not Assigned(APipelineRegistry) then
    raise EArgumentNilException.Create('APipelineRegistry must be assigned.');

  FModelRegistry := AModelRegistry;
  FProviderRegistry := AProviderRegistry;
  FTemplateRegistry := ATemplateRegistry;
  FPipelineRegistry := APipelineRegistry;

  FCompatibilityManager := TYakkoRuntimeCompatibilityManager.Create;

  { TODO: add fallback chains for deterministic fallback sequencing. }
  { TODO: add negotiation engine integration after deterministic composition is stable. }
  { TODO: add orchestration graphs only after composition contracts are frozen. }
  { TODO: add execution planning only after compatibility and composition are stable. }
  { TODO: add provider federation support after single-provider deterministic flow is validated. }
  { TODO: add semantic orchestration metadata after explicit composition metrics exist. }
  { TODO: add adaptive composition after deterministic composition has full test coverage. }
  { TODO: add distributed composition after local ownership and consistency are hardened. }
end;

destructor TYakkoRuntimeCompositionManager.Destroy;
begin
  FreeAndNil(FCompatibilityManager);
  inherited;
end;

function TYakkoRuntimeCompositionManager.BuildResolutionRequest(
  ARequest: TYakkoRuntimeCompositionRequest;
  const ANameMetadataKey: string
): TYakkoResolutionRequest;
var
  LName: string;
begin
  Result := TYakkoResolutionRequest.Create;
  CopyCapabilities(ARequest.RequiredCapabilities, Result.RequiredCapabilities);

  LName := GetDictionaryValueOrEmpty(ARequest.Metadata, ANameMetadataKey);
  if LName <> '' then
    Result.Metadata.AddOrSetValue('name', LName);
end;

function TYakkoRuntimeCompositionManager.HasAnyResolvedItem(AResult: TYakkoRuntimeCompositionResult): Boolean;
begin
  Result :=
    Assigned(AResult.Model) or
    Assigned(AResult.Provider) or
    Assigned(AResult.Template) or
    Assigned(AResult.Pipeline);
end;

procedure TYakkoRuntimeCompositionManager.ApplyResolutionFailure(
  AResult: TYakkoRuntimeCompositionResult;
  const AStepName: string;
  AResolutionResult: TYakkoResolutionResult
);
begin
  if HasAnyResolvedItem(AResult) then
    AResult.Status := csPartial
  else
    AResult.Status := csFailed;

  if Assigned(AResolutionResult) then
    AResult.Reason := Format('%s resolution failed: %s', [AStepName, AResolutionResult.Reason])
  else
    AResult.Reason := Format('%s resolution failed.', [AStepName]);

  AResult.Metadata.AddOrSetValue('status', AResult.Status.ToString);
  AResult.Metadata.AddOrSetValue('reason', AResult.Reason);
end;

function TYakkoRuntimeCompositionManager.ResolveModel(
  ARequest: TYakkoRuntimeCompositionRequest;
  AResult: TYakkoRuntimeCompositionResult
): Boolean;
var
  LResolutionRequest: TYakkoResolutionRequest;
  LResolutionResult: TYakkoResolutionResult;
begin
  LResolutionRequest := BuildResolutionRequest(ARequest, CModelNameMetadataKey);
  try
    LResolutionResult := FModelRegistry.ResolveModel(LResolutionRequest);
    try
      Result := Assigned(LResolutionResult) and LResolutionResult.Success and Assigned(LResolutionResult.ResolvedItem);
      if Result then
      begin
        AResult.Model := LResolutionResult.ResolvedItem;
        AResult.Metadata.AddOrSetValue('resolved_model', LResolutionResult.ResolvedItem.Name);
      end
      else
        ApplyResolutionFailure(AResult, 'Model', LResolutionResult);
    finally
      LResolutionResult.Free;
    end;
  finally
    LResolutionRequest.Free;
  end;
end;

function TYakkoRuntimeCompositionManager.ResolveProvider(
  ARequest: TYakkoRuntimeCompositionRequest;
  AResult: TYakkoRuntimeCompositionResult
): Boolean;
var
  LResolutionRequest: TYakkoResolutionRequest;
  LResolutionResult: TYakkoResolutionResult;
begin
  LResolutionRequest := BuildResolutionRequest(ARequest, CProviderNameMetadataKey);
  try
    LResolutionResult := FProviderRegistry.ResolveProvider(LResolutionRequest);
    try
      Result := Assigned(LResolutionResult) and LResolutionResult.Success and Assigned(LResolutionResult.ResolvedItem);
      if Result then
      begin
        AResult.Provider := LResolutionResult.ResolvedItem;
        AResult.Metadata.AddOrSetValue('resolved_provider', LResolutionResult.ResolvedItem.Name);
      end
      else
        ApplyResolutionFailure(AResult, 'Provider', LResolutionResult);
    finally
      LResolutionResult.Free;
    end;
  finally
    LResolutionRequest.Free;
  end;
end;

function TYakkoRuntimeCompositionManager.ResolveTemplate(
  ARequest: TYakkoRuntimeCompositionRequest;
  AResult: TYakkoRuntimeCompositionResult
): Boolean;
var
  LResolutionRequest: TYakkoResolutionRequest;
  LResolutionResult: TYakkoResolutionResult;
begin
  LResolutionRequest := BuildResolutionRequest(ARequest, CTemplateNameMetadataKey);
  try
    LResolutionResult := FTemplateRegistry.ResolveTemplate(LResolutionRequest);
    try
      Result := Assigned(LResolutionResult) and LResolutionResult.Success and Assigned(LResolutionResult.ResolvedItem);
      if Result then
      begin
        AResult.Template := LResolutionResult.ResolvedItem;
        AResult.Metadata.AddOrSetValue('resolved_template', LResolutionResult.ResolvedItem.Name);
      end
      else
        ApplyResolutionFailure(AResult, 'Template', LResolutionResult);
    finally
      LResolutionResult.Free;
    end;
  finally
    LResolutionRequest.Free;
  end;
end;

function TYakkoRuntimeCompositionManager.ResolvePipeline(
  ARequest: TYakkoRuntimeCompositionRequest;
  AResult: TYakkoRuntimeCompositionResult
): Boolean;
var
  LResolutionRequest: TYakkoResolutionRequest;
  LResolutionResult: TYakkoResolutionResult;
begin
  LResolutionRequest := BuildResolutionRequest(ARequest, CPipelineNameMetadataKey);
  try
    LResolutionResult := FPipelineRegistry.ResolvePipeline(LResolutionRequest);
    try
      Result := Assigned(LResolutionResult) and LResolutionResult.Success and Assigned(LResolutionResult.ResolvedItem);
      if Result then
      begin
        AResult.Pipeline := LResolutionResult.ResolvedItem;
        AResult.Metadata.AddOrSetValue('resolved_pipeline', LResolutionResult.ResolvedItem.Name);
      end
      else
        ApplyResolutionFailure(AResult, 'Pipeline', LResolutionResult);
    finally
      LResolutionResult.Free;
    end;
  finally
    LResolutionRequest.Free;
  end;
end;

function TYakkoRuntimeCompositionManager.ValidateComposedRuntime(AResult: TYakkoRuntimeCompositionResult): Boolean;
var
  LCompatibilityRequest: TYakkoCompatibilityRequest;
  LCompatibilityResult: TYakkoCompatibilityResult;
begin
  LCompatibilityRequest := TYakkoCompatibilityRequest.Create;
  try
    LCompatibilityRequest.Target := ctFullRuntime;
    LCompatibilityRequest.Model := AResult.Model;
    LCompatibilityRequest.Provider := AResult.Provider;
    LCompatibilityRequest.Template := AResult.Template;
    LCompatibilityRequest.Pipeline := AResult.Pipeline;

    LCompatibilityResult := FCompatibilityManager.Validate(LCompatibilityRequest);
    try
      AResult.CompatibilityResult := LCompatibilityResult;
      Result := Assigned(LCompatibilityResult) and LCompatibilityResult.Compatible;
    finally
      LCompatibilityResult.Free;
    end;
  finally
    LCompatibilityRequest.Free;
  end;
end;

function TYakkoRuntimeCompositionManager.Compose(ARequest: TYakkoRuntimeCompositionRequest): TYakkoRuntimeCompositionResult;
begin
  Result := TYakkoRuntimeCompositionResult.Create;

  if not Assigned(ARequest) then
  begin
    Result.Status := csFailed;
    Result.Reason := 'Composition request must be assigned.';
    Result.Metadata.AddOrSetValue('status', Result.Status.ToString);
    Result.Metadata.AddOrSetValue('reason', Result.Reason);
    Exit;
  end;

  Result.Metadata.AddOrSetValue('composition_mode', 'deterministic-explicit');
  Result.Metadata.AddOrSetValue('request_created_at', DateTimeToStr(ARequest.CreatedAt));
  Result.Metadata.AddOrSetValue('composed_at', DateTimeToStr(Now));

  if not ResolveModel(ARequest, Result) then
    Exit;

  if not ResolveProvider(ARequest, Result) then
    Exit;

  if not ResolveTemplate(ARequest, Result) then
    Exit;

  if not ResolvePipeline(ARequest, Result) then
    Exit;

  if not ValidateComposedRuntime(Result) then
  begin
    Result.Status := csFailed;
    if Assigned(Result.CompatibilityResult) then
      Result.Reason := 'Compatibility validation failed: ' + Result.CompatibilityResult.Reason
    else
      Result.Reason := 'Compatibility validation failed.';

    Result.Metadata.AddOrSetValue('status', Result.Status.ToString);
    Result.Metadata.AddOrSetValue('reason', Result.Reason);
    Exit;
  end;

  Result.Status := csSuccess;
  Result.Reason := 'Runtime composition completed with deterministic resolution and compatibility validation.';
  Result.Metadata.AddOrSetValue('status', Result.Status.ToString);
  Result.Metadata.AddOrSetValue('reason', Result.Reason);
end;

end.
