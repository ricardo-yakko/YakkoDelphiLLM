unit uYakkoGeradorComponent;

{ Componente de inferencia e streaming de tokens.
  Responsabilidades:
  - pipeline modular de inferencia
  - tokenizacao, sampler e decode loop
  - emissao de eventos de geracao
  - configuracao central via TYakkoInferenceConfig
  Ownership:
  - Events/CancellationToken/Pipeline sao owned localmente
  - Modelo/Contexto/Sessao/Tokenizer/ChatTemplate/ToolManager/Config sao borrowed. }

interface

uses
  System.Classes,
  System.SysUtils,
  System.Math,
  System.Diagnostics,
  uYakkoInferenceConfigComponent,
  uYakkoModeloComponent,
  uYakkoContextoComponent,
  uYakkoSessaoComponent,
  uYakkoChatTemplateComponent,
  uYakkoTokenizerComponent,
  uYakkoToolManagerComponent,
  uYakkoGenerationEventsComponent,
  uYakkoFullExportsComponent,
  uYakkoLlamaTypes;

type
  ELlamaGeradorError = class(Exception);

  TLLamaPos = Int32;
  PLLamaPos = ^TLLamaPos;
  TLlamaSeqId = Int32;
  PLlamaSeqId = ^TLlamaSeqId;
  PPLlamaSeqId = ^PLlamaSeqId;

  TLlamaChatMessage = record
    role: PAnsiChar;
    content: PAnsiChar;
  end;
  PLlamaChatMessage = ^TLlamaChatMessage;

  TLlamaBatch = record
    n_tokens: Int32;
    token: PLlamaToken;
    embd: PSingle;
    pos: PLLamaPos;
    n_seq_id: ^Int32;
    seq_id: PPLlamaSeqId;
    logits: PShortInt;
  end;

  TLlamaSamplerChainParams = record
    no_perf: Boolean;
  end;

  TFnModelChatTemplate = function(model: TLlamaModelHandle; name: PAnsiChar): PAnsiChar; cdecl;
  TFnModelHasEncoder = function(model: TLlamaModelHandle): Boolean; cdecl;
  TFnModelDecoderStartToken = function(model: TLlamaModelHandle): TLlamaToken; cdecl;
  TFnChatApplyTemplate = function(tmpl: PAnsiChar; chat: PLlamaChatMessage; n_msg: NativeUInt; add_ass: Boolean; buf: PAnsiChar; length: Int32): Int32; cdecl;
  TFnTokenize = function(vocab: TLlamaVocabHandle; text: PAnsiChar; text_len: Int32; tokens: PLlamaToken; n_tokens_max: Int32; add_special: Boolean; parse_special: Boolean): Int32; cdecl;
  TFnTokenToPiece = function(vocab: TLlamaVocabHandle; token: TLlamaToken; buf: PAnsiChar; length: Int32; lstrip: Int32; special: Boolean): Int32; cdecl;
  TFnBatchGetOne = function(tokens: PLlamaToken; n_tokens: Int32): TLlamaBatch; cdecl;
  TFnEncode = function(ctx: TLlamaContextoHandle; batch: TLlamaBatch): Int32; cdecl;
  TFnDecode = function(ctx: TLlamaContextoHandle; batch: TLlamaBatch): Int32; cdecl;
  TFnVocabBos = function(vocab: TLlamaVocabHandle): TLlamaToken; cdecl;
  TFnVocabIsEog = function(vocab: TLlamaVocabHandle; token: TLlamaToken): Boolean; cdecl;
  TFnVocabIsControl = function(vocab: TLlamaVocabHandle; token: TLlamaToken): Boolean; cdecl;
  TFnSamplerChainDefaultParams = function: TLlamaSamplerChainParams; cdecl;
  TFnSamplerChainInit = function(params: TLlamaSamplerChainParams): TLlamaSamplerHandle; cdecl;
  TFnSamplerChainAdd = procedure(chain: TLlamaSamplerHandle; smpl: TLlamaSamplerHandle); cdecl;
  TFnSamplerInitTopK = function(k: Int32): TLlamaSamplerHandle; cdecl;
  TFnSamplerInitTopP = function(p: Single; min_keep: NativeUInt): TLlamaSamplerHandle; cdecl;
  TFnSamplerInitTemp = function(t: Single): TLlamaSamplerHandle; cdecl;
  TFnSamplerInitDist = function(seed: Cardinal): TLlamaSamplerHandle; cdecl;
  TFnSamplerInitGreedy = function: TLlamaSamplerHandle; cdecl;
  TFnSamplerSample = function(smpl: TLlamaSamplerHandle; ctx: TLlamaContextoHandle; idx: Int32): TLlamaToken; cdecl;
  TFnSamplerFree = procedure(smpl: TLlamaSamplerHandle); cdecl;

  TYakkoGerador = class;

  TYakkoInferenceStage = (
    isIdle,
    isPromptPreparation,
    isTokenization,
    isMemoryAdjustment,
    isSessionPreparation,
    isSampling,
    isGeneration,
    isStreaming,
    isStatistics,
    isFinalization
  );

  TYakkoOnPipelineStageEvent = reference to procedure(const AStage: TYakkoInferenceStage);

  TYakkoInferenceRequest = class
  public
    Prompt: string;
    PromptSistema: string;
    Mensagens: TArray<TLlamaMensagem>;
    MaxTokens: Integer;
    Config: TYakkoInferenceConfig;
    Sessao: TYakkoSessao;
    ToolManager: TYakkoToolManager;
    CancellationToken: TYakkoCancellationToken;
    Events: TYakkoGenerationEvents;
    LegacyOnToken: TLlamaTextoParcialProc;
  end;

  TYakkoInferenceResult = class
  public
    TextoGerado: string;
    Stats: TYakkoGenerationStats;
    Cancelado: Boolean;
    Falhou: Boolean;
  end;

  { Pipeline modular de inferencia.
    Coordena estagios sem assumir ownership das dependencias externas. }
  TYakkoInferencePipeline = class
  private
    FGerador: TYakkoGerador;
    FPipelineAtiva: Boolean;
    FStageAtual: TYakkoInferenceStage;
    procedure EnterStage(const AStage: TYakkoInferenceStage);
    procedure LeaveStage(const AStage: TYakkoInferenceStage);
    procedure ValidarRequest(const ARequest: TYakkoInferenceRequest);
  public
    OnStageStarted: TYakkoOnPipelineStageEvent;
    OnStageFinished: TYakkoOnPipelineStageEvent;

    constructor Create(AGerador: TYakkoGerador);
    function PodeExecutar: Boolean;
    function Executar(ARequest: TYakkoInferenceRequest): TYakkoInferenceResult;

    property PipelineAtiva: Boolean read FPipelineAtiva;
    property StageAtual: TYakkoInferenceStage read FStageAtual;
  end;

  TYakkoGerador = class(TComponent)
  private const
    LLAMA_TOKEN_NULL = -1;
  private
    { Referencias externas sem ownership; o ciclo de vida pertence ao Engine. }
    FModelo: TYakkoModelo;
    FContexto: TYakkoContexto;
    FSessao: TYakkoSessao;
    FChatTemplate: TYakkoChatTemplate;
    FTokenizer: TYakkoTokenizer;
    FToolManager: TYakkoToolManager;
    FConfig: TYakkoInferenceConfig;
    FOwnsConfig: Boolean;
    FEvents: TYakkoGenerationEvents;
    FCancellationToken: TYakkoCancellationToken;
    FInferencePipeline: TYakkoInferencePipeline;
    FGenerationState: TYakkoGenerationState;
    FDestruindo: Boolean;

    function ExtrairTextoEmitivel(var APendenteUtf8: UTF8String): string;
    function RenderPromptComTemplate(const APrompt: string; const APromptSistema: string; const AMensagens: TArray<TLlamaMensagem>): UTF8String;
    function Tokenizar(const APromptUtf8: UTF8String): TLlamaTokenArray;
    function TokenParaTexto(const AToken: TLlamaToken): RawByteString;
    function ConstruirSampler: TLlamaSamplerHandle;
    procedure PrepararContexto(APromptTokenCount: Integer; AMaxTokens: Integer);
    function GetConfig: TYakkoInferenceConfig;
    procedure SetConfig(const Value: TYakkoInferenceConfig);
    function GetSamplingParams: TYakkoSamplingParams;
    procedure SetModelo(const Value: TYakkoModelo);
    procedure SetChatTemplate(const Value: TYakkoChatTemplate);
    procedure SetSamplingParams(const Value: TYakkoSamplingParams);
    procedure SetTokenizer(const Value: TYakkoTokenizer);
    procedure SetToolManager(const Value: TYakkoToolManager);
    procedure SetContexto(const Value: TYakkoContexto);
    procedure SetSessao(const Value: TYakkoSessao);
    procedure SetGenerationState(const Value: TYakkoGenerationState);
    function ContextoEfetivo: TYakkoContexto;
    procedure EmitOnToken(const ATokenText: string; const ALegacyOnToken: TLlamaTextoParcialProc);
    procedure EmitOnReasoningToken(const ATokenText: string);
    procedure EmitOnToolCall(const ARawPayload: string);
    procedure EmitOnError(const AMensagem: string);
    procedure EmitOnCancelled(const ATextoParcial: string; const AStats: TYakkoGenerationStats);
    procedure EmitOnFinished(const ATextoFinal: string; const AStats: TYakkoGenerationStats);
    procedure EmitOnStatistics(const AStats: TYakkoGenerationStats);
    function IsCancellationRequested: Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    function EstimarTokensComMensagens(const APrompt: string; const APromptSistema: string; const AMensagens: TArray<TLlamaMensagem>): Integer;
    function Gerar(const APrompt: string; AMaxTokens: Integer = -1; AAoReceberTexto: TLlamaTextoParcialProc = nil): string;
    function GerarComMensagens(const APrompt: string; const APromptSistema: string; const AMensagens: TArray<TLlamaMensagem>; AMaxTokens: Integer = -1; AAoReceberTexto: TLlamaTextoParcialProc = nil): string;
    function PodeGerar: Boolean;
    function PodeDestruir: Boolean;
    function PodeExecutarPipeline: Boolean;
    procedure CancelarGeracao;

    { Retorna o orcamento de tokens disponivel no contexto atual.
      Chat usa isso sem precisar referenciar TYakkoContexto diretamente. }
    function ContextoDisponivel: Integer;

    { Fecha e reabre o contexto, limpando o KV-cache (usado em ReiniciarSessao). }
    procedure ResetarContexto;

    { Parametros desacoplados de sampling centralizados na configuracao. }
    property SamplingParams: TYakkoSamplingParams read GetSamplingParams write SetSamplingParams;
    { Configuracao central de inferencia.
      Ownership: externo (normalmente TYakkoEngine). }
    property Config: TYakkoInferenceConfig read GetConfig write SetConfig;
    { Eventos estruturados de geracao.
      Ownership: TYakkoGerador e owner de FEvents. }
    property Events: TYakkoGenerationEvents read FEvents;
    { Cancelamento cooperativo.
      Ownership: TYakkoGerador e owner de FCancellationToken. }
    property CancellationToken: TYakkoCancellationToken read FCancellationToken;
    { Pipeline modular de inferencia.
      Ownership: TYakkoGerador e owner de FInferencePipeline. }
    property InferencePipeline: TYakkoInferencePipeline read FInferencePipeline;
    property GenerationState: TYakkoGenerationState read FGenerationState;

    property Modelo: TYakkoModelo read FModelo write SetModelo;
    property Contexto: TYakkoContexto read FContexto write SetContexto;
    { Referencia externa sem ownership; fronteira logica de sessao conversacional. }
    property Sessao: TYakkoSessao read FSessao write SetSessao;
    { Referencia externa sem ownership. }
    property ChatTemplate: TYakkoChatTemplate read FChatTemplate write SetChatTemplate;
    { Referencia externa sem ownership. }
    property Tokenizer: TYakkoTokenizer read FTokenizer write SetTokenizer;
    { Referencia externa sem ownership para registro/execucao de tools. }
    property ToolManager: TYakkoToolManager read FToolManager write SetToolManager;
  end;

