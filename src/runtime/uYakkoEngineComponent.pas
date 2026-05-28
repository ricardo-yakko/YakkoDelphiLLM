unit uYakkoEngineComponent;

{ Componente orquestrador central do runtime.
  Responsabilidades:
  - ownership principal dos componentes core
  - wiring de dependencias entre componentes
  - teardown seguro em ordem deterministica
  - fonte central de configuracao via TYakkoInferenceConfig. }

interface

uses
  System.Classes,
  System.SysUtils,
  uYakkoLLM,
  uYakkoInferenceConfigComponent,
  uYakkoFullExportsComponent,
  uYakkoModeloComponent,
  uYakkoChatTemplateComponent,
  uYakkoTokenizerComponent,
  uYakkoContextoComponent,
  uYakkoSessaoComponent,
  uYakkoToolManagerComponent,
  uYakkoMemoryManagerComponent,
  uYakkoGeradorComponent,
  uYakkoChatComponent,
  uYakkoInferenceOrchestration,
  uYakkoLlamaTypes;

type
  TYakkoEngine = class(TComponent)
  private
    FDestruindo: Boolean;
    FConfig: TYakkoInferenceConfig;
    FFullExports: TYakkoFullExports;
    FPaths: TYakkoPaths;
    FModelo: TYakkoModelo;
    FChatTemplate: TYakkoChatTemplate;
    FTokenizer: TYakkoTokenizer;
    FContexto: TYakkoContexto;
    FSessao: TYakkoSessao;
    FToolManager: TYakkoToolManager;
    FMemoryManager: TYakkoMemoryManager;
    FGerador: TYakkoGerador;
    FChat: TYakkoChat;
    FContextAssembler: TYakkoContextAssembler;

    procedure InicializarComponentesPrincipais;
    procedure ConectarDependencias;
    function ReferenciaPodeDestruir(AComponente: TComponent): Boolean;
    procedure LiberarComponenteReferencia(var AComponente: TComponent);

    procedure SetPaths(const Value: TYakkoPaths);
    procedure SetConfig(const Value: TYakkoInferenceConfig);
    procedure SetFullExports(const Value: TYakkoFullExports);
    procedure SetModelo(const Value: TYakkoModelo);
    procedure SetChatTemplate(const Value: TYakkoChatTemplate);
    procedure SetTokenizer(const Value: TYakkoTokenizer);
    procedure SetContexto(const Value: TYakkoContexto);
    procedure SetSessao(const Value: TYakkoSessao);
    procedure SetToolManager(const Value: TYakkoToolManager);
    procedure SetMemoryManager(const Value: TYakkoMemoryManager);
    procedure SetGerador(const Value: TYakkoGerador);
    procedure SetChat(const Value: TYakkoChat);
    procedure SetContextAssembler(const Value: TYakkoContextAssembler);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Cria uma nova sessao de Chat usando o Gerador corrente.
      O chamador e responsavel por destruir o objeto retornado. }
    function NovaChat: TYakkoChat;
    { Aplica DllPath do Paths ao Modelo quando FModelo.DllPath estiver vazio. }
    procedure SincronizarPathsModelo;

    function PodeDestruir: Boolean;
  published
    property Paths: TYakkoPaths read FPaths write SetPaths;
    { Engine e owner principal da configuracao unificada por padrao.
      Referencias externas sao tratadas como borrowed (sem ownership). }
    property Config: TYakkoInferenceConfig read FConfig write SetConfig;
    { Engine e owner principal de FullExports por padrao.
      Referencias externas sao tratadas como borrowed (sem ownership). }
    property FullExports: TYakkoFullExports read FFullExports write SetFullExports;
    { Engine e owner principal de Modelo por padrao.
      Referencias externas sao tratadas como borrowed (sem ownership). }
    property Modelo: TYakkoModelo read FModelo write SetModelo;
    { Engine e owner principal do ChatTemplate por padrao.
      Referencias externas sao tratadas como borrowed (sem ownership). }
    property ChatTemplate: TYakkoChatTemplate read FChatTemplate write SetChatTemplate;
    { Engine e owner principal do Tokenizer por padrao.
      Referencias externas sao tratadas como borrowed (sem ownership). }
    property Tokenizer: TYakkoTokenizer read FTokenizer write SetTokenizer;
    { Referencia externa sem ownership para Modelo quando atribuida de fora. }
    property Contexto: TYakkoContexto read FContexto write SetContexto;
    { Referencia externa sem ownership para Contexto/Chat quando atribuida de fora. }
    property Sessao: TYakkoSessao read FSessao write SetSessao;
    { Engine e owner principal do ToolManager por padrao.
      Referencias externas sao tratadas como borrowed (sem ownership). }
    property ToolManager: TYakkoToolManager read FToolManager write SetToolManager;
    { Referencia externa sem ownership para Tokenizer/ChatTemplate/Gerador quando atribuida de fora. }
    property MemoryManager: TYakkoMemoryManager read FMemoryManager write SetMemoryManager;
    { Referencia externa sem ownership para Modelo/Contexto quando atribuida de fora. }
    property Gerador: TYakkoGerador read FGerador write SetGerador;
    { Referencia externa sem ownership para Gerador quando atribuida de fora. }
    property Chat: TYakkoChat read FChat write SetChat;
    { Engine e owner principal do montador de contexto por padrao. }
    property ContextAssembler: TYakkoContextAssembler read FContextAssembler write SetContextAssembler;
  end;

