unit uYakkoChatComponent;

{ Fronteira conversacional do runtime.
  Responsabilidades:
  - historico de mensagens
  - memoria estruturada e auto-resumo
  - delegacao da inferencia para TYakkoGerador
  Ownership:
  - Gerador/MemoryManager/Config sao referencias borrowed. }

interface

uses
  System.Classes,
  System.SysUtils,
  uYakkoInferenceConfigComponent,
  uYakkoGeradorComponent,
  uYakkoMemoryManagerComponent,
  uYakkoInferenceOrchestration,
  uYakkoLlamaTypes;

type
  TYakkoChat = class(TComponent)
  private const
      MEMORIA_ESTRUTURADA_MAX_LINHAS = 18;

  private
    { Referencia externa sem ownership; o ciclo de vida pertence ao Engine. }
    FGerador: TYakkoGerador;
    FMemoryManager: TYakkoMemoryManager;
    FConfig: TYakkoInferenceConfig;
    FContextAssembler: TYakkoContextAssembler;
    FOwnsConfig: Boolean;
    FPromptSistema: string;
    FHistorico: TArray<TLlamaMensagem>;
    FAutoResumoContagem: Integer;
    FDestruindo: Boolean;

    procedure EnsureConfigurado;
    procedure AdicionarMensagem(ARole: TLlamaMensagemRole; const AConteudo: string);
    function ContextoOrcamento: Integer;
    function FatiaHistorico(AInicio, AFimExclusivo: Integer): TArray<TLlamaMensagem>;
    function EncontrarUltimaRespostaAssistente: string;
    function ConstruirMemoriaEstruturada(const APromptAtual: string): string;
    function NomeAssistenteAtual(const APromptAtual: string = ''): string;
    function ProjetoAtual(const APromptAtual: string = ''): string;
    function NomeUsuarioAtual(const APromptAtual: string = ''): string;
    function ChamadaUsuarioAtual(const APromptAtual: string = ''): string;
    function PromptSistemaComMemoria(const APromptAtual: string): string;
    procedure SubstituirHistoricoPorResumo(const AResumo: string; AManterMensagensRecentes: Integer);
    function TryResponderDeterministicamente(const APrompt: string; out AResposta: string): Boolean;
    function TentarAutoResumo(const AProximaPergunta: string; AMaxTokens: Integer): Boolean;
    function AutoResumoAtivo: Boolean;
    function AutoResumoMaxTokens: Integer;
    function AutoResumoMensagensRecentes: Integer;
    function StripTaggedBlock(const AValue, AOpenTag, ACloseTag: string): string;
    function GetConfig: TYakkoInferenceConfig;
    procedure SetConfig(const Value: TYakkoInferenceConfig);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    function AutoResumoContagem: Integer;
    function AutoResumoLimiar: Double;
    function EstimarTokensSessao: Integer;
    procedure LimparHistorico;
    procedure ReiniciarSessao;
    procedure RegistrarTroca(const APrompt, AResposta: string);
    procedure AtualizarUltimaMensagemAssistente(const AConteudo: string);
    function QuantidadeMensagens: Integer;
    function SanitizeModelResponseText(const AValue: string): string;
    function Perguntar(const APrompt: string; AMaxTokens: Integer = -1; AAoReceberTexto: TLlamaTextoParcialProc = nil): string;
    function PodeGerar: Boolean;
    function PodeDestruir: Boolean;
  published
    property Gerador: TYakkoGerador read FGerador write FGerador;
    { Referencia externa sem ownership. }
    property MemoryManager: TYakkoMemoryManager read FMemoryManager write FMemoryManager;
    { Referencia externa sem ownership. }
    property ContextAssembler: TYakkoContextAssembler read FContextAssembler write FContextAssembler;
    { Configuracao compartilhada sem ownership. }
    property Config: TYakkoInferenceConfig read GetConfig write SetConfig;
    property PromptSistema: string read FPromptSistema write FPromptSistema;
  end;

implementation

function LimparTrechoCapturado(const AValor: string): string; forward;
function TextoComecaComQualquer(const ATexto: string; const APrefixos: array of string): Boolean; forward;

