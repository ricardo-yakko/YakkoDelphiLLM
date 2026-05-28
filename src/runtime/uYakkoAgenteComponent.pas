unit uYakkoAgenteComponent;

{ Componente de alto nivel para operacao do agente.
  Responsabilidades:
  - ciclo de vida (initialize/finalize)
  - aplicacao de configuracao em runtime
  - interface de pergunta/resposta para UI
  Ownership:
  - referencias para Engine/Modelo/Paths sao borrowed. }

interface

uses
  Winapi.Messages,
  System.Classes,
  System.SysUtils,
  System.IOUtils,
  Vcl.StdCtrls,
  uYakkoLLM,
  uYakkoModeloComponent,
  uYakkoEngineComponent,
  uYakkoGeradorComponent;

type
  TYakkoTextoEvent = procedure(Sender: TObject; const ATexto: string) of object;
  TYakkoErroEvent = procedure(Sender: TObject; const AMensagem: string; var ARaiseException: Boolean) of object;

  TYakkoAgente = class(TComponent)
  private const
    DEFAULT_N_CTX = 4096;
    DEFAULT_MAX_TOKENS = 4096;
    DEFAULT_GPU_LAYERS = 999;
  private
    FActive: Boolean;
    FAutoInitialize: Boolean;
    FPaths: TYakkoPaths;
    FModelo: TYakkoModelo;
    FSystemPrompt: string;
    FUseThinkMode: Boolean;
    FShowThinkBlocks: Boolean;
    FSanitizeOutput: Boolean;

    FNCtxPadrao: Cardinal;
    FMaxTokensPadrao: Integer;
    FGpuLayers: Integer;
    FTemperatura: Single;
    FTopK: Integer;
    FTopP: Single;

    FEngine: TYakkoEngine;

    FOnInitialized: TNotifyEvent;
    FOnFinalized: TNotifyEvent;
    FOnBeforeAsk: TYakkoTextoEvent;
    FOnAfterAsk: TYakkoTextoEvent;
    FOnPartialText: TYakkoTextoEvent;
    FOnError: TYakkoErroEvent;
    FOutputMemo: TMemo;

    procedure SetEngine(const Value: TYakkoEngine);
    procedure SetModelo(const Value: TYakkoModelo);
    procedure SetPaths(const Value: TYakkoPaths);

    procedure SetActive(const Value: Boolean);
    procedure SetNCtxPadrao(const Value: Cardinal);
    procedure SetMaxTokensPadrao(const Value: Integer);
    procedure SetGpuLayers(const Value: Integer);
    procedure SetTemperatura(const Value: Single);
    procedure SetTopK(const Value: Integer);
    procedure SetTopP(const Value: Single);
    procedure SetUseThinkMode(const Value: Boolean);
    procedure SetShowThinkBlocks(const Value: Boolean);
    procedure SetSanitizeOutput(const Value: Boolean);

    procedure DoError(const AMessage: string);
    procedure ApplyRuntimeConfig;

    function ResolveAssociatedModelPath: string;
    function ResolveAssociatedGpuLayers: Integer;

    function ResolveModelPath: string;

    function StripTaggedBlock(const AValue, AOpenTag, ACloseTag: string): string;
    function SanitizeModelResponseText(const AValue: string): string;
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure InitializeAgent;
    procedure FinalizeAgent;
    procedure RestartSession;
    procedure SetSystemPrompt(const APrompt: string);

    function Ask(const APrompt: string; AMaxTokens: Integer = -1): string;
    function IsInitialized: Boolean;

    property Paths: TYakkoPaths read FPaths write SetPaths;
    property Modelo: TYakkoModelo read FModelo write SetModelo;
  published
    property Active: Boolean read FActive write SetActive default False;
    property AutoInitialize: Boolean read FAutoInitialize write FAutoInitialize default False;
    property Engine: TYakkoEngine read FEngine write SetEngine;
    property OutputMemo: TMemo read FOutputMemo write FOutputMemo;
    property SystemPrompt: string read FSystemPrompt write FSystemPrompt;
    property UseThinkMode: Boolean read FUseThinkMode write SetUseThinkMode default False;
    property ShowThinkBlocks: Boolean read FShowThinkBlocks write SetShowThinkBlocks default False;
    property SanitizeOutput: Boolean read FSanitizeOutput write SetSanitizeOutput default True;

    property NCtxPadrao: Cardinal read FNCtxPadrao write SetNCtxPadrao default DEFAULT_N_CTX;
    property MaxTokensPadrao: Integer read FMaxTokensPadrao write SetMaxTokensPadrao default DEFAULT_MAX_TOKENS;
    property GpuLayers: Integer read FGpuLayers write SetGpuLayers default DEFAULT_GPU_LAYERS;
    property Temperatura: Single read FTemperatura write SetTemperatura;
    property TopK: Integer read FTopK write SetTopK default 64;
    property TopP: Single read FTopP write SetTopP;

    property OnInitialized: TNotifyEvent read FOnInitialized write FOnInitialized;
    property OnFinalized: TNotifyEvent read FOnFinalized write FOnFinalized;
    property OnBeforeAsk: TYakkoTextoEvent read FOnBeforeAsk write FOnBeforeAsk;
    property OnAfterAsk: TYakkoTextoEvent read FOnAfterAsk write FOnAfterAsk;
    property OnPartialText: TYakkoTextoEvent read FOnPartialText write FOnPartialText;
    property OnError: TYakkoErroEvent read FOnError write FOnError;
  end;