implementation

{ TYakkoInferencePipeline }

constructor TYakkoInferencePipeline.Create(AGerador: TYakkoGerador);
begin
  inherited Create;
  FGerador := AGerador;
  FPipelineAtiva := False;
  FStageAtual := isIdle;
  OnStageStarted := nil;
  OnStageFinished := nil;
end;

function TYakkoInferencePipeline.PodeExecutar: Boolean;
begin
  Result := Assigned(FGerador) and (not FPipelineAtiva) and (not FGerador.FDestruindo);
end;

procedure TYakkoInferencePipeline.EnterStage(const AStage: TYakkoInferenceStage);
begin
  FStageAtual := AStage;
  if Assigned(OnStageStarted) then
    OnStageStarted(AStage);
end;

procedure TYakkoInferencePipeline.LeaveStage(const AStage: TYakkoInferenceStage);
begin
  if Assigned(OnStageFinished) then
    OnStageFinished(AStage);
end;

procedure TYakkoInferencePipeline.ValidarRequest(const ARequest: TYakkoInferenceRequest);
begin
  if not Assigned(FGerador) then
    raise ELlamaGeradorError.Create('Pipeline sem gerador associado.');

  if not Assigned(ARequest) then
    raise ELlamaGeradorError.Create('InferenceRequest nao informado.');

  if Assigned(ARequest.Sessao) and (not ARequest.Sessao.SessaoAtiva) then
    raise ELlamaGeradorError.Create('Sessao inativa nao pode gerar. Reinicie a sessao antes de continuar.');

  if not Assigned(ARequest.CancellationToken) then
    raise ELlamaGeradorError.Create('CancellationToken nao configurado no request.');

  if not FGerador.PodeGerar then
    raise ELlamaGeradorError.Create('Gerador nao esta pronto para gerar. Verifique Modelo, Contexto, Sessao e estado carregado.');
