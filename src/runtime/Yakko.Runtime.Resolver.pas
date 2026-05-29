unit Yakko.Runtime.Resolver;

{ Explicit runtime resolver layer for YakkoDelphiLLM.

  Architectural intent:
  - sit after Registry and Capabilities, before any future execution planning;
  - resolve providers, models, templates and pipelines deterministically;
  - keep selection explicit so capability branching does not spread across the codebase;
  - prepare future negotiation and fallback without introducing heuristics too early.

  Layer distinction:
  - Registry answers "what runtime items exist?";
  - Capabilities answers "what can each item do?";
  - Resolver answers "which declared item should be selected for this explicit request?";
  - this unit intentionally does not perform AI planning, auto-learning, RTTI
    scanning, distributed orchestration or probabilistic scoring.

  Resolution policy:
  - deterministic;
  - explicit request metadata;
  - explicit capability compatibility checks;
  - no heuristic ranking;
  - no reflection;
  - no automatic negotiation yet. }

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Yakko.Runtime.Registry,
  Yakko.Runtime.Capabilities;

type
  TYakkoResolutionTarget =
  (
    rtModel,
    rtProvider,
    rtTemplate,
    rtPipeline
  );

  TYakkoResolutionTargetHelper = record helper for TYakkoResolutionTarget
  public
    function ToString: string;
  end;

  TYakkoResolutionMetadata = TDictionary<string, string>;

  TYakkoResolutionRequest = class
  private
    FTarget: TYakkoResolutionTarget;
    FRequiredCapabilities: TYakkoRuntimeCapabilities;
    FMetadata: TYakkoResolutionMetadata;
    FCreatedAt: TDateTime;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    function Clone: TYakkoResolutionRequest;
    function ToDebugString: string;

    property Target: TYakkoResolutionTarget read FTarget write FTarget;
    property RequiredCapabilities: TYakkoRuntimeCapabilities read FRequiredCapabilities;
    property Metadata: TYakkoResolutionMetadata read FMetadata;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
  end;

  TYakkoResolutionResult = class
  private
    FResolvedItem: TYakkoRegistryItem;
    FSuccess: Boolean;
    FReason: string;
    FMetadata: TYakkoResolutionMetadata;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    function Clone: TYakkoResolutionResult;
    function ToDebugString: string;

    property ResolvedItem: TYakkoRegistryItem read FResolvedItem;
    property Success: Boolean read FSuccess write FSuccess;
    property Reason: string read FReason write FReason;
    property Metadata: TYakkoResolutionMetadata read FMetadata;
  end;

  TYakkoRuntimeResolver = class
  private
    FRegistry: TYakkoRuntimeRegistry;
  public
    constructor Create(ARegistry: TYakkoRuntimeRegistry);

    function Resolve(ARequest: TYakkoResolutionRequest): TYakkoResolutionResult;
  end;

implementation

const
  CResolutionNameKey = 'name';
  CResolutionItemNameKey = 'item_name';
  CResolutionCapabilitiesKey = 'capabilities';
  CItemCapabilitiesKey = 'capabilities';

procedure CloneStringDictionary(ASource, ADest: TYakkoResolutionMetadata);
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

function GetStringValueOrEmpty(ADictionary: TYakkoResolutionMetadata; const AKey: string): string;
begin
  Result := '';
  if Assigned(ADictionary) and ADictionary.ContainsKey(AKey) then
    Result := Trim(ADictionary[AKey]);
end;

function ResolutionTargetToRegistryItemType(ATarget: TYakkoResolutionTarget): TYakkoRegistryItemType;
begin
  case ATarget of
    rtModel:
      Result := ritModel;
    rtProvider:
      Result := ritProvider;
    rtTemplate:
      Result := ritTemplate;
    rtPipeline:
      Result := ritPipeline;
  else
    Result := ritModel;
  end;
end;

function ParseCapabilityTokens(const AValue: string): TArray<string>;
var
  LList: TStringList;
  LToken: string;
  LIndex: Integer;
begin
  LList := TStringList.Create;
  try
    LList.StrictDelimiter := True;
    LList.Delimiter := ',';
    LList.DelimitedText := StringReplace(StringReplace(StringReplace(AValue, ';', ',', [rfReplaceAll]), '|', ',', [rfReplaceAll]), ' ', ',', [rfReplaceAll]);
    SetLength(Result, 0);
    for LIndex := 0 to LList.Count - 1 do
    begin
      LToken := Trim(LList[LIndex]);
      if LToken = '' then
        Continue;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LToken.ToLower;
    end;
  finally
    LList.Free;
  end;
end;

