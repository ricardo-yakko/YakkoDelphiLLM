unit uYakkoInferenceOrchestration;

{ Orquestracao backend-agnostic de requests e montagem de contexto.
  Esta camada separa intencao logica da execucao no gerador. }

interface

uses
  System.Classes,
  System.SysUtils,
  System.Generics.Collections,
  uYakkoLlamaTypes;

type
  EYakkoInferenceRequestError = class(Exception);

  TYakkoInferenceMode = (
    imChat,
    imRAG,
    imToolAgent,
    imSummarization,
    imEmbedding,
    imReasoning,
    imStructuredOutput
  );

  TYakkoRetrievedChunk = class
  private
    FMetadata: TDictionary<string, string>;
  public
    SourceId: string;
    Content: string;
    Score: Double;

    constructor Create;
    destructor Destroy; override;

    property Metadata: TDictionary<string, string> read FMetadata;
  end;

  TYakkoInferenceRequest = class
  private
    FMetadata: TDictionary<string, string>;
    FRetrievedChunks: TArray<TYakkoRetrievedChunk>;
  public
    Mode: TYakkoInferenceMode;
    Prompt: string;
    SystemPrompt: string;
    Messages: TArray<TLlamaMensagem>;
    RetrievedContext: string;
    MaxTokens: Integer;
    Temperature: Double;
    UseMemory: Boolean;
    UseTools: Boolean;
    UseReasoning: Boolean;

    constructor Create;
    destructor Destroy; override;

    procedure AddRetrievedChunk(AChunk: TYakkoRetrievedChunk);
    procedure ClearRetrievedChunks;
    procedure Validate;

    property RetrievedChunks: TArray<TYakkoRetrievedChunk> read FRetrievedChunks write FRetrievedChunks;
    property Metadata: TDictionary<string, string> read FMetadata;
  end;

  TYakkoAssembledContext = record
    Prompt: string;
    SystemPrompt: string;
    Messages: TArray<TLlamaMensagem>;
  end;

  TYakkoContextAssembler = class(TComponent)
  private
    function BuildRetrievedContextText(ARequest: TYakkoInferenceRequest): string;
    function ApplyContextBudget(const AText: string; ARequest: TYakkoInferenceRequest; AReserveTokens: Integer): string;
  protected
    procedure ValidateRequest(ARequest: TYakkoInferenceRequest); virtual;
  public
    function BuildPrompt(ARequest: TYakkoInferenceRequest): string; virtual;
    function BuildSystemPrompt(ARequest: TYakkoInferenceRequest): string; virtual;
    function BuildMessages(ARequest: TYakkoInferenceRequest): TArray<TLlamaMensagem>; virtual;
    function Assemble(ARequest: TYakkoInferenceRequest): TYakkoAssembledContext; virtual;
  end;

  TYakkoBasePipeline = class
  public
    function SupportsMode(AMode: TYakkoInferenceMode): Boolean; virtual; abstract;
  end;

  TYakkoChatPipeline = class(TYakkoBasePipeline)
  public
    function SupportsMode(AMode: TYakkoInferenceMode): Boolean; override;
  end;

  TYakkoRAGPipeline = class(TYakkoBasePipeline)
  public
    function SupportsMode(AMode: TYakkoInferenceMode): Boolean; override;
  end;

  TYakkoAgentPipeline = class(TYakkoBasePipeline)
  public
    function SupportsMode(AMode: TYakkoInferenceMode): Boolean; override;
  end;

  TYakkoEmbeddingPipeline = class(TYakkoBasePipeline)
  public
    function SupportsMode(AMode: TYakkoInferenceMode): Boolean; override;
  end;

implementation

{ TYakkoRetrievedChunk }

constructor TYakkoRetrievedChunk.Create;
begin
  inherited Create;
  FMetadata := TDictionary<string, string>.Create;
  SourceId := '';
  Content := '';
  Score := 0;
end;