end;

function TYakkoInferencePipeline.Executar(ARequest: TYakkoInferenceRequest): TYakkoInferenceResult;
var
  LContexto: TYakkoContexto;
  LSessao: TYakkoSessao;
  LConfig: TYakkoInferenceConfig;
  LPromptUtf8: UTF8String;
  LResponseUtf8: UTF8String;
  LPendenteUtf8: UTF8String;
  LPromptTokens: TLlamaTokenArray;
  LSampler: TLlamaSamplerHandle;
  LBatch: TLlamaBatch;
  LGenerated: Integer;
  LNewToken: TLlamaToken;
  LDecoderStartToken: TLlamaToken;
  LPiece: RawByteString;
  LMaxTokens: Integer;
  LTextoParcial: string;
  LDecodeResult: Integer;
  LTotalWatch: TStopwatch;
  LEvalWatch: TStopwatch;
  LInReasoning: Boolean;
  LGeracaoSessaoIniciada: Boolean;
  LToolManager: TYakkoToolManager;
  LToolCall: TYakkoToolCall;
  LToolResult: TYakkoToolResult;
begin
  if not PodeExecutar then
    raise ELlamaGeradorError.Create('Pipeline ocupada ou indisponivel para execucao.');

  ValidarRequest(ARequest);

  Result := TYakkoInferenceResult.Create;
  FillChar(Result.Stats, SizeOf(Result.Stats), 0);
  Result.Cancelado := False;
  Result.Falhou := False;
  Result.TextoGerado := '';

  FPipelineAtiva := True;
  FStageAtual := isIdle;
  LGeracaoSessaoIniciada := False;
  LSessao := nil;

  try
    try
      if (FGerador.FGenerationState = gsGerando) or (FGerador.FGenerationState = gsCancelando) then
        raise ELlamaGeradorError.Create('Gerador ja esta em execucao. Use outra instancia para concorrencia.');

    LContexto := FGerador.ContextoEfetivo;
    if not Assigned(LContexto) then
      raise ELlamaGeradorError.Create('Contexto nao configurado para geracao.');

    LSessao := ARequest.Sessao;
    if not Assigned(LSessao) then
      LSessao := FGerador.FSessao;

    LToolManager := ARequest.ToolManager;
    if not Assigned(LToolManager) then
      LToolManager := FGerador.FToolManager;

    LConfig := ARequest.Config;
    if not Assigned(LConfig) then
      LConfig := FGerador.FConfig;

    if Assigned(LSessao) then
    begin
      LSessao.MarcarGeracaoIniciada;
      LGeracaoSessaoIniciada := True;
    end;

    ARequest.CancellationToken.Reset;
    FGerador.SetGenerationState(gsGerando);
    LInReasoning := False;

    EnterStage(isPromptPreparation);
    LPromptUtf8 := FGerador.RenderPromptComTemplate(ARequest.Prompt, ARequest.PromptSistema, ARequest.Mensagens);
    LeaveStage(isPromptPreparation);

    EnterStage(isTokenization);
    LPromptTokens := FGerador.Tokenizar(LPromptUtf8);
    if Length(LPromptTokens) = 0 then
      raise ELlamaGeradorError.Create('O prompt nao gerou tokens.');
    Result.Stats.PromptTokens := Length(LPromptTokens);
    LeaveStage(isTokenization);

    EnterStage(isMemoryAdjustment);
    { Etapa reservada para integracao futura com MemoryManager e RAG. }
    LeaveStage(isMemoryAdjustment);

    EnterStage(isSessionPreparation);
    if ARequest.MaxTokens > 0 then
      LMaxTokens := ARequest.MaxTokens
    else if Assigned(LConfig) then
      LMaxTokens := LConfig.MaxTokens
    else
      LMaxTokens := 64;
    FGerador.PrepararContexto(Length(LPromptTokens), LMaxTokens);
    LeaveStage(isSessionPreparation);

    EnterStage(isSampling);
    LSampler := FGerador.ConstruirSampler;
    LeaveStage(isSampling);

    LTotalWatch := TStopwatch.StartNew;

      try
        if ARequest.CancellationToken.IsCancelled then
        begin
          FGerador.SetGenerationState(gsCancelando);
          Result.Stats.TotalTimeMs := LTotalWatch.Elapsed.TotalMilliseconds;
          Result.Cancelado := True;
          FGerador.EmitOnCancelled('', Result.Stats);
          Exit;
        end;

        LBatch := TFnBatchGetOne(llama_batch_get_one)(@LPromptTokens[0], Length(LPromptTokens));

        if LSampler = nil then
          raise ELlamaGeradorError.Create('Sampler nao inicializado para a etapa de geracao.');

      EnterStage(isGeneration);
      if TFnModelHasEncoder(llama_model_has_encoder)(FGerador.FModelo.Handle) then
      begin
        if TFnEncode(llama_encode)(LContexto.Handle, LBatch) <> 0 then
          raise ELlamaGeradorError.Create('Falha ao processar o prompt no encoder.');

        LDecoderStartToken := TFnModelDecoderStartToken(llama_model_decoder_start_token)(FGerador.FModelo.Handle);
        if LDecoderStartToken = -1 then
          LDecoderStartToken := TFnVocabBos(llama_vocab_bos)(FGerador.FModelo.Vocab);

        LBatch := TFnBatchGetOne(llama_batch_get_one)(@LDecoderStartToken, 1);
      end;
      LeaveStage(isGeneration);

      Result.Stats.PromptEvalTimeMs := LTotalWatch.Elapsed.TotalMilliseconds;

      LResponseUtf8 := '';
      LPendenteUtf8 := '';
      LGenerated := 0;
      LEvalWatch := TStopwatch.StartNew;

      EnterStage(isStreaming);
      while LGenerated < LMaxTokens do
      begin
        if ARequest.CancellationToken.IsCancelled then
        begin
          FGerador.SetGenerationState(gsCancelando);
          Break;
        end;

        LDecodeResult := TFnDecode(llama_decode)(LContexto.Handle, LBatch);
        if LDecodeResult <> 0 then
          raise ELlamaGeradorError.CreateFmt(
            'llama_decode retornou %d (batch=%d, n_ctx=%d). Reduza o prompt ou aumente o contexto/batch.',
            [LDecodeResult, LBatch.n_tokens, LContexto.NCtx]
          );

        LNewToken := TFnSamplerSample(llama_sampler_sample)(LSampler, LContexto.Handle, -1);

        if TFnVocabIsEog(llama_vocab_is_eog)(FGerador.FModelo.Vocab, LNewToken) then
          Break;

        if not TFnVocabIsControl(llama_vocab_is_control)(FGerador.FModelo.Vocab, LNewToken) then
        begin
          LPiece := FGerador.TokenParaTexto(LNewToken);
          if LPiece <> '' then
          begin
            LResponseUtf8 := LResponseUtf8 + UTF8String(LPiece);

            if Pos('<think>', string(LPiece)) > 0 then
              LInReasoning := True;

            if LInReasoning then
              FGerador.EmitOnReasoningToken(UTF8ToString(UTF8String(LPiece)));

            if Pos('</think>', string(LPiece)) > 0 then
              LInReasoning := False;

            if Assigned(LToolManager) and
               LToolManager.TryProcessRawPayload(UTF8ToString(UTF8String(LPiece)), LToolCall, LToolResult) then
            begin
              FGerador.EmitOnToolCall(LToolManager.BuildToolEventPayload('start', LToolCall, LToolResult));
              if LToolResult.Sucesso then
                FGerador.EmitOnToolCall(LToolManager.BuildToolEventPayload('success', LToolCall, LToolResult))
              else
                FGerador.EmitOnToolCall(LToolManager.BuildToolEventPayload('failure', LToolCall, LToolResult));
            end;

            if Assigned(ARequest.LegacyOnToken) then
            begin
              LPendenteUtf8 := LPendenteUtf8 + UTF8String(LPiece);
              LTextoParcial := FGerador.ExtrairTextoEmitivel(LPendenteUtf8);
              if LTextoParcial <> '' then
                FGerador.EmitOnToken(LTextoParcial, ARequest.LegacyOnToken);
            end;
          end;
        end;

        LBatch := TFnBatchGetOne(llama_batch_get_one)(@LNewToken, 1);
        Inc(LGenerated);
        if Assigned(LSessao) then
          LSessao.MarcarTokenProcessado(LNewToken);
      end;
      LeaveStage(isStreaming);

      if Assigned(ARequest.LegacyOnToken) and (LPendenteUtf8 <> '') then
        FGerador.EmitOnToken(UTF8ToString(LPendenteUtf8), ARequest.LegacyOnToken);

      EnterStage(isStatistics);
      Result.Stats.GeneratedTokens := LGenerated;
      Result.Stats.EvalTimeMs := LEvalWatch.Elapsed.TotalMilliseconds;
      Result.Stats.TotalTimeMs := LTotalWatch.Elapsed.TotalMilliseconds;
      if Result.Stats.EvalTimeMs > 0 then
        Result.Stats.TokensPerSecond := Result.Stats.GeneratedTokens / (Result.Stats.EvalTimeMs / 1000.0)
      else
        Result.Stats.TokensPerSecond := 0;
      FGerador.EmitOnStatistics(Result.Stats);
      LeaveStage(isStatistics);
      finally
        if (LSampler <> nil) and Assigned(llama_sampler_free) then
          TFnSamplerFree(llama_sampler_free)(LSampler);
      end;

    EnterStage(isFinalization);
    Result.TextoGerado := Trim(UTF8ToString(LResponseUtf8));
    Result.Cancelado := ARequest.CancellationToken.IsCancelled;

    if Result.Cancelado then
    begin
      FGerador.SetGenerationState(gsFinalizado);
      FGerador.EmitOnCancelled(Result.TextoGerado, Result.Stats);
    end
    else
    begin
      FGerador.SetGenerationState(gsFinalizado);
      FGerador.EmitOnFinished(Result.TextoGerado, Result.Stats);
    end;
    LeaveStage(isFinalization);

      if LGeracaoSessaoIniciada and Assigned(LSessao) then
        LSessao.MarcarGeracaoFinalizada(Result.Stats.GeneratedTokens > 0);
    except
      on E: Exception do
      begin
        Result.Falhou := True;
        if LGeracaoSessaoIniciada and Assigned(LSessao) then
          LSessao.MarcarGeracaoFalha;
        FGerador.SetGenerationState(gsFalhou);
        FGerador.EmitOnError(E.Message);
        FreeAndNil(Result);
        raise;
      end;
    end;
  finally
    FStageAtual := isIdle;
    FPipelineAtiva := False;
  end;
