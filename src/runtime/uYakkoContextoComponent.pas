unit uYakkoContextoComponent;

{ Componente de contexto de inferencia.
  Responsabilidades:
  - abrir/fechar contexto backend
  - gerir n_ctx e threads efetivos
  - validar precondicoes de uso do modelo
  Ownership:
  - Modelo/Config sao referencias borrowed. }

interface

uses
  System.SysUtils,
  System.Classes,
  uYakkoInferenceConfigComponent,
  uYakkoModeloComponent,
  uYakkoFullExportsComponent,
  uYakkoLlamaTypes;

type
  ELlamaContextoError = class(Exception);

  TLlamaContextoHandle = Pointer;

  TLlamaContextParams = record
    n_ctx           : Cardinal;
    n_batch         : Cardinal;
    n_ubatch        : Cardinal;
    n_seq_max       : Cardinal;
    n_rs_seq        : Cardinal;
    n_threads       : Int32;
    n_threads_batch : Int32;
    ctx_type                : Integer;
    rope_scaling_type       : Integer;
    pooling_type            : Integer;
    attention_type          : Integer;
    flash_attn_type         : Integer;
    rope_freq_base          : Single;
    rope_freq_scale         : Single;
    yarn_ext_factor         : Single;
    yarn_attn_factor        : Single;
    yarn_beta_fast          : Single;
    yarn_beta_slow          : Single;
    yarn_orig_ctx           : Cardinal;
    defrag_thold            : Single;
    cb_eval                 : Pointer;
    cb_eval_user_data       : Pointer;
    type_k                  : Integer;
    type_v                  : Integer;
    abort_callback          : Pointer;
    abort_callback_data     : Pointer;
    embeddings              : Boolean;
    offload_kqv             : Boolean;
    no_perf                 : Boolean;
    op_offload              : Boolean;
    swa_full                : Boolean;
    kv_unified              : Boolean;
    samplers                : Pointer;
    n_samplers              : NativeUInt;
  end;

  TFnContextDefaultParams = function: TLlamaContextParams; cdecl;
  TFnInitFromModel        = function(model: TLlamaModelHandle; params: TLlamaContextParams): TLlamaContextoHandle; cdecl;
  TFnContextFree          = procedure(ctx: TLlamaContextoHandle); cdecl;
  TFnContextNCtx          = function(ctx: TLlamaContextoHandle): Cardinal; cdecl;
  TFnContextNThreads      = function(ctx: TLlamaContextoHandle): Int32; cdecl;
  TFnContextSetNThreads   = procedure(ctx: TLlamaContextoHandle; n_threads: Int32; n_threads_batch: Int32); cdecl;

  TYakkoContexto = class(TComponent)
  private
    { Referencia externa sem ownership; o ciclo de vida pertence ao Engine. }
    FModelo: TYakkoModelo;
    FConfig: TYakkoInferenceConfig;
    FOwnsConfig: Boolean;
    FHandle: TLlamaContextoHandle;
    FNCtx: Cardinal;
    FThreads: Int32;
    FNCtxPadrao: Cardinal;
    FDestruindo: Boolean;
    procedure SetModelo(const Value: TYakkoModelo);
    function GetConfig: TYakkoInferenceConfig;
    procedure SetConfig(const Value: TYakkoInferenceConfig);
    procedure SetNCtxPadrao(const Value: Cardinal);
    function GetEstaAberto: Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure Abrir(ACtxSize: Cardinal = 0; AThreads: Int32 = 0);
    procedure Fechar;

    function NCtx: Cardinal;
    function NThreads: Int32;
    function PodeDestruir: Boolean;

    property Handle: TLlamaContextoHandle read FHandle;
    property EstaAberto: Boolean read GetEstaAberto;
  published
    property Modelo: TYakkoModelo read FModelo write SetModelo;
    { Configuracao centralizada compartilhada, sem ownership local. }
    property Config: TYakkoInferenceConfig read GetConfig write SetConfig;
    { Encaminha para Config.NCtx quando disponivel. }
    property NCtxPadrao: Cardinal read FNCtxPadrao write SetNCtxPadrao default 512;
  end;

implementation

constructor TYakkoContexto.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FModelo := nil;
  FConfig := nil;
  FOwnsConfig := False;
  FHandle := nil;
  FNCtx := 0;
  FThreads := 0;
  FNCtxPadrao := 512;
  FDestruindo := False;
end;

destructor TYakkoContexto.Destroy;
begin
  if FDestruindo then
    Exit;
  FDestruindo := True;
  Fechar;
  if FOwnsConfig then
    FreeAndNil(FConfig)
  else
    FConfig := nil;
  FOwnsConfig := False;
  FModelo := nil;
  inherited;
end;

procedure TYakkoContexto.SetModelo(const Value: TYakkoModelo);
begin
  if FModelo = Value then
    Exit;

  if FHandle <> nil then
    Fechar;

  FModelo := Value;
end;