function NormalizarParaComparacao(const AValor: string): string;
begin
  Result := LowerCase(AValor);
  Result := StringReplace(Result, 'Ã¡', 'a', [rfReplaceAll]);
  Result := StringReplace(Result, 'Ã ', 'a', [rfReplaceAll]);
  Result := StringReplace(Result, 'Ã¢', 'a', [rfReplaceAll]);
  Result := StringReplace(Result, 'Ã£', 'a', [rfReplaceAll]);
  Result := StringReplace(Result, 'Ã¤', 'a', [rfReplaceAll]);
  Result := StringReplace(Result, 'Ã©', 'e', [rfReplaceAll]);
  Result := StringReplace(Result, 'Ã¨', 'e', [rfReplaceAll]);
  Result := StringReplace(Result, 'Ãª', 'e', [rfReplaceAll]);
  Result := StringReplace(Result, 'Ã«', 'e', [rfReplaceAll]);
  Result := StringReplace(Result, 'Ã­', 'i', [rfReplaceAll]);
  Result := StringReplace(Result, 'Ã¬', 'i', [rfReplaceAll]);
  Result := StringReplace(Result, 'Ã®', 'i', [rfReplaceAll]);
  Result := StringReplace(Result, 'Ã¯', 'i', [rfReplaceAll]);
  Result := StringReplace(Result, 'Ã³', 'o', [rfReplaceAll]);
  Result := StringReplace(Result, 'Ã²', 'o', [rfReplaceAll]);
  Result := StringReplace(Result, 'Ã´', 'o', [rfReplaceAll]);
  Result := StringReplace(Result, 'Ãµ', 'o', [rfReplaceAll]);
  Result := StringReplace(Result, 'Ã¶', 'o', [rfReplaceAll]);
  Result := StringReplace(Result, 'Ãº', 'u', [rfReplaceAll]);
  Result := StringReplace(Result, 'Ã¹', 'u', [rfReplaceAll]);
  Result := StringReplace(Result, 'Ã»', 'u', [rfReplaceAll]);
  Result := StringReplace(Result, 'Ã¼', 'u', [rfReplaceAll]);
  Result := StringReplace(Result, 'Ã§', 'c', [rfReplaceAll]);
end;

function TYakkoChat.StripTaggedBlock(const AValue, AOpenTag, ACloseTag: string): string;
var
  LLowerValue: string;
  LOpenLower: string;
  LCloseLower: string;
  LStartPos: Integer;
  LRelativeEndPos: Integer;
  LEndPos: Integer;
begin
  Result := AValue;
  LOpenLower := LowerCase(AOpenTag);
  LCloseLower := LowerCase(ACloseTag);

  while True do
  begin
    LLowerValue := LowerCase(Result);
    LStartPos := Pos(LOpenLower, LLowerValue);
    if LStartPos <= 0 then
      Break;

    LRelativeEndPos := Pos(LCloseLower, Copy(LLowerValue, LStartPos + Length(LOpenLower), MaxInt));
    if LRelativeEndPos <= 0 then
    begin
      Delete(Result, LStartPos, MaxInt);
      Break;
    end;

    LEndPos := LStartPos + Length(LOpenLower) + LRelativeEndPos + Length(LCloseLower) - 2;
    Delete(Result, LStartPos, LEndPos - LStartPos + 1);
  end;
end;

function TYakkoChat.SanitizeModelResponseText(const AValue: string): string;
const
  CONTROL_TAGS: array[0..9] of string = (
    '<start_of_turn>model',
    '<start_of_turn>assistant',
    '<start_of_turn>system',
    '<start_of_turn>user',
    '<start_of_turn>',
    '</start_of_turn>',
    '<end_of_turn>',
    '<end_turn>',
    '<|end_of_turn|>',
    '<|eot_id|>'
  );
var
  I: Integer;
  LShowThinkBlocks: Boolean;