end;

constructor TYakkoGerador.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FModelo := nil;
  FContexto := nil;
  FSessao := nil;
  FChatTemplate := nil;
  FTokenizer := nil;
  FToolManager := nil;
  FConfig := TYakkoInferenceConfig.Create;
  FOwnsConfig := True;
  FEvents := TYakkoGenerationEvents.Create;
  FCancellationToken := TYakkoCancellationToken.Create;
  FInferencePipeline := TYakkoInferencePipeline.Create(Self);
  FGenerationState := gsIdle;
  FDestruindo := False;
end;

destructor TYakkoGerador.Destroy;
begin
  if FDestruindo then
    Exit;
  FDestruindo := True;
  FGenerationState := gsFinalizado;
  FreeAndNil(FInferencePipeline);
  FreeAndNil(FCancellationToken);
  FreeAndNil(FEvents);
  if FOwnsConfig then
    FreeAndNil(FConfig)
  else
    FConfig := nil;
  FOwnsConfig := False;
  FSessao := nil;
  FChatTemplate := nil;
  FTokenizer := nil;
  FToolManager := nil;
  FContexto := nil;
  FModelo := nil;
  inherited;
end;

function Utf8SequenceLength(AByte: Byte): Integer;
begin
  if (AByte and $80) = 0 then
    Exit(1);
  if (AByte and $E0) = $C0 then
    Exit(2);
  if (AByte and $F0) = $E0 then
    Exit(3);
  if (AByte and $F8) = $F0 then
    Exit(4);
  Result := 1;
