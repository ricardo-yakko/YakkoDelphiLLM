unit uYakkoStudioRagModal;

interface

uses
  System.Classes,
  System.SysUtils,
  System.Math,
  System.Types,
  System.IOUtils,
  System.Generics.Collections,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.Controls,
  Vcl.Dialogs,
  FireDAC.Comp.UI,
  FireDAC.VCLUI.Wait,
  uYakkoLLM,
  uYakkoLlamaTypes,
  uYakkoFullExportsComponent,
  uYakkoModeloComponent,
  uYakkoContextoComponent,
  uYakkoInferenceOrchestration,
  uYakkoVectorStoreSQLite,
  uYakkoEngineComponent;

type
  TRagChunk = record
    SourceFile: string;
    ChunkText: string;
    Embedding: TArray<Single>;
  end;

  TYakkoStudioRagModalForm = class(TForm)
    LbArquivos: TLabel;
    LbPergunta: TLabel;
    LbTopK: TLabel;
    LbMaxTokens: TLabel;
    LbStatus: TLabel;

    MemoArquivos: TMemo;
    MemoPergunta: TMemo;
    MemoResposta: TMemo;

    BtnSelecionarArquivos: TButton;
    BtnGerarEmbeddings: TButton;
    BtnPerguntar: TButton;
    BtnFechar: TButton;

    EdTopK: TEdit;
    EdMaxTokens: TEdit;
  private
    FEngine: TYakkoEngine;
    FEmbeddingExports: TYakkoFullExports;
    FEmbeddingModelo: TYakkoModelo;
    FEmbeddingContexto: TYakkoContexto;
    FEmbeddingModelPath: string;
    FFiles: TStringList;
    FChunks: TArray<TRagChunk>;
    FVectorStore: TYakkoVectorStoreSQLite;
    FWaitCursor: TFDGUIxWaitCursor;

    procedure UpdateStatus(const AText: string);
    procedure EnsureEmbeddingRuntime;
    function EnsureReadyForEmbedding: Boolean;
    function ResolveEmbeddingModelPath: string;
    function PrepareTextForEmbedding(const AText: string; AIsQuery: Boolean): string;
    function ReadTextFileSmart(const AFileName: string): string;
    function SplitTextIntoChunks(const AText: string; AChunkSize: Integer; AOverlap: Integer): TArray<string>;
    function TokenizeUtf8(const ATextUtf8: UTF8String): TArray<Int32>;
    function ComputeEmbedding(const AText: string; AIsQuery: Boolean = False): TArray<Single>;
    function InferLabelFromFileName(const AFileName: string): string;
    function GetVectorStorePath: string;
    function GetSelectedFilesArray: TArray<string>;
    function BuildContextFromTopK(const AQuestionEmbedding: TArray<Single>; ATopK: Integer;
      out ASelectedCount: Integer; out ABestScore: Single): string;

  published
    procedure BtnSelecionarArquivosClick(Sender: TObject);
    procedure BtnGerarEmbeddingsClick(Sender: TObject);
    procedure BtnPerguntarClick(Sender: TObject);
    procedure BtnFecharClick(Sender: TObject);

  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    class function ExecuteRagOnce(AEngine: TYakkoEngine; const AFilesCsv, AQuestion: string;
      ATopK, AMaxTokens: Integer; out AOutput: string; const AEmbeddingModelPath: string = ''): Boolean;

    property Engine: TYakkoEngine read FEngine write FEngine;
    property EmbeddingModelPath: string read FEmbeddingModelPath write FEmbeddingModelPath;
  end;

implementation

{$R *.dfm}

