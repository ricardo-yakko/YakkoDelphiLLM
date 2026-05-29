unit Yakko.Runtime.Configuration;

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TYakkoRuntimeConfigurationMetadata = TDictionary<string, string>;

  TYakkoModelConfiguration = class
  private
    FName: string;
    FMaxContextTokens: Integer;
    FMetadata: TYakkoRuntimeConfigurationMetadata;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function Clone: TYakkoModelConfiguration;
    function ToDebugString: string;
    property Name: string read FName write FName;
    property MaxContextTokens: Integer read FMaxContextTokens write FMaxContextTokens;
    property Metadata: TYakkoRuntimeConfigurationMetadata read FMetadata;
  end;

  TYakkoProviderConfiguration = class
  private
    FName: string;
    FEndpoint: string;
    FMetadata: TYakkoRuntimeConfigurationMetadata;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function Clone: TYakkoProviderConfiguration;
    function ToDebugString: string;
    property Name: string read FName write FName;
    property Endpoint: string read FEndpoint write FEndpoint;
    property Metadata: TYakkoRuntimeConfigurationMetadata read FMetadata;
  end;

  TYakkoPipelineConfiguration = class
  private
    FName: string;
    FStreamingEnabled: Boolean;
    FMetadata: TYakkoRuntimeConfigurationMetadata;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function Clone: TYakkoPipelineConfiguration;
    function ToDebugString: string;
    property Name: string read FName write FName;
    property StreamingEnabled: Boolean read FStreamingEnabled write FStreamingEnabled;
    property Metadata: TYakkoRuntimeConfigurationMetadata read FMetadata;
  end;

  TYakkoRuntimeConfiguration = class
  private
    FModel: TYakkoModelConfiguration;
    FProvider: TYakkoProviderConfiguration;
    FPipeline: TYakkoPipelineConfiguration;
    FMetadata: TYakkoRuntimeConfigurationMetadata;

    procedure SetModel(const Value: TYakkoModelConfiguration);
    procedure SetProvider(const Value: TYakkoProviderConfiguration);
    procedure SetPipeline(const Value: TYakkoPipelineConfiguration);
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    function Clone: TYakkoRuntimeConfiguration;
    function ToDebugString: string;

    property Model: TYakkoModelConfiguration read FModel write SetModel;
    property Provider: TYakkoProviderConfiguration read FProvider write SetProvider;
    property Pipeline: TYakkoPipelineConfiguration read FPipeline write SetPipeline;
    property Metadata: TYakkoRuntimeConfigurationMetadata read FMetadata;
  end;

implementation

procedure CloneStringDictionary(ASource, ADest: TYakkoRuntimeConfigurationMetadata);
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

{ TYakkoModelConfiguration }

constructor TYakkoModelConfiguration.Create;
begin
  inherited Create;
  FName := '';
  FMaxContextTokens := 4096;
  FMetadata := TYakkoRuntimeConfigurationMetadata.Create;
end;

destructor TYakkoModelConfiguration.Destroy;
begin
  FreeAndNil(FMetadata);
  inherited;
end;

procedure TYakkoModelConfiguration.Clear;
begin
  FName := '';
  FMaxContextTokens := 4096;
  FMetadata.Clear;
end;

function TYakkoModelConfiguration.Clone: TYakkoModelConfiguration;
begin
  Result := TYakkoModelConfiguration.Create;
  Result.FName := FName;
  Result.FMaxContextTokens := FMaxContextTokens;
  CloneStringDictionary(FMetadata, Result.FMetadata);
end;

function TYakkoModelConfiguration.ToDebugString: string;
begin
  Result := Format('TYakkoModelConfiguration(Name=%s, MaxContextTokens=%d, Metadata=%d)',
    [FName, FMaxContextTokens, FMetadata.Count]);
end;

{ TYakkoProviderConfiguration }

constructor TYakkoProviderConfiguration.Create;
begin
  inherited Create;
  FName := '';
  FEndpoint := '';
  FMetadata := TYakkoRuntimeConfigurationMetadata.Create;
end;

destructor TYakkoProviderConfiguration.Destroy;
begin
  FreeAndNil(FMetadata);
  inherited;
end;

procedure TYakkoProviderConfiguration.Clear;
begin
  FName := '';
  FEndpoint := '';
  FMetadata.Clear;