end;

function TYakkoGerador.ExtrairTextoEmitivel(var APendenteUtf8: UTF8String): string;
var
  LEmitirUtf8: UTF8String;
  LLeadingIndex: Integer;
  LPrefixLength: Integer;
  LBytesDisponiveis: Integer;
begin
  Result := '';
  if APendenteUtf8 = '' then
    Exit;

  LPrefixLength := Length(APendenteUtf8);
  LLeadingIndex := LPrefixLength;

  while (LLeadingIndex > 0) and ((Byte(APendenteUtf8[LLeadingIndex]) and $C0) = $80) do
    Dec(LLeadingIndex);

  if LLeadingIndex <= 0 then
    Exit;

  LBytesDisponiveis := LPrefixLength - LLeadingIndex + 1;
  if Utf8SequenceLength(Byte(APendenteUtf8[LLeadingIndex])) > LBytesDisponiveis then
    LPrefixLength := LLeadingIndex - 1;

  if LPrefixLength <= 0 then
    Exit;

  LEmitirUtf8 := Copy(APendenteUtf8, 1, LPrefixLength);
  Delete(APendenteUtf8, 1, LPrefixLength);
  Result := UTF8ToString(LEmitirUtf8);
end;

function TYakkoGerador.RenderPromptComTemplate(const APrompt: string; const APromptSistema: string; const AMensagens: TArray<TLlamaMensagem>): UTF8String;
begin
  if not Assigned(FChatTemplate) then
    raise ELlamaGeradorError.Create('ChatTemplate nao configurado. Associe TYakkoChatTemplate ao gerador.');
  Result := FChatTemplate.BuildPromptFromLegacy(APrompt, APromptSistema, AMensagens);