type
  TLlamaToken = Int32;
  PLlamaToken = ^TLlamaToken;
  TLLamaPos = Int32;
  PLLamaPos = ^TLLamaPos;
  TLlamaSeqId = Int32;
  PLlamaSeqId = ^TLlamaSeqId;
  PPLlamaSeqId = ^PLlamaSeqId;

  TLlamaBatch = record
    n_tokens: Int32;
    token: PLlamaToken;
    embd: PSingle;
    pos: PLLamaPos;
    n_seq_id: ^Int32;
    seq_id: PPLlamaSeqId;
    logits: PShortInt;
  end;

  TFnTokenize = function(vocab: TLlamaVocabHandle; text: PAnsiChar; text_len: Int32;
    tokens: PLlamaToken; n_tokens_max: Int32; add_special: Boolean; parse_special: Boolean): Int32; cdecl;
  TFnBatchGetOne = function(tokens: PLlamaToken; n_tokens: Int32): TLlamaBatch; cdecl;
  TFnDecode = function(ctx: TLlamaContextoHandle; batch: TLlamaBatch): Int32; cdecl;
  TFnEncode = function(ctx: TLlamaContextoHandle; batch: TLlamaBatch): Int32; cdecl;
  TFnContextNBatch = function(ctx: TLlamaContextoHandle): Cardinal; cdecl;
  TFnModelHasEncoder = function(model: TLlamaModelHandle): Boolean; cdecl;
  TFnSetEmbeddings = procedure(ctx: TLlamaContextoHandle; embeddings: Boolean); cdecl;
  TFnGetEmbeddings = function(ctx: TLlamaContextoHandle): PSingle; cdecl;
  TFnGetEmbeddingsIth = function(ctx: TLlamaContextoHandle; i: Int32): PSingle; cdecl;
  TFnGetEmbeddingsSeq = function(ctx: TLlamaContextoHandle; seq_id: Int32): PSingle; cdecl;

{ TYakkoStudioRagModalForm }

constructor TYakkoStudioRagModalForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEngine := nil;
  FEmbeddingExports := nil;
  FEmbeddingModelo := nil;
  FEmbeddingContexto := nil;
  FEmbeddingModelPath := '';
  FFiles := TStringList.Create;
  FVectorStore := nil;
  FWaitCursor := TFDGUIxWaitCursor.Create(Self);
  FWaitCursor.Provider := 'Forms';
  SetLength(FChunks, 0);
end;

destructor TYakkoStudioRagModalForm.Destroy;
begin
  SetLength(FChunks, 0);
  if Assigned(FEmbeddingContexto) and FEmbeddingContexto.EstaAberto then
    FEmbeddingContexto.Fechar;
  if Assigned(FEmbeddingModelo) and FEmbeddingModelo.EstaCarregado then
    FEmbeddingModelo.Descarregar;
  FreeAndNil(FEmbeddingContexto);
  FreeAndNil(FEmbeddingModelo);
  FreeAndNil(FEmbeddingExports);
  FreeAndNil(FVectorStore);
  FreeAndNil(FFiles);
  inherited;
end;

procedure TYakkoStudioRagModalForm.UpdateStatus(const AText: string);
begin
  LbStatus.Caption := 'Status: ' + AText;
  Application.ProcessMessages;
end;

procedure TYakkoStudioRagModalForm.BtnSelecionarArquivosClick(Sender: TObject);
var
  LDialog: TOpenDialog;
  I: Integer;
begin
  LDialog := TOpenDialog.Create(Self);
  try
    LDialog.Options := [ofFileMustExist, ofAllowMultiSelect, ofEnableSizing];
    LDialog.Filter :=
      'Textos|*.txt;*.md;*.log;*.csv;*.json;*.xml;*.pas;*.dpr;*.ini|Todos|*.*';

    if not LDialog.Execute then
      Exit;

    FFiles.Assign(LDialog.Files);
    MemoArquivos.Lines.BeginUpdate;
    try
      MemoArquivos.Clear;
      for I := 0 to FFiles.Count - 1 do
        MemoArquivos.Lines.Add(FFiles[I]);
    finally
      MemoArquivos.Lines.EndUpdate;
    end;

    SetLength(FChunks, 0);
    UpdateStatus(Format('%d arquivo(s) selecionado(s). Gere embeddings.', [FFiles.Count]));
  finally
    LDialog.Free;
  end;
end;

procedure TYakkoStudioRagModalForm.EnsureEmbeddingRuntime;
var
  LEmbeddingModelPath: string;
  LDllPath: string;
  LNeedsModelReload: Boolean;
