unit uYakkoMemoryManagerComponent;

{ Gestor de memoria conversacional.
  Responsabilidades:
  - estimar uso de contexto
  - aplicar auto-resumo e janela deslizante
  - manter historico dentro do budget disponivel
  Ownership:
  - Tokenizer/ChatTemplate/Gerador/Config sao referencias borrowed. }

interface

uses
  System.Classes,
  System.SysUtils,
  uYakkoInferenceConfigComponent,
  uYakkoTokenizerComponent,
  uYakkoChatTemplateComponent,
  uYakkoGeradorComponent,
  uYakkoGenerationEventsComponent,
  uYakkoLlamaTypes;

type
  EYakkoMemoryManagerError = class(Exception);

  TYakkoMemoryManager = class(TComponent)
  private const
    FALLBACK_MAX_MENSAGENS = 12;
    PROMPT_SISTEMA_RESUMO =
      'Resuma memoria de conversa em portugues do Brasil. '
      + 'Responda em formato fixo e curto, com estes rotulos em linhas separadas: Objetivo, Regra, Fatos confirmados, Pendencias. '
      + 'Preserve termos exatos do usuario e nomes proprios exatamente como foram informados. '
      + 'Nao troque sinonimos por interpretacoes, nao invente, nao repita historico irrelevante e nao use markdown, JSON, listas numeradas, tags especiais ou <think>.';
    PROMPT_RESUMO =
      'Resuma o historico anterior de forma objetiva e literal, mantendo os fatos importantes com os termos exatos usados na conversa.';
  private
    FTokenizer: TYakkoTokenizer;
    FChatTemplate: TYakkoChatTemplate;
    FGerador: TYakkoGerador;
    FConfig: TYakkoInferenceConfig;
    FDestruindo: Boolean;

    procedure EnsureDependenciasBasicas;
    procedure EnsureEstadoConsistente;
    procedure ValidarMensagens(const AMensagens: TArray<TLlamaMensagem>);
    function AutoResumoAtivo: Boolean;
    function AutoResumoLimiar: Double;
    function AutoResumoMaxTokens: Integer;
    function AutoResumoMensagensRecentes: Integer;
    function FatiaMensagens(const AMensagens: TArray<TLlamaMensagem>; AInicio, AFimExclusivo: Integer): TArray<TLlamaMensagem>;
    procedure SubstituirPorResumo(var AMensagens: TArray<TLlamaMensagem>; const AResumo: string; AManterMensagensRecentes: Integer);
    procedure LimitarJanelaMensagens(var AMensagens: TArray<TLlamaMensagem>; AMaxMensagens: Integer);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    function ContextoValido: Boolean;
    function BudgetDisponivel: Integer;
    function PodeResumir: Boolean;

    function EstimarUsoContexto(const AProximaPergunta: string; const APromptSistema: string; const AMensagens: TArray<TLlamaMensagem>): Integer;
    function DeveResumir(const AProximaPergunta: string; const APromptSistema: string; const AMensagens: TArray<TLlamaMensagem>): Boolean;
    function ResumirHistorico(var AMensagens: TArray<TLlamaMensagem>; const AProximaPergunta: string; const APromptSistema: string; var AAutoResumoContagem: Integer): Boolean;
    procedure AjustarContexto(var AMensagens: TArray<TLlamaMensagem>; const AProximaPergunta: string; const APromptSistema: string; AMaxContexto: Integer; var AAutoResumoContagem: Integer);

    property Tokenizer: TYakkoTokenizer read FTokenizer write FTokenizer;
    property ChatTemplate: TYakkoChatTemplate read FChatTemplate write FChatTemplate;
    property Gerador: TYakkoGerador read FGerador write FGerador;
    property Config: TYakkoInferenceConfig read FConfig write FConfig;
  end;

implementation

constructor TYakkoMemoryManager.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTokenizer := nil;
  FChatTemplate := nil;
  FGerador := nil;
  FConfig := nil;
  FDestruindo := False;
end;

destructor TYakkoMemoryManager.Destroy;
begin
  if FDestruindo then
    Exit;

  FDestruindo := True;
  FGerador := nil;
  FTokenizer := nil;
  FChatTemplate := nil;
  FConfig := nil;
  inherited;
end;

