unit Yakko.Runtime.SpecializedRegistries;

{ Specialized registry layer for YakkoDelphiLLM modern runtime.

  Architectural intent:
  - keep RuntimeRegistry as the canonical low-level storage for registered items;
  - expose semantic registries for model/provider/template/pipeline operations;
  - reduce branching and avoid generic registry knowledge spread in callers;
  - prepare multi-model and multi-provider evolution with explicit contracts.

  RuntimeRegistry vs Specialized Registries:
  - RuntimeRegistry answers generic storage operations over all item types;
  - specialized registries answer semantic operations for one domain each;
  - specialized registries delegate deterministic selection to RuntimeResolver;
  - this keeps selection logic centralized and prevents registry branching chaos.

  This unit intentionally avoids:
  - DI container;
  - plugin loader;
  - reflection or RTTI scanning;
  - auto-discovery;
  - dynamic module loading;
  - inference behavior changes.

  Reason for avoiding generic-only registry usage:
  - generic registries tend to push type-check branching to every caller;
  - semantic registries keep APIs explicit and easier to evolve safely. }

interface

uses
  Winapi.Windows,
  System.SysUtils,
  Yakko.Runtime.Registry,
  Yakko.Runtime.Capabilities,
  Yakko.Runtime.Resolver;

type
  TYakkoSpecializedRegistryBase = class abstract
  private
    FRuntimeRegistry: TYakkoRuntimeRegistry;
    FResolver: TYakkoRuntimeResolver;
    FTarget: TYakkoResolutionTarget;
    FItemType: TYakkoRegistryItemType;
  protected
    constructor Create(
      ARuntimeRegistry: TYakkoRuntimeRegistry;
      ATarget: TYakkoResolutionTarget;
      AItemType: TYakkoRegistryItemType
    );

    procedure RegisterTypedItem(AItem: TYakkoRegistryItem);
    function ResolveTyped(ARequest: TYakkoResolutionRequest): TYakkoResolutionResult;
    function FindTypedByName(const AName: string): TYakkoRegistryItem;
    function SupportsTypedCapability(const AName: string; ACapability: TYakkoRuntimeCapability): Boolean;
  public
    destructor Destroy; override;

    property RuntimeRegistry: TYakkoRuntimeRegistry read FRuntimeRegistry;
    property Resolver: TYakkoRuntimeResolver read FResolver;
  end;

  TYakkoModelRegistry = class(TYakkoSpecializedRegistryBase)
  public
    constructor Create(ARuntimeRegistry: TYakkoRuntimeRegistry);

    procedure RegisterModel(AItem: TYakkoRegistryItem);
    function ResolveModel(ARequest: TYakkoResolutionRequest): TYakkoResolutionResult;
    function FindByName(const AName: string): TYakkoRegistryItem;
    function SupportsCapability(const AName: string; ACapability: TYakkoRuntimeCapability): Boolean;
  end;

  TYakkoProviderRegistry = class(TYakkoSpecializedRegistryBase)
  public
    constructor Create(ARuntimeRegistry: TYakkoRuntimeRegistry);

    procedure RegisterProvider(AItem: TYakkoRegistryItem);
    function ResolveProvider(ARequest: TYakkoResolutionRequest): TYakkoResolutionResult;
    function FindByName(const AName: string): TYakkoRegistryItem;
    function SupportsCapability(const AName: string; ACapability: TYakkoRuntimeCapability): Boolean;
  end;

  TYakkoTemplateRegistry = class(TYakkoSpecializedRegistryBase)
  public
    constructor Create(ARuntimeRegistry: TYakkoRuntimeRegistry);

    procedure RegisterTemplate(AItem: TYakkoRegistryItem);
    function ResolveTemplate(ARequest: TYakkoResolutionRequest): TYakkoResolutionResult;
    function FindByName(const AName: string): TYakkoRegistryItem;
    function SupportsCapability(const AName: string; ACapability: TYakkoRuntimeCapability): Boolean;
  end;

  TYakkoPipelineRegistry = class(TYakkoSpecializedRegistryBase)
  public
    constructor Create(ARuntimeRegistry: TYakkoRuntimeRegistry);

    procedure RegisterPipeline(AItem: TYakkoRegistryItem);
    function ResolvePipeline(ARequest: TYakkoResolutionRequest): TYakkoResolutionResult;
    function FindByName(const AName: string): TYakkoRegistryItem;
    function SupportsCapability(const AName: string; ACapability: TYakkoRuntimeCapability): Boolean;
  end;

