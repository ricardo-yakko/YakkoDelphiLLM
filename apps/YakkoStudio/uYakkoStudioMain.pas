unit uYakkoStudioMain;

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.IOUtils,
  System.Variants,
  System.Classes,
  System.StrUtils,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Dialogs,
  uYakkoChatComponent,
  uYakkoContextoComponent, uYakkoLLM, uYakkoDllComponent, uYakkoEngineComponent,
  uYakkoFullExportsComponent, uYakkoGeradorComponent, uYakkoModeloComponent,
  uYakkoAgenteComponent, uYakkoToolManagerComponent, uYakkoInferenceConfigComponent,
  uYakkoGenerationEventsComponent, Vcl.StdCtrls, uYakkoStudioRagModal;

type
  TToolHoraAtual = class(TYakkoTool)
  public
    function Nome: string; override;
    function Descricao: string; override;
    function Execute(const AParametrosJson: string): string; override;
  end;

  TYakkoStudioMainForm = class(TForm)
    BtnInicializar: TButton;
    BtnFinalizar: TButton;
    BtnPerguntarAgente: TButton;
    BtnPerguntarChat: TButton;
    BtnCancelar: TButton;
    BtnReiniciarSessao: TButton;
    BtnTestarTool: TButton;
    BtnSimularConversa: TButton;
    BtnRagModal: TButton;
    CkUseThink: TCheckBox;
    CkSanitize: TCheckBox;
    CbTemplatePersona: TComboBox;
    EdDelayMs: TEdit;
    EdInteracoes: TEdit;
    EdMaxTokens: TEdit;
    EdNCtx: TEdit;
    EdTemperatura: TEdit;
    EdTopK: TEdit;
    EdTopP: TEdit;
    LbMaxTokens: TLabel;
    LbNCtx: TLabel;
    LbPrompt: TLabel;
    LbSaida: TLabel;
    LbSistema: TLabel;
    LbStatus: TLabel;
    LbTemplatePersona: TLabel;
    LbDelayMs: TLabel;
    LbInteracoes: TLabel;
    LbTemperatura: TLabel;
    LbTopK: TLabel;
    LbTopP: TLabel;
    MemoPrompt: TMemo;
    MemoSaida: TMemo;
    MemoSistema: TMemo;
    YakkoAgente1: TYakkoAgente;
    YakkoModelo1: TYakkoModelo;
    YakkoGerador1: TYakkoGerador;
    YakkoEngine1: TYakkoEngine;
    YakkoDll1: TYakkoDll;
    YakkoPaths1: TYakkoPaths;
    YakkoContexto1: TYakkoContexto;
    YakkoChat1: TYakkoChat;
    YakkoFullExports1: TYakkoFullExports;
    procedure BtnCancelarClick(Sender: TObject);
    procedure BtnFinalizarClick(Sender: TObject);
    procedure BtnInicializarClick(Sender: TObject);
    procedure BtnPerguntarAgenteClick(Sender: TObject);
    procedure BtnPerguntarChatClick(Sender: TObject);
    procedure BtnReiniciarSessaoClick(Sender: TObject);
    procedure BtnRagModalClick(Sender: TObject);
    procedure BtnSimularConversaClick(Sender: TObject);
    procedure BtnTestarToolClick(Sender: TObject);
    procedure CbTemplatePersonaChange(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormCreate(Sender: TObject);
  private
    FToolRegistrada: Boolean;
    FSilenciarEventosGeracao: Boolean;
    function StrToIntPadrao(const AValue: string; ADefault: Integer): Integer;
    function StrToFloatPadrao(const AValue: string; ADefault: Double): Double;
    procedure AplicarConfiguracaoUI;
    procedure ConectarEventos;
    procedure GarantirInicializado;
    function GetCmdValue(const AName, ADefault: string): string;
    procedure RunCliRagTestIfRequested;
    function GetTemplateSistemaSelecionado: string;
    procedure AplicarTemplateSelecionado;
    procedure AppendSaida(const AText: string);
    procedure SetStatus(const AText: string);
  public
  end;

var
  Form1: TYakkoStudioMainForm;

procedure ExecuteCliRagFromParams;

implementation

{$R *.dfm}

procedure CliWriteLine(const AText: string);
var
  LHandle: THandle;
  LWritten: DWORD;
  LText: string;
begin
  LHandle := GetStdHandle(STD_OUTPUT_HANDLE);
  if LHandle = INVALID_HANDLE_VALUE then
    Exit;

  LText := AText + sLineBreak;
  WriteConsoleW(LHandle, PChar(LText), Length(LText), LWritten, nil);
end;

{ TToolHoraAtual }

function TToolHoraAtual.Nome: string;
begin
  Result := 'hora_atual';
end;

function TYakkoStudioMainForm.GetCmdValue(const AName, ADefault: string): string;
var
  I: Integer;
  LPrefix: string;
  LParam: string;
begin
  Result := ADefault;
  LPrefix := '--' + LowerCase(AName) + '=';

  for I := 1 to ParamCount do
  begin
    LParam := Trim(ParamStr(I));
    if Pos(LPrefix, LowerCase(LParam)) = 1 then
    begin
      Result := Trim(Copy(LParam, Length(LPrefix) + 1, MaxInt));
      if (Length(Result) >= 2) and (Result[1] = '"') and (Result[Length(Result)] = '"') then
        Result := Copy(Result, 2, Length(Result) - 2);
      Exit(Result);
    end;
  end;
end;
function TToolHoraAtual.Descricao: string;
begin
  Result := 'Retorna data e hora atuais do sistema.';
end;

function TToolHoraAtual.Execute(const AParametrosJson: string): string;
begin
  Result := DateTimeToStr(Now);
end;

{ TYakkoStudioMainForm }

procedure TYakkoStudioMainForm.FormCreate(Sender: TObject);
begin
  FToolRegistrada := False;
  FSilenciarEventosGeracao := False;
  EdNCtx.Text := '4096';
  EdMaxTokens.Text := '512';
  EdTemperatura.Text := '0.7';
  EdTopK.Text := '40';
  EdTopP.Text := '0.95';
  EdInteracoes.Text := '4';
  EdDelayMs.Text := '800';
  CbTemplatePersona.Items.Clear;
  CbTemplatePersona.Items.Add('Tecnico de Informatica');
  CbTemplatePersona.Items.Add('Medico Clinico');
  CbTemplatePersona.ItemIndex := 0;
  CkUseThink.Checked := False;
  CkSanitize.Checked := True;
  MemoSistema.Lines.Text := GetTemplateSistemaSelecionado;
  MemoPrompt.Lines.Text := 'Explique rapidamente como usar TYakkoEngine com TYakkoChat.';

  SetStatus('Pronto para inicializar.');
  ConectarEventos;
end;

procedure TYakkoStudioMainForm.RunCliRagTestIfRequested;
var
  LFiles: string;
  LQuestion: string;
  LTopK: Integer;
  LMaxTokens: Integer;
  LResposta: string;
  LOutFile: string;
  LDllPath: string;
  LModelPath: string;
  LEmbeddingModelPath: string;
begin
  if not AttachConsole(DWORD(-1)) then
    AllocConsole;

  try
    CliWriteLine('Modo CLI RAG iniciado...');

    LFiles := GetCmdValue('files', '');
    LQuestion := GetCmdValue('q', 'Resuma os pontos principais dos arquivos.');
    LTopK := StrToIntPadrao(GetCmdValue('topk', '4'), 4);
    LMaxTokens := StrToIntPadrao(GetCmdValue('maxtokens', '1024'), 1024);
    LOutFile := GetCmdValue('out', TPath.Combine(ExtractFilePath(ParamStr(0)), 'rag_cli_output.txt'));
    LDllPath := GetCmdValue('dll', '');
    LModelPath := GetCmdValue('model', '');
    LEmbeddingModelPath := GetCmdValue('embedding-model', GetCmdValue('embed-model', ''));

    if Trim(LDllPath) <> '' then
    begin
      YakkoModelo1.DllPath := LDllPath;
      YakkoPaths1.Dlls := LDllPath;
      YakkoFullExports1.DllPath := LDllPath;
    end;

    if Trim(LModelPath) <> '' then
      YakkoModelo1.ModelPath := LModelPath;

    if Trim(LFiles) = '' then
      raise Exception.Create('Informe --files=arquivo1;arquivo2 para usar o modo --rag-test.');

    AplicarConfiguracaoUI;
    if not FToolRegistrada then
    begin
      YakkoEngine1.ToolManager.RegistrarTool(TToolHoraAtual.Create);
      FToolRegistrada := True;
    end;

    CliWriteLine('Inicializando engine...');
    CliWriteLine('Modelo path: ' + YakkoModelo1.ModelPath);
    CliWriteLine('DLL path: ' + YakkoModelo1.DllPath);
    if Trim(LEmbeddingModelPath) <> '' then
      CliWriteLine('Embedding model path: ' + LEmbeddingModelPath);

    try
      YakkoAgente1.InitializeAgent;
    except
      on E: Exception do
        raise Exception.Create('Erro na inicializacao do agente: ' + E.Message);
    end;

    CliWriteLine('IsInitialized apos init: ' + BoolToStr(YakkoAgente1.IsInitialized, True));
    if not YakkoAgente1.IsInitialized then
      raise Exception.Create('Falha ao inicializar o engine para RAG CLI.');

    if not TYakkoStudioRagModalForm.ExecuteRagOnce(YakkoEngine1, LFiles, LQuestion, LTopK, LMaxTokens, LResposta, LEmbeddingModelPath) then
      raise Exception.Create('Nao foi possivel gerar resposta RAG.');

    TFile.WriteAllText(LOutFile, LResposta, TEncoding.UTF8);

    CliWriteLine('--- RESPOSTA RAG ---');
    CliWriteLine(LResposta);
    CliWriteLine('--------------------');
    CliWriteLine('Arquivo de saida: ' + LOutFile);
    Halt(0);
  except
    on E: Exception do
    begin
      if LOutFile <> '' then
      begin
        try
          ForceDirectories(ExtractFilePath(LOutFile));
          TFile.WriteAllText(LOutFile, 'ERRO: ' + E.Message, TEncoding.UTF8);
        except
        end;
      end;
      CliWriteLine('ERRO: ' + E.Message);
      Halt(1);
    end;
  end;
end;

function TYakkoStudioMainForm.GetTemplateSistemaSelecionado: string;
begin
  if CbTemplatePersona.ItemIndex = 1 then
  begin
    Result :=
      'Voce e um medico clinico experiente. ' +
      'Explique em linguagem simples, com foco em orientacao geral e sinais de alerta. ' +
      'Nao forneca diagnostico definitivo sem exames e recomende procurar atendimento quando houver risco.';
    Exit;
  end;

  Result :=
    'Voce e um tecnico em informatica experiente. ' +
    'Explique passo a passo, de forma objetiva, priorizando diagnostico e solucoes praticas.';
end;

function TYakkoStudioMainForm.StrToIntPadrao(const AValue: string; ADefault: Integer): Integer;
begin
  if not TryStrToInt(Trim(AValue), Result) then
    Result := ADefault;
end;

function TYakkoStudioMainForm.StrToFloatPadrao(const AValue: string; ADefault: Double): Double;
var
  LText: string;
begin
  LText := Trim(AValue);
  if not TryStrToFloat(LText, Result) then
    if not TryStrToFloat(StringReplace(LText, '.', ',', [rfReplaceAll]), Result) then
      if not TryStrToFloat(StringReplace(LText, ',', '.', [rfReplaceAll]), Result) then
        Result := ADefault;
end;

procedure TYakkoStudioMainForm.SetStatus(const AText: string);
begin
  LbStatus.Caption := 'Status: ' + AText;
end;

procedure TYakkoStudioMainForm.AppendSaida(const AText: string);
begin
  if AText = '' then
    Exit;

  MemoSaida.SelStart := Length(MemoSaida.Text);
  MemoSaida.SelLength := 0;
  MemoSaida.SelText := AText;
  MemoSaida.Perform(EM_SCROLLCARET, 0, 0);
end;

procedure TYakkoStudioMainForm.ConectarEventos;
begin
  YakkoGerador1.Events.OnToken :=
    procedure(const ATokenText: string)
    begin
      if FSilenciarEventosGeracao then
        Exit;
      AppendSaida(ATokenText);
    end;

  YakkoGerador1.Events.OnFinished :=
    procedure(const ATextoFinal: string; const AStats: TYakkoGenerationStats)
    begin
      if FSilenciarEventosGeracao then
        Exit;
      AppendSaida(sLineBreak + sLineBreak +
        Format('[fim] prompt=%d, gerados=%d, tps=%.2f',
          [AStats.PromptTokens, AStats.GeneratedTokens, AStats.TokensPerSecond]) +
        sLineBreak);
      SetStatus('Geracao finalizada.');
    end;

  YakkoGerador1.Events.OnCancelled :=
    procedure(const ATextoParcial: string; const AStats: TYakkoGenerationStats)
    begin
      if FSilenciarEventosGeracao then
        Exit;
      AppendSaida(sLineBreak + '[cancelado]' + sLineBreak);
      SetStatus('Geracao cancelada.');
    end;

  YakkoGerador1.Events.OnError :=
    procedure(const AMensagem: string)
    begin
      if FSilenciarEventosGeracao then
        Exit;
      AppendSaida(sLineBreak + '[erro] ' + AMensagem + sLineBreak);
      SetStatus('Erro em geracao.');
    end;

  YakkoGerador1.Events.OnToolCall :=
    procedure(const ARawPayload: string)
    begin
      if FSilenciarEventosGeracao then
        Exit;
      AppendSaida(sLineBreak + '[tool] ' + ARawPayload + sLineBreak);
    end;
end;

procedure TYakkoStudioMainForm.AplicarConfiguracaoUI;
begin
  YakkoAgente1.Engine := YakkoEngine1;
  YakkoAgente1.OutputMemo := MemoSaida;
  AplicarTemplateSelecionado;

  YakkoAgente1.NCtxPadrao := StrToIntPadrao(EdNCtx.Text, 4096);
  YakkoAgente1.MaxTokensPadrao := StrToIntPadrao(EdMaxTokens.Text, 512);
  YakkoAgente1.Temperatura := StrToFloatPadrao(EdTemperatura.Text, 0.7);
  YakkoAgente1.TopK := StrToIntPadrao(EdTopK.Text, 40);
  YakkoAgente1.TopP := StrToFloatPadrao(EdTopP.Text, 0.95);
  YakkoAgente1.UseThinkMode := CkUseThink.Checked;
  YakkoAgente1.SanitizeOutput := CkSanitize.Checked;

  YakkoEngine1.Config.AutoResumo := True;
  YakkoEngine1.Config.AutoResumoLimiar := 0.70;
  YakkoEngine1.Config.AutoResumoMaxTokens := 256;
  YakkoEngine1.Config.AutoResumoMensagensRecentes := 4;
end;

procedure TYakkoStudioMainForm.AplicarTemplateSelecionado;
var
  LSistema: string;
begin
  LSistema := GetTemplateSistemaSelecionado;
  MemoSistema.Lines.Text := LSistema;
  YakkoAgente1.SystemPrompt := LSistema;
  YakkoEngine1.Chat.PromptSistema := LSistema;
end;

procedure TYakkoStudioMainForm.GarantirInicializado;
begin
  if not YakkoAgente1.IsInitialized then
    BtnInicializarClick(nil);
end;

procedure TYakkoStudioMainForm.BtnInicializarClick(Sender: TObject);
begin
  try
    AplicarConfiguracaoUI;
    if not FToolRegistrada then
    begin
      YakkoEngine1.ToolManager.RegistrarTool(TToolHoraAtual.Create);
      FToolRegistrada := True;
    end;

    YakkoAgente1.InitializeAgent;
    SetStatus('Inicializado.');
  except
    on E: Exception do
      SetStatus('Falha ao inicializar: ' + E.Message);
  end;
end;

procedure TYakkoStudioMainForm.BtnFinalizarClick(Sender: TObject);
begin
  try
    YakkoAgente1.FinalizeAgent;
    SetStatus('Finalizado.');
  except
    on E: Exception do
      SetStatus('Falha ao finalizar: ' + E.Message);
  end;
end;

procedure TYakkoStudioMainForm.BtnPerguntarAgenteClick(Sender: TObject);
var
  LResposta: string;
begin
  GarantirInicializado;
  AplicarTemplateSelecionado;
  MemoSaida.Clear;
  SetStatus('Gerando via Agente...');

  LResposta := YakkoAgente1.Ask(MemoPrompt.Text, StrToIntPadrao(EdMaxTokens.Text, 512));
  AppendSaida(sLineBreak + sLineBreak + '[agente] resposta final:' + sLineBreak + LResposta + sLineBreak);
end;

procedure TYakkoStudioMainForm.BtnPerguntarChatClick(Sender: TObject);
var
  LResposta: string;
begin
  GarantirInicializado;
  AplicarTemplateSelecionado;
  MemoSaida.Clear;
  SetStatus('Gerando via Chat...');
  LResposta := YakkoEngine1.Chat.Perguntar(
    MemoPrompt.Text,
    StrToIntPadrao(EdMaxTokens.Text, 512),
    procedure(const AToken: string)
    begin
      AppendSaida(AToken);
    end
  );

  AppendSaida(sLineBreak + sLineBreak + '[chat] resposta final:' + sLineBreak + LResposta + sLineBreak);
end;

procedure TYakkoStudioMainForm.BtnCancelarClick(Sender: TObject);
begin
  YakkoEngine1.Gerador.CancelarGeracao;
  SetStatus('Cancelamento solicitado.');
end;

procedure TYakkoStudioMainForm.BtnReiniciarSessaoClick(Sender: TObject);
begin
  GarantirInicializado;
  YakkoEngine1.Chat.ReiniciarSessao;
  SetStatus('Sessao reiniciada.');
end;

procedure TYakkoStudioMainForm.BtnTestarToolClick(Sender: TObject);
var
  LToolCall: TYakkoToolCall;
  LToolResult: TYakkoToolResult;
begin
  GarantirInicializado;

  if YakkoEngine1.ToolManager.TryProcessRawPayload('{"name":"hora_atual","arguments":{}}', LToolCall, LToolResult) then
  begin
    if LToolResult.Sucesso then
      AppendSaida(sLineBreak + '[tool-test] ' + LToolCall.Nome + ' => ' + LToolResult.ResultadoTexto + sLineBreak)
    else
      AppendSaida(sLineBreak + '[tool-test] erro: ' + LToolResult.Erro + sLineBreak);
  end
  else
    AppendSaida(sLineBreak + '[tool-test] payload nao reconhecido.' + sLineBreak);
end;

procedure TYakkoStudioMainForm.BtnRagModalClick(Sender: TObject);
var
  LRagForm: TYakkoStudioRagModalForm;
begin
  GarantirInicializado;
  LRagForm := TYakkoStudioRagModalForm.Create(Self);
  try
    LRagForm.Engine := YakkoEngine1;
    LRagForm.ShowModal;
  finally
    LRagForm.Free;
  end;
end;

procedure TYakkoStudioMainForm.BtnSimularConversaClick(Sender: TObject);
const
  CPromptVendedor =
    'Voce e um vendedor das Casas Bahia. ' +
    'Seu objetivo e entender a necessidade do cliente e vender uma TV adequada com argumentos claros. ' +
    'Responda sempre em no maximo 2 frases curtas, sem listas, sem markup e sem repetir contrato completo.';
  CPromptComprador =
    'Voce e um comprador interessado em comprar uma TV. ' +
    'Faca perguntas realistas e curtas sobre preco, tamanho, imagem, garantia e pagamento. ' +
    'Responda sempre em no maximo 2 frases, sem listas e sem repetir texto longo.';
var
  LInteracoes: Integer;
  LDelayMs: Integer;
  LMaxTokens: Integer;
  LAutoResumoAnterior: Boolean;
  I: Integer;
  LContextoRodada: string;
  LPerguntaComprador: string;
  LRespostaVendedor: string;
  LRespostaComprador: string;
begin
  GarantirInicializado;
  LInteracoes := StrToIntPadrao(EdInteracoes.Text, 4);
  if LInteracoes < 1 then
    LInteracoes := 1;

  LDelayMs := StrToIntPadrao(EdDelayMs.Text, 800);
  if LDelayMs < 0 then
    LDelayMs := 0;

  LMaxTokens := StrToIntPadrao(EdMaxTokens.Text, 128);
  if LMaxTokens < 64 then
    LMaxTokens := 64
  else if LMaxTokens > 128 then
    LMaxTokens := 128;

  MemoSaida.Clear;
  LContextoRodada :=
    'Cliente quer TV para sala media, 4K Smart, orcamento ate R$ 3.000.';
  LPerguntaComprador := 'Oi, quero uma TV 4K Smart para sala media ate R$ 3.000. Qual opcao voce sugere?';

  LAutoResumoAnterior := YakkoEngine1.Config.AutoResumo;
  YakkoEngine1.Config.AutoResumo := False;
  FSilenciarEventosGeracao := True;
  try
    SetStatus('Simulando conversa comprador x vendedor (modo curto)...');
    for I := 1 to LInteracoes do
    begin
      AppendSaida(Format(sLineBreak + '[Interacao %d]' + sLineBreak, [I]));

      YakkoEngine1.Chat.ReiniciarSessao;
      YakkoEngine1.Chat.PromptSistema := CPromptVendedor;
      LRespostaVendedor := YakkoEngine1.Chat.Perguntar(
        'Contexto atual: ' + LContextoRodada + sLineBreak +
        'Mensagem do comprador: ' + LPerguntaComprador + sLineBreak +
        'Responda de forma comercial objetiva em ate 2 frases curtas.',
        LMaxTokens
      );
      LRespostaVendedor := YakkoEngine1.Chat.SanitizeModelResponseText(LRespostaVendedor);
      LRespostaVendedor := StringReplace(LRespostaVendedor, '[Nome do vendedor]', 'Vendedor Casas Bahia', [rfReplaceAll, rfIgnoreCase]);
      AppendSaida('[Vendedor] ' + LRespostaVendedor + sLineBreak);

      YakkoEngine1.Chat.ReiniciarSessao;
      YakkoEngine1.Chat.PromptSistema := CPromptComprador;
      LRespostaComprador := YakkoEngine1.Chat.Perguntar(
        'Contexto atual: ' + LContextoRodada + sLineBreak +
        'Oferta do vendedor: ' + LRespostaVendedor + sLineBreak +
        'Responda como comprador em ate 2 frases, com duvida ou contraproposta.',
        LMaxTokens
      );
      LRespostaComprador := YakkoEngine1.Chat.SanitizeModelResponseText(LRespostaComprador);
      AppendSaida('[Comprador] ' + LRespostaComprador + sLineBreak);

      LContextoRodada := RightStr(
        LContextoRodada + ' Vendedor: ' + LRespostaVendedor + ' Comprador: ' + LRespostaComprador,
        1200
      );
      LPerguntaComprador := LRespostaComprador;

      if (LDelayMs > 0) and (I < LInteracoes) then
      begin
        SetStatus(Format('Aguardando %d ms para proxima interacao...', [LDelayMs]));
        Application.ProcessMessages;
        Sleep(LDelayMs);
        Application.ProcessMessages;
      end;
    end;

    SetStatus(Format('Simulacao finalizada com %d interacoes (modo curto).', [LInteracoes]));
  finally
    FSilenciarEventosGeracao := False;
    YakkoEngine1.Config.AutoResumo := LAutoResumoAnterior;
  end;
end;

procedure TYakkoStudioMainForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  YakkoAgente1.FinalizeAgent;
end;

procedure TYakkoStudioMainForm.CbTemplatePersonaChange(Sender: TObject);
begin
  AplicarTemplateSelecionado;
  SetStatus('Template aplicado: ' + CbTemplatePersona.Text);
end;

procedure ExecuteCliRagFromParams;
begin
  if Form1 = nil then
    Form1 := TYakkoStudioMainForm.Create(nil);
  Form1.RunCliRagTestIfRequested;
end;

end.




