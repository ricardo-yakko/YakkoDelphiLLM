unit uYakkoModeloComponent;

{ Componente de ciclo de vida do modelo.
  Responsabilidades:
  - carregar/descarregar arquivo de modelo
  - inicializar backend nativo
  - expor metadados (n_ctx_train, descricao etc.)
  Ownership:
  - FullExports e referencia borrowed definida pelo Engine. }

interface

uses
  System.Classes,
  System.SysUtils,
  System.IOUtils,
  Winapi.Windows,
  uYakkoLlamaTypes,
  uYakkoFullExportsComponent;

type
  ELlamaModeloError = class(Exception);

  TGGMLBackendDevHandle = Pointer;
  TGGMLBackendBufferTypeHandle = Pointer;
  TLlamaProgressCallback = function(progress: Single; user_data: Pointer): Boolean; cdecl;

  TLlamaModelTensorBuftOverride = record
    pattern: PAnsiChar;
    buft: TGGMLBackendBufferTypeHandle;
  end;
  PLlamaModelTensorBuftOverride = ^TLlamaModelTensorBuftOverride;

  TLlamaModelKvOverride = record
    tag: Integer;
    key: array[0..127] of AnsiChar;
    case Integer of
      0: (val_i64: Int64);
      1: (val_f64: Double);
      2: (val_bool: Boolean);
      3: (val_str: array[0..127] of AnsiChar);
  end;
  PLlamaModelKvOverride = ^TLlamaModelKvOverride;

  TLlamaModelParams = record
    devices: ^TGGMLBackendDevHandle;
    tensor_buft_overrides: PLlamaModelTensorBuftOverride;
    n_gpu_layers: Int32;
    split_mode: Integer;
    main_gpu: Int32;
    tensor_split: PSingle;
    progress_callback: TLlamaProgressCallback;
    progress_callback_user_data: Pointer;
    kv_overrides: PLlamaModelKvOverride;
    vocab_only: Boolean;
    use_mmap: Boolean;
    use_direct_io: Boolean;
    use_mlock: Boolean;
    check_tensors: Boolean;
    use_extra_bufts: Boolean;
    no_host: Boolean;
    no_alloc: Boolean;
  end;

  { Ponteiros tipados para as funcoes da DLL }
  TFnBackendInit = procedure; cdecl;
  TFnBackendFree = procedure; cdecl;
  TFnGgmlBackendLoadAllFromPath = procedure(path: PAnsiChar); cdecl;
  TFnGgmlBackendLoadAll = procedure; cdecl;
  TFnModelDefaultParams = function: TLlamaModelParams; cdecl;
  TFnModelLoadFromFile = function(path: PAnsiChar; params: TLlamaModelParams): TLlamaModelHandle; cdecl;
  TFnModelFree = procedure(model: TLlamaModelHandle); cdecl;
  TFnModelGetVocab = function(model: TLlamaModelHandle): TLlamaVocabHandle; cdecl;
  TFnModelNCtxTrain = function(model: TLlamaModelHandle): Int32; cdecl;
  TFnModelNEmbd = function(model: TLlamaModelHandle): Int32; cdecl;
  TFnModelDesc = function(model: TLlamaModelHandle; buf: PAnsiChar; buf_size: NativeUInt): Int32; cdecl;

  TYakkoModelo = class(TComponent)
  private
    { Configuracao designer }
    FDllPath: string;
    FModelPath: string;
    FGpuLayersPadrao: Integer;

    { Estado runtime }
    FFullExports: TYakkoFullExports;
    FHandle: TLlamaModelHandle;
    FVocab: TLlamaVocabHandle;
    FCaminho: string;
    FBackendIniciado: Boolean;
    FDestruindo: Boolean;

    procedure SetFullExports(const Value: TYakkoFullExports);
    procedure IniciarBackend;
    procedure LiberarBackend;
    function ResolveDllCaminho: string;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure Carregar(const ACaminho: string; AGpuLayers: Integer = -1);
    procedure Descarregar;
    function EstaCarregado: Boolean;
    function PodeDestruir: Boolean;

    function NCtxTrain: Integer;
    function NEmbedding: Integer;
    function Descricao: string;

    property Handle: TLlamaModelHandle read FHandle;
    property Vocab: TLlamaVocabHandle read FVocab;
    property Caminho: string read FCaminho;
  published
    property DllPath: string read FDllPath write FDllPath;
    property ModelPath: string read FModelPath write FModelPath;
    property GpuLayersPadrao: Integer read FGpuLayersPadrao write FGpuLayersPadrao;
    { Referencia externa sem ownership. O ciclo de vida de FullExports pertence ao Engine. }
    property FullExports: TYakkoFullExports read FFullExports write SetFullExports;
  end;