implementation

function CreateResolutionFailure(const AReason: string): TYakkoResolutionResult;
begin
  Result := TYakkoResolutionResult.Create;
  Result.Success := False;
  Result.Reason := AReason;
  Result.Metadata.AddOrSetValue('status', 'failed');
  Result.Metadata.AddOrSetValue('reason', AReason);
end;

{ TYakkoSpecializedRegistryBase }

constructor TYakkoSpecializedRegistryBase.Create(
  ARuntimeRegistry: TYakkoRuntimeRegistry;
  ATarget: TYakkoResolutionTarget;
  AItemType: TYakkoRegistryItemType
);
begin
  inherited Create;
  if not Assigned(ARuntimeRegistry) then
    raise EArgumentNilException.Create('ARuntimeRegistry must be assigned.');

  FRuntimeRegistry := ARuntimeRegistry;
  FResolver := TYakkoRuntimeResolver.Create(FRuntimeRegistry);
  FTarget := ATarget;
  FItemType := AItemType;

  { The specialized registry owns only its resolver and never owns the shared runtime registry. }
  { TODO: add embedding registries as explicit semantic registries. }
  { TODO: add tool registries as explicit semantic registries. }
  { TODO: add reasoning registries for explicit reasoning-capable components. }
  { TODO: add multimodal registries for image/audio/video-capable components. }
  { TODO: add vector store registries for retrieval infrastructure components. }
  { TODO: add reranker registries for ranking pipelines and evaluation passes. }
  { TODO: add provider federation policies after single-node deterministic flow is stable. }
  { TODO: add distributed registries after local ownership and consistency are validated. }
end;

destructor TYakkoSpecializedRegistryBase.Destroy;
begin
  FreeAndNil(FResolver);
  inherited;
end;

procedure TYakkoSpecializedRegistryBase.RegisterTypedItem(AItem: TYakkoRegistryItem);
var
  LItemToRegister: TYakkoRegistryItem;
begin
  if not Assigned(AItem) then
    raise EArgumentNilException.Create('AItem must be assigned.');

  LItemToRegister := AItem.Clone;
  try
    LItemToRegister.ItemType := FItemType;
    FRuntimeRegistry.RegisterItem(LItemToRegister);
  finally
    LItemToRegister.Free;
  end;
end;

function TYakkoSpecializedRegistryBase.ResolveTyped(ARequest: TYakkoResolutionRequest): TYakkoResolutionResult;
var
  LRequest: TYakkoResolutionRequest;
begin
  if not Assigned(ARequest) then
    Exit(CreateResolutionFailure('Resolution request must be assigned.'));

  LRequest := ARequest.Clone;
  try
    LRequest.Target := FTarget;
    Result := FResolver.Resolve(LRequest);
  finally
    LRequest.Free;
  end;
end;

function TYakkoSpecializedRegistryBase.FindTypedByName(const AName: string): TYakkoRegistryItem;
var
  LItem: TYakkoRegistryItem;
begin
  Result := nil;
  LItem := FRuntimeRegistry.FindByName(AName);
  if not Assigned(LItem) then
    Exit;

  if LItem.ItemType <> FItemType then
    Exit;

  Result := LItem.Clone;
end;

function TYakkoSpecializedRegistryBase.SupportsTypedCapability(const AName: string; ACapability: TYakkoRuntimeCapability): Boolean;
var
  LRequest: TYakkoResolutionRequest;
  LResult: TYakkoResolutionResult;
begin
  LRequest := TYakkoResolutionRequest.Create;
  try
    LRequest.Target := FTarget;
    LRequest.Metadata.AddOrSetValue('name', AName);
    LRequest.RequiredCapabilities.Add(ACapability);

    LResult := FResolver.Resolve(LRequest);
    try
      Result := LResult.Success;
    finally
      LResult.Free;
    end;
  finally
    LRequest.Free;
  end;