function TYakkoMemoryManager.AutoResumoAtivo: Boolean;
begin
  Result := (not Assigned(FConfig)) or FConfig.AutoResumo;
end;

function TYakkoMemoryManager.AutoResumoLimiar: Double;
begin
  if Assigned(FConfig) then
    Exit(FConfig.AutoResumoLimiar);
  Result := 0.70;
end;

function TYakkoMemoryManager.AutoResumoMaxTokens: Integer;
begin
  if Assigned(FConfig) then
    Exit(FConfig.AutoResumoMaxTokens);
  Result := 256;
end;

function TYakkoMemoryManager.AutoResumoMensagensRecentes: Integer;
begin
  if Assigned(FConfig) then
    Exit(FConfig.AutoResumoMensagensRecentes);
  Result := 4;
end;

procedure TYakkoMemoryManager.EnsureDependenciasBasicas;
begin
  if FDestruindo then
    raise EYakkoMemoryManagerError.Create('MemoryManager em destruicao.');

  if not Assigned(FGerador) then
    raise EYakkoMemoryManagerError.Create('Gerador nao configurado no MemoryManager.');

  if not Assigned(FTokenizer) then
    raise EYakkoMemoryManagerError.Create('Tokenizer nao configurado no MemoryManager.');

  if not Assigned(FChatTemplate) then
    raise EYakkoMemoryManagerError.Create('ChatTemplate nao configurado no MemoryManager.');
end;

procedure TYakkoMemoryManager.EnsureEstadoConsistente;
begin
  EnsureDependenciasBasicas;

  if (FGerador.GenerationState = gsGerando) or (FGerador.GenerationState = gsCancelando) then
    raise EYakkoMemoryManagerError.Create('Nao e permitido ajustar memoria durante geracao ativa.');
end;

procedure TYakkoMemoryManager.ValidarMensagens(const AMensagens: TArray<TLlamaMensagem>);
var
  I: Integer;
begin
  for I := 0 to High(AMensagens) do
  begin
    case AMensagens[I].Role of
      mrSystem, mrUser, mrAssistant:
        ;
    else
      raise EYakkoMemoryManagerError.CreateFmt('Role de mensagem invalida no indice %d.', [I]);
    end;
  end;
end;

function TYakkoMemoryManager.ContextoValido: Boolean;
begin
  Result := (not FDestruindo)
    and Assigned(FGerador)
    and Assigned(FTokenizer)
    and Assigned(FChatTemplate)
    and FTokenizer.PodeTokenizar
    and FChatTemplate.PodeMontarPrompt;
end;

function TYakkoMemoryManager.BudgetDisponivel: Integer;
begin
  if not Assigned(FGerador) then
    Exit(0);
  Result := FGerador.ContextoDisponivel;
end;

function TYakkoMemoryManager.PodeResumir: Boolean;
begin
  Result := ContextoValido and (BudgetDisponivel > 0);
end;

function TYakkoMemoryManager.EstimarUsoContexto(const AProximaPergunta: string; const APromptSistema: string; const AMensagens: TArray<TLlamaMensagem>): Integer;
begin
  EnsureDependenciasBasicas;
  ValidarMensagens(AMensagens);

  if not ContextoValido then
    raise EYakkoMemoryManagerError.Create('Contexto invalido para estimativa de memoria.');

  Result := FGerador.EstimarTokensComMensagens(AProximaPergunta, APromptSistema, AMensagens);
end;

function TYakkoMemoryManager.FatiaMensagens(const AMensagens: TArray<TLlamaMensagem>; AInicio, AFimExclusivo: Integer): TArray<TLlamaMensagem>;
var
  I: Integer;
begin
  if AInicio < 0 then
    AInicio := 0;
  if AFimExclusivo > Length(AMensagens) then
    AFimExclusivo := Length(AMensagens);
  if AFimExclusivo < AInicio then
    AFimExclusivo := AInicio;

  SetLength(Result, AFimExclusivo - AInicio);
  for I := 0 to High(Result) do
    Result[I] := AMensagens[AInicio + I];
end;

procedure TYakkoMemoryManager.SubstituirPorResumo(var AMensagens: TArray<TLlamaMensagem>; const AResumo: string; AManterMensagensRecentes: Integer);
var
  LNovoHistorico: TArray<TLlamaMensagem>;
  LRecentes: TArray<TLlamaMensagem>;
  LRecentesInicio: Integer;
  LIndex: Integer;