implementation

function ResolveLlamaDllFile(const AValue: string): string;
var
  LPath: string;
begin
  LPath := Trim(AValue);
  if LPath = '' then
    Exit('');

  if FileExists(LPath) then
    Exit(LPath);

  if DirectoryExists(LPath) then
    Exit(TPath.Combine(ExcludeTrailingPathDelimiter(LPath), 'llama.dll'));

  if SameText(ExtractFileName(LPath), 'llama.dll') then
    Exit(LPath);

  if DirectoryExists(ExtractFilePath(LPath)) then
    Exit(TPath.Combine(ExcludeTrailingPathDelimiter(ExtractFilePath(LPath)), 'llama.dll'));

  Result := LPath;
end;

{ TYakkoModelo }

constructor TYakkoModelo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FGpuLayersPadrao := 999;
  FFullExports := nil;
  FHandle := nil;
  FVocab := nil;
  FCaminho := '';
  FBackendIniciado := False;
  FDestruindo := False;
end;

destructor TYakkoModelo.Destroy;
begin
  if FDestruindo then
    Exit;
  FDestruindo := True;
  Descarregar;
  FFullExports := nil;
  inherited;
end;

function TYakkoModelo.ResolveDllCaminho: string;
begin
  Result := ResolveLlamaDllFile(FDllPath);
end;

procedure TYakkoModelo.SetFullExports(const Value: TYakkoFullExports);
begin
  if FFullExports = Value then
    Exit;

  FFullExports := Value;
end;

procedure TYakkoModelo.IniciarBackend;
var
  HGgml: HMODULE;
  FnFromPath: TFnGgmlBackendLoadAllFromPath;
  FnAll: TFnGgmlBackendLoadAll;
  LDllPath: string;
  DllDir: AnsiString;
begin
  if FBackendIniciado then
    Exit;

  if not Assigned(llama_backend_init) then
    raise ELlamaModeloError.Create('Export llama_backend_init nao disponivel.');

  LDllPath := '';
  if Assigned(FFullExports) then
    LDllPath := ResolveLlamaDllFile(FFullExports.DllPath)
  else
    LDllPath := ResolveDllCaminho;

  DllDir := AnsiString(ExcludeTrailingPathDelimiter(ExtractFilePath(LDllPath)));
  HGgml := GetModuleHandle('ggml.dll');
  if HGgml = 0 then
    HGgml := LoadLibrary('ggml.dll');
  if HGgml <> 0 then
  begin
    FnFromPath := GetProcAddress(HGgml, 'ggml_backend_load_all_from_path');
    if Assigned(FnFromPath) then
      FnFromPath(PAnsiChar(DllDir))
    else
    begin
      FnAll := GetProcAddress(HGgml, 'ggml_backend_load_all');
      if Assigned(FnAll) then
        FnAll();
    end;
  end;

  TFnBackendInit(llama_backend_init)();
  FBackendIniciado := True;
end;

procedure TYakkoModelo.LiberarBackend;
begin
  if not FBackendIniciado then
    Exit;

  if Assigned(llama_backend_free) then
    TFnBackendFree(llama_backend_free)();

  FBackendIniciado := False;
end;

procedure TYakkoModelo.Carregar(const ACaminho: string; AGpuLayers: Integer);
var
  LDllPath: string;
  LGpuLayers: Integer;
  LParams: TLlamaModelParams;
  LPathAnsi: AnsiString;