implementation

constructor TYakkoAgente.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FAutoInitialize := False;
  FSanitizeOutput := True;
  FPaths := nil;
  FModelo := nil;
  FEngine := nil;
  FOutputMemo := nil;

  FNCtxPadrao := DEFAULT_N_CTX;
  FMaxTokensPadrao := DEFAULT_MAX_TOKENS;
  FGpuLayers := DEFAULT_GPU_LAYERS;
  FTemperatura := 0.0;
  FTopK := 64;
  FTopP := 0.95;
end;

destructor TYakkoAgente.Destroy;
begin
  try
    FinalizeAgent;
  finally
    inherited Destroy;
  end;
end;

procedure TYakkoAgente.Loaded;
begin
  inherited Loaded;
  if FAutoInitialize and (not (csDesigning in ComponentState)) then
    SetActive(True);
end;

procedure TYakkoAgente.DoError(const AMessage: string);
var
  LRaise: Boolean;
begin
  LRaise := True;
  if Assigned(FOnError) then
    FOnError(Self, AMessage, LRaise);

  if LRaise then
    raise Exception.Create(AMessage);
end;

function TYakkoAgente.ResolveModelPath: string;
begin
  Result := ResolveAssociatedModelPath;
  if Result <> '' then
    Exit;

  DoError('Modelo principal nao configurado. Configure TYakkoModelo.ModelPath ou TYakkoPaths.Modelos.');
end;

function TYakkoAgente.ResolveAssociatedModelPath: string;
begin
  Result := '';

  if Assigned(FEngine) and Assigned(FEngine.Modelo) then
    Result := Trim(FEngine.Modelo.ModelPath);
  if (Result = '') and Assigned(FModelo) then
    Result := Trim(FModelo.ModelPath);
end;

function TYakkoAgente.ResolveAssociatedGpuLayers: Integer;
begin
  Result := FGpuLayers;
  if Assigned(FEngine) and Assigned(FEngine.Modelo) then
    Result := FEngine.Modelo.GpuLayersPadrao
  else if Assigned(FModelo) then
    Result := FModelo.GpuLayersPadrao;
end;

procedure TYakkoAgente.ApplyRuntimeConfig;
begin
  if not Assigned(FEngine) or not Assigned(FEngine.Contexto) or not Assigned(FEngine.Modelo)
    or not Assigned(FEngine.ChatTemplate) or not Assigned(FEngine.Tokenizer)
    or not Assigned(FEngine.Gerador) or not Assigned(FEngine.Chat) then
    DoError('Engine incompleto. Conecte Modelo/ChatTemplate/Tokenizer/Contexto/Gerador/Chat no TYakkoEngine.');

  FEngine.Config.NCtx := FNCtxPadrao;
  FEngine.Config.MaxTokens := FMaxTokensPadrao;
  FEngine.Config.Sampling.Temperature := FTemperatura;
  FEngine.Config.Sampling.TopK := FTopK;
  FEngine.Config.Sampling.TopP := FTopP;
  FEngine.Config.UseThinkMode := FUseThinkMode;
  FEngine.Config.ShowThinkBlocks := FShowThinkBlocks;
  FEngine.Config.SanitizeOutput := FSanitizeOutput;

  FEngine.Contexto.NCtxPadrao := FEngine.Config.NCtx;
  FEngine.Modelo.GpuLayersPadrao := ResolveAssociatedGpuLayers;

  if Trim(FSystemPrompt) <> '' then
    FEngine.Chat.PromptSistema := FSystemPrompt;
end;

