unit Yakko.Runtime.Compatibility;

{ Explicit runtime compatibility layer for YakkoDelphiLLM.

  Architectural intent:
  - validate deterministic compatibility after explicit resolution;
  - keep compatibility rules centralized and explicit;
  - avoid scattered compatibility if/else chains and cross-module knowledge spread;
  - prepare future negotiation, fallback and orchestration without enabling them yet.

  Capabilities vs Resolver vs CompatibilityLayer:
  - Capabilities describe what each runtime item can do;
  - Resolver selects which runtime item should be used;
  - CompatibilityLayer validates if selected items are compatible together.

  Why explicit compatibility validation:
  - prevents compatibility explosion caused by ad-hoc branching;
  - enforces predictable checks based on metadata and declared capabilities;
  - prepares multi-provider and orchestration evolution in a controlled way.

  This unit intentionally avoids:
  - AI planning;
  - adaptive negotiation;
  - probabilistic scoring;
  - distributed orchestration;
  - inference behavior changes. }

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Yakko.Runtime.Registry,
  Yakko.Runtime.Capabilities;

type
  TYakkoCompatibilityTarget =
  (
    ctModelProvider,
    ctModelTemplate,
    ctProviderPipeline,
    ctTemplatePipeline,
    ctFullRuntime
  );

  TYakkoCompatibilityTargetHelper = record helper for TYakkoCompatibilityTarget
  public
    function ToString: string;
  end;

  TYakkoCompatibilityMetadata = TDictionary<string, string>;

  TYakkoCompatibilityRequest = class
  private
    FTarget: TYakkoCompatibilityTarget;
    FModel: TYakkoRegistryItem;
    FProvider: TYakkoRegistryItem;
    FTemplate: TYakkoRegistryItem;
    FPipeline: TYakkoRegistryItem;
    FMetadata: TYakkoCompatibilityMetadata;
    FCreatedAt: TDateTime;

    procedure SetModel(const Value: TYakkoRegistryItem);
    procedure SetProvider(const Value: TYakkoRegistryItem);
    procedure SetTemplate(const Value: TYakkoRegistryItem);
    procedure SetPipeline(const Value: TYakkoRegistryItem);
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    function Clone: TYakkoCompatibilityRequest;
    function ToDebugString: string;

    property Target: TYakkoCompatibilityTarget read FTarget write FTarget;
    property Model: TYakkoRegistryItem read FModel write SetModel;
    property Provider: TYakkoRegistryItem read FProvider write SetProvider;
    property Template: TYakkoRegistryItem read FTemplate write SetTemplate;
    property Pipeline: TYakkoRegistryItem read FPipeline write SetPipeline;
    property Metadata: TYakkoCompatibilityMetadata read FMetadata;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
  end;

  TYakkoCompatibilityResult = class
  private
    FCompatible: Boolean;
    FReason: string;
    FMissingCapabilities: TYakkoRuntimeCapabilities;
    FMetadata: TYakkoCompatibilityMetadata;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    function Clone: TYakkoCompatibilityResult;
    function ToDebugString: string;

    property Compatible: Boolean read FCompatible write FCompatible;
    property Reason: string read FReason write FReason;
    property MissingCapabilities: TYakkoRuntimeCapabilities read FMissingCapabilities;
    property Metadata: TYakkoCompatibilityMetadata read FMetadata;
  end;

  TYakkoRuntimeCompatibilityManager = class
  private
    function ValidateRequiredComponents(
      ARequest: TYakkoCompatibilityRequest;
      AResult: TYakkoCompatibilityResult
    ): Boolean;

    function ValidateMinimumCapabilities(
      ARequest: TYakkoCompatibilityRequest;
      AResult: TYakkoCompatibilityResult
    ): Boolean;

    function ValidateTargetRules(
      ARequest: TYakkoCompatibilityRequest;
      AResult: TYakkoCompatibilityResult
    ): Boolean;

    function ValidatePairCompatibility(
      ASourceItem: TYakkoRegistryItem;
      ATargetItem: TYakkoRegistryItem;
      ATargetLabelPlural: string;
      ARequiredCapabilitiesKey: string;
      AResult: TYakkoCompatibilityResult
    ): Boolean;
  public
    constructor Create;

    function Validate(ARequest: TYakkoCompatibilityRequest): TYakkoCompatibilityResult;
  end;

implementation

procedure CloneStringDictionary(ASource, ADest: TYakkoCompatibilityMetadata);
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