begin
  if not Assigned(FEngine) then
    raise Exception.Create('Engine principal nao configurado para embeddings.');

  if FEmbeddingExports = nil then
    FEmbeddingExports := TYakkoFullExports.Create(nil);

  if FEmbeddingModelo = nil then
  begin
    FEmbeddingModelo := TYakkoModelo.Create(nil);
    FEmbeddingModelo.FullExports := FEmbeddingExports;
  end;

  if FEmbeddingContexto = nil then
  begin
    FEmbeddingContexto := TYakkoContexto.Create(nil);
    FEmbeddingContexto.Modelo := FEmbeddingModelo;
    FEmbeddingContexto.NCtxPadrao := 4096;
  end;

  LEmbeddingModelPath := ResolveEmbeddingModelPath;
  LDllPath := Trim(FEngine.Modelo.DllPath);
  if LDllPath = '' then
    LDllPath := Trim(FEngine.FullExports.DllPath);

  FEmbeddingExports.DllPath := LDllPath;
  FEmbeddingModelo.FullExports := FEmbeddingExports;

  LNeedsModelReload := (not FEmbeddingModelo.EstaCarregado)
    or (not SameText(FEmbeddingModelo.Caminho, LEmbeddingModelPath))
    or (not SameText(Trim(FEmbeddingModelo.DllPath), LDllPath));

  if LNeedsModelReload then
  begin
    if FEmbeddingContexto.EstaAberto then
      FEmbeddingContexto.Fechar;
    if FEmbeddingModelo.EstaCarregado then
      FEmbeddingModelo.Descarregar;

    FEmbeddingModelo.DllPath := LDllPath;
    FEmbeddingModelo.GpuLayersPadrao := FEngine.Modelo.GpuLayersPadrao;
    FEmbeddingModelo.ModelPath := LEmbeddingModelPath;
    FEmbeddingModelo.Carregar(LEmbeddingModelPath, FEmbeddingModelo.GpuLayersPadrao);
    FEmbeddingContexto.Modelo := FEmbeddingModelo;
  end;
end;

function TYakkoStudioRagModalForm.EnsureReadyForEmbedding: Boolean;
begin
  EnsureEmbeddingRuntime;
  Result := Assigned(FEmbeddingModelo)
    and Assigned(FEmbeddingContexto)
    and FEmbeddingModelo.EstaCarregado;
end;

function TYakkoStudioRagModalForm.ResolveEmbeddingModelPath: string;
var
  LBaseDir: string;
begin
  if Trim(FEmbeddingModelPath) <> '' then
    Exit(Trim(FEmbeddingModelPath));

  if Assigned(FEngine) and Assigned(FEngine.Paths) and (Trim(FEngine.Paths.ModeloEmbeddings) <> '') then
    Exit(Trim(FEngine.Paths.ModeloEmbeddings));

  if Assigned(FEngine) and Assigned(FEngine.Modelo) and (Trim(FEngine.Modelo.ModelPath) <> '') then
    LBaseDir := ExtractFileDir(FEngine.Modelo.ModelPath)
  else
    LBaseDir := TPath.Combine(TPath.GetDocumentsPath, 'harmonica.io\models');

  Result := TPath.Combine(LBaseDir, 'nomic-embed-text-v1.5.Q4_K_M.gguf');
  if FileExists(Result) then
    Exit;

  Result := TPath.Combine(LBaseDir, 'Qwen3-Embedding-0.6B-Q8_0.gguf');
  if FileExists(Result) then
    Exit;

  if Assigned(FEngine) and Assigned(FEngine.Modelo) then
    Result := Trim(FEngine.Modelo.ModelPath)
  else
    Result := '';
end;

function TYakkoStudioRagModalForm.PrepareTextForEmbedding(const AText: string; AIsQuery: Boolean): string;
var
  LModelPath: string;
begin
  Result := Trim(AText);
  LModelPath := LowerCase(ResolveEmbeddingModelPath);
  if Pos('nomic-embed-text', LModelPath) > 0 then
  begin
    if AIsQuery then
      Result := 'search_query: ' + Result
    else
      Result := 'search_document: ' + Result;
    Exit;
  end;

  if AIsQuery and (Pos('qwen3-embedding', LModelPath) > 0) then
  begin
    Result :=
      'Instruct: Given a product catalog query, retrieve relevant passages that answer the query.' + sLineBreak +
      'Query: ' + Result;
    Exit;
  end;

  if AIsQuery and (Pos('multilingual-e5', LModelPath) > 0) then
  begin
    Result :=
      'Instruct: Given a product catalog query, retrieve relevant passages that answer the query.' + sLineBreak +
      'Query: ' + Result;
  end;