procedure TYakkoAgente.InitializeAgent;
begin
  if FActive then
    Exit;

  try
    if not Assigned(FEngine) then
      DoError('TYakkoEngine nao associado. Defina a propriedade Engine do agente.');

    if not Assigned(FEngine.Modelo) then
      DoError('Engine.Modelo nao associado.');
    if not Assigned(FEngine.Contexto) then
      DoError('Engine.Contexto nao associado.');
    if not Assigned(FEngine.ChatTemplate) then
      DoError('Engine.ChatTemplate nao associado.');
    if not Assigned(FEngine.Tokenizer) then
      DoError('Engine.Tokenizer nao associado.');
    if not Assigned(FEngine.Gerador) then
      DoError('Engine.Gerador nao associado.');
    if not Assigned(FEngine.Chat) then
      DoError('Engine.Chat nao associado.');

    if not Assigned(FModelo) then
      FModelo := FEngine.Modelo;

    FEngine.Modelo.Carregar(ResolveModelPath, ResolveAssociatedGpuLayers);
    FEngine.Chat.ReiniciarSessao;
    ApplyRuntimeConfig;

    FActive := True;
    if Assigned(FOnInitialized) then
      FOnInitialized(Self);
  except
    on E: Exception do
    begin
      FActive := False;
      FinalizeAgent;
      DoError(E.Message);
    end;
  end;
end;

procedure TYakkoAgente.FinalizeAgent;
begin
  try
    if Assigned(FEngine) and Assigned(FEngine.Chat) then
    begin
      try
        FEngine.Chat.ReiniciarSessao;
      except
        { Fechamento defensivo: ignora falhas de estado parcial na sessao. }
      end;
    end;

    if Assigned(FEngine) and Assigned(FEngine.Modelo) then
    begin
      try
        FEngine.Modelo.Descarregar;
      except
        { Fechamento defensivo: ignora falhas de descarregamento tardio. }
      end;
    end;
  finally
    FActive := False;
    if Assigned(FOnFinalized) and (not (csDestroying in ComponentState)) then
      FOnFinalized(Self);
  end;
end;

procedure TYakkoAgente.SetEngine(const Value: TYakkoEngine);
begin
  if FEngine = Value then
    Exit;

  if FActive then
    DoError('Nao e possivel trocar Engine com o agente ativo. Defina Active=False antes.');

  FEngine := Value;
  if Assigned(FEngine) then
  begin
    if Assigned(FEngine.Modelo) then
      FModelo := FEngine.Modelo;
    if Assigned(FEngine.Paths) then
      FPaths := FEngine.Paths
    else if Assigned(FPaths) then
      FEngine.Paths := FPaths;

    if Assigned(FEngine.Config) then
    begin
      FNCtxPadrao := FEngine.Config.NCtx;
      FMaxTokensPadrao := FEngine.Config.MaxTokens;
      FTemperatura := FEngine.Config.Sampling.Temperature;
      FTopK := FEngine.Config.Sampling.TopK;
      FTopP := FEngine.Config.Sampling.TopP;
      FUseThinkMode := FEngine.Config.UseThinkMode;
      FShowThinkBlocks := FEngine.Config.ShowThinkBlocks;
      FSanitizeOutput := FEngine.Config.SanitizeOutput;
    end;
  end;
end;

procedure TYakkoAgente.SetModelo(const Value: TYakkoModelo);
begin
  if FModelo = Value then
    Exit;

  if FActive then
    DoError('Nao e possivel trocar Modelo com o agente ativo. Defina Active=False antes.');

  FModelo := Value;
  if Assigned(FEngine) then
    FEngine.Modelo := FModelo;
end;

procedure TYakkoAgente.SetPaths(const Value: TYakkoPaths);
begin
  FPaths := Value;
  if Assigned(FEngine) then
    FEngine.Paths := FPaths;
end;

procedure TYakkoAgente.RestartSession;
begin
  if not FActive then
  begin
    if FAutoInitialize then
      InitializeAgent
    else
      DoError('Agente nao inicializado. Ative Active=True ou chame InitializeAgent.');
  end;

  FEngine.Chat.ReiniciarSessao;
  if Trim(FSystemPrompt) <> '' then
    FEngine.Chat.PromptSistema := FSystemPrompt;
end;

procedure TYakkoAgente.SetSystemPrompt(const APrompt: string);
begin
  FSystemPrompt := APrompt;
  if FActive then
    FEngine.Chat.PromptSistema := FSystemPrompt;
end;

function TYakkoAgente.StripTaggedBlock(const AValue, AOpenTag, ACloseTag: string): string;
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