end;

function TYakkoGerador.Tokenizar(const APromptUtf8: UTF8String): TLlamaTokenArray;
begin
  if not Assigned(FTokenizer) then
    raise ELlamaGeradorError.Create('Tokenizer nao configurado. Associe TYakkoTokenizer ao gerador.');
  Result := FTokenizer.TokenizeUtf8(APromptUtf8);
end;

function TYakkoGerador.TokenParaTexto(const AToken: TLlamaToken): RawByteString;
begin
  if not Assigned(FTokenizer) then
    raise ELlamaGeradorError.Create('Tokenizer nao configurado. Associe TYakkoTokenizer ao gerador.');
  Result := FTokenizer.DetokenizeToken(AToken);
end;

function TYakkoGerador.ConstruirSampler: TLlamaSamplerHandle;
var
  LParams: TLlamaSamplerChainParams;
  LSampling: TYakkoSamplingParams;
begin
  LSampling := GetSamplingParams;

  if LSampling.Temperature <= 0 then
    Exit(TFnSamplerInitGreedy(llama_sampler_init_greedy)());

  LParams := TFnSamplerChainDefaultParams(llama_sampler_chain_default_params)();
  LParams.no_perf := False;

  Result := TFnSamplerChainInit(llama_sampler_chain_init)(LParams);
  if Result = nil then
    raise ELlamaGeradorError.Create('Nao foi possivel criar a cadeia de samplers.');

  if LSampling.TopK > 0 then
    TFnSamplerChainAdd(llama_sampler_chain_add)(Result, TFnSamplerInitTopK(llama_sampler_init_top_k)(LSampling.TopK));

  if LSampling.TopP > 0 then
    TFnSamplerChainAdd(llama_sampler_chain_add)(Result, TFnSamplerInitTopP(llama_sampler_init_top_p)(LSampling.TopP, 1));

  TFnSamplerChainAdd(llama_sampler_chain_add)(Result, TFnSamplerInitTemp(llama_sampler_init_temp)(LSampling.Temperature));
  TFnSamplerChainAdd(llama_sampler_chain_add)(Result, TFnSamplerInitDist(llama_sampler_init_dist)(LSampling.Seed));
end;

function TYakkoGerador.GetConfig: TYakkoInferenceConfig;
begin
  if not Assigned(FConfig) then
  begin
    FConfig := TYakkoInferenceConfig.Create;
    FOwnsConfig := True;
  end;
  Result := FConfig;
end;

procedure TYakkoGerador.SetConfig(const Value: TYakkoInferenceConfig);
var
  LAnterior: TYakkoInferenceConfig;
  LAnteriorOwned: Boolean;
begin
  if FConfig = Value then
    Exit;

  LAnterior := FConfig;
  LAnteriorOwned := FOwnsConfig;
  FConfig := Value;

  if not Assigned(FConfig) then
  begin
    FConfig := TYakkoInferenceConfig.Create;
    FOwnsConfig := True;
  end
  else
    FOwnsConfig := False;

  if LAnteriorOwned and (LAnterior <> FConfig) then
    FreeAndNil(LAnterior);
end;

function TYakkoGerador.GetSamplingParams: TYakkoSamplingParams;
begin
  Result := GetConfig.Sampling;
end;

procedure TYakkoGerador.SetModelo(const Value: TYakkoModelo);
begin
  FModelo := Value;
  if Assigned(FChatTemplate) and (FChatTemplate.Modelo <> FModelo) then
    FChatTemplate.Modelo := FModelo;
  if Assigned(FTokenizer) and (FTokenizer.Modelo <> FModelo) then
    FTokenizer.Modelo := FModelo;
end;

procedure TYakkoGerador.SetChatTemplate(const Value: TYakkoChatTemplate);
begin
  FChatTemplate := Value;
  if Assigned(FChatTemplate) and Assigned(FModelo) and (FChatTemplate.Modelo <> FModelo) then
    FChatTemplate.Modelo := FModelo;