end;

function TYakkoStudioRagModalForm.ReadTextFileSmart(const AFileName: string): string;
var
  LBytes: TBytes;
  LUtf8: TEncoding;
begin
  Result := '';
  if not FileExists(AFileName) then
    Exit;

  LBytes := TFile.ReadAllBytes(AFileName);
  if Length(LBytes) = 0 then
    Exit;

  LUtf8 := TEncoding.UTF8;
  try
    Result := LUtf8.GetString(LBytes);
  except
    Result := TFile.ReadAllText(AFileName, TEncoding.Default);
  end;

  Result := Trim(Result);
end;

function TYakkoStudioRagModalForm.SplitTextIntoChunks(const AText: string; AChunkSize: Integer; AOverlap: Integer): TArray<string>;
var
  LPos: Integer;
  LStep: Integer;
  LChunk: string;
  LList: TList<string>;
begin
  LList := TList<string>.Create;
  try
    if AChunkSize < 200 then
      AChunkSize := 200;
    if AOverlap < 0 then
      AOverlap := 0;
    if AOverlap >= AChunkSize then
      AOverlap := AChunkSize div 4;

    LStep := AChunkSize - AOverlap;
    LPos := 1;
    while LPos <= Length(AText) do
    begin
      LChunk := Trim(Copy(AText, LPos, AChunkSize));
      if LChunk <> '' then
        LList.Add(LChunk);
      Inc(LPos, LStep);
    end;

    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

function TYakkoStudioRagModalForm.TokenizeUtf8(const ATextUtf8: UTF8String): TArray<Int32>;
var
  LNeeded: Integer;
  LCount: Integer;
begin
  Result := nil;

  if not Assigned(llama_tokenize) then
    raise Exception.Create('Export llama_tokenize nao disponivel na DLL.');

  if not Assigned(FEmbeddingModelo) then
    raise Exception.Create('Modelo de embedding nao configurado para tokenizacao.');

  LNeeded := TFnTokenize(llama_tokenize)(FEmbeddingModelo.Vocab, PAnsiChar(Pointer(ATextUtf8)), Length(ATextUtf8), nil, 0, True, True);
  if LNeeded >= 0 then
    raise Exception.Create('Falha ao calcular tamanho da tokenizacao de embedding.');

  SetLength(Result, Abs(LNeeded));
  if Length(Result) = 0 then
    Exit;

  LCount := TFnTokenize(llama_tokenize)(
    FEmbeddingModelo.Vocab,
    PAnsiChar(Pointer(ATextUtf8)),
    Length(ATextUtf8),
    @Result[0],
    Length(Result),
    True,
    True
  );

  if LCount < 0 then
    raise Exception.Create('Falha na tokenizacao para embedding.');

  if LCount <> Length(Result) then
    SetLength(Result, LCount);
end;

