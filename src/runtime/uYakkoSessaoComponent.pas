unit uYakkoSessaoComponent;

{ Estado de sessao conversacional desacoplado.
  Responsabilidades:
  - acompanhar estado de geracao e tokens processados
  - controlar validade logica de sessao/KV cache
  - impor guardas contra operacoes invalidas em geracao ativa
  Ownership:
  - Contexto/Chat/Config sao referencias borrowed. }

interface

uses
  System.Classes,
  System.SysUtils,
  uYakkoInferenceConfigComponent,
  uYakkoContextoComponent;

type
  EYakkoSessaoError = class(Exception);

  { Sessao conversacional logica desacoplada dos detalhes internos do backend.
    Ownership: referencias externas sem ownership (Contexto e Chat). }
  TYakkoSessao = class(TComponent)
  private
    FContexto: TYakkoContexto;
    FConfig: TYakkoInferenceConfig;
    FOwnsConfig: Boolean;
    FChat: TComponent;
    FTokensProcessados: Integer;
    FUltimoToken: Integer;
    FSessaoAtiva: Boolean;
    FKVCacheValido: Boolean;
    FEmGeracao: Boolean;
    FDestruindo: Boolean;
    procedure SetContexto(const Value: TYakkoContexto);
    function GetConfig: TYakkoInferenceConfig;
    procedure SetConfig(const Value: TYakkoInferenceConfig);
    procedure SetChat(const Value: TComponent);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure ResetarSessao;
    procedure LimparKVCache;

    procedure MarcarGeracaoIniciada;
    procedure MarcarTokenProcessado(const AToken: Integer);
    procedure MarcarGeracaoFinalizada(const AGerouTokens: Boolean);
    procedure MarcarGeracaoFalha;

    function TokensUtilizados: Integer;
    function PodeGerar: Boolean;
    function PodeDestruir: Boolean;

    property SessaoAtiva: Boolean read FSessaoAtiva;
    property KVCacheValido: Boolean read FKVCacheValido;
    property EmGeracao: Boolean read FEmGeracao;
  published
    property Contexto: TYakkoContexto read FContexto write SetContexto;
    { Configuracao compartilhada sem ownership; reservada para politicas futuras de sessao. }
    property Config: TYakkoInferenceConfig read GetConfig write SetConfig;
    property Chat: TComponent read FChat write SetChat;
  end;

implementation

constructor TYakkoSessao.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FContexto := nil;
  FConfig := nil;
  FOwnsConfig := False;
  FChat := nil;
  FTokensProcessados := 0;
  FUltimoToken := -1;
  FSessaoAtiva := True;
  FKVCacheValido := False;
  FEmGeracao := False;
  FDestruindo := False;
end;

destructor TYakkoSessao.Destroy;
begin
  if FDestruindo then
    Exit;

  FDestruindo := True;
  FEmGeracao := False;
  FContexto := nil;
  if FOwnsConfig then
    FreeAndNil(FConfig)
  else
    FConfig := nil;
  FOwnsConfig := False;
  FChat := nil;
  inherited;
end;

procedure TYakkoSessao.SetContexto(const Value: TYakkoContexto);
begin
  if FContexto = Value then
    Exit;

  if FEmGeracao then
    raise EYakkoSessaoError.Create('Nao e permitido trocar o contexto durante geracao ativa.');

  if Assigned(FContexto) and FContexto.EstaAberto then
    FKVCacheValido := False;

  FContexto := Value;
end;

function TYakkoSessao.GetConfig: TYakkoInferenceConfig;
begin
  if not Assigned(FConfig) then
  begin
    FConfig := TYakkoInferenceConfig.Create;
    FOwnsConfig := True;
  end;
  Result := FConfig;
end;

procedure TYakkoSessao.SetConfig(const Value: TYakkoInferenceConfig);
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
end;

procedure TYakkoSessao.SetChat(const Value: TComponent);
begin
  if FChat = Value then
    Exit;

  FChat := Value;
end;

procedure TYakkoSessao.ResetarSessao;
begin
  if FDestruindo then
    Exit;

  if FEmGeracao then
    raise EYakkoSessaoError.Create('Nao e permitido resetar a sessao durante geracao ativa.');

  LimparKVCache;
  FTokensProcessados := 0;
  FUltimoToken := -1;
  FSessaoAtiva := True;
end;

procedure TYakkoSessao.LimparKVCache;
begin
  if FDestruindo then
    Exit;

  if FEmGeracao then
    raise EYakkoSessaoError.Create('Nao e permitido limpar o KV cache durante geracao ativa.');

  if Assigned(FContexto) and FContexto.EstaAberto then
    FContexto.Fechar;

  FKVCacheValido := False;
end;

procedure TYakkoSessao.MarcarGeracaoIniciada;
begin
  if FDestruindo then
    raise EYakkoSessaoError.Create('Sessao em destruicao nao pode iniciar geracao.');

  if not FSessaoAtiva then
    raise EYakkoSessaoError.Create('Sessao inativa nao pode iniciar geracao.');

  if not Assigned(FContexto) then
    raise EYakkoSessaoError.Create('Contexto nao configurado na sessao.');

  if FEmGeracao then
    raise EYakkoSessaoError.Create('Sessao ja esta em geracao.');

  FEmGeracao := True;
end;

procedure TYakkoSessao.MarcarTokenProcessado(const AToken: Integer);
begin
  if not FEmGeracao then
    Exit;

  Inc(FTokensProcessados);
  FUltimoToken := AToken;
end;

procedure TYakkoSessao.MarcarGeracaoFinalizada(const AGerouTokens: Boolean);
begin
  if not FEmGeracao then
    Exit;

  FEmGeracao := False;
  if AGerouTokens then
    FKVCacheValido := True;
end;

procedure TYakkoSessao.MarcarGeracaoFalha;
begin
  FEmGeracao := False;
end;

function TYakkoSessao.TokensUtilizados: Integer;
begin
  Result := FTokensProcessados;
end;

function TYakkoSessao.PodeGerar: Boolean;
begin
  Result :=
    (not FDestruindo) and
    FSessaoAtiva and
    (not FEmGeracao) and
    Assigned(FContexto);
end;

function TYakkoSessao.PodeDestruir: Boolean;
begin
  Result := not FEmGeracao;
end;

initialization
  System.Classes.RegisterClass(TYakkoSessao);

end.