end;

procedure TYakkoGerador.SetSamplingParams(const Value: TYakkoSamplingParams);
begin
  if not Assigned(Value) then
  begin
    GetSamplingParams.ResetToDefaults;
    Exit;
  end;

  GetSamplingParams.Assign(Value);
end;

procedure TYakkoGerador.SetTokenizer(const Value: TYakkoTokenizer);
begin
  FTokenizer := Value;
  if Assigned(FTokenizer) and Assigned(FModelo) and (FTokenizer.Modelo <> FModelo) then
    FTokenizer.Modelo := FModelo;
end;

procedure TYakkoGerador.SetToolManager(const Value: TYakkoToolManager);
begin
  FToolManager := Value;
end;

procedure TYakkoGerador.SetContexto(const Value: TYakkoContexto);
begin
  FContexto := Value;

  if Assigned(FSessao) and (FSessao.Contexto <> FContexto) then
    FSessao.Contexto := FContexto;
end;

procedure TYakkoGerador.SetSessao(const Value: TYakkoSessao);
begin
  FSessao := Value;

  if not Assigned(FSessao) then
    Exit;

  if Assigned(FContexto) and (FSessao.Contexto <> FContexto) then
    FSessao.Contexto := FContexto
  else if Assigned(FSessao.Contexto) then
    FContexto := FSessao.Contexto;
end;

procedure TYakkoGerador.SetGenerationState(const Value: TYakkoGenerationState);
begin
  FGenerationState := Value;
end;

function TYakkoGerador.IsCancellationRequested: Boolean;
begin
  Result := Assigned(FCancellationToken) and FCancellationToken.IsCancelled;
end;

function TYakkoGerador.ContextoEfetivo: TYakkoContexto;
begin
  if Assigned(FSessao) and Assigned(FSessao.Contexto) then
    Exit(FSessao.Contexto);
  Result := FContexto;
end;

procedure TYakkoGerador.EmitOnToken(const ATokenText: string; const ALegacyOnToken: TLlamaTextoParcialProc);
begin
  if FDestruindo or (ATokenText = '') then
    Exit;

  if IsCancellationRequested then
    Exit;

  if Assigned(FEvents) and Assigned(FEvents.OnToken) then
    FEvents.OnToken(ATokenText);

  if Assigned(ALegacyOnToken) then
    ALegacyOnToken(ATokenText);
end;

procedure TYakkoGerador.EmitOnReasoningToken(const ATokenText: string);
begin
  if FDestruindo or (ATokenText = '') then
    Exit;

  if IsCancellationRequested then
    Exit;

  if Assigned(FEvents) and Assigned(FEvents.OnReasoningToken) then
    FEvents.OnReasoningToken(ATokenText);
end;

procedure TYakkoGerador.EmitOnToolCall(const ARawPayload: string);
begin
  if FDestruindo or (ARawPayload = '') then
    Exit;

  if Assigned(FEvents) and Assigned(FEvents.OnToolCall) then
    FEvents.OnToolCall(ARawPayload);
end;

procedure TYakkoGerador.EmitOnError(const AMensagem: string);
begin
  if FDestruindo then
    Exit;

  if Assigned(FEvents) and Assigned(FEvents.OnError) then
    FEvents.OnError(AMensagem);
end;

procedure TYakkoGerador.EmitOnCancelled(const ATextoParcial: string; const AStats: TYakkoGenerationStats);
begin
  if FDestruindo then
    Exit;

  if Assigned(FEvents) and Assigned(FEvents.OnCancelled) then
    FEvents.OnCancelled(ATextoParcial, AStats);
end;

procedure TYakkoGerador.EmitOnFinished(const ATextoFinal: string; const AStats: TYakkoGenerationStats);
begin
  if FDestruindo then
    Exit;

  if Assigned(FEvents) and Assigned(FEvents.OnFinished) then
    FEvents.OnFinished(ATextoFinal, AStats);
end;

procedure TYakkoGerador.EmitOnStatistics(const AStats: TYakkoGenerationStats);
begin
  if FDestruindo then
    Exit;

  if Assigned(FEvents) and Assigned(FEvents.OnStatistics) then
    FEvents.OnStatistics(AStats);
end;

procedure TYakkoGerador.CancelarGeracao;
begin
  if not Assigned(FCancellationToken) then
    Exit;

  if FGenerationState = gsGerando then
    SetGenerationState(gsCancelando);
  FCancellationToken.Cancel;
end;

procedure TYakkoGerador.PrepararContexto(APromptTokenCount: Integer; AMaxTokens: Integer);
var
  LContexto: TYakkoContexto;
  LRequiredCtx: Cardinal;