function TYakkoStudioRagModalForm.ComputeEmbedding(const AText: string; AIsQuery: Boolean): TArray<Single>;
var
  LTextUtf8: UTF8String;
  LTokens: TArray<Int32>;
  LChunkEmbedding: TArray<Single>;
  LAcumulado: TArray<Single>;
  LChunkCount: Integer;
  LOffset: Integer;
  LChunkSize: Integer;
  LChunkTokens: TArray<Int32>;
  LMaxTokensPerCall: Integer;
  I: Integer;
  LNorm: Double;

  function ComputeEmbeddingFromTokens(const ATokens: TArray<Int32>): TArray<Single>;
  var
    LBatch: TLlamaBatch;
    LRes: Integer;
    LEmb: PSingle;
    LDim: Integer;
    LNeededCtx: Cardinal;
    LRetried: Boolean;
  begin
    SetLength(Result, 0);
    if Length(ATokens) = 0 then
      Exit;

    LNeededCtx := Cardinal(Max(Length(ATokens) + 8, 256));
    if (not FEmbeddingContexto.EstaAberto) or (FEmbeddingContexto.NCtx < LNeededCtx) then
      FEmbeddingContexto.Abrir(LNeededCtx, FEngine.Config.Threads);

    LRetried := False;
    repeat
      TFnSetEmbeddings(llama_set_embeddings)(FEmbeddingContexto.Handle, True);
      LBatch := TFnBatchGetOne(llama_batch_get_one)(@ATokens[0], Length(ATokens));

      if Assigned(llama_model_has_encoder) and TFnModelHasEncoder(llama_model_has_encoder)(FEmbeddingModelo.Handle) then
      begin
        if not Assigned(llama_encode) then
          raise Exception.Create('Export llama_encode nao disponivel.');
        LRes := TFnEncode(llama_encode)(FEmbeddingContexto.Handle, LBatch);
      end
      else
      begin
        if not Assigned(llama_decode) then
          raise Exception.Create('Export llama_decode nao disponivel.');
        LRes := TFnDecode(llama_decode)(FEmbeddingContexto.Handle, LBatch);
      end;

      if (LRes = 1) and (not LRetried) then
      begin
        LRetried := True;
        FEmbeddingContexto.Fechar;
        FEmbeddingContexto.Abrir(LNeededCtx, FEngine.Config.Threads);
        Continue;
      end;

      Break;
    until False;

    if LRes <> 0 then
      raise Exception.CreateFmt('Falha ao calcular embedding (codigo %d).', [LRes]);

    LEmb := nil;
    if Assigned(llama_get_embeddings_seq) then
      LEmb := TFnGetEmbeddingsSeq(llama_get_embeddings_seq)(FEmbeddingContexto.Handle, 0);
    if (LEmb = nil) and Assigned(llama_get_embeddings_ith) then
      LEmb := TFnGetEmbeddingsIth(llama_get_embeddings_ith)(FEmbeddingContexto.Handle, Length(ATokens) - 1);
    if LEmb = nil then
      LEmb := TFnGetEmbeddings(llama_get_embeddings)(FEmbeddingContexto.Handle);

    if LEmb = nil then
      raise Exception.Create('Nao foi possivel obter vetor de embedding.');

    LDim := FEmbeddingModelo.NEmbedding;
    if LDim <= 0 then
      raise Exception.Create('Dimensao de embedding invalida.');

    SetLength(Result, LDim);
    Move(LEmb^, Result[0], LDim * SizeOf(Single));
  end;
begin
  SetLength(Result, 0);

  if not EnsureReadyForEmbedding then
    raise Exception.Create('Engine/Modelo/Contexto nao estao prontos para embeddings.');

  if not Assigned(llama_batch_get_one) then
    raise Exception.Create('Export llama_batch_get_one nao disponivel.');
  if not Assigned(llama_set_embeddings) then
    raise Exception.Create('Export llama_set_embeddings nao disponivel.');
  if not Assigned(llama_get_embeddings) then
    raise Exception.Create('Export llama_get_embeddings nao disponivel.');

  LTextUtf8 := UTF8String(PrepareTextForEmbedding(AText, AIsQuery));
  if LTextUtf8 = '' then
    Exit;

  LTokens := TokenizeUtf8(LTextUtf8);
  if Length(LTokens) = 0 then
    Exit;

  LMaxTokensPerCall := 0;
  if Assigned(llama_n_batch) and FEmbeddingContexto.EstaAberto then
    LMaxTokensPerCall := Integer(TFnContextNBatch(llama_n_batch)(FEmbeddingContexto.Handle));

  if LMaxTokensPerCall <= 0 then
    LMaxTokensPerCall := Integer(FEmbeddingContexto.NCtx);
  if LMaxTokensPerCall > 64 then
    Dec(LMaxTokensPerCall, 32);

  if (LMaxTokensPerCall <= 0) or (Length(LTokens) <= LMaxTokensPerCall) then
    Result := ComputeEmbeddingFromTokens(LTokens)
  else
  begin
    SetLength(LAcumulado, 0);
    LChunkCount := 0;
    LOffset := 0;

    while LOffset < Length(LTokens) do
    begin
      LChunkSize := Min(LMaxTokensPerCall, Length(LTokens) - LOffset);
      SetLength(LChunkTokens, LChunkSize);
      Move(LTokens[LOffset], LChunkTokens[0], LChunkSize * SizeOf(Int32));

      LChunkEmbedding := ComputeEmbeddingFromTokens(LChunkTokens);
      if Length(LChunkEmbedding) > 0 then
      begin
        if Length(LAcumulado) = 0 then
          SetLength(LAcumulado, Length(LChunkEmbedding));

        for I := 0 to High(LAcumulado) do
          LAcumulado[I] := LAcumulado[I] + LChunkEmbedding[I];

        Inc(LChunkCount);
      end;

      Inc(LOffset, LChunkSize);
    end;

    if LChunkCount <= 0 then
      Exit;

    SetLength(Result, Length(LAcumulado));
    for I := 0 to High(Result) do
      Result[I] := LAcumulado[I] / LChunkCount;
  end;

  LNorm := 0;
  for I := 0 to High(Result) do
    LNorm := LNorm + Result[I] * Result[I];

  LNorm := Sqrt(LNorm);
  if LNorm > 0 then
    for I := 0 to High(Result) do
      Result[I] := Result[I] / LNorm;