end;

function TYakkoProviderConfiguration.Clone: TYakkoProviderConfiguration;
begin
  Result := TYakkoProviderConfiguration.Create;
  Result.FName := FName;
  Result.FEndpoint := FEndpoint;
  CloneStringDictionary(FMetadata, Result.FMetadata);
end;

function TYakkoProviderConfiguration.ToDebugString: string;
begin
  Result := Format('TYakkoProviderConfiguration(Name=%s, Endpoint=%s, Metadata=%d)',
    [FName, FEndpoint, FMetadata.Count]);
end;

{ TYakkoPipelineConfiguration }

constructor TYakkoPipelineConfiguration.Create;
begin
  inherited Create;
  FName := '';
  FStreamingEnabled := False;
  FMetadata := TYakkoRuntimeConfigurationMetadata.Create;
end;

destructor TYakkoPipelineConfiguration.Destroy;
begin
  FreeAndNil(FMetadata);
  inherited;
end;

procedure TYakkoPipelineConfiguration.Clear;
begin
  FName := '';
  FStreamingEnabled := False;
  FMetadata.Clear;
end;

function TYakkoPipelineConfiguration.Clone: TYakkoPipelineConfiguration;
begin
  Result := TYakkoPipelineConfiguration.Create;
  Result.FName := FName;
  Result.FStreamingEnabled := FStreamingEnabled;
  CloneStringDictionary(FMetadata, Result.FMetadata);
end;

function TYakkoPipelineConfiguration.ToDebugString: string;
begin
  Result := Format('TYakkoPipelineConfiguration(Name=%s, StreamingEnabled=%s, Metadata=%d)',
    [FName, BoolToStr(FStreamingEnabled, True), FMetadata.Count]);
end;

{ TYakkoRuntimeConfiguration }

constructor TYakkoRuntimeConfiguration.Create;
begin
  inherited Create;
  FModel := TYakkoModelConfiguration.Create;
  FProvider := TYakkoProviderConfiguration.Create;
  FPipeline := TYakkoPipelineConfiguration.Create;
  FMetadata := TYakkoRuntimeConfigurationMetadata.Create;
end;

destructor TYakkoRuntimeConfiguration.Destroy;
begin
  FreeAndNil(FMetadata);
  FreeAndNil(FPipeline);
  FreeAndNil(FProvider);
  FreeAndNil(FModel);
  inherited;
end;

procedure TYakkoRuntimeConfiguration.SetModel(
  const Value: TYakkoModelConfiguration);
begin
  FreeAndNil(FModel);
  if Assigned(Value) then
    FModel := Value.Clone
  else
    FModel := TYakkoModelConfiguration.Create;
end;

procedure TYakkoRuntimeConfiguration.SetProvider(
  const Value: TYakkoProviderConfiguration);
begin
  FreeAndNil(FProvider);
  if Assigned(Value) then
    FProvider := Value.Clone
  else
    FProvider := TYakkoProviderConfiguration.Create;
end;

procedure TYakkoRuntimeConfiguration.SetPipeline(
  const Value: TYakkoPipelineConfiguration);
begin
  FreeAndNil(FPipeline);
  if Assigned(Value) then
    FPipeline := Value.Clone
  else
    FPipeline := TYakkoPipelineConfiguration.Create;
end;

procedure TYakkoRuntimeConfiguration.Clear;
begin
  FModel.Clear;
  FProvider.Clear;
  FPipeline.Clear;
  FMetadata.Clear;

  { TODO: add profile sets when runtime configuration profiles are introduced. }
end;

function TYakkoRuntimeConfiguration.Clone: TYakkoRuntimeConfiguration;
begin
  Result := TYakkoRuntimeConfiguration.Create;
  Result.SetModel(FModel);
  Result.SetProvider(FProvider);
  Result.SetPipeline(FPipeline);
  CloneStringDictionary(FMetadata, Result.FMetadata);
end;

function TYakkoRuntimeConfiguration.ToDebugString: string;
begin
  Result := Format(
    'TYakkoRuntimeConfiguration(Model=%s, Provider=%s, Pipeline=%s, Metadata=%d)',
    [FModel.ToDebugString, FProvider.ToDebugString, FPipeline.ToDebugString, FMetadata.Count]
  );
end;

end.