begin
  LContexto := ContextoEfetivo;

  if not Assigned(LContexto) then
    raise ELlamaGeradorError.Create('Contexto nao configurado. Associe TYakkoContexto diretamente ou via TYakkoSessao.');

  { Nao reutilizar PodeGerar aqui: durante GerarComMensagens a sessao pode
    estar em estado "em geracao" por controle cooperativo e ainda assim estar valida
    para abertura/reabertura do contexto. }
  if not Assigned(FModelo) then
    raise ELlamaGeradorError.Create('Modelo nao configurado no gerador.');
  if not FModelo.EstaCarregado then
    raise ELlamaGeradorError.Create('Modelo nao carregado. Carregue o modelo antes de gerar.');
  if not Assigned(FChatTemplate) then
    raise ELlamaGeradorError.Create('ChatTemplate nao configurado no gerador.');
  if not Assigned(FTokenizer) then
    raise ELlamaGeradorError.Create('Tokenizer nao configurado no gerador.');
  if not FChatTemplate.PodeMontarPrompt then
    raise ELlamaGeradorError.Create('ChatTemplate nao esta pronto para montar prompt. Verifique modelo carregado.');
  if not FTokenizer.PodeTokenizar then
    raise ELlamaGeradorError.Create('Tokenizer nao esta pronto para tokenizar. Verifique modelo carregado.');

  if LContexto.EstaAberto then
    LContexto.Fechar;

  if LContexto.Modelo <> FModelo then
    LContexto.Modelo := FModelo;

  if LContexto.NCtxPadrao = 0 then
  begin
    LContexto.Abrir(0);
    Exit;
  end;

  LRequiredCtx := Max(Cardinal(APromptTokenCount + AMaxTokens + 64), LContexto.NCtxPadrao);
  LContexto.Abrir(LRequiredCtx);
end;

function TYakkoGerador.EstimarTokensComMensagens(const APrompt: string; const APromptSistema: string; const AMensagens: TArray<TLlamaMensagem>): Integer;
var
  LPromptUtf8: UTF8String;
begin
  if not PodeGerar then
    raise ELlamaGeradorError.Create('Gerador nao esta pronto para estimar tokens.');

  LPromptUtf8 := RenderPromptComTemplate(APrompt, APromptSistema, AMensagens);
  Result := Length(FTokenizer.TokenizeUtf8(LPromptUtf8));
end;

function TYakkoGerador.Gerar(const APrompt: string; AMaxTokens: Integer; AAoReceberTexto: TLlamaTextoParcialProc): string;
begin
  Result := GerarComMensagens(APrompt, '', [], AMaxTokens, AAoReceberTexto);
end;

function TYakkoGerador.ContextoDisponivel: Integer;
var
  LContexto: TYakkoContexto;
begin
  LContexto := ContextoEfetivo;

  if LContexto = nil then
    Exit(0);
  if LContexto.NCtxPadrao > 0 then
    Exit(LContexto.NCtxPadrao);
  if LContexto.NCtx > 0 then
    Exit(LContexto.NCtx);
  Result := 0;
end;

procedure TYakkoGerador.ResetarContexto;
var
  LContexto: TYakkoContexto;
begin
  if Assigned(FSessao) then
  begin
    FSessao.ResetarSessao;
    Exit;
  end;

  LContexto := ContextoEfetivo;
  if LContexto = nil then
    Exit;
  LContexto.Fechar;
end;

function TYakkoGerador.PodeGerar: Boolean;
var
  LContexto: TYakkoContexto;
  LSessaoPronta: Boolean;
begin
  LContexto := ContextoEfetivo;
  LSessaoPronta :=
    (not Assigned(FSessao)) or
    (FSessao.SessaoAtiva and (not FSessao.EmGeracao));

  Result :=
    Assigned(FModelo) and
    Assigned(LContexto) and
    Assigned(FChatTemplate) and
    Assigned(FTokenizer) and
    LSessaoPronta and
    FModelo.EstaCarregado and
    FChatTemplate.PodeMontarPrompt and
    FTokenizer.PodeTokenizar;
end;

function TYakkoGerador.PodeDestruir: Boolean;
var
  LContexto: TYakkoContexto;
begin
  LContexto := ContextoEfetivo;

  Result :=
    ((not Assigned(FSessao)) or FSessao.PodeDestruir) and
    ((not Assigned(LContexto)) or LContexto.PodeDestruir);
end;

function TYakkoGerador.PodeExecutarPipeline: Boolean;
begin
  Result := Assigned(FInferencePipeline) and FInferencePipeline.PodeExecutar;
end;

function TYakkoGerador.GerarComMensagens(const APrompt: string; const APromptSistema: string; const AMensagens: TArray<TLlamaMensagem>; AMaxTokens: Integer; AAoReceberTexto: TLlamaTextoParcialProc): string;
var
  LRequest: TYakkoInferenceRequest;
  LResult: TYakkoInferenceResult;
begin
  if not Assigned(FInferencePipeline) then
    raise ELlamaGeradorError.Create('Pipeline de inferencia nao configurada no gerador.');

  LRequest := TYakkoInferenceRequest.Create;
  LResult := nil;
  try
    LRequest.Prompt := APrompt;
    LRequest.PromptSistema := APromptSistema;
    LRequest.Mensagens := AMensagens;
    LRequest.MaxTokens := AMaxTokens;
    LRequest.Config := FConfig;
    LRequest.Sessao := FSessao;
    LRequest.ToolManager := FToolManager;
    LRequest.CancellationToken := FCancellationToken;
    LRequest.Events := FEvents;
    LRequest.LegacyOnToken := AAoReceberTexto;

    LResult := FInferencePipeline.Executar(LRequest);
    Result := LResult.TextoGerado;
  finally
    LResult.Free;
    LRequest.Free;
  end;
end;

initialization
  System.Classes.RegisterClass(TYakkoGerador);

end.