end;

function TYakkoStudioRagModalForm.InferLabelFromFileName(const AFileName: string): string;
var
  LName: string;
begin
  LName := AnsiUpperCase(AFileName);
  if Pos('PASTA-TERMICA', LName) > 0 then
    Exit('pasta termica');
  if Pos('PASTA-SOLDA', LName) > 0 then
    Exit('pasta de solda');
  if Pos('SOLDA-FIO', LName) > 0 then
    Exit('solda em fio');
  if Pos('FLUXO', LName) > 0 then
    Exit('fluxo');
  Result := '';
end;

procedure TYakkoStudioRagModalForm.BtnGerarEmbeddingsClick(Sender: TObject);
var
  I: Integer;
  LChunkIndex: Integer;
  LErros: Integer;
  LFileText: string;
  LFileChunks: TArray<string>;
  LChunkText: string;
  LChunk: TRagChunk;
  LChunkList: TList<TRagChunk>;
begin
  if FFiles.Count = 0 then
    raise Exception.Create('Selecione ao menos um arquivo antes de gerar embeddings.');

  if not EnsureReadyForEmbedding then
    raise Exception.Create('Inicialize o modelo antes de gerar embeddings.');

  LChunkList := TList<TRagChunk>.Create;
  try
    LErros := 0;
    UpdateStatus('Gerando embeddings...');

    if FVectorStore = nil then
      FVectorStore := TYakkoVectorStoreSQLite.Create(GetVectorStorePath);

    for I := 0 to FFiles.Count - 1 do
    begin
      UpdateStatus(Format('Lendo %s', [ExtractFileName(FFiles[I])]));
      LFileText := ReadTextFileSmart(FFiles[I]);
      if LFileText = '' then
        Continue;

      LFileChunks := SplitTextIntoChunks(LFileText, 900, 120);
      FVectorStore.DeleteSourceChunks(FFiles[I]);
      LChunkIndex := 0;
      for LChunkText in LFileChunks do
      begin
        try
          LChunk.SourceFile := FFiles[I];
          LChunk.ChunkText := LChunkText;
          LChunk.Embedding := ComputeEmbedding(LChunkText, False);
          if Length(LChunk.Embedding) > 0 then
          begin
            LChunkList.Add(LChunk);
            FVectorStore.SaveChunk(FFiles[I], LChunkIndex, LChunkText, LChunk.Embedding);
            Inc(LChunkIndex);
          end;
        except
          on E: Exception do
          begin
            Inc(LErros);
            UpdateStatus('Aviso: chunk ignorado (' + ExtractFileName(FFiles[I]) + '): ' + E.Message);
          end;
        end;
      end;
    end;

    FChunks := LChunkList.ToArray;
    UpdateStatus(Format('Embeddings gerados: %d chunk(s), erros: %d.', [Length(FChunks), LErros]));
  finally
    LChunkList.Free;
  end;
end;

function TYakkoStudioRagModalForm.BuildContextFromTopK(const AQuestionEmbedding: TArray<Single>; ATopK: Integer;
  out ASelectedCount: Integer; out ABestScore: Single): string;
var
  I: Integer;
  LSourceName: string;
  LLabelHint: string;
  LDbResults: TArray<TYakkoVectorSearchResult>;
  LBuilder: TStringList;
