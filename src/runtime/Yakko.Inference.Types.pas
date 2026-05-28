unit Yakko.Inference.Types;

{ Inference domain model for YakkoDelphiLLM runtime.
  Architectural intent:
  - separate conversational semantics from execution semantics;
  - isolate execution contracts (request/result/state/metrics) from low-level backend code;
  - prepare the runtime for modern streaming inference and richer completion control;
  - keep tool calling, reasoning and future speculative decoding concerns explicit in domain types.

  ConversationState and PromptDocument describe what the model should receive.
  InferenceRequest and InferenceResult describe how execution should happen and what happened.
  This Request/Result boundary reduces coupling and makes runtime migration safer. }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Yakko.Prompt.Document;

type
  TYakkoInferenceState =
  (
    isIdle,
    isPreparing,
    isTokenizing,
    isGenerating,
    isStreaming,
    isCompleted,
    isCancelled,
    isError
  );

  TYakkoGenerationMetrics = class
  private
    FTotalTokens: Integer;
    FPromptTokens: Integer;
    FGeneratedTokens: Integer;
    FPromptTimeMs: Int64;
    FGenerationTimeMs: Int64;
    FTokensPerSecond: Double;
    FStartedAt: TDateTime;
    FFinishedAt: TDateTime;
  public
    constructor Create;

    procedure Clear;
    function Clone: TYakkoGenerationMetrics;
    function ToDebugString: string;

    property TotalTokens: Integer read FTotalTokens write FTotalTokens;
    property PromptTokens: Integer read FPromptTokens write FPromptTokens;
    property GeneratedTokens: Integer read FGeneratedTokens write FGeneratedTokens;
    property PromptTimeMs: Int64 read FPromptTimeMs write FPromptTimeMs;
    property GenerationTimeMs: Int64 read FGenerationTimeMs write FGenerationTimeMs;
    property TokensPerSecond: Double read FTokensPerSecond write FTokensPerSecond;
    property StartedAt: TDateTime read FStartedAt write FStartedAt;
    property FinishedAt: TDateTime read FFinishedAt write FFinishedAt;
  end;

  TYakkoInferenceMetadata = TDictionary<string, string>;

  TYakkoInferenceRequest = class
  private
    FPromptDocument: TYakkoPromptDocument;
    FMaxTokens: Integer;
    FTemperature: Single;
    FTopP: Single;
    FTopK: Integer;
    FMinP: Single;
    FStopSequences: TArray<string>;
    FStream: Boolean;
    FMetadata: TYakkoInferenceMetadata;
    procedure SetPromptDocument(const Value: TYakkoPromptDocument);
  public
    constructor Create;
    destructor Destroy; override;

    function Clone: TYakkoInferenceRequest;
    function ToDebugString: string;

    property PromptDocument: TYakkoPromptDocument read FPromptDocument write SetPromptDocument;
    property MaxTokens: Integer read FMaxTokens write FMaxTokens;
    property Temperature: Single read FTemperature write FTemperature;
    property TopP: Single read FTopP write FTopP;
    property TopK: Integer read FTopK write FTopK;
    property MinP: Single read FMinP write FMinP;
    property StopSequences: TArray<string> read FStopSequences write FStopSequences;
    property Stream: Boolean read FStream write FStream;
    property Metadata: TYakkoInferenceMetadata read FMetadata;
  end;

  TYakkoInferenceResult = class
  private
    FGeneratedText: string;
    FFinishReason: string;
    FState: TYakkoInferenceState;
    FMetrics: TYakkoGenerationMetrics;
    FMetadata: TYakkoInferenceMetadata;
    procedure SetMetrics(const Value: TYakkoGenerationMetrics);
  public
    constructor Create;
    destructor Destroy; override;

    function Clone: TYakkoInferenceResult;
    function ToDebugString: string;

    property GeneratedText: string read FGeneratedText write FGeneratedText;
    property FinishReason: string read FFinishReason write FFinishReason;
    property State: TYakkoInferenceState read FState write FState;
    property Metrics: TYakkoGenerationMetrics read FMetrics write SetMetrics;
    property Metadata: TYakkoInferenceMetadata read FMetadata;
  end;

implementation

procedure CloneStringDictionary(ASource, ADest: TYakkoInferenceMetadata);
var
  LPair: TPair<string, string>;
begin
  if not Assigned(ADest) then
    raise EArgumentNilException.Create('ADest must be assigned.');

  ADest.Clear;
  if not Assigned(ASource) then
    Exit;

  for LPair in ASource do
    ADest.AddOrSetValue(LPair.Key, LPair.Value);
end;

{ TYakkoGenerationMetrics }

constructor TYakkoGenerationMetrics.Create;
begin
  inherited Create;
  Clear;
end;

procedure TYakkoGenerationMetrics.Clear;
begin
  FTotalTokens := 0;
  FPromptTokens := 0;
  FGeneratedTokens := 0;
  FPromptTimeMs := 0;
  FGenerationTimeMs := 0;
  FTokensPerSecond := 0;
  FStartedAt := 0;
  FFinishedAt := 0;
end;