function TYakkoAgente.SanitizeModelResponseText(const AValue: string): string;
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
begin
  Result := Trim(AValue);

  if not FShowThinkBlocks then
  begin
    Result := StripTaggedBlock(Result, '<think>', '</think>');
    Result := StringReplace(Result, '<think>', '', [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, '</think>', '', [rfReplaceAll, rfIgnoreCase]);
  end;

  for I := Low(CONTROL_TAGS) to High(CONTROL_TAGS) do
    Result := StringReplace(Result, CONTROL_TAGS[I], '', [rfReplaceAll, rfIgnoreCase]);

  Result := Trim(Result);
end;

function TYakkoAgente.Ask(const APrompt: string; AMaxTokens: Integer): string;
var
  LPrompt: string;
  LResposta: string;
begin
  if not FActive then
  begin
    if FAutoInitialize then
      InitializeAgent
    else
      DoError('Agente nao inicializado. Ative Active=True ou chame InitializeAgent.');
  end;

  LPrompt := Trim(APrompt);
  if LPrompt = '' then
    DoError('Prompt vazio. Informe um texto para o agente.');

  if Assigned(FOnBeforeAsk) then
    FOnBeforeAsk(Self, LPrompt);

  if Assigned(FOutputMemo) then
  begin
    FOutputMemo.Lines.Clear;
    FOutputMemo.SelStart := Length(FOutputMemo.Text);
    FOutputMemo.SelLength := 0;
  end;

  if FUseThinkMode and (Pos('/think ', LowerCase(LPrompt)) <> 1) then
    LPrompt := '/think ' + LPrompt;

  try
    LResposta := FEngine.Chat.Perguntar(
      LPrompt,
      AMaxTokens,
      procedure(const ATexto: string)
      begin
        if Assigned(FOutputMemo) then
        begin
          FOutputMemo.SelStart := Length(FOutputMemo.Text);
          FOutputMemo.SelLength := 0;
          FOutputMemo.SelText := ATexto;
          FOutputMemo.Perform(EM_SCROLLCARET, 0, 0);
        end;

        if Assigned(FOnPartialText) then
          FOnPartialText(Self, ATexto);
      end
    );

    if FSanitizeOutput then
      LResposta := SanitizeModelResponseText(LResposta);

    FEngine.Chat.AtualizarUltimaMensagemAssistente(LResposta);
    Result := LResposta;

    if Assigned(FOutputMemo) then
    begin
      FOutputMemo.Lines.Text := Result;
      FOutputMemo.SelStart := Length(FOutputMemo.Text);
      FOutputMemo.SelLength := 0;
      FOutputMemo.Perform(EM_SCROLLCARET, 0, 0);
    end;

    if Assigned(FOnAfterAsk) then
      FOnAfterAsk(Self, Result);
  except
    on E: Exception do
    begin
      DoError(E.Message);
      Result := '';
    end;
  end;
end;

function TYakkoAgente.IsInitialized: Boolean;
begin
  Result := FActive;
end;

procedure TYakkoAgente.SetActive(const Value: Boolean);
begin
  if csDesigning in ComponentState then
  begin
    FActive := Value;
    Exit;
  end;

  if Value then
    InitializeAgent
  else
    FinalizeAgent;
end;

procedure TYakkoAgente.SetNCtxPadrao(const Value: Cardinal);
begin
  FNCtxPadrao := Value;
  if Assigned(FEngine) then
    FEngine.Config.NCtx := Value;
  if FActive and Assigned(FEngine) then
    FEngine.Contexto.NCtxPadrao := FEngine.Config.NCtx;
end;

procedure TYakkoAgente.SetMaxTokensPadrao(const Value: Integer);
begin
  FMaxTokensPadrao := Value;
  if Assigned(FEngine) then
    FEngine.Config.MaxTokens := Value;
end;

procedure TYakkoAgente.SetGpuLayers(const Value: Integer);
begin
  FGpuLayers := Value;
  if FActive and Assigned(FEngine) then
    FEngine.Modelo.GpuLayersPadrao := Value;
end;

procedure TYakkoAgente.SetTemperatura(const Value: Single);
begin
  FTemperatura := Value;
  if Assigned(FEngine) then
    FEngine.Config.Sampling.Temperature := Value;
end;

procedure TYakkoAgente.SetTopK(const Value: Integer);
begin
  FTopK := Value;
  if Assigned(FEngine) then
    FEngine.Config.Sampling.TopK := Value;
end;

procedure TYakkoAgente.SetTopP(const Value: Single);
begin
  FTopP := Value;
  if Assigned(FEngine) then
    FEngine.Config.Sampling.TopP := Value;
end;

procedure TYakkoAgente.SetUseThinkMode(const Value: Boolean);
begin
  FUseThinkMode := Value;
  if Assigned(FEngine) then
    FEngine.Config.UseThinkMode := Value;
end;

procedure TYakkoAgente.SetShowThinkBlocks(const Value: Boolean);
begin
  FShowThinkBlocks := Value;
  if Assigned(FEngine) then
    FEngine.Config.ShowThinkBlocks := Value;
end;

procedure TYakkoAgente.SetSanitizeOutput(const Value: Boolean);
begin
  FSanitizeOutput := Value;
  if Assigned(FEngine) then
    FEngine.Config.SanitizeOutput := Value;
end;

initialization
  RegisterClass(TYakkoAgente);

end.