begin
  ASelectedCount := 0;
  ABestScore := 0;

  if Assigned(FVectorStore) and (FFiles <> nil) and (FFiles.Count > 0) then
  begin
    LDbResults := FVectorStore.SearchSimilar(AQuestionEmbedding, ATopK, MemoPergunta.Text, GetSelectedFilesArray, 0.20);
    if Length(LDbResults) > 0 then
    begin
      ASelectedCount := Length(LDbResults);
      ABestScore := LDbResults[0].Similaridade;
      LBuilder := TStringList.Create;
      try
        LBuilder.Add('[VectorBackend: sqlite-vec]');
        LBuilder.Add('');

        for I := 0 to High(LDbResults) do
        begin
          LSourceName := ExtractFileName(LDbResults[I].SourceFile);
          LBuilder.Add(Format('[Fonte: %s | score=%.3f]', [LSourceName, LDbResults[I].Similaridade]));
          LLabelHint := InferLabelFromFileName(LSourceName);
          if LLabelHint <> '' then
          begin
            LBuilder.Add('[Rotulo-sugerido-por-nome: ' + LLabelHint + ']');
            if LLabelHint = 'pasta termica' then
              LBuilder.Add('[Uso-termico-sugerido: indicado para interface termica de dissipador]')
            else if (LLabelHint = 'fluxo') or (LLabelHint = 'pasta de solda') or (LLabelHint = 'solda em fio') then
              LBuilder.Add('[Uso-termico-sugerido: nao indicado como pasta termica para dissipador]');
          end;
          LBuilder.Add(LDbResults[I].Content);
          LBuilder.Add('');
        end;
        Exit(Trim(LBuilder.Text));
      finally
        LBuilder.Free;
      end;
    end;
  end;

  Result := '';
end;

function TYakkoStudioRagModalForm.GetVectorStorePath: string;
begin
  Result := TPath.Combine(
    ExtractFilePath(ParamStr(0)),
    ChangeFileExt(ExtractFileName(ResolveEmbeddingModelPath), '') + '.rag-cache.sqlite'
  );
end;

function TYakkoStudioRagModalForm.GetSelectedFilesArray: TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, FFiles.Count);
  for I := 0 to FFiles.Count - 1 do
    Result[I] := FFiles[I];
end;

procedure TYakkoStudioRagModalForm.BtnPerguntarClick(Sender: TObject);
var
  LQuestion: string;
  LTopK: Integer;
  LMaxTokens: Integer;
  LQuestionEmbedding: TArray<Single>;
  LContext: string;
  LSystemPrompt: string;
  LResposta: string;
  LSelectedCount: Integer;
  LBestScore: Single;
  LRequest: TYakkoInferenceRequest;
  LAssembler: TYakkoContextAssembler;
  LAssembled: TYakkoAssembledContext;
  LOwnsAssembler: Boolean;