begin
  if EstaCarregado then
    Descarregar;

  if not Assigned(FFullExports) then
    raise ELlamaModeloError.Create(
      'FullExports nao configurado. Associe TYakkoFullExports antes de carregar o modelo.');

  LDllPath := ResolveDllCaminho;
  if LDllPath = '' then
    LDllPath := Trim(FFullExports.DllPath);

  if LDllPath = '' then
    raise ELlamaModeloError.Create(
      'Caminho da llama.dll nao configurado. Defina TYakkoModelo.DllPath ou TYakkoFullExports.DllPath.');
  if not FileExists(LDllPath) then
    raise ELlamaModeloError.CreateFmt('llama.dll nao encontrada no caminho: %s', [LDllPath]);

  if not FFullExports.EstaCarregado then
    FFullExports.Carregar(LDllPath);

  IniciarBackend;

  try
    if AGpuLayers < 0 then
      LGpuLayers := FGpuLayersPadrao
    else
      LGpuLayers := AGpuLayers;

    if not Assigned(llama_model_default_params) then
      raise ELlamaModeloError.Create('Export llama_model_default_params nao disponivel.');
    if not Assigned(llama_model_load_from_file) then
      raise ELlamaModeloError.Create('Export llama_model_load_from_file nao disponivel.');
    if not Assigned(llama_model_get_vocab) then
      raise ELlamaModeloError.Create('Export llama_model_get_vocab nao disponivel.');

    LParams := TFnModelDefaultParams(llama_model_default_params)();
    LParams.n_gpu_layers := LGpuLayers;

    LPathAnsi := AnsiString(ACaminho);
    FHandle := TFnModelLoadFromFile(llama_model_load_from_file)(PAnsiChar(LPathAnsi), LParams);

    if FHandle = nil then
      raise ELlamaModeloError.CreateFmt('Nao foi possivel carregar o modelo: %s', [ACaminho]);

    FVocab := TFnModelGetVocab(llama_model_get_vocab)(FHandle);
    FCaminho := ACaminho;
  except
    on E: Exception do
    begin
      Descarregar;
      raise ELlamaModeloError.CreateFmt('Falha ao carregar modelo: %s', [E.Message]);
    end;
  end;
end;

procedure TYakkoModelo.Descarregar;
var
  LHandle: TLlamaModelHandle;
begin
  LHandle := FHandle;
  FHandle := nil;
  FVocab := nil;
  FCaminho := '';

  if (LHandle <> nil) and Assigned(llama_model_free) then
    TFnModelFree(llama_model_free)(LHandle);

  LiberarBackend;
end;

function TYakkoModelo.EstaCarregado: Boolean;
begin
  Result := FHandle <> nil;
end;

function TYakkoModelo.PodeDestruir: Boolean;
begin
  Result := (FHandle = nil) and (not FBackendIniciado);
end;

function TYakkoModelo.NCtxTrain: Integer;
begin
  if not EstaCarregado then
    raise ELlamaModeloError.Create('Modelo nao carregado.');
  if not Assigned(llama_model_n_ctx_train) then
    raise ELlamaModeloError.Create('Export llama_model_n_ctx_train nao disponivel.');
  Result := TFnModelNCtxTrain(llama_model_n_ctx_train)(FHandle);
end;

function TYakkoModelo.NEmbedding: Integer;
begin
  if not EstaCarregado then
    raise ELlamaModeloError.Create('Modelo nao carregado.');
  if not Assigned(llama_model_n_embd) then
    raise ELlamaModeloError.Create('Export llama_model_n_embd nao disponivel.');
  Result := TFnModelNEmbd(llama_model_n_embd)(FHandle);
end;

function TYakkoModelo.Descricao: string;
var
  Buf: array[0..255] of AnsiChar;
begin
  if not EstaCarregado then
    raise ELlamaModeloError.Create('Modelo nao carregado.');
  if not Assigned(llama_model_desc) then
    raise ELlamaModeloError.Create('Export llama_model_desc nao disponivel.');
  TFnModelDesc(llama_model_desc)(FHandle, @Buf[0], SizeOf(Buf));
  Result := string(AnsiString(PAnsiChar(@Buf[0])));
end;

initialization
  System.Classes.RegisterClass(TYakkoModelo);

end.