function ItemSupportsRequestedCapabilities(AItem: TYakkoRegistryItem; ARequest: TYakkoResolutionRequest): Boolean;
var
  LRequested: TArray<TYakkoRuntimeCapability>;
  LRequestedCapability: TYakkoRuntimeCapability;
  LDeclaredTokens: TArray<string>;
  LDeclaredCapToken: string;
  LDeclaredCaps: string;
  LSupported: Boolean;
begin
  Result := True;
  if not Assigned(ARequest) or not Assigned(ARequest.RequiredCapabilities) then
    Exit;

  LRequested := ARequest.RequiredCapabilities.ToArray;
  if Length(LRequested) = 0 then
    Exit;

  LDeclaredCaps := '';
  if Assigned(AItem) and Assigned(AItem.Metadata) and AItem.Metadata.ContainsKey(CItemCapabilitiesKey) then
    LDeclaredCaps := AItem.Metadata[CItemCapabilitiesKey];

  LDeclaredTokens := ParseCapabilityTokens(LDeclaredCaps);
  for LRequestedCapability in LRequested do
  begin
    LSupported := False;
    for LDeclaredCapToken in LDeclaredTokens do
    begin
      if SameText(LDeclaredCapToken, LRequestedCapability.ToString) then
      begin
        LSupported := True;
        Break;
      end;
    end;

    if not LSupported then
      Exit(False);
  end;
end;

function CreateResolutionFailure(const AReason: string): TYakkoResolutionResult;
begin
  Result := TYakkoResolutionResult.Create;
  Result.FSuccess := False;
  Result.FReason := AReason;
  Result.Metadata.AddOrSetValue('status', 'failed');
  Result.Metadata.AddOrSetValue('reason', AReason);
end;

{ TYakkoResolutionTargetHelper }

function TYakkoResolutionTargetHelper.ToString: string;
begin
  case Self of
    rtModel:
      Result := 'model';
    rtProvider:
      Result := 'provider';
    rtTemplate:
      Result := 'template';
    rtPipeline:
      Result := 'pipeline';
  else
    Result := 'model';
  end;
end;

{ TYakkoResolutionRequest }

constructor TYakkoResolutionRequest.Create;
begin
  inherited Create;
  FTarget := rtModel;
  FRequiredCapabilities := TYakkoRuntimeCapabilities.Create;
  FMetadata := TYakkoResolutionMetadata.Create;
  FCreatedAt := Now;

  { Explicit request ownership keeps criteria and dependencies local to the request. }
  { TODO: add capability negotiation inputs for future multi-provider selection. }
  { TODO: add scoring hints only after deterministic resolution is stable. }
  { TODO: add fallback preferences only when negotiation exists. }
  { TODO: add execution-planning hints only after resolver responsibilities are fixed. }
end;

destructor TYakkoResolutionRequest.Destroy;
begin
  FreeAndNil(FRequiredCapabilities);
  FreeAndNil(FMetadata);
  inherited;
end;

procedure TYakkoResolutionRequest.Clear;
begin
  FTarget := rtModel;
  FreeAndNil(FRequiredCapabilities);
  FRequiredCapabilities := TYakkoRuntimeCapabilities.Create;
  FMetadata.Clear;
  FCreatedAt := Now;
end;

function TYakkoResolutionRequest.Clone: TYakkoResolutionRequest;
var
  LCapability: TYakkoRuntimeCapability;
begin
  Result := TYakkoResolutionRequest.Create;
  try
    Result.FTarget := FTarget;
    Result.FCreatedAt := FCreatedAt;
    for LCapability in FRequiredCapabilities.ToArray do
      Result.FRequiredCapabilities.Add(LCapability);
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoResolutionRequest.ToDebugString: string;
begin
  Result := Format(
    'TYakkoResolutionRequest(Target=%s, RequiredCapabilities=%s, Metadata=%d, CreatedAt=%s)',
    [
      FTarget.ToString,
      FRequiredCapabilities.ToDebugString,
      FMetadata.Count,
      DateTimeToStr(FCreatedAt)
    ]
  );
end;

{ TYakkoResolutionResult }

constructor TYakkoResolutionResult.Create;
begin
  inherited Create;
  FResolvedItem := nil;
  FSuccess := False;
  FReason := '';
  FMetadata := TYakkoResolutionMetadata.Create;

  { The result owns its resolved snapshot so callers never mutate registry state by accident. }
  { TODO: add semantic compatibility metadata for future selection traceability. }
  { TODO: add fallback-chain metadata once provider negotiation is introduced. }
end;

destructor TYakkoResolutionResult.Destroy;
begin
  FreeAndNil(FResolvedItem);
  FreeAndNil(FMetadata);
  inherited;
end;

procedure TYakkoResolutionResult.Clear;
begin
  FreeAndNil(FResolvedItem);
  FSuccess := False;
  FReason := '';
  FMetadata.Clear;
end;