begin
  if AManterMensagensRecentes < 0 then
    AManterMensagensRecentes := 0;

  if AManterMensagensRecentes > Length(AMensagens) then
    AManterMensagensRecentes := Length(AMensagens);

  LRecentesInicio := Length(AMensagens) - AManterMensagensRecentes;
  LRecentes := FatiaMensagens(AMensagens, LRecentesInicio, Length(AMensagens));

  SetLength(LNovoHistorico, Length(LRecentes) + 1);
  LNovoHistorico[0].Role := mrSystem;
  LNovoHistorico[0].Conteudo := 'Resumo automatico da conversa ate aqui:' + sLineBreak + Trim(AResumo);

  for LIndex := 0 to High(LRecentes) do
    LNovoHistorico[LIndex + 1] := LRecentes[LIndex];

  AMensagens := LNovoHistorico;
end;

procedure TYakkoMemoryManager.LimitarJanelaMensagens(var AMensagens: TArray<TLlamaMensagem>; AMaxMensagens: Integer);
var
  LManter: Integer;
begin
  if AMaxMensagens <= 0 then
    Exit;

  if Length(AMensagens) <= AMaxMensagens then
    Exit;

  LManter := AMaxMensagens;
  AMensagens := FatiaMensagens(AMensagens, Length(AMensagens) - LManter, Length(AMensagens));
end;

function TYakkoMemoryManager.DeveResumir(const AProximaPergunta: string; const APromptSistema: string; const AMensagens: TArray<TLlamaMensagem>): Boolean;
var
  LOrcamento: Integer;
  LTokensProjetados: Integer;
begin
  Result := False;

  if not AutoResumoAtivo then
    Exit;

  if Length(AMensagens) <= AutoResumoMensagensRecentes then
    Exit;

  if not PodeResumir then
    Exit;

  LOrcamento := BudgetDisponivel;
  if LOrcamento <= 0 then
    Exit;

  LTokensProjetados := EstimarUsoContexto(AProximaPergunta, APromptSistema, AMensagens);
  Result := LTokensProjetados >= Trunc(LOrcamento * AutoResumoLimiar);
end;

function TYakkoMemoryManager.ResumirHistorico(var AMensagens: TArray<TLlamaMensagem>; const AProximaPergunta: string; const APromptSistema: string; var AAutoResumoContagem: Integer): Boolean;
var
  LHistoricoParaResumo: TArray<TLlamaMensagem>;
  LResumo: string;
begin
  EnsureEstadoConsistente;
  ValidarMensagens(AMensagens);

  Result := False;
  if not DeveResumir(AProximaPergunta, APromptSistema, AMensagens) then
    Exit;

  LHistoricoParaResumo := FatiaMensagens(AMensagens, 0, Length(AMensagens) - AutoResumoMensagensRecentes);
  if Length(LHistoricoParaResumo) = 0 then
    Exit;

  LResumo := Trim(FGerador.GerarComMensagens(
    PROMPT_RESUMO,
    PROMPT_SISTEMA_RESUMO,
    LHistoricoParaResumo,
    AutoResumoMaxTokens,
    nil
  ));

  if LResumo = '' then
    Exit;

  SubstituirPorResumo(AMensagens, LResumo, AutoResumoMensagensRecentes);
  Inc(AAutoResumoContagem);
  Result := True;
end;

procedure TYakkoMemoryManager.AjustarContexto(var AMensagens: TArray<TLlamaMensagem>; const AProximaPergunta: string; const APromptSistema: string; AMaxContexto: Integer; var AAutoResumoContagem: Integer);
begin
  EnsureEstadoConsistente;
  ValidarMensagens(AMensagens);

  if not ResumirHistorico(AMensagens, AProximaPergunta, APromptSistema, AAutoResumoContagem) then
  begin
    { Fallback de janela deslizante para evitar crescimento ilimitado. }
    if AMaxContexto > 0 then
      LimitarJanelaMensagens(AMensagens, FALLBACK_MAX_MENSAGENS);
  end;
end;

initialization
  System.Classes.RegisterClass(TYakkoMemoryManager);

end.

