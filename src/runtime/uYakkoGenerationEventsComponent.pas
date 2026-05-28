unit uYakkoGenerationEventsComponent;

{ Eventos estruturados de geracao.
  Responsabilidades:
  - consolidar callbacks de token/finalizacao/erro
  - reduzir acoplamento entre pipeline e consumidores de eventos. }

interface

uses
  System.SysUtils;

type
  { Estatisticas estruturadas de geracao para telemetria e profiling. }
  TYakkoGenerationStats = record
    PromptTokens: Integer;
    GeneratedTokens: Integer;
    TokensPerSecond: Double;
    PromptEvalTimeMs: Double;
    EvalTimeMs: Double;
    TotalTimeMs: Double;
  end;

  TYakkoGenerationState = (
    gsIdle,
    gsGerando,
    gsCancelando,
    gsFinalizado,
    gsFalhou
  );

  TYakkoOnTokenEvent = reference to procedure(const ATokenText: string);
  TYakkoOnFinishedEvent = reference to procedure(const ATextoFinal: string; const AStats: TYakkoGenerationStats);
  TYakkoOnErrorEvent = reference to procedure(const AMensagem: string);
  TYakkoOnCancelledEvent = reference to procedure(const ATextoParcial: string; const AStats: TYakkoGenerationStats);
  TYakkoOnStatisticsEvent = reference to procedure(const AStats: TYakkoGenerationStats);
  TYakkoOnToolCallEvent = reference to procedure(const ARawPayload: string);

  { Estrutura de eventos desacoplada do backend para futura execucao concorrente. }
  TYakkoGenerationEvents = class
  public
    OnToken: TYakkoOnTokenEvent;
    OnFinished: TYakkoOnFinishedEvent;
    OnError: TYakkoOnErrorEvent;
    OnCancelled: TYakkoOnCancelledEvent;
    OnStatistics: TYakkoOnStatisticsEvent;
    OnReasoningToken: TYakkoOnTokenEvent;
    OnToolCall: TYakkoOnToolCallEvent;

    procedure Clear;
  end;

  { Token de cancelamento cooperativo.
    Nao usa excecao para fluxo normal de cancelamento. }
  TYakkoCancellationToken = class
  private
    FCancelled: Boolean;
  public
    constructor Create;
    procedure Cancel;
    procedure Reset;
    function IsCancelled: Boolean;
  end;

implementation

procedure TYakkoGenerationEvents.Clear;
begin
  OnToken := nil;
  OnFinished := nil;
  OnError := nil;
  OnCancelled := nil;
  OnStatistics := nil;
  OnReasoningToken := nil;
  OnToolCall := nil;
end;

constructor TYakkoCancellationToken.Create;
begin
  inherited Create;
  FCancelled := False;
end;

procedure TYakkoCancellationToken.Cancel;
begin
  FCancelled := True;
end;

procedure TYakkoCancellationToken.Reset;
begin
  FCancelled := False;
end;

function TYakkoCancellationToken.IsCancelled: Boolean;
begin
  Result := FCancelled;
end;

end.