implementation

constructor TYakkoEngine.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDestruindo := False;
  FConfig := nil;
  FPaths := nil;
  FFullExports := nil;
  FModelo := nil;
  FChatTemplate := nil;
  FTokenizer := nil;
  FContexto := nil;
  FSessao := nil;
  FToolManager := nil;
  FMemoryManager := nil;
  FGerador := nil;
  FChat := nil;
  FContextAssembler := nil;
  InicializarComponentesPrincipais;
end;

destructor TYakkoEngine.Destroy;
var
  LRef: TComponent;
begin
  if FDestruindo then
    Exit;

  FDestruindo := True;

  if Assigned(FChat) then
  begin
    FChat.Gerador := nil;
    FChat.MemoryManager := nil;
    FChat.Config := nil;
    FChat.ContextAssembler := nil;
  end;
  if Assigned(FMemoryManager) then
  begin
    FMemoryManager.Gerador := nil;
    FMemoryManager.Tokenizer := nil;
    FMemoryManager.ChatTemplate := nil;
    FMemoryManager.Config := nil;
  end;
  if Assigned(FGerador) then
  begin
    FGerador.Config := nil;
    FGerador.ToolManager := nil;
    FGerador.Sessao := nil;
    FGerador.ChatTemplate := nil;
    FGerador.Tokenizer := nil;
    FGerador.Contexto := nil;
    FGerador.Modelo := nil;
  end;
  if Assigned(FSessao) then
  begin
    FSessao.Config := nil;
    FSessao.Chat := nil;
    FSessao.Contexto := nil;
  end;
  if Assigned(FContexto) then
    FContexto.Config := nil;
  if Assigned(FChatTemplate) then
    FChatTemplate.Modelo := nil;
  if Assigned(FTokenizer) then
    FTokenizer.Modelo := nil;
  if Assigned(FContexto) then
    FContexto.Modelo := nil;

  { Ordem de teardown obrigatoria:
    Chat -> ContextAssembler -> Gerador -> Sessao -> ToolManager -> MemoryManager -> ChatTemplate -> Tokenizer -> Contexto -> Modelo -> FullExports
    Observacao: a Pipeline e destruida internamente no destructor do TYakkoGerador. }
  LRef := FChat;
  LiberarComponenteReferencia(LRef);
  FChat := nil;

  LRef := FContextAssembler;
  LiberarComponenteReferencia(LRef);
  FContextAssembler := nil;

  LRef := FGerador;
  LiberarComponenteReferencia(LRef);
  FGerador := nil;

  LRef := FSessao;
  LiberarComponenteReferencia(LRef);
  FSessao := nil;

  LRef := FToolManager;
  LiberarComponenteReferencia(LRef);
  FToolManager := nil;

  LRef := FMemoryManager;
  LiberarComponenteReferencia(LRef);
  FMemoryManager := nil;

  LRef := FChatTemplate;
  LiberarComponenteReferencia(LRef);
  FChatTemplate := nil;

  LRef := FTokenizer;
  LiberarComponenteReferencia(LRef);
  FTokenizer := nil;

  LRef := FContexto;
  LiberarComponenteReferencia(LRef);
  FContexto := nil;

  LRef := FModelo;
  LiberarComponenteReferencia(LRef);
  FModelo := nil;

  LRef := FFullExports;
  LiberarComponenteReferencia(LRef);
  FFullExports := nil;

  if Assigned(FConfig) then
    FreeAndNil(FConfig);

  inherited Destroy;