begin
  Result := Trim(AValue);
  LShowThinkBlocks := Assigned(FConfig) and FConfig.ShowThinkBlocks;

  if not LShowThinkBlocks then
  begin
    Result := StripTaggedBlock(Result, '<think>', '</think>');
    Result := StringReplace(Result, '<think>', '', [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, '</think>', '', [rfReplaceAll, rfIgnoreCase]);
  end;

  for I := Low(CONTROL_TAGS) to High(CONTROL_TAGS) do
    Result := StringReplace(Result, CONTROL_TAGS[I], '', [rfReplaceAll, rfIgnoreCase]);

  Result := Trim(Result);
end;
function TextoEhPergunta(const ATextoNormalizado: string): Boolean;
var
  LTexto: string;
begin
  LTexto := Trim(ATextoNormalizado);
  Result := (Pos('?', LTexto) > 0)
    or TextoComecaComQualquer(LTexto, [
      'qual ',
      'quais ',
      'quem ',
      'quando ',
      'onde ',
      'como ',
      'o que ',
      'que '
    ]);
end;

function CapturarAteSeparador(const AValor: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(AValor) do
  begin
    if CharInSet(AValor[I], [',', '.', ';', ':', '!', '?', #13, #10]) then
      Break;
    Result := Result + AValor[I];
  end;
  Result := LimparTrechoCapturado(Result);
end;

function TryExtrairAposPadrao(const ATexto, ATextoNormalizado: string;
  const APadraoNormalizado: string; out AValor: string): Boolean;
var
  Posicao: Integer;
begin
  Posicao := Pos(APadraoNormalizado, ATextoNormalizado);
  Result := Posicao > 0;
  if Result then
    AValor := CapturarAteSeparador(Copy(ATexto, Posicao + Length(APadraoNormalizado), MaxInt))
  else
    AValor := '';
end;

function TryExtrairAposPadroes(const ATexto, ATextoNormalizado: string;
  const APadroesNormalizados: array of string; out AValor: string): Boolean;
var
  LPadrao: string;
begin
  for LPadrao in APadroesNormalizados do
    if TryExtrairAposPadrao(ATexto, ATextoNormalizado, LPadrao, AValor) then
      Exit(True);

  AValor := '';
  Result := False;
end;

function TextoContemQualquer(const ATexto: string; const ATermos: array of string): Boolean;
var
  LTermo: string;
begin
  for LTermo in ATermos do
    if Pos(LTermo, ATexto) > 0 then
      Exit(True);

  Result := False;
end;

function TextoComecaComQualquer(const ATexto: string; const APrefixos: array of string): Boolean;
var
  LPrefixo: string;
begin
  for LPrefixo in APrefixos do
  begin
    if Pos(LPrefixo, ATexto) = 1 then
      Exit(True);
  end;

  Result := False;
end;

function LimparTrechoCapturado(const AValor: string): string;
begin
  Result := Trim(AValor);
  while (Result <> '') and CharInSet(Result[1], ['"', '''', ' ', '.', ',', ';', ':', '!', '?']) do
    Delete(Result, 1, 1);
  while (Result <> '') and CharInSet(Result[Length(Result)], ['"', '''', ' ', '.', ',', ';', ':', '!', '?']) do
    Delete(Result, Length(Result), 1);
end;

function ValorPareceNome(const AValor: string): Boolean;
var
  LValor: string;
  LNormalizado: string;
  LPartes: TArray<string>;
begin
  LValor := Trim(AValor);
  LNormalizado := NormalizarParaComparacao(LValor);
  LPartes := LValor.Split([' '], TStringSplitOptions.ExcludeEmpty);

  Result := (LValor <> '')
    and (Length(LValor) <= 48)
    and (Length(LPartes) <= 3)
    and (Pos('?', LValor) = 0)
    and (Pos('qual', LNormalizado) = 0)
    and (Pos('quais', LNormalizado) = 0)
    and (Pos('quem', LNormalizado) = 0)
    and (Pos('meu ', LNormalizado) = 0)
    and (Pos('seu ', LNormalizado) = 0)
    and (Pos('nome', LNormalizado) = 0)
    and (Pos('projeto', LNormalizado) = 0);
end;

function LimparNomeCapturado(const AValor: string): string;
const
  CONECTORES: array[0..10] of string = (
    ' e eu ',
    ' eu ',
    ' que ',
    ' porque ',
    ' pois ',
    ' para ',
    ' com ',
    ' no projeto ',
    ' mas ',
    ' mesmo ',
    ' nao '
  );
var
  LNormalizado: string;
  LPos: Integer;
  LConector: string;
begin
  Result := LimparTrechoCapturado(AValor);
  LNormalizado := ' ' + NormalizarParaComparacao(Result) + ' ';

  for LConector in CONECTORES do
  begin
    LPos := Pos(LConector, LNormalizado);
    if LPos > 0 then
    begin
      Result := Trim(Copy(Result, 1, LPos - 1));
      Break;
    end;
  end;

  Result := LimparTrechoCapturado(Result);
end;

function LimparProjetoCapturado(const AValor: string): string;
const
  CONECTORES: array[0..5] of string = (
    ' com ',
    ' que ',
    ' para ',
    ' e ',
    ' onde ',
    ' porque '
  );
var
  LNormalizado: string;
  LPos: Integer;
  LConector: string;
begin
  Result := LimparTrechoCapturado(AValor);
  LNormalizado := ' ' + NormalizarParaComparacao(Result) + ' ';

  for LConector in CONECTORES do
  begin
    LPos := Pos(LConector, LNormalizado);
    if LPos > 0 then
    begin
      Result := Trim(Copy(Result, 1, LPos - 1));
      Break;
    end;
  end;

  Result := LimparTrechoCapturado(Result);
end;

function MensagemMemoravel(const ATexto: string): Boolean;
var
  LTexto: string;
begin
  LTexto := NormalizarParaComparacao(ATexto);
  Result := TextoContemQualquer(LTexto, [
    'meu nome e ',
    'seu nome e ',
    'seu nome mudou para ',
    'pode me chamar de ',
    'me chame de ',
    'me chama de ',
    'a partir de agora',
    'prefiro',
    'preferencia',
    'gosto ',
    'nao gosto',
    'plano',
    'fase ',
    'prioridade',
    'regra',
    'trabalho',
    'uso ',
    'projeto',
    'quero '
  ]);
end;

function UmaLinha(const ATexto: string): string;
begin
  Result := Trim(StringReplace(StringReplace(ATexto, #13#10, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
end;

function TryExtrairNomeAssistenteDoTexto(const ATexto: string; out ANome: string): Boolean;
var
  TextoNormalizado: string;
begin
  TextoNormalizado := NormalizarParaComparacao(ATexto);
  if TextoEhPergunta(TextoNormalizado) then
  begin
    ANome := '';
    Exit(False);
  end;

  Result := TryExtrairAposPadroes(ATexto, TextoNormalizado, [
    'a partir de agora seu nome e ',
    'seu nome mudou para ',
    'seu nome agora e ',
    'seu nome e '
  ], ANome);
  ANome := LimparNomeCapturado(ANome);
  Result := Result and ValorPareceNome(ANome);
end;

function TryExtrairNomeUsuarioDoTexto(const ATexto: string; out ANome: string): Boolean;
var
  TextoNormalizado: string;
begin
  TextoNormalizado := NormalizarParaComparacao(ATexto);
  if TextoEhPergunta(TextoNormalizado) then
  begin
    ANome := '';
    Exit(False);
  end;

  Result := TryExtrairAposPadrao(ATexto, TextoNormalizado, 'meu nome e ', ANome);
  ANome := LimparNomeCapturado(ANome);
  Result := Result and ValorPareceNome(ANome);
end;

function TryExtrairChamadaUsuarioDoTexto(const ATexto: string; out AChamada: string): Boolean;
var
  TextoNormalizado: string;
begin
  TextoNormalizado := NormalizarParaComparacao(ATexto);
  if TextoEhPergunta(TextoNormalizado) then
  begin
    AChamada := '';
    Exit(False);
  end;

  Result := TryExtrairAposPadroes(ATexto, TextoNormalizado, [
    'pode me chamar de ',
    'me chame de ',
    'me chama de ',
    'me chamar de '
  ], AChamada);
  AChamada := LimparNomeCapturado(AChamada);
  Result := Result and ValorPareceNome(AChamada);
end;

constructor TYakkoChat.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FGerador := nil;
  FMemoryManager := nil;
  FConfig := nil;
  FOwnsConfig := False;
  FPromptSistema := '';
  FAutoResumoContagem := 0;
  FDestruindo := False;
  SetLength(FHistorico, 0);
end;

destructor TYakkoChat.Destroy;
begin
  if FDestruindo then
    Exit;
  FDestruindo := True;
  SetLength(FHistorico, 0);
  if FOwnsConfig then
    FreeAndNil(FConfig)
  else
    FConfig := nil;
  FOwnsConfig := False;
  FMemoryManager := nil;
  FGerador := nil;
  inherited;
end;

function TYakkoChat.GetConfig: TYakkoInferenceConfig;
begin
  if not Assigned(FConfig) then
  begin
    FConfig := TYakkoInferenceConfig.Create;
    FOwnsConfig := True;
  end;
  Result := FConfig;
end;

procedure TYakkoChat.SetConfig(const Value: TYakkoInferenceConfig);
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

function TYakkoChat.AutoResumoAtivo: Boolean;
begin
  Result := (not Assigned(FConfig)) or FConfig.AutoResumo;
end;

function TYakkoChat.AutoResumoMaxTokens: Integer;
begin
  if Assigned(FConfig) then
    Exit(FConfig.AutoResumoMaxTokens);
  Result := 256;
end;

function TYakkoChat.AutoResumoMensagensRecentes: Integer;
begin
  if Assigned(FConfig) then
    Exit(FConfig.AutoResumoMensagensRecentes);
  Result := 4;
end;

procedure TYakkoChat.EnsureConfigurado;
begin
  if not Assigned(FGerador) then
    raise Exception.Create('Gerador nao configurado. Associe TYakkoGerador ao chat.');
end;

function TYakkoChat.PodeGerar: Boolean;
begin
  Result := Assigned(FGerador) and FGerador.PodeGerar;
end;

function TYakkoChat.PodeDestruir: Boolean;
begin
  Result := True;
end;

function TYakkoChat.ContextoOrcamento: Integer;
begin
  if Assigned(FMemoryManager) then
    Exit(FMemoryManager.BudgetDisponivel);

  if FGerador = nil then
    Exit(0);
  Result := FGerador.ContextoDisponivel;
end;

function TYakkoChat.FatiaHistorico(AInicio, AFimExclusivo: Integer): TArray<TLlamaMensagem>;
var
  I: Integer;
begin
  if AInicio < 0 then
    AInicio := 0;
  if AFimExclusivo > Length(FHistorico) then
    AFimExclusivo := Length(FHistorico);
  if AFimExclusivo < AInicio then
    AFimExclusivo := AInicio;

  SetLength(Result, AFimExclusivo - AInicio);
  for I := 0 to High(Result) do
    Result[I] := FHistorico[AInicio + I];
end;

function TYakkoChat.EncontrarUltimaRespostaAssistente: string;
var
  I: Integer;
begin
  Result := '';
  for I := High(FHistorico) downto Low(FHistorico) do
    if FHistorico[I].Role = mrAssistant then
      Exit(FHistorico[I].Conteudo);
end;

function TYakkoChat.NomeAssistenteAtual(const APromptAtual: string): string;
var
  I: Integer;
begin
  Result := '';

  if (APromptAtual <> '') and TryExtrairNomeAssistenteDoTexto(APromptAtual, Result) then
    Exit;

  for I := High(FHistorico) downto Low(FHistorico) do
    if (FHistorico[I].Role = mrUser) and TryExtrairNomeAssistenteDoTexto(FHistorico[I].Conteudo, Result) then
      Exit;
end;

function TYakkoChat.NomeUsuarioAtual(const APromptAtual: string): string;
var
  I: Integer;
begin
  Result := '';

  if (APromptAtual <> '') and TryExtrairNomeUsuarioDoTexto(APromptAtual, Result) then
    Exit;

  for I := High(FHistorico) downto Low(FHistorico) do
    if (FHistorico[I].Role = mrUser) and TryExtrairNomeUsuarioDoTexto(FHistorico[I].Conteudo, Result) then
      Exit;
end;

function TYakkoChat.ChamadaUsuarioAtual(const APromptAtual: string): string;
var
  I: Integer;
begin
  Result := '';

  if (APromptAtual <> '') and TryExtrairChamadaUsuarioDoTexto(APromptAtual, Result) then
    Exit;

  for I := High(FHistorico) downto Low(FHistorico) do
    if (FHistorico[I].Role = mrUser) and TryExtrairChamadaUsuarioDoTexto(FHistorico[I].Conteudo, Result) then
      Exit;
end;

function TYakkoChat.ProjetoAtual(const APromptAtual: string): string;
var
  I: Integer;
  LTextoNormalizado: string;

  function TentarExtrairProjeto(const ATexto: string; out AProjeto: string): Boolean;
  var
    LNormalizado: string;
  begin
    AProjeto := '';
    LNormalizado := NormalizarParaComparacao(ATexto);
    Result := TryExtrairAposPadroes(ATexto, LNormalizado, [
      'projeto chamado ',
      'projeto ',
      'assistente local chamada ',
      'assistente local chamado '
    ], AProjeto);
    AProjeto := LimparProjetoCapturado(AProjeto);
    Result := Result and (AProjeto <> '') and (Length(AProjeto) <= 48);
  end;

begin
  Result := '';

  if (APromptAtual <> '') and TentarExtrairProjeto(APromptAtual, Result) then
    Exit;

  for I := High(FHistorico) downto Low(FHistorico) do
    if (FHistorico[I].Role = mrUser) and TentarExtrairProjeto(FHistorico[I].Conteudo, Result) then
      Exit;

  LTextoNormalizado := '';
  for I := High(FHistorico) downto Low(FHistorico) do
    if FHistorico[I].Role = mrUser then
    begin
      LTextoNormalizado := NormalizarParaComparacao(FHistorico[I].Conteudo);
      if Pos('hamonica', LTextoNormalizado) > 0 then
        Exit('Hamonica');
    end;
end;

function TYakkoChat.ConstruirMemoriaEstruturada(const APromptAtual: string): string;
var
  I: Integer;
  LMemoria: TStringList;
  LNome: string;
  LChamadaUsuario: string;
  LNomeAssistente: string;
  LProjeto: string;

  procedure AdicionarItemMemoria(const ATexto: string);
  var
    LItem: string;
  begin
    LItem := '- ' + UmaLinha(ATexto);
    if (LItem <> '- ') and (LMemoria.IndexOf(LItem) < 0) then
      LMemoria.Add(LItem);
    while LMemoria.Count > MEMORIA_ESTRUTURADA_MAX_LINHAS do
      LMemoria.Delete(3);
  end;

begin
  LMemoria := TStringList.Create;
  try
    LNome := NomeUsuarioAtual(APromptAtual);
    if LNome <> '' then
      LMemoria.Add('Nome do usuario: ' + LNome);

    LChamadaUsuario := ChamadaUsuarioAtual(APromptAtual);
    if LChamadaUsuario <> '' then
      LMemoria.Add('Forma preferida de chamar o usuario: ' + LChamadaUsuario);

    LNomeAssistente := NomeAssistenteAtual(APromptAtual);
    if LNomeAssistente <> '' then
      LMemoria.Add('Nome da assistente: ' + LNomeAssistente);

    LProjeto := ProjetoAtual(APromptAtual);
    if LProjeto <> '' then
      LMemoria.Add('Projeto atual: ' + LProjeto);

    for I := 0 to High(FHistorico) do
      if ((FHistorico[I].Role = mrUser) and MensagemMemoravel(FHistorico[I].Conteudo))
         or ((FHistorico[I].Role = mrSystem) and (Pos('Resumo automatico', FHistorico[I].Conteudo) > 0)) then
        AdicionarItemMemoria(FHistorico[I].Conteudo);

    if (APromptAtual <> '') and MensagemMemoravel(APromptAtual) then
      AdicionarItemMemoria(APromptAtual);

    Result := Trim(LMemoria.Text);
  finally
    LMemoria.Free;
  end;
end;

function TYakkoChat.PromptSistemaComMemoria(const APromptAtual: string): string;
var
  LMemoria: string;
begin
  LMemoria := ConstruirMemoriaEstruturada(APromptAtual);
  Result := FPromptSistema;
  if LMemoria <> '' then
    Result := Result + sLineBreak + sLineBreak
      + 'Memoria estruturada confirmada desta sessao:' + sLineBreak
      + LMemoria + sLineBreak
      + 'Use essa memoria como fonte prioritaria para nomes, preferencias, planos, regras e correcoes do usuario. '
      + 'Se houver conflito, o fato mais recente prevalece.';
end;

function TYakkoChat.TryResponderDeterministicamente(const APrompt: string; out AResposta: string): Boolean;
var
  PromptNormalizado: string;
  Nome: string;
  NomeUsuario: string;
  ChamadaUsuario: string;
  Projeto: string;
begin
  AResposta := '';
  PromptNormalizado := NormalizarParaComparacao(APrompt);

  if (Pos('meu nome', PromptNormalizado) > 0) and (Pos('qual', PromptNormalizado) > 0) and (Pos('seu', PromptNormalizado) > 0) then
  begin
    Nome := NomeAssistenteAtual('');
    NomeUsuario := NomeUsuarioAtual('');
    Projeto := ProjetoAtual('');

    if Nome <> '' then
      AResposta := 'Meu nome e ' + Nome + '.'
    else
      AResposta := 'Ainda nao tenho um nome definido.';

    if NomeUsuario <> '' then
      AResposta := AResposta + ' Voce e ' + NomeUsuario + '.';

    ChamadaUsuario := ChamadaUsuarioAtual('');
    if (ChamadaUsuario <> '') and (not SameText(ChamadaUsuario, NomeUsuario)) then
      AResposta := AResposta + ' Posso te chamar de ' + ChamadaUsuario + '.';

    if (Pos('projeto', PromptNormalizado) > 0) and (Projeto <> '') then
      AResposta := AResposta + ' O projeto e ' + Projeto + '.';

    Exit(True);
  end;

  NomeUsuario := '';
  ChamadaUsuario := '';
  if TryExtrairNomeUsuarioDoTexto(APrompt, NomeUsuario) then
    TryExtrairChamadaUsuarioDoTexto(APrompt, ChamadaUsuario)
  else if not TryExtrairChamadaUsuarioDoTexto(APrompt, ChamadaUsuario) then
    ChamadaUsuario := '';

  if (NomeUsuario <> '') or (ChamadaUsuario <> '') then
  begin
    if NomeUsuario <> '' then
      AResposta := 'Entendi. Seu nome e ' + NomeUsuario + '.'
    else
      AResposta := 'Entendi.';

    if ChamadaUsuario <> '' then
      AResposta := AResposta + ' Vou te chamar de ' + ChamadaUsuario + '.';

    Exit(True);
  end;

  if TryExtrairNomeAssistenteDoTexto(APrompt, Nome) then
  begin
    AResposta := 'Certo. Meu nome agora e ' + Nome + '.';
    Exit(True);
  end;

  if (Pos('a partir de agora', PromptNormalizado) > 0) and (Pos('seu nome', PromptNormalizado) > 0) then
  begin
    Nome := NomeAssistenteAtual(APrompt);
    NomeUsuario := NomeUsuarioAtual(APrompt);
    if Nome <> '' then
    begin
      AResposta := 'Certo. Meu nome agora e ' + Nome + '.';
      if NomeUsuario <> '' then
        AResposta := AResposta + ' Voce e ' + NomeUsuario + '.';
      Exit(True);
    end;
  end;

  if Pos('qual e o seu nome', PromptNormalizado) > 0 then
  begin
    Nome := NomeAssistenteAtual('');
    if Nome <> '' then
      AResposta := 'Meu nome e ' + Nome + '.'
    else
      AResposta := 'Ainda nao tenho um nome definido.';
    Exit(True);
  end;

  if Pos('qual e o seu', PromptNormalizado) > 0 then
  begin
    Nome := NomeAssistenteAtual('');
    NomeUsuario := NomeUsuarioAtual('');
    if Nome <> '' then
      AResposta := 'Meu nome e ' + Nome + '.'
    else
      AResposta := 'Ainda nao tenho um nome definido.';
    if NomeUsuario <> '' then
      AResposta := AResposta + ' Voce e ' + NomeUsuario + '.';
    Exit(True);
  end;

  if (Pos('qual e o meu nome', PromptNormalizado) > 0) or
     (Pos('qual era meu nome', PromptNormalizado) > 0) then
  begin
    NomeUsuario := NomeUsuarioAtual('');
    if NomeUsuario <> '' then
    begin
      AResposta := 'Seu nome e ' + NomeUsuario + '.';
      ChamadaUsuario := ChamadaUsuarioAtual('');
      if (ChamadaUsuario <> '') and (not SameText(ChamadaUsuario, NomeUsuario)) then
        AResposta := AResposta + ' Posso te chamar de ' + ChamadaUsuario + '.';
    end;
    Exit(AResposta <> '');
  end;

  if ((Pos('tentando melhorar', PromptNormalizado) > 0)
      or (Pos('queremos melhorar', PromptNormalizado) > 0)
      or (Pos('quer melhorar', PromptNormalizado) > 0))
     and (Pos('hamonica', PromptNormalizado) > 0) then
  begin
    AResposta := 'Estamos tentando melhorar a memoria longa da conversa no Hamonica.';
    Exit(True);
  end;

  if Pos('o que era mesmo', PromptNormalizado) > 0 then
  begin
    AResposta := EncontrarUltimaRespostaAssistente;
    Exit(AResposta <> '');
  end;

  Result := False;
end;

procedure TYakkoChat.SubstituirHistoricoPorResumo(const AResumo: string; AManterMensagensRecentes: Integer);
var
  LNovoHistorico: TArray<TLlamaMensagem>;
  LRecentes: TArray<TLlamaMensagem>;
  LRecentesInicio: Integer;
  LIndex: Integer;
begin
  if AManterMensagensRecentes < 0 then
    AManterMensagensRecentes := 0;

  if AManterMensagensRecentes > Length(FHistorico) then
    AManterMensagensRecentes := Length(FHistorico);

  LRecentesInicio := Length(FHistorico) - AManterMensagensRecentes;
  LRecentes := FatiaHistorico(LRecentesInicio, Length(FHistorico));

  SetLength(LNovoHistorico, Length(LRecentes) + 1);
  LNovoHistorico[0].Role := mrSystem;
  LNovoHistorico[0].Conteudo := 'Resumo automatico da conversa ate aqui:' + sLineBreak + Trim(AResumo);

  for LIndex := 0 to High(LRecentes) do
    LNovoHistorico[LIndex + 1] := LRecentes[LIndex];

  FHistorico := LNovoHistorico;
end;

function TYakkoChat.TentarAutoResumo(const AProximaPergunta: string; AMaxTokens: Integer): Boolean;
const
  PROMPT_SISTEMA_RESUMO =
    'Resuma memoria de conversa em portugues do Brasil. '
    + 'Responda em formato fixo e curto, com estes rÃ³tulos em linhas separadas: Objetivo, Regra, Fatos confirmados, Pendencias. '
    + 'Preserve termos exatos do usuario e nomes proprios exatamente como foram informados. '
    + 'Nao troque sinÃ´nimos por interpretacoes, nao invente, nao repita historico irrelevante e nao use markdown, JSON, listas numeradas, tags especiais ou <think>.';
  PROMPT_RESUMO =
    'Resuma o historico anterior de forma objetiva e literal, mantendo os fatos importantes com os termos exatos usados na conversa.';
var
  LHistoricoAntigo: TArray<TLlamaMensagem>;
  LHistoricoParaResumo: TArray<TLlamaMensagem>;
  LOrcamento: Integer;
  LResumo: string;
  LTokensProjetados: Integer;
  LRequest: TYakkoInferenceRequest;
  LAssembler: TYakkoContextAssembler;
  LAssembled: TYakkoAssembledContext;
  LOwnsAssembler: Boolean;
begin
  if not AutoResumoAtivo then
    Exit(False);

  if Assigned(FMemoryManager) then
  begin
    { Delega a estrategia principal de resumo para TYakkoMemoryManager. }
    Result := FMemoryManager.ResumirHistorico(
      FHistorico,
      AProximaPergunta,
      PromptSistemaComMemoria(AProximaPergunta),
      FAutoResumoContagem
    );
    Exit;
  end;

  Result := False;
  if Length(FHistorico) <= AutoResumoMensagensRecentes then
    Exit;

  LOrcamento := ContextoOrcamento;
  if LOrcamento <= 0 then
    Exit;

  LTokensProjetados := FGerador.EstimarTokensComMensagens(AProximaPergunta, PromptSistemaComMemoria(AProximaPergunta), FHistorico);
  if LTokensProjetados < Trunc(LOrcamento * AutoResumoLimiar) then
    Exit;

  LHistoricoParaResumo := FatiaHistorico(0, Length(FHistorico) - AutoResumoMensagensRecentes);
  if Length(LHistoricoParaResumo) = 0 then
    Exit;

  LHistoricoAntigo := FHistorico;
  LRequest := TYakkoInferenceRequest.Create;
  LOwnsAssembler := not Assigned(FContextAssembler);
  if LOwnsAssembler then
    LAssembler := TYakkoContextAssembler.Create(nil)
  else
    LAssembler := FContextAssembler;
  try
    LRequest.Mode := imSummarization;
    LRequest.Prompt := PROMPT_RESUMO;
    LRequest.SystemPrompt := PROMPT_SISTEMA_RESUMO;
    LRequest.Messages := LHistoricoParaResumo;
    LRequest.UseMemory := False;
    LRequest.UseTools := False;
    LRequest.UseReasoning := False;
    LRequest.MaxTokens := AutoResumoMaxTokens;
    if Assigned(FConfig) then
      LRequest.Temperature := FConfig.Sampling.Temperature;

    LAssembled := LAssembler.Assemble(LRequest);
    LResumo := Trim(FGerador.GerarComMensagens(
      LAssembled.Prompt,
      LAssembled.SystemPrompt,
      LAssembled.Messages,
      AutoResumoMaxTokens,
      nil
    ));
  finally
    LRequest.Free;
    if LOwnsAssembler then
      LAssembler.Free;
  end;

  if LResumo = '' then
    Exit;

  FHistorico := LHistoricoAntigo;
  SubstituirHistoricoPorResumo(LResumo, AutoResumoMensagensRecentes);
  Inc(FAutoResumoContagem);
  Result := True;
end;

function TYakkoChat.AutoResumoContagem: Integer;
begin
  Result := FAutoResumoContagem;
end;

function TYakkoChat.AutoResumoLimiar: Double;
begin
  if Assigned(FConfig) then
    Exit(FConfig.AutoResumoLimiar);
  Result := 0.70;
end;

function TYakkoChat.EstimarTokensSessao: Integer;
begin
  if Assigned(FMemoryManager) then
  begin
    { Estimativa de sessao delegada para MemoryManager quando disponivel. }
    if not FMemoryManager.ContextoValido then
      Exit(0);
    Exit(FMemoryManager.EstimarUsoContexto('', PromptSistemaComMemoria(''), FHistorico));
  end;

  if not PodeGerar then
    Exit(0);
  Result := FGerador.EstimarTokensComMensagens('', PromptSistemaComMemoria(''), FHistorico);
end;

procedure TYakkoChat.AdicionarMensagem(ARole: TLlamaMensagemRole; const AConteudo: string);
var
  LIndex: Integer;
begin
  if AConteudo = '' then
    Exit;

  LIndex := Length(FHistorico);
  SetLength(FHistorico, LIndex + 1);
  FHistorico[LIndex].Role := ARole;
  FHistorico[LIndex].Conteudo := AConteudo;
end;

procedure TYakkoChat.LimparHistorico;
begin
  SetLength(FHistorico, 0);
end;

procedure TYakkoChat.ReiniciarSessao;
begin
  LimparHistorico;
  FAutoResumoContagem := 0;

  if Assigned(FGerador) then
  begin
    try
      FGerador.ResetarContexto;
    except
      { Shutdown defensivo: limpar sessao nao deve falhar no fechamento parcial. }
    end;
  end;
end;

procedure TYakkoChat.RegistrarTroca(const APrompt, AResposta: string);
begin
  AdicionarMensagem(mrUser, APrompt);
  AdicionarMensagem(mrAssistant, AResposta);
end;

procedure TYakkoChat.AtualizarUltimaMensagemAssistente(const AConteudo: string);
var
  LCount: Integer;
  LIndex: Integer;
  LShiftIndex: Integer;
begin
  for LIndex := High(FHistorico) downto Low(FHistorico) do
    if FHistorico[LIndex].Role = mrAssistant then
    begin
      if AConteudo <> '' then
      begin
        FHistorico[LIndex].Conteudo := AConteudo;
        Exit;
      end;

      LCount := Length(FHistorico);
      for LShiftIndex := LIndex to LCount - 2 do
        FHistorico[LShiftIndex] := FHistorico[LShiftIndex + 1];
      SetLength(FHistorico, LCount - 1);
      Exit;
    end;
end;

function TYakkoChat.QuantidadeMensagens: Integer;
begin
  Result := Length(FHistorico);
end;

function TYakkoChat.Perguntar(const APrompt: string; AMaxTokens: Integer; AAoReceberTexto: TLlamaTextoParcialProc): string;
var
  LRequest: TYakkoInferenceRequest;
  LAssembler: TYakkoContextAssembler;
  LAssembled: TYakkoAssembledContext;
  LOwnsAssembler: Boolean;
begin
  EnsureConfigurado;

  if TryResponderDeterministicamente(APrompt, Result) then
  begin
    RegistrarTroca(APrompt, Result);
    Exit;
  end;

  if Assigned(FMemoryManager) then
    FMemoryManager.AjustarContexto(FHistorico, APrompt, PromptSistemaComMemoria(APrompt), AMaxTokens, FAutoResumoContagem)
  else
    TentarAutoResumo(APrompt, AMaxTokens);

  LRequest := TYakkoInferenceRequest.Create;
  LOwnsAssembler := not Assigned(FContextAssembler);
  if LOwnsAssembler then
    LAssembler := TYakkoContextAssembler.Create(nil)
  else
    LAssembler := FContextAssembler;
  try
    LRequest.Mode := imChat;
    LRequest.Prompt := APrompt;
    LRequest.SystemPrompt := PromptSistemaComMemoria(APrompt);
    LRequest.Messages := FHistorico;
    LRequest.UseMemory := True;
    LRequest.UseTools := Assigned(FGerador) and Assigned(FGerador.ToolManager);
    LRequest.UseReasoning := Assigned(FConfig) and FConfig.UseThinkMode;
    LRequest.MaxTokens := AMaxTokens;
    if Assigned(FConfig) then
      LRequest.Temperature := FConfig.Sampling.Temperature;

    LAssembled := LAssembler.Assemble(LRequest);
    Result := FGerador.GerarComMensagens(
      LAssembled.Prompt,
      LAssembled.SystemPrompt,
      LAssembled.Messages,
      AMaxTokens,
      AAoReceberTexto
    );
  finally
    LRequest.Free;
    if LOwnsAssembler then
      LAssembler.Free;
  end;

  if (not Assigned(FConfig)) or FConfig.SanitizeOutput then
    Result := SanitizeModelResponseText(Result);
  RegistrarTroca(APrompt, Result);
end;

initialization
  System.Classes.RegisterClass(TYakkoChat);

end.