function TYakkoContexto.GetConfig: TYakkoInferenceConfig;
begin
  if not Assigned(FConfig) then
  begin
    FConfig := TYakkoInferenceConfig.Create;
    FOwnsConfig := True;
  end;
  Result := FConfig;
end;

procedure TYakkoContexto.SetConfig(const Value: TYakkoInferenceConfig);
var
  LAnterior: TYakkoInferenceConfig;
  LAnteriorOwned: Boolean;
begin
  if FConfig = Value then
    Exit;

  LAnterior := FConfig;
  LAnteriorOwned := FOwnsConfig;

  FConfig := Value;
  FOwnsConfig := False;

  if LAnteriorOwned and (LAnterior <> FConfig) then
    FreeAndNil(LAnterior);

  if Assigned(FConfig) and (FConfig.NCtx > 0) then
    FNCtxPadrao := Cardinal(FConfig.NCtx);
end;

procedure TYakkoContexto.SetNCtxPadrao(const Value: Cardinal);
begin
  FNCtxPadrao := Value;
  if Assigned(FConfig) and (Value > 0) then
    FConfig.NCtx := Value;
end;

function TYakkoContexto.GetEstaAberto: Boolean;
begin
  Result := FHandle <> nil;
end;

procedure TYakkoContexto.Abrir(ACtxSize: Cardinal; AThreads: Int32);
var
  LParams: TLlamaContextParams;
  LCpuCount: Integer;
begin
  if FModelo = nil then
    raise ELlamaContextoError.Create('Modelo nao configurado. Associe TYakkoModelo ao contexto.');

  if not FModelo.EstaCarregado then
    raise ELlamaContextoError.Create('Modelo nao carregado. Chame Modelo.Carregar primeiro.');

  if FHandle <> nil then
    Fechar;

  if not Assigned(llama_context_default_params) then
    raise ELlamaContextoError.Create('Export llama_context_default_params nao disponivel.');
  if not Assigned(llama_init_from_model) then
    raise ELlamaContextoError.Create('Export llama_init_from_model nao disponivel.');
  if not Assigned(llama_n_ctx) then
    raise ELlamaContextoError.Create('Export llama_n_ctx nao disponivel.');
  if not Assigned(llama_n_threads) then
    raise ELlamaContextoError.Create('Export llama_n_threads nao disponivel.');

  LParams := TFnContextDefaultParams(llama_context_default_params)();

  if ACtxSize > 0 then
    LParams.n_ctx := ACtxSize;
  if (ACtxSize = 0) and Assigned(FConfig) and (FConfig.NCtx > 0) then
    LParams.n_ctx := Cardinal(FConfig.NCtx);
  if (ACtxSize = 0) and (FNCtxPadrao > 0) then
    LParams.n_ctx := FNCtxPadrao;
  if (ACtxSize = 0) and (FNCtxPadrao = 0) then
    LParams.n_ctx := Cardinal(FModelo.NCtxTrain);

  if AThreads > 0 then
    LParams.n_threads := AThreads
  else if Assigned(FConfig) and (FConfig.Threads > 0) then
    LParams.n_threads := FConfig.Threads
  else
  begin
    LCpuCount := TThread.ProcessorCount;
    if LCpuCount > 1 then
      LParams.n_threads := LCpuCount div 2
    else
      LParams.n_threads := 1;
  end;
  LParams.n_threads_batch := LParams.n_threads;

  LParams.n_batch := LParams.n_ctx;
  if LParams.n_seq_max = 0 then
    LParams.n_seq_max := 1;
  if (LParams.n_ubatch = 0) or (LParams.n_ubatch > LParams.n_batch) then
    LParams.n_ubatch := LParams.n_batch;

  LParams.offload_kqv := True;

  FHandle := TFnInitFromModel(llama_init_from_model)(FModelo.Handle, LParams);

  if FHandle = nil then
    raise ELlamaContextoError.Create('Nao foi possivel criar o contexto.');

  FNCtx := TFnContextNCtx(llama_n_ctx)(FHandle);
  FThreads := TFnContextNThreads(llama_n_threads)(FHandle);
end;

procedure TYakkoContexto.Fechar;
begin
  if FHandle = nil then
    Exit;

  if Assigned(llama_free) then
    TFnContextFree(llama_free)(FHandle);

  FHandle := nil;
  FNCtx := 0;
  FThreads := 0;
end;

function TYakkoContexto.NCtx: Cardinal;
begin
  if FHandle <> nil then
    Result := TFnContextNCtx(llama_n_ctx)(FHandle)
  else
    Result := 0;
end;

function TYakkoContexto.NThreads: Int32;
begin
  if FHandle <> nil then
    Result := TFnContextNThreads(llama_n_threads)(FHandle)
  else
    Result := 0;
end;

function TYakkoContexto.PodeDestruir: Boolean;
begin
  Result := FHandle = nil;
end;

initialization
  System.Classes.RegisterClass(TYakkoContexto);

end.