end;

procedure TYakkoEngine.InicializarComponentesPrincipais;
begin
  try
    if not Assigned(FConfig) then
      FConfig := TYakkoInferenceConfig.Create;
    if not Assigned(FFullExports) then
      FFullExports := TYakkoFullExports.Create(Self);
    if not Assigned(FModelo) then
      FModelo := TYakkoModelo.Create(Self);
    if not Assigned(FChatTemplate) then
      FChatTemplate := TYakkoChatTemplate.Create(Self);
    if not Assigned(FTokenizer) then
      FTokenizer := TYakkoTokenizer.Create(Self);
    if not Assigned(FContexto) then
      FContexto := TYakkoContexto.Create(Self);
    if not Assigned(FSessao) then
      FSessao := TYakkoSessao.Create(Self);
    if not Assigned(FToolManager) then
      FToolManager := TYakkoToolManager.Create(Self);
    if not Assigned(FMemoryManager) then
      FMemoryManager := TYakkoMemoryManager.Create(Self);
    if not Assigned(FGerador) then
      FGerador := TYakkoGerador.Create(Self);
    if not Assigned(FChat) then
      FChat := TYakkoChat.Create(Self);
    if not Assigned(FContextAssembler) then
      FContextAssembler := TYakkoContextAssembler.Create(Self);
    ConectarDependencias;
  except
    on E: Exception do
    begin
      { Rollback de inicializacao parcial: tolera falhas no meio da montagem. }
      if Assigned(FChat) and (FChat.Owner = Self) then
        FreeAndNil(FChat)
      else
        FChat := nil;

      if Assigned(FGerador) and (FGerador.Owner = Self) then
        FreeAndNil(FGerador)
      else
        FGerador := nil;

      if Assigned(FContextAssembler) and (FContextAssembler.Owner = Self) then
        FreeAndNil(FContextAssembler)
      else
        FContextAssembler := nil;

      if Assigned(FContexto) and (FContexto.Owner = Self) then
        FreeAndNil(FContexto)
      else
        FContexto := nil;

      if Assigned(FSessao) and (FSessao.Owner = Self) then
        FreeAndNil(FSessao)
      else
        FSessao := nil;

      if Assigned(FToolManager) and (FToolManager.Owner = Self) then
        FreeAndNil(FToolManager)
      else
        FToolManager := nil;

      if Assigned(FMemoryManager) and (FMemoryManager.Owner = Self) then
        FreeAndNil(FMemoryManager)
      else
        FMemoryManager := nil;

      if Assigned(FChatTemplate) and (FChatTemplate.Owner = Self) then
        FreeAndNil(FChatTemplate)
      else
        FChatTemplate := nil;

      if Assigned(FTokenizer) and (FTokenizer.Owner = Self) then
        FreeAndNil(FTokenizer)
      else
        FTokenizer := nil;

      if Assigned(FModelo) and (FModelo.Owner = Self) then
        FreeAndNil(FModelo)
      else
        FModelo := nil;

      if Assigned(FConfig) then
        FreeAndNil(FConfig);

      if Assigned(FFullExports) and (FFullExports.Owner = Self) then
        FreeAndNil(FFullExports)
      else
        FFullExports := nil;

      raise Exception.CreateFmt('Falha ao inicializar TYakkoEngine: %s', [E.Message]);
    end;
  end;
end;

procedure TYakkoEngine.ConectarDependencias;
begin
  if Assigned(FModelo) then
    FModelo.FullExports := FFullExports;

  if Assigned(FContexto) then
    FContexto.Config := FConfig;

  if Assigned(FContexto) then
    FContexto.Modelo := FModelo;

  if Assigned(FSessao) then
  begin
    FSessao.Config := FConfig;
    FSessao.Contexto := FContexto;
    FSessao.Chat := FChat;
  end;

  if Assigned(FChatTemplate) then
    FChatTemplate.Modelo := FModelo;

  if Assigned(FTokenizer) then
    FTokenizer.Modelo := FModelo;

  if Assigned(FMemoryManager) then
  begin
    FMemoryManager.Config := FConfig;
    FMemoryManager.Tokenizer := FTokenizer;
    FMemoryManager.ChatTemplate := FChatTemplate;
    FMemoryManager.Gerador := FGerador;
  end;

  if Assigned(FGerador) then
  begin
    FGerador.Config := FConfig;
    FGerador.Modelo := FModelo;
    FGerador.Contexto := FContexto;
    FGerador.Sessao := FSessao;
    FGerador.ToolManager := FToolManager;
    FGerador.ChatTemplate := FChatTemplate;
    FGerador.Tokenizer := FTokenizer;
  end;

  if Assigned(FChat) then
  begin
    FChat.Config := FConfig;
    FChat.Gerador := FGerador;
    FChat.MemoryManager := FMemoryManager;
    FChat.ContextAssembler := FContextAssembler;
  end;