end;

{ TYakkoModelRegistry }

constructor TYakkoModelRegistry.Create(ARuntimeRegistry: TYakkoRuntimeRegistry);
begin
  inherited Create(ARuntimeRegistry, rtModel, ritModel);
end;

procedure TYakkoModelRegistry.RegisterModel(AItem: TYakkoRegistryItem);
begin
  RegisterTypedItem(AItem);
end;

function TYakkoModelRegistry.ResolveModel(ARequest: TYakkoResolutionRequest): TYakkoResolutionResult;
begin
  Result := ResolveTyped(ARequest);
end;

function TYakkoModelRegistry.FindByName(const AName: string): TYakkoRegistryItem;
begin
  Result := FindTypedByName(AName);
end;

function TYakkoModelRegistry.SupportsCapability(const AName: string; ACapability: TYakkoRuntimeCapability): Boolean;
begin
  Result := SupportsTypedCapability(AName, ACapability);
end;

{ TYakkoProviderRegistry }

constructor TYakkoProviderRegistry.Create(ARuntimeRegistry: TYakkoRuntimeRegistry);
begin
  inherited Create(ARuntimeRegistry, rtProvider, ritProvider);
end;

procedure TYakkoProviderRegistry.RegisterProvider(AItem: TYakkoRegistryItem);
begin
  RegisterTypedItem(AItem);
end;

function TYakkoProviderRegistry.ResolveProvider(ARequest: TYakkoResolutionRequest): TYakkoResolutionResult;
begin
  Result := ResolveTyped(ARequest);
end;

function TYakkoProviderRegistry.FindByName(const AName: string): TYakkoRegistryItem;
begin
  Result := FindTypedByName(AName);
end;

function TYakkoProviderRegistry.SupportsCapability(const AName: string; ACapability: TYakkoRuntimeCapability): Boolean;
begin
  Result := SupportsTypedCapability(AName, ACapability);
end;

{ TYakkoTemplateRegistry }

constructor TYakkoTemplateRegistry.Create(ARuntimeRegistry: TYakkoRuntimeRegistry);
begin
  inherited Create(ARuntimeRegistry, rtTemplate, ritTemplate);
end;

procedure TYakkoTemplateRegistry.RegisterTemplate(AItem: TYakkoRegistryItem);
begin
  RegisterTypedItem(AItem);
end;

function TYakkoTemplateRegistry.ResolveTemplate(ARequest: TYakkoResolutionRequest): TYakkoResolutionResult;
begin
  Result := ResolveTyped(ARequest);
end;

function TYakkoTemplateRegistry.FindByName(const AName: string): TYakkoRegistryItem;
begin
  Result := FindTypedByName(AName);
end;

function TYakkoTemplateRegistry.SupportsCapability(const AName: string; ACapability: TYakkoRuntimeCapability): Boolean;
begin
  Result := SupportsTypedCapability(AName, ACapability);
end;

{ TYakkoPipelineRegistry }

constructor TYakkoPipelineRegistry.Create(ARuntimeRegistry: TYakkoRuntimeRegistry);
begin
  inherited Create(ARuntimeRegistry, rtPipeline, ritPipeline);
end;

procedure TYakkoPipelineRegistry.RegisterPipeline(AItem: TYakkoRegistryItem);
begin
  RegisterTypedItem(AItem);
end;

function TYakkoPipelineRegistry.ResolvePipeline(ARequest: TYakkoResolutionRequest): TYakkoResolutionResult;
begin
  Result := ResolveTyped(ARequest);
end;

function TYakkoPipelineRegistry.FindByName(const AName: string): TYakkoRegistryItem;
begin
  Result := FindTypedByName(AName);
end;

function TYakkoPipelineRegistry.SupportsCapability(const AName: string; ACapability: TYakkoRuntimeCapability): Boolean;
begin
  Result := SupportsTypedCapability(AName, ACapability);
end;

end.