function GetDictionaryValueOrEmpty(ADictionary: TYakkoCompatibilityMetadata; const AKey: string): string;
begin
  Result := '';
  if Assigned(ADictionary) and ADictionary.ContainsKey(AKey) then
    Result := Trim(ADictionary[AKey]);
end;

function ParseTokens(const AValue: string): TArray<string>;
var
  LRaw: string;
  LList: TStringList;
  LIndex: Integer;
  LToken: string;
begin
  LRaw := StringReplace(StringReplace(StringReplace(AValue, ';', ',', [rfReplaceAll]), '|', ',', [rfReplaceAll]), #9, ',', [rfReplaceAll]);
  LList := TStringList.Create;
  try
    LList.StrictDelimiter := True;
    LList.Delimiter := ',';
    LList.DelimitedText := LRaw;

    SetLength(Result, 0);
    for LIndex := 0 to LList.Count - 1 do
    begin
      LToken := Trim(LList[LIndex]).ToLower;
      if LToken = '' then
        Continue;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LToken;
    end;
  finally
    LList.Free;
  end;
end;

function TokensContain(const ATokens: TArray<string>; const AValue: string): Boolean;
var
  LToken: string;
begin
  Result := False;
  for LToken in ATokens do
  begin
    if SameText(LToken, AValue) then
      Exit(True);
  end;
end;

function TryParseRuntimeCapability(const AValue: string; out ACapability: TYakkoRuntimeCapability): Boolean;
var
  LNormalized: string;
begin
  LNormalized := Trim(AValue).ToLower;

  Result := True;
  if SameText(LNormalized, 'chat-completion') then
    ACapability := rcChatCompletion
  else if SameText(LNormalized, 'streaming') then
    ACapability := rcStreaming
  else if SameText(LNormalized, 'tool-calling') then
    ACapability := rcToolCalling
  else if SameText(LNormalized, 'reasoning') then
    ACapability := rcReasoning
  else if SameText(LNormalized, 'json-mode') then
    ACapability := rcJsonMode
  else if SameText(LNormalized, 'grammar-constraints') then
    ACapability := rcGrammarConstraints
  else if SameText(LNormalized, 'embeddings') then
    ACapability := rcEmbeddings
  else if SameText(LNormalized, 'vision') then
    ACapability := rcVision
  else if SameText(LNormalized, 'multimodal') then
    ACapability := rcMultimodal
  else if SameText(LNormalized, 'speculative-decoding') then
    ACapability := rcSpeculativeDecoding
  else
    Result := False;
end;

function ItemHasCapability(AItem: TYakkoRegistryItem; ACapability: TYakkoRuntimeCapability): Boolean;
var
  LCapabilitiesRaw: string;
  LDeclaredTokens: TArray<string>;
begin
  if not Assigned(AItem) or not Assigned(AItem.Metadata) then
    Exit(False);

  LCapabilitiesRaw := GetDictionaryValueOrEmpty(AItem.Metadata, 'capabilities');
  if LCapabilitiesRaw = '' then
    Exit(False);

  LDeclaredTokens := ParseTokens(LCapabilitiesRaw);
  Result := TokensContain(LDeclaredTokens, ACapability.ToString);
end;

procedure AppendResultFailure(
  AResult: TYakkoCompatibilityResult;
  const AReason: string
);
begin
  AResult.Compatible := False;
  AResult.Reason := AReason;
  AResult.Metadata.AddOrSetValue('status', 'failed');
  AResult.Metadata.AddOrSetValue('reason', AReason);
end;

procedure AddMissingCapability(
  AResult: TYakkoCompatibilityResult;
  ACapability: TYakkoRuntimeCapability
);
begin
  if not AResult.MissingCapabilities.Supports(ACapability) then
    AResult.MissingCapabilities.Add(ACapability);
end;

{ TYakkoCompatibilityTargetHelper }

function TYakkoCompatibilityTargetHelper.ToString: string;
begin
  case Self of
    ctModelProvider:
      Result := 'model-provider';
    ctModelTemplate:
      Result := 'model-template';
    ctProviderPipeline:
      Result := 'provider-pipeline';
    ctTemplatePipeline:
      Result := 'template-pipeline';
    ctFullRuntime:
      Result := 'full-runtime';
  else
    Result := 'model-provider';
  end;
end;

{ TYakkoCompatibilityRequest }

constructor TYakkoCompatibilityRequest.Create;
begin
  inherited Create;
  FTarget := ctModelProvider;
  FModel := nil;
  FProvider := nil;
  FTemplate := nil;
  FPipeline := nil;
  FMetadata := TYakkoCompatibilityMetadata.Create;
  FCreatedAt := Now;

  { TODO: add negotiation engine request fields after deterministic baseline is stable. }
  { TODO: add compatibility scoring hints only when deterministic checks are locked. }
  { TODO: add fallback chain preferences after compatibility outcomes are explicit. }
  { TODO: add execution planning hooks after compatibility contracts are mature. }
end;

destructor TYakkoCompatibilityRequest.Destroy;
begin
  FreeAndNil(FModel);
  FreeAndNil(FProvider);
  FreeAndNil(FTemplate);
  FreeAndNil(FPipeline);
  FreeAndNil(FMetadata);
  inherited;
end;

procedure TYakkoCompatibilityRequest.SetModel(const Value: TYakkoRegistryItem);
begin
  FreeAndNil(FModel);
  if Assigned(Value) then
    FModel := Value.Clone;
end;

procedure TYakkoCompatibilityRequest.SetProvider(const Value: TYakkoRegistryItem);
begin
  FreeAndNil(FProvider);
  if Assigned(Value) then
    FProvider := Value.Clone;
end;

procedure TYakkoCompatibilityRequest.SetTemplate(const Value: TYakkoRegistryItem);
begin
  FreeAndNil(FTemplate);
  if Assigned(Value) then
    FTemplate := Value.Clone;
end;

procedure TYakkoCompatibilityRequest.SetPipeline(const Value: TYakkoRegistryItem);
begin
  FreeAndNil(FPipeline);
  if Assigned(Value) then
    FPipeline := Value.Clone;
end;

procedure TYakkoCompatibilityRequest.Clear;
begin
  FTarget := ctModelProvider;
  FreeAndNil(FModel);
  FreeAndNil(FProvider);
  FreeAndNil(FTemplate);
  FreeAndNil(FPipeline);
  FMetadata.Clear;
  FCreatedAt := Now;
end;

function TYakkoCompatibilityRequest.Clone: TYakkoCompatibilityRequest;
begin
  Result := TYakkoCompatibilityRequest.Create;
  try
    Result.FTarget := FTarget;
    Result.FCreatedAt := FCreatedAt;
    Result.Model := FModel;
    Result.Provider := FProvider;
    Result.Template := FTemplate;
    Result.Pipeline := FPipeline;
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoCompatibilityRequest.ToDebugString: string;
begin
  Result := Format(
    'TYakkoCompatibilityRequest(Target=%s, Model=%s, Provider=%s, Template=%s, Pipeline=%s, Metadata=%d, CreatedAt=%s)',
    [
      FTarget.ToString,
      BoolToStr(Assigned(FModel), True),
      BoolToStr(Assigned(FProvider), True),
      BoolToStr(Assigned(FTemplate), True),
      BoolToStr(Assigned(FPipeline), True),
      FMetadata.Count,
      DateTimeToStr(FCreatedAt)
    ]
  );
end;

{ TYakkoCompatibilityResult }

constructor TYakkoCompatibilityResult.Create;
begin
  inherited Create;
  FCompatible := False;
  FReason := '';
  FMissingCapabilities := TYakkoRuntimeCapabilities.Create;
  FMetadata := TYakkoCompatibilityMetadata.Create;

  { TODO: add provider federation metadata after local compatibility flow is validated. }
  { TODO: add orchestration graph markers when orchestration contracts are introduced. }
  { TODO: add semantic compatibility traces for richer diagnostics. }
  { TODO: add distributed compatibility validation traces for future multi-node support. }
end;

destructor TYakkoCompatibilityResult.Destroy;
begin
  FreeAndNil(FMissingCapabilities);
  FreeAndNil(FMetadata);
  inherited;
end;

procedure TYakkoCompatibilityResult.Clear;
begin
  FCompatible := False;
  FReason := '';
  FreeAndNil(FMissingCapabilities);
  FMissingCapabilities := TYakkoRuntimeCapabilities.Create;
  FMetadata.Clear;
end;

function TYakkoCompatibilityResult.Clone: TYakkoCompatibilityResult;
var
  LCapability: TYakkoRuntimeCapability;
begin
  Result := TYakkoCompatibilityResult.Create;
  try
    Result.FCompatible := FCompatible;
    Result.FReason := FReason;
    for LCapability in FMissingCapabilities.ToArray do
      Result.FMissingCapabilities.Add(LCapability);
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoCompatibilityResult.ToDebugString: string;
begin
  Result := Format(
    'TYakkoCompatibilityResult(Compatible=%s, Reason=%s, MissingCapabilities=%s, Metadata=%d)',
    [
      BoolToStr(FCompatible, True),
      FReason,
      FMissingCapabilities.ToDebugString,
      FMetadata.Count
    ]
  );
end;

{ TYakkoRuntimeCompatibilityManager }

constructor TYakkoRuntimeCompatibilityManager.Create;
begin
  inherited Create;

  { Deterministic compatibility manager with explicit rules only. }
  { TODO: add negotiation engine integration after deterministic validation is fully adopted. }
  { TODO: add compatibility scoring only after deterministic compatibility rules stabilize. }
  { TODO: add fallback chains only after explicit compatibility transitions are modeled. }
end;

function TYakkoRuntimeCompatibilityManager.ValidateRequiredComponents(
  ARequest: TYakkoCompatibilityRequest;
  AResult: TYakkoCompatibilityResult
): Boolean;
begin
  Result := True;

  case ARequest.Target of
    ctModelProvider:
      Result := Assigned(ARequest.Model) and Assigned(ARequest.Provider);
    ctModelTemplate:
      Result := Assigned(ARequest.Model) and Assigned(ARequest.Template);
    ctProviderPipeline:
      Result := Assigned(ARequest.Provider) and Assigned(ARequest.Pipeline);
    ctTemplatePipeline:
      Result := Assigned(ARequest.Template) and Assigned(ARequest.Pipeline);
    ctFullRuntime:
      Result := Assigned(ARequest.Model) and Assigned(ARequest.Provider) and Assigned(ARequest.Template) and Assigned(ARequest.Pipeline);
  end;

  if not Result then
    AppendResultFailure(
      AResult,
      Format('Missing required components for target %s.', [ARequest.Target.ToString])
    );
end;

function TYakkoRuntimeCompatibilityManager.ValidateMinimumCapabilities(
  ARequest: TYakkoCompatibilityRequest;
  AResult: TYakkoCompatibilityResult
): Boolean;

  function HasDeclaredCapabilities(AItem: TYakkoRegistryItem): Boolean;
  var
    LRawCaps: string;
  begin
    if not Assigned(AItem) then
      Exit(True);
    LRawCaps := GetDictionaryValueOrEmpty(AItem.Metadata, 'capabilities');
    Result := LRawCaps <> '';
  end;

begin
  Result :=
    HasDeclaredCapabilities(ARequest.Model) and
    HasDeclaredCapabilities(ARequest.Provider) and
    HasDeclaredCapabilities(ARequest.Template) and
    HasDeclaredCapabilities(ARequest.Pipeline);

  if not Result then
  begin
    AppendResultFailure(AResult, 'One or more required components do not declare capabilities metadata.');
    AResult.Metadata.AddOrSetValue('missing_capabilities_metadata', 'true');
  end;
end;

function TYakkoRuntimeCompatibilityManager.ValidatePairCompatibility(
  ASourceItem: TYakkoRegistryItem;
  ATargetItem: TYakkoRegistryItem;
  ATargetLabelPlural: string;
  ARequiredCapabilitiesKey: string;
  AResult: TYakkoCompatibilityResult
): Boolean;
var
  LAllowListRaw: string;
  LAllowListTokens: TArray<string>;
  LRequiredRaw: string;
  LRequiredTokens: TArray<string>;
  LCapabilityToken: string;
  LCapability: TYakkoRuntimeCapability;
begin
  Result := True;

  if not Assigned(ASourceItem) or not Assigned(ATargetItem) then
    Exit;

  LAllowListRaw := GetDictionaryValueOrEmpty(ASourceItem.Metadata, 'supported_' + ATargetLabelPlural);
  if LAllowListRaw <> '' then
  begin
    LAllowListTokens := ParseTokens(LAllowListRaw);
    if not TokensContain(LAllowListTokens, ATargetItem.Name.ToLower) then
    begin
      AppendResultFailure(
        AResult,
        Format(
          'Explicit allow-list mismatch: %s does not support %s %s.',
          [ASourceItem.Name, ATargetLabelPlural, ATargetItem.Name]
        )
      );
      Exit(False);
    end;
  end;

  LRequiredRaw := GetDictionaryValueOrEmpty(ASourceItem.Metadata, ARequiredCapabilitiesKey);
  if LRequiredRaw = '' then
    Exit;

  LRequiredTokens := ParseTokens(LRequiredRaw);
  for LCapabilityToken in LRequiredTokens do
  begin
    if not TryParseRuntimeCapability(LCapabilityToken, LCapability) then
      Continue;

    if not ItemHasCapability(ATargetItem, LCapability) then
    begin
      AddMissingCapability(AResult, LCapability);
      Result := False;
    end;
  end;

  if not Result then
    AppendResultFailure(
      AResult,
      Format(
        'Capability mismatch between %s and %s.',
        [ASourceItem.Name, ATargetItem.Name]
      )
    );
end;

function TYakkoRuntimeCompatibilityManager.ValidateTargetRules(
  ARequest: TYakkoCompatibilityRequest;
  AResult: TYakkoCompatibilityResult
): Boolean;
begin
  case ARequest.Target of
    ctModelProvider:
      Result :=
        ValidatePairCompatibility(ARequest.Model, ARequest.Provider, 'providers', 'requires_provider_capabilities', AResult) and
        ValidatePairCompatibility(ARequest.Provider, ARequest.Model, 'models', 'requires_model_capabilities', AResult);

    ctModelTemplate:
      Result :=
        ValidatePairCompatibility(ARequest.Model, ARequest.Template, 'templates', 'requires_template_capabilities', AResult) and
        ValidatePairCompatibility(ARequest.Template, ARequest.Model, 'models', 'requires_model_capabilities', AResult);

    ctProviderPipeline:
      Result :=
        ValidatePairCompatibility(ARequest.Provider, ARequest.Pipeline, 'pipelines', 'requires_pipeline_capabilities', AResult) and
        ValidatePairCompatibility(ARequest.Pipeline, ARequest.Provider, 'providers', 'requires_provider_capabilities', AResult);

    ctTemplatePipeline:
      Result :=
        ValidatePairCompatibility(ARequest.Template, ARequest.Pipeline, 'pipelines', 'requires_pipeline_capabilities', AResult) and
        ValidatePairCompatibility(ARequest.Pipeline, ARequest.Template, 'templates', 'requires_template_capabilities', AResult);

    ctFullRuntime:
      Result :=
        ValidatePairCompatibility(ARequest.Model, ARequest.Provider, 'providers', 'requires_provider_capabilities', AResult) and
        ValidatePairCompatibility(ARequest.Provider, ARequest.Model, 'models', 'requires_model_capabilities', AResult) and
        ValidatePairCompatibility(ARequest.Model, ARequest.Template, 'templates', 'requires_template_capabilities', AResult) and
        ValidatePairCompatibility(ARequest.Template, ARequest.Model, 'models', 'requires_model_capabilities', AResult) and
        ValidatePairCompatibility(ARequest.Provider, ARequest.Pipeline, 'pipelines', 'requires_pipeline_capabilities', AResult) and
        ValidatePairCompatibility(ARequest.Pipeline, ARequest.Provider, 'providers', 'requires_provider_capabilities', AResult) and
        ValidatePairCompatibility(ARequest.Template, ARequest.Pipeline, 'pipelines', 'requires_pipeline_capabilities', AResult) and
        ValidatePairCompatibility(ARequest.Pipeline, ARequest.Template, 'templates', 'requires_template_capabilities', AResult);
  else
    Result := False;
  end;

  if not Result and (AResult.Reason = '') then
    AppendResultFailure(
      AResult,
      Format('Target validation failed for %s.', [ARequest.Target.ToString])
    );
end;

function TYakkoRuntimeCompatibilityManager.Validate(
  ARequest: TYakkoCompatibilityRequest
): TYakkoCompatibilityResult;
begin
  Result := TYakkoCompatibilityResult.Create;

  if not Assigned(ARequest) then
  begin
    AppendResultFailure(Result, 'Compatibility request must be assigned.');
    Exit;
  end;

  Result.Metadata.AddOrSetValue('target', ARequest.Target.ToString);
  Result.Metadata.AddOrSetValue('request_created_at', DateTimeToStr(ARequest.CreatedAt));
  Result.Metadata.AddOrSetValue('validated_at', DateTimeToStr(Now));
  Result.Metadata.AddOrSetValue('validation_mode', 'deterministic-explicit');

  if not ValidateRequiredComponents(ARequest, Result) then
    Exit;

  if not ValidateMinimumCapabilities(ARequest, Result) then
    Exit;

  if not ValidateTargetRules(ARequest, Result) then
    Exit;

  Result.Compatible := True;
  Result.Reason := 'Compatibility validated with deterministic explicit rules.';
  Result.Metadata.AddOrSetValue('status', 'compatible');
  Result.Metadata.AddOrSetValue('reason', Result.Reason);
end;

end.
