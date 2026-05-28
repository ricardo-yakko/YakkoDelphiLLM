unit uYakkoInferenceConfigComponent;

{ Configuracao unificada do runtime de inferencia.
  Responsabilidades:
  - centralizar defaults e validacoes
  - representar intencao logica backend-agnostic
  - servir como ponto de extensao para presets/profiles futuros
  Ownership:
  - TYakkoInferenceConfig e owner de subconfigs (ex.: Sampling). }

interface

uses
  System.Classes,
  System.SysUtils;

type
  EYakkoSamplingError = class(Exception);
  EYakkoInferenceConfigError = class(Exception);

  { Parametros de sampling backend-agnostic. }
  TYakkoSamplingParams = class(TPersistent)
  private const
    DEFAULT_TEMPERATURE = 0.7;
    DEFAULT_TOP_K = 64;
    DEFAULT_TOP_P = 0.95;
    DEFAULT_SEED = Cardinal($FFFFFFFF);
  private
    FTemperature: Single;
    FTopK: Integer;
    FTopP: Single;
    FSeed: Cardinal;
    procedure SetTemperature(const Value: Single);
    procedure SetTopK(const Value: Integer);
    procedure SetTopP(const Value: Single);
    procedure SetSeed(const Value: Cardinal);
  public
    constructor Create;
    procedure Assign(Source: TPersistent); override;
    procedure AssignFrom(ASource: TYakkoSamplingParams);
    procedure ResetToDefaults;

    property Temperature: Single read FTemperature write SetTemperature;
    property TopK: Integer read FTopK write SetTopK;
    property TopP: Single read FTopP write SetTopP;
    property Seed: Cardinal read FSeed write SetSeed;
  end;

  { Fonte central de configuracao de inferencia.
    Ownership: esta classe e owner de subconfigs como Sampling. }
  TYakkoInferenceConfig = class(TPersistent)
  private const
    DEFAULT_MAX_TOKENS = 64;
    DEFAULT_N_CTX = 512;
    DEFAULT_THREADS = 2;
    DEFAULT_AUTO_RESUMO = True;
    DEFAULT_AUTO_RESUMO_LIMIAR = 0.70;
    DEFAULT_AUTO_RESUMO_MAX_TOKENS = 256;
    DEFAULT_AUTO_RESUMO_MENSAGENS_RECENTES = 4;
    DEFAULT_USE_THINK_MODE = False;
    DEFAULT_SHOW_THINK_BLOCKS = False;
    DEFAULT_SANITIZE_OUTPUT = True;
  private
    FSampling: TYakkoSamplingParams;
    FMaxTokens: Integer;
    FNCtx: Integer;
    FThreads: Integer;
    FAutoResumo: Boolean;
    FAutoResumoLimiar: Double;
    FAutoResumoMaxTokens: Integer;
    FAutoResumoMensagensRecentes: Integer;
    FUseThinkMode: Boolean;
    FShowThinkBlocks: Boolean;
    FSanitizeOutput: Boolean;
    procedure SetMaxTokens(const Value: Integer);
    procedure SetNCtx(const Value: Integer);
    procedure SetThreads(const Value: Integer);
    procedure SetAutoResumoLimiar(const Value: Double);
    procedure SetAutoResumoMaxTokens(const Value: Integer);
    procedure SetAutoResumoMensagensRecentes(const Value: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
    procedure ResetToDefaults;

    { Retorna copia mutavel para futuro suporte a snapshots/profiles. }
    function Clone: TYakkoInferenceConfig;

    property Sampling: TYakkoSamplingParams read FSampling;
  published
    property MaxTokens: Integer read FMaxTokens write SetMaxTokens default DEFAULT_MAX_TOKENS;
    property NCtx: Integer read FNCtx write SetNCtx default DEFAULT_N_CTX;
    property Threads: Integer read FThreads write SetThreads default DEFAULT_THREADS;
    property AutoResumo: Boolean read FAutoResumo write FAutoResumo default DEFAULT_AUTO_RESUMO;
    property AutoResumoLimiar: Double read FAutoResumoLimiar write SetAutoResumoLimiar;
    property AutoResumoMaxTokens: Integer read FAutoResumoMaxTokens write SetAutoResumoMaxTokens default DEFAULT_AUTO_RESUMO_MAX_TOKENS;
    property AutoResumoMensagensRecentes: Integer read FAutoResumoMensagensRecentes write SetAutoResumoMensagensRecentes default DEFAULT_AUTO_RESUMO_MENSAGENS_RECENTES;
    property UseThinkMode: Boolean read FUseThinkMode write FUseThinkMode default DEFAULT_USE_THINK_MODE;
    property ShowThinkBlocks: Boolean read FShowThinkBlocks write FShowThinkBlocks default DEFAULT_SHOW_THINK_BLOCKS;
    property SanitizeOutput: Boolean read FSanitizeOutput write FSanitizeOutput default DEFAULT_SANITIZE_OUTPUT;
  end;

implementation

{ TYakkoSamplingParams }

constructor TYakkoSamplingParams.Create;
begin
  inherited Create;
  ResetToDefaults;
end;

procedure TYakkoSamplingParams.Assign(Source: TPersistent);
begin
  if Source is TYakkoSamplingParams then
  begin
    AssignFrom(TYakkoSamplingParams(Source));
    Exit;
  end;
  inherited Assign(Source);
end;

procedure TYakkoSamplingParams.AssignFrom(ASource: TYakkoSamplingParams);
begin
  if not Assigned(ASource) then
    Exit;

  Temperature := ASource.Temperature;
  TopK := ASource.TopK;
  TopP := ASource.TopP;
  Seed := ASource.Seed;
end;

procedure TYakkoSamplingParams.ResetToDefaults;
begin
  FTemperature := DEFAULT_TEMPERATURE;
  FTopK := DEFAULT_TOP_K;
  FTopP := DEFAULT_TOP_P;
  FSeed := DEFAULT_SEED;
end;

procedure TYakkoSamplingParams.SetTemperature(const Value: Single);
begin
  { Temperature=0 ativa modo greedy. }
  if Value < 0 then
    raise EYakkoSamplingError.Create('Temperature deve ser >= 0.');

  FTemperature := Value;
end;

procedure TYakkoSamplingParams.SetTopK(const Value: Integer);
begin
  if Value < 0 then
    raise EYakkoSamplingError.Create('TopK deve ser >= 0.');

  FTopK := Value;
end;

procedure TYakkoSamplingParams.SetTopP(const Value: Single);
begin
  if (Value <= 0) or (Value > 1.0) then
    raise EYakkoSamplingError.Create('TopP deve estar no intervalo (0, 1].');

  FTopP := Value;
end;

procedure TYakkoSamplingParams.SetSeed(const Value: Cardinal);
begin
  { Seed=0 e permitido para cenarios de random seed. }
  FSeed := Value;
end;

{ TYakkoInferenceConfig }

constructor TYakkoInferenceConfig.Create;
begin
  inherited Create;
  FSampling := TYakkoSamplingParams.Create;
  ResetToDefaults;
end;

destructor TYakkoInferenceConfig.Destroy;
begin
  FreeAndNil(FSampling);
  inherited;
end;

procedure TYakkoInferenceConfig.Assign(Source: TPersistent);
var
  LSource: TYakkoInferenceConfig;
begin
  if Source is TYakkoInferenceConfig then
  begin
    LSource := TYakkoInferenceConfig(Source);
    Sampling.Assign(LSource.Sampling);
    MaxTokens := LSource.MaxTokens;
    NCtx := LSource.NCtx;
    Threads := LSource.Threads;
    AutoResumo := LSource.AutoResumo;
    AutoResumoLimiar := LSource.AutoResumoLimiar;
    AutoResumoMaxTokens := LSource.AutoResumoMaxTokens;
    AutoResumoMensagensRecentes := LSource.AutoResumoMensagensRecentes;
    UseThinkMode := LSource.UseThinkMode;
    ShowThinkBlocks := LSource.ShowThinkBlocks;
    SanitizeOutput := LSource.SanitizeOutput;
    Exit;
  end;

  inherited Assign(Source);
end;

procedure TYakkoInferenceConfig.ResetToDefaults;
begin
  FSampling.ResetToDefaults;
  FMaxTokens := DEFAULT_MAX_TOKENS;
  FNCtx := DEFAULT_N_CTX;
  FThreads := DEFAULT_THREADS;
  FAutoResumo := DEFAULT_AUTO_RESUMO;
  FAutoResumoLimiar := DEFAULT_AUTO_RESUMO_LIMIAR;
  FAutoResumoMaxTokens := DEFAULT_AUTO_RESUMO_MAX_TOKENS;
  FAutoResumoMensagensRecentes := DEFAULT_AUTO_RESUMO_MENSAGENS_RECENTES;
  FUseThinkMode := DEFAULT_USE_THINK_MODE;
  FShowThinkBlocks := DEFAULT_SHOW_THINK_BLOCKS;
  FSanitizeOutput := DEFAULT_SANITIZE_OUTPUT;
end;

function TYakkoInferenceConfig.Clone: TYakkoInferenceConfig;
begin
  Result := TYakkoInferenceConfig.Create;
  Result.Assign(Self);
end;

procedure TYakkoInferenceConfig.SetMaxTokens(const Value: Integer);
begin
  if Value <= 0 then
    raise EYakkoInferenceConfigError.Create('MaxTokens deve ser > 0.');

  FMaxTokens := Value;
end;

procedure TYakkoInferenceConfig.SetNCtx(const Value: Integer);
begin
  if Value <= 0 then
    raise EYakkoInferenceConfigError.Create('NCtx deve ser > 0.');

  FNCtx := Value;
end;

procedure TYakkoInferenceConfig.SetThreads(const Value: Integer);
begin
  if Value <= 0 then
    raise EYakkoInferenceConfigError.Create('Threads deve ser > 0.');

  FThreads := Value;
end;

procedure TYakkoInferenceConfig.SetAutoResumoLimiar(const Value: Double);
begin
  if (Value <= 0) or (Value > 1.0) then
    raise EYakkoInferenceConfigError.Create('AutoResumoLimiar deve estar no intervalo (0, 1].');

  FAutoResumoLimiar := Value;
end;

procedure TYakkoInferenceConfig.SetAutoResumoMaxTokens(const Value: Integer);
begin
  if Value <= 0 then
    raise EYakkoInferenceConfigError.Create('AutoResumoMaxTokens deve ser > 0.');

  FAutoResumoMaxTokens := Value;
end;

procedure TYakkoInferenceConfig.SetAutoResumoMensagensRecentes(const Value: Integer);
begin
  if Value < 0 then
    raise EYakkoInferenceConfigError.Create('AutoResumoMensagensRecentes deve ser >= 0.');

  FAutoResumoMensagensRecentes := Value;
end;

end.