destructor TYakkoRetrievedChunk.Destroy;
begin
  FreeAndNil(FMetadata);
  inherited;
end;

{ TYakkoInferenceRequest }

constructor TYakkoInferenceRequest.Create;
begin
  inherited Create;
  FMetadata := TDictionary<string, string>.Create;
  FRetrievedChunks := [];
  Messages := [];
  Mode := imChat;
  Prompt := '';
  SystemPrompt := '';
  RetrievedContext := '';
  MaxTokens := -1;
  Temperature := 0;
  UseMemory := False;
  UseTools := False;
  UseReasoning := False;
end;

destructor TYakkoInferenceRequest.Destroy;
begin
  ClearRetrievedChunks;
  FreeAndNil(FMetadata);
  inherited;
end;

procedure TYakkoInferenceRequest.AddRetrievedChunk(AChunk: TYakkoRetrievedChunk);
var
  LIndex: Integer;
begin
  if not Assigned(AChunk) then
    Exit;

  LIndex := Length(FRetrievedChunks);
  SetLength(FRetrievedChunks, LIndex + 1);
  FRetrievedChunks[LIndex] := AChunk;
end;

procedure TYakkoInferenceRequest.ClearRetrievedChunks;
var
  I: Integer;
begin
  for I := 0 to High(FRetrievedChunks) do
    FRetrievedChunks[I].Free;
  FRetrievedChunks := [];
end;

procedure TYakkoInferenceRequest.Validate;
var
  LModeValue: Integer;
begin
  LModeValue := Ord(Mode);
  if (LModeValue < Ord(Low(TYakkoInferenceMode))) or (LModeValue > Ord(High(TYakkoInferenceMode))) then
    raise EYakkoInferenceRequestError.Create('TYakkoInferenceRequest.Mode invalido.');

  if Trim(Prompt) = '' then
    raise EYakkoInferenceRequestError.Create('TYakkoInferenceRequest.Prompt nao pode ser vazio.');

  if Mode = imRAG then
  begin
    if Trim(RetrievedContext) = '' then
      if Length(FRetrievedChunks) = 0 then
        raise EYakkoInferenceRequestError.Create('imRAG requer RetrievedContext ou RetrievedChunks.');

    if UseMemory then
      raise EYakkoInferenceRequestError.Create('imRAG nao pode misturar memoria conversacional automaticamente.');

    if Length(Messages) > 0 then
      raise EYakkoInferenceRequestError.Create('imRAG nao aceita historico conversacional em Messages.');
  end;

  if Mode = imEmbedding then
  begin
    if (Trim(SystemPrompt) <> '') or (Length(Messages) > 0) or UseMemory or UseTools or UseReasoning then
      raise EYakkoInferenceRequestError.Create('imEmbedding deve ser isolado de prompts conversacionais, memoria e tools.');
  end;
end;

{ TYakkoContextAssembler }

function TYakkoContextAssembler.ApplyContextBudget(const AText: string;
  ARequest: TYakkoInferenceRequest; AReserveTokens: Integer): string;
var
  LCharsBudget: Integer;
begin
  Result := Trim(AText);
  if Result = '' then
    Exit;

  if not Assigned(ARequest) or (ARequest.MaxTokens <= 0) then
    Exit;

  LCharsBudget := (ARequest.MaxTokens + AReserveTokens) * 6;
  if (LCharsBudget > 0) and (Length(Result) > LCharsBudget) then
    Result := Trim(Copy(Result, 1, LCharsBudget)) + sLineBreak + '[context-truncated]';
end;

function TYakkoContextAssembler.BuildRetrievedContextText(
  ARequest: TYakkoInferenceRequest): string;
var
  I: Integer;
  LBuilder: TStringList;