begin
  if not EnsureReadyForEmbedding then
    raise Exception.Create('Inicialize o engine antes de perguntar.');

  if Length(FChunks) = 0 then
    raise Exception.Create('Ainda nao ha embeddings. Clique em Gerar Embeddings primeiro.');

  LQuestion := Trim(MemoPergunta.Text);
  if LQuestion = '' then
    raise Exception.Create('Digite uma pergunta.');

  LTopK := StrToIntDef(Trim(EdTopK.Text), 4);
  if LTopK < 1 then
    LTopK := 1;

  LMaxTokens := StrToIntDef(Trim(EdMaxTokens.Text), 1024);
  if LMaxTokens < 64 then
    LMaxTokens := 64;

  UpdateStatus('Calculando embedding da pergunta...');
  LQuestionEmbedding := ComputeEmbedding(LQuestion, True);

  UpdateStatus('Buscando chunks similares...');
  LContext := BuildContextFromTopK(LQuestionEmbedding, LTopK, LSelectedCount, LBestScore);
  if Trim(LContext) = '' then
    raise Exception.Create('Nao foi possivel recuperar contexto relevante para a pergunta.');

  LSystemPrompt :=
    'Voce e um assistente RAG tecnico para catalogo de componentes. ' +
    'Use APENAS fatos do CONTEXTO RECUPERADO e nunca invente componentes, valores ou aplicacoes. ' +
    'Se a evidencia for insuficiente, responda exatamente: "Nao encontrei evidencias suficientes nos componentes analisados." ' +
    'Se houver evidencia, cada afirmacao deve citar explicitamente a fonte e um trecho literal curto da evidencia. ' +
    'Nao faca inferencias que nao estejam textualmente apoiadas no contexto. ' +
    'Quando houver [Rotulo-sugerido-por-nome] e [Uso-termico-sugerido], trate esses campos como evidencia prioritaria. ' +
    'Finalize com "Fontes:" listando apenas nomes de arquivos presentes no contexto.';

  UpdateStatus('Gerando resposta RAG...');
  LRequest := TYakkoInferenceRequest.Create;
  LOwnsAssembler := not Assigned(FEngine.ContextAssembler);
  if LOwnsAssembler then
    LAssembler := TYakkoContextAssembler.Create(nil)
  else
    LAssembler := FEngine.ContextAssembler;
  try
    LRequest.Mode := imRAG;
    LRequest.Prompt :=
      Format('Qualidade da recuperacao: %d trecho(s), melhor score %.3f.', [LSelectedCount, LBestScore]) + sLineBreak +
      'Priorize trechos com score maior.' + sLineBreak + sLineBreak +
      'Formato obrigatorio da resposta:' + sLineBreak +
      '- Item/Resposta: <conteudo objetivo>' + sLineBreak +
      '- Evidencia: "<citacao literal curta do contexto>"' + sLineBreak +
      '- Fonte: <nome-do-arquivo.json>' + sLineBreak +
      'Se nao houver evidencia literal para uma parte da pergunta, diga isso explicitamente.' + sLineBreak + sLineBreak +
      LQuestion;
    LRequest.SystemPrompt := LSystemPrompt;
    LRequest.RetrievedContext := LContext;
    LRequest.Messages := [];
    LRequest.MaxTokens := LMaxTokens;
    LRequest.UseMemory := False;
    LRequest.UseTools := False;
    LRequest.UseReasoning := False;

    LAssembled := LAssembler.Assemble(LRequest);
    LResposta := FEngine.Gerador.GerarComMensagens(LAssembled.Prompt, LAssembled.SystemPrompt, LAssembled.Messages, LMaxTokens, nil);
  finally
    LRequest.Free;
    if LOwnsAssembler then
      LAssembler.Free;
  end;
  LResposta := FEngine.Chat.SanitizeModelResponseText(LResposta);

  MemoResposta.Lines.Text := LResposta;
  UpdateStatus('Resposta gerada.');
end;

procedure TYakkoStudioRagModalForm.BtnFecharClick(Sender: TObject);
begin
  ModalResult := mrOk;
end;

class function TYakkoStudioRagModalForm.ExecuteRagOnce(AEngine: TYakkoEngine; const AFilesCsv, AQuestion: string;
  ATopK, AMaxTokens: Integer; out AOutput: string; const AEmbeddingModelPath: string): Boolean;
var
  LForm: TYakkoStudioRagModalForm;
  LItems: TArray<string>;
  LItem: string;
begin
  AOutput := '';

  LForm := TYakkoStudioRagModalForm.Create(nil);
  try
    LForm.Engine := AEngine;
    LForm.EmbeddingModelPath := Trim(AEmbeddingModelPath);
    if Trim(AFilesCsv) <> '' then
    begin
      LItems := AFilesCsv.Split([';'], TStringSplitOptions.ExcludeEmpty);
      for LItem in LItems do
        if FileExists(Trim(LItem)) then
          LForm.FFiles.Add(Trim(LItem));
    end;

    if LForm.FFiles.Count = 0 then
      raise Exception.Create('Nenhum arquivo valido foi informado em --files.');

    LForm.EdTopK.Text := IntToStr(ATopK);
    LForm.EdMaxTokens.Text := IntToStr(AMaxTokens);
    LForm.MemoPergunta.Lines.Text := Trim(AQuestion);

    LForm.BtnGerarEmbeddingsClick(nil);
    LForm.BtnPerguntarClick(nil);

    AOutput := Trim(LForm.MemoResposta.Lines.Text);
    Result := AOutput <> '';
  finally
    LForm.Free;
  end;
end;

end.