function TYakkoResolutionResult.Clone: TYakkoResolutionResult;
begin
  Result := TYakkoResolutionResult.Create;
  try
    Result.FSuccess := FSuccess;
    Result.FReason := FReason;
    if Assigned(FResolvedItem) then
      Result.FResolvedItem := FResolvedItem.Clone;
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoResolutionResult.ToDebugString: string;
var
  LResolvedItemText: string;
begin
  if Assigned(FResolvedItem) then
    LResolvedItemText := FResolvedItem.ToDebugString
  else
    LResolvedItemText := '<nil>';

  Result := Format(
    'TYakkoResolutionResult(Success=%s, Reason=%s, Item=%s, Metadata=%d)',
    [
      BoolToStr(FSuccess, True),
      FReason,
      LResolvedItemText,
      FMetadata.Count
    ]
  );
end;

{ TYakkoRuntimeResolver }

constructor TYakkoRuntimeResolver.Create(ARegistry: TYakkoRuntimeRegistry);
begin
  inherited Create;
  if not Assigned(ARegistry) then
    raise EArgumentNilException.Create('ARegistry must be assigned.');
  FRegistry := ARegistry;

  { Resolver depends on explicit registry ownership and does not own the registry. }
  { TODO: add capability negotiation before selecting a final target. }
  { TODO: add weighted resolution only after explicit deterministic selection is stable. }
  { TODO: add provider fallback only after negotiation exists. }
  { TODO: add execution planning only after selection semantics are stable. }
  { TODO: add adaptive routing only after deterministic behavior is validated. }
  { TODO: add distributed resolution only after local resolution is stable. }
end;

function TYakkoRuntimeResolver.Resolve(ARequest: TYakkoResolutionRequest): TYakkoResolutionResult;
var
  LExpectedType: TYakkoRegistryItemType;
  LCandidates: TObjectList<TYakkoRegistryItem>;
  LCandidate: TYakkoRegistryItem;
  LRequestedName: string;
  LDeclaredName: string;
  LCapabilitiesRaw: string;
  LMatchesName: Boolean;
  LMatchesCapabilities: Boolean;
  LSelection: TYakkoRegistryItem;
begin
  if not Assigned(ARequest) then
    Exit(CreateResolutionFailure('Resolution request must be assigned.'));

  if not Assigned(FRegistry) then
    Exit(CreateResolutionFailure('Runtime registry is not assigned.'));

  LExpectedType := ResolutionTargetToRegistryItemType(ARequest.Target);
  LCandidates := FRegistry.FindByType(LExpectedType);
  try
    if LCandidates.Count = 0 then
      Exit(CreateResolutionFailure(Format('No registry items found for target %s.', [ARequest.Target.ToString])));

    LRequestedName := GetStringValueOrEmpty(ARequest.Metadata, CResolutionNameKey);
    if LRequestedName = '' then
      LRequestedName := GetStringValueOrEmpty(ARequest.Metadata, CResolutionItemNameKey);

    LSelection := nil;
    for LCandidate in LCandidates do
    begin
      LMatchesName := True;
      if LRequestedName <> '' then
      begin
        LDeclaredName := Trim(LCandidate.Name);
        LMatchesName := SameText(LDeclaredName, LRequestedName);
      end;

      LMatchesCapabilities := ItemSupportsRequestedCapabilities(LCandidate, ARequest);
      if not LMatchesName or not LMatchesCapabilities then
        Continue;

      LSelection := LCandidate;
      Break;
    end;

    if not Assigned(LSelection) then
    begin
      LCapabilitiesRaw := GetStringValueOrEmpty(ARequest.Metadata, CResolutionCapabilitiesKey);
      if LCapabilitiesRaw <> '' then
        Exit(CreateResolutionFailure(Format('No %s matched name "%s" and capabilities "%s".', [ARequest.Target.ToString, LRequestedName, LCapabilitiesRaw])));
      Exit(CreateResolutionFailure(Format('No %s matched the explicit criteria.', [ARequest.Target.ToString])));
    end;

    Result := TYakkoResolutionResult.Create;
    Result.FSuccess := True;
    Result.FReason := 'Resolved deterministically from registry and explicit capabilities.';
    Result.FResolvedItem := LSelection.Clone;
    Result.Metadata.AddOrSetValue('status', 'resolved');
    Result.Metadata.AddOrSetValue('target', ARequest.Target.ToString);
    Result.Metadata.AddOrSetValue('registry_item', LSelection.Name);
    Result.Metadata.AddOrSetValue('registry_item_type', LSelection.ItemType.ToString);
    Result.Metadata.AddOrSetValue('selection_policy', 'deterministic-explicit');
    Result.Metadata.AddOrSetValue('request_created_at', DateTimeToStr(ARequest.CreatedAt));
    Result.Metadata.AddOrSetValue('resolved_at', DateTimeToStr(Now));
  finally
    LCandidates.Free;
  end;
end;

end.