begin
  Result := Trim(ARequest.RetrievedContext);
  if Result <> '' then
    Exit(ApplyContextBudget(Result, ARequest, 64));

  if Length(ARequest.RetrievedChunks) = 0 then
    Exit('');

  LBuilder := TStringList.Create;
  try
    for I := 0 to High(ARequest.RetrievedChunks) do
    begin
      if not Assigned(ARequest.RetrievedChunks[I]) then
        Continue;
      if Trim(ARequest.RetrievedChunks[I].Content) = '' then
        Continue;

      if Trim(ARequest.RetrievedChunks[I].SourceId) <> '' then
        LBuilder.Add('[Fonte: ' + Trim(ARequest.RetrievedChunks[I].SourceId) + ']');
      LBuilder.Add(Trim(ARequest.RetrievedChunks[I].Content));
      LBuilder.Add('');
    end;
    Result := ApplyContextBudget(Trim(LBuilder.Text), ARequest, 64);
  finally
    LBuilder.Free;
  end;
end;

procedure TYakkoContextAssembler.ValidateRequest(ARequest: TYakkoInferenceRequest);
begin
  if not Assigned(ARequest) then
    raise EYakkoInferenceRequestError.Create('TYakkoInferenceRequest nao informado.');
  ARequest.Validate;
end;

function TYakkoContextAssembler.BuildPrompt(ARequest: TYakkoInferenceRequest): string;
var
  LRetrieved: string;
begin
  ValidateRequest(ARequest);

  case ARequest.Mode of
    imRAG:
      begin
        LRetrieved := BuildRetrievedContextText(ARequest);
        Result :=
          'Contexto recuperado:' + sLineBreak +
          LRetrieved + sLineBreak + sLineBreak +
          'Pergunta atual:' + sLineBreak +
          Trim(ARequest.Prompt);
      end;
  else
    Result := Trim(ARequest.Prompt);
  end;

  if Result = '' then
    raise EYakkoInferenceRequestError.Create('Falha ao montar prompt final.');
end;

function TYakkoContextAssembler.BuildSystemPrompt(
  ARequest: TYakkoInferenceRequest): string;
begin
  ValidateRequest(ARequest);

  case ARequest.Mode of
    imEmbedding:
      Result := '';
    imRAG:
      begin
        Result := Trim(ARequest.SystemPrompt);
        if Result = '' then
          Result := 'Use apenas o contexto recuperado. Nao misture memoria conversacional nem invente fatos externos.';
      end;
  else
    Result := Trim(ARequest.SystemPrompt);
  end;
end;

function TYakkoContextAssembler.BuildMessages(
  ARequest: TYakkoInferenceRequest): TArray<TLlamaMensagem>;
begin
  ValidateRequest(ARequest);

  case ARequest.Mode of
    imChat,
    imSummarization,
    imToolAgent,
    imReasoning,
    imStructuredOutput:
      Result := ARequest.Messages;
  else
    Result := [];
  end;
end;

function TYakkoContextAssembler.Assemble(
  ARequest: TYakkoInferenceRequest): TYakkoAssembledContext;
begin
  ValidateRequest(ARequest);
  Result.SystemPrompt := BuildSystemPrompt(ARequest);
  Result.Messages := BuildMessages(ARequest);
  Result.Prompt := BuildPrompt(ARequest);
end;

{ TYakkoChatPipeline }

function TYakkoChatPipeline.SupportsMode(AMode: TYakkoInferenceMode): Boolean;
begin
  Result := AMode = imChat;
end;

{ TYakkoRAGPipeline }

function TYakkoRAGPipeline.SupportsMode(AMode: TYakkoInferenceMode): Boolean;
begin
  Result := AMode = imRAG;
end;

{ TYakkoAgentPipeline }

function TYakkoAgentPipeline.SupportsMode(AMode: TYakkoInferenceMode): Boolean;
begin
  Result := AMode in [imToolAgent, imReasoning, imStructuredOutput];
end;

{ TYakkoEmbeddingPipeline }

function TYakkoEmbeddingPipeline.SupportsMode(AMode: TYakkoInferenceMode): Boolean;
begin
  Result := AMode = imEmbedding;
end;

end.