end;

function TYakkoEngine.ReferenciaPodeDestruir(AComponente: TComponent): Boolean;
begin
  Result := Assigned(AComponente) and (AComponente.Owner = Self);
end;

procedure TYakkoEngine.LiberarComponenteReferencia(var AComponente: TComponent);
begin
  if not Assigned(AComponente) then
    Exit;

  if ReferenciaPodeDestruir(AComponente) then
    AComponente.Free;

  AComponente := nil;
end;

procedure TYakkoEngine.SetPaths(const Value: TYakkoPaths);
begin
  FPaths := Value;
  { Paths nao e mais propagado ao Modelo.
    Use SincronizarPathsModelo explicitamente quando necessario. }
end;

procedure TYakkoEngine.SetConfig(const Value: TYakkoInferenceConfig);
begin
  if FConfig = Value then
    Exit;

  if Assigned(FConfig) and (FConfig <> Value) then
    FreeAndNil(FConfig);

  if Assigned(Value) then
    FConfig := Value.Clone
  else
    FConfig := TYakkoInferenceConfig.Create;

  ConectarDependencias;
end;

procedure TYakkoEngine.SetFullExports(const Value: TYakkoFullExports);
var
  LAnterior: TYakkoFullExports;
begin
  if FFullExports = Value then
    Exit;

  LAnterior := FFullExports;
  FFullExports := Value;
  if not Assigned(FFullExports) then
    FFullExports := TYakkoFullExports.Create(Self);

  if ReferenciaPodeDestruir(LAnterior) and (LAnterior <> FFullExports) then
    LAnterior.Free;

  ConectarDependencias;
end;

procedure TYakkoEngine.SetModelo(const Value: TYakkoModelo);
var
  LAnterior: TYakkoModelo;
begin
  LAnterior := FModelo;
  FModelo := Value;
  if not Assigned(FModelo) then
    FModelo := TYakkoModelo.Create(Self);

  if ReferenciaPodeDestruir(LAnterior) and (LAnterior <> FModelo) then
    LAnterior.Free;

  ConectarDependencias;
end;

procedure TYakkoEngine.SetTokenizer(const Value: TYakkoTokenizer);
var
  LAnterior: TYakkoTokenizer;
begin
  LAnterior := FTokenizer;
  FTokenizer := Value;
  if not Assigned(FTokenizer) then
    FTokenizer := TYakkoTokenizer.Create(Self);

  if ReferenciaPodeDestruir(LAnterior) and (LAnterior <> FTokenizer) then
    LAnterior.Free;

  ConectarDependencias;
end;

procedure TYakkoEngine.SetChatTemplate(const Value: TYakkoChatTemplate);
var
  LAnterior: TYakkoChatTemplate;
begin
  LAnterior := FChatTemplate;
  FChatTemplate := Value;
  if not Assigned(FChatTemplate) then
    FChatTemplate := TYakkoChatTemplate.Create(Self);

  if ReferenciaPodeDestruir(LAnterior) and (LAnterior <> FChatTemplate) then
    LAnterior.Free;

  ConectarDependencias;
end;

procedure TYakkoEngine.SetContexto(const Value: TYakkoContexto);
var
  LAnterior: TYakkoContexto;
begin
  LAnterior := FContexto;
  FContexto := Value;
  if not Assigned(FContexto) then
    FContexto := TYakkoContexto.Create(Self);

  if ReferenciaPodeDestruir(LAnterior) and (LAnterior <> FContexto) then
    LAnterior.Free;

  ConectarDependencias;
end;

procedure TYakkoEngine.SetGerador(const Value: TYakkoGerador);
var
  LAnterior: TYakkoGerador;
begin
  LAnterior := FGerador;
  FGerador := Value;
  if not Assigned(FGerador) then
    FGerador := TYakkoGerador.Create(Self);

  if ReferenciaPodeDestruir(LAnterior) and (LAnterior <> FGerador) then
    LAnterior.Free;

  ConectarDependencias;