function TYakkoGenerationMetrics.Clone: TYakkoGenerationMetrics;
begin
  Result := TYakkoGenerationMetrics.Create;
  Result.FTotalTokens := FTotalTokens;
  Result.FPromptTokens := FPromptTokens;
  Result.FGeneratedTokens := FGeneratedTokens;
  Result.FPromptTimeMs := FPromptTimeMs;
  Result.FGenerationTimeMs := FGenerationTimeMs;
  Result.FTokensPerSecond := FTokensPerSecond;
  Result.FStartedAt := FStartedAt;
  Result.FFinishedAt := FFinishedAt;
end;

function TYakkoGenerationMetrics.ToDebugString: string;
begin
  Result := Format(
    'TYakkoGenerationMetrics(TotalTokens=%d, PromptTokens=%d, GeneratedTokens=%d, PromptTimeMs=%d, GenerationTimeMs=%d, TokensPerSecond=%.4f)',
    [
      FTotalTokens,
      FPromptTokens,
      FGeneratedTokens,
      FPromptTimeMs,
      FGenerationTimeMs,
      FTokensPerSecond
    ]
  );
end;

{ TYakkoInferenceRequest }

constructor TYakkoInferenceRequest.Create;
begin
  inherited Create;
  FPromptDocument := TYakkoPromptDocument.Create;
  FMaxTokens := 256;
  FTemperature := 0.7;
  FTopP := 0.95;
  FTopK := 40;
  FMinP := 0.05;
  FStopSequences := [];
  FStream := False;
  FMetadata := TYakkoInferenceMetadata.Create;

  { TODO: add speculative decoding policy fields (draft model, max speculative tokens). }
  { TODO: add cancellation token references once cooperative cancellation is introduced. }
  { TODO: add batching fields for grouped request execution. }
  { TODO: add grammar/json-schema constraint references for constrained decoding. }
end;

destructor TYakkoInferenceRequest.Destroy;
begin
  FreeAndNil(FMetadata);
  FreeAndNil(FPromptDocument);
  FStopSequences := nil;
  inherited;
end;

procedure TYakkoInferenceRequest.SetPromptDocument(const Value: TYakkoPromptDocument);
begin
  if Value = FPromptDocument then
    Exit;

  FreeAndNil(FPromptDocument);
  if Assigned(Value) then
    FPromptDocument := Value.Clone
  else
    FPromptDocument := TYakkoPromptDocument.Create;
end;

function TYakkoInferenceRequest.Clone: TYakkoInferenceRequest;
var
  I: Integer;
begin
  Result := TYakkoInferenceRequest.Create;
  try
    Result.SetPromptDocument(FPromptDocument);
    Result.FMaxTokens := FMaxTokens;
    Result.FTemperature := FTemperature;
    Result.FTopP := FTopP;
    Result.FTopK := FTopK;
    Result.FMinP := FMinP;
    Result.FStream := FStream;

    SetLength(Result.FStopSequences, Length(FStopSequences));
    for I := 0 to High(FStopSequences) do
      Result.FStopSequences[I] := FStopSequences[I];

    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoInferenceRequest.ToDebugString: string;
begin
  Result := Format(
    'TYakkoInferenceRequest(MaxTokens=%d, Temperature=%.3f, TopP=%.3f, TopK=%d, MinP=%.3f, Stream=%s, StopSequences=%d, Metadata=%d, PromptBlocks=%d)',
    [
      FMaxTokens,
      FTemperature,
      FTopP,
      FTopK,
      FMinP,
      BoolToStr(FStream, True),
      Length(FStopSequences),
      FMetadata.Count,
      FPromptDocument.BlockCount
    ]
  );
end;

{ TYakkoInferenceResult }

constructor TYakkoInferenceResult.Create;
begin
  inherited Create;
  FGeneratedText := '';
  FFinishReason := '';
  FState := isIdle;
  FMetrics := TYakkoGenerationMetrics.Create;
  FMetadata := TYakkoInferenceMetadata.Create;

  { TODO: add reasoning trace summary fields once private reasoning traces are modeled. }
  { TODO: add token attribution containers once token-level tracing is available. }
  { TODO: add KV cache reuse diagnostics for backend-specific optimizations. }
  { TODO: add multimodal inference output descriptors when non-text outputs are supported. }
end;

destructor TYakkoInferenceResult.Destroy;
begin
  FreeAndNil(FMetadata);
  FreeAndNil(FMetrics);
  inherited;
end;

procedure TYakkoInferenceResult.SetMetrics(const Value: TYakkoGenerationMetrics);
begin
  if Value = FMetrics then
    Exit;

  FreeAndNil(FMetrics);
  if Assigned(Value) then
    FMetrics := Value.Clone
  else
    FMetrics := TYakkoGenerationMetrics.Create;
end;

function TYakkoInferenceResult.Clone: TYakkoInferenceResult;
begin
  Result := TYakkoInferenceResult.Create;
  try
    Result.FGeneratedText := FGeneratedText;
    Result.FFinishReason := FFinishReason;
    Result.FState := FState;
    Result.SetMetrics(FMetrics);
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoInferenceResult.ToDebugString: string;
begin
  Result := Format(
    'TYakkoInferenceResult(State=%d, FinishReason=%s, GeneratedTextLength=%d, Metadata=%d, Metrics=%s)',
    [
      Ord(FState),
      FFinishReason,
      Length(FGeneratedText),
      FMetadata.Count,
      FMetrics.ToDebugString
    ]
  );
end;

end.