end;

procedure TYakkoEngine.SetSessao(const Value: TYakkoSessao);
var
  LAnterior: TYakkoSessao;
begin
  LAnterior := FSessao;
  FSessao := Value;
  if not Assigned(FSessao) then
    FSessao := TYakkoSessao.Create(Self);

  if ReferenciaPodeDestruir(LAnterior) and (LAnterior <> FSessao) then
    LAnterior.Free;

  ConectarDependencias;
end;

procedure TYakkoEngine.SetToolManager(const Value: TYakkoToolManager);
var
  LAnterior: TYakkoToolManager;
begin
  LAnterior := FToolManager;
  FToolManager := Value;
  if not Assigned(FToolManager) then
    FToolManager := TYakkoToolManager.Create(Self);

  if ReferenciaPodeDestruir(LAnterior) and (LAnterior <> FToolManager) then
    LAnterior.Free;

  ConectarDependencias;
end;

procedure TYakkoEngine.SetMemoryManager(const Value: TYakkoMemoryManager);
var
  LAnterior: TYakkoMemoryManager;
begin
  LAnterior := FMemoryManager;
  FMemoryManager := Value;
  if not Assigned(FMemoryManager) then
    FMemoryManager := TYakkoMemoryManager.Create(Self);

  if ReferenciaPodeDestruir(LAnterior) and (LAnterior <> FMemoryManager) then
    LAnterior.Free;

  ConectarDependencias;
end;

procedure TYakkoEngine.SetChat(const Value: TYakkoChat);
var
  LAnterior: TYakkoChat;
begin
  LAnterior := FChat;
  FChat := Value;
  if not Assigned(FChat) then
    FChat := TYakkoChat.Create(Self);

  if ReferenciaPodeDestruir(LAnterior) and (LAnterior <> FChat) then
    LAnterior.Free;

  ConectarDependencias;
end;

procedure TYakkoEngine.SetContextAssembler(const Value: TYakkoContextAssembler);
var
  LAnterior: TYakkoContextAssembler;
begin
  LAnterior := FContextAssembler;
  FContextAssembler := Value;
  if not Assigned(FContextAssembler) then
    FContextAssembler := TYakkoContextAssembler.Create(Self);

  if ReferenciaPodeDestruir(LAnterior) and (LAnterior <> FContextAssembler) then
    LAnterior.Free;

  ConectarDependencias;
end;

function TYakkoEngine.NovaChat: TYakkoChat;
begin
  if FGerador = nil then
    raise Exception.Create(
      'Engine.Gerador nao configurado. Associe TYakkoGerador antes de criar uma sessao.');
  Result := TYakkoChat.Create(nil);
  { Sessao isolada: chat criado pelo chamador, sem ownership do engine. }
  Result.Gerador := FGerador;
  Result.MemoryManager := FMemoryManager;
  Result.Config := FConfig;
  Result.ContextAssembler := FContextAssembler;
end;

procedure TYakkoEngine.SincronizarPathsModelo;
begin
  if not Assigned(FModelo) or not Assigned(FPaths) then
    Exit;
  if (FModelo.DllPath = '') and (FPaths.Dlls <> '') then
    FModelo.DllPath := FPaths.Dlls;
end;

function TYakkoEngine.PodeDestruir: Boolean;
begin
  Result :=
    (FConfig <> nil) and
    ((FChat = nil) or (FChat.Gerador = nil) or ReferenciaPodeDestruir(FChat)) and
    ((FGerador = nil) or (FGerador.PodeDestruir)) and
    ((FSessao = nil) or (FSessao.PodeDestruir)) and
    ((FToolManager = nil) or ReferenciaPodeDestruir(FToolManager)) and
    ((FMemoryManager = nil) or ReferenciaPodeDestruir(FMemoryManager)) and
    ((FContextAssembler = nil) or ReferenciaPodeDestruir(FContextAssembler)) and
    ((FChatTemplate = nil) or ReferenciaPodeDestruir(FChatTemplate)) and
    ((FTokenizer = nil) or ReferenciaPodeDestruir(FTokenizer)) and
    ((FContexto = nil) or (FContexto.PodeDestruir)) and
    ((FModelo = nil) or (FModelo.PodeDestruir)) and
    ((FFullExports = nil) or ReferenciaPodeDestruir(FFullExports));
end;

initialization
  System.Classes.RegisterClass(TYakkoEngine);

end.
