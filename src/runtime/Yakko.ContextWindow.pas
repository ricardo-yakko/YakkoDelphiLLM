unit Yakko.ContextWindow;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Yakko.Message;

type
  TYakkoContextWindowMetadata = TDictionary<string, string>;

  TYakkoContextWindow = class
  private
    FMaxMessages: Integer;
    FRecentMessages: TYakkoMessageList;
    FSummaryPlaceholders: TList<string>;
    FMetadata: TYakkoContextWindowMetadata;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    function Clone: TYakkoContextWindow;
    function ToDebugString: string;

    property MaxMessages: Integer read FMaxMessages write FMaxMessages;
    property RecentMessages: TYakkoMessageList read FRecentMessages;
    property SummaryPlaceholders: TList<string> read FSummaryPlaceholders;
    property Metadata: TYakkoContextWindowMetadata read FMetadata;
  end;

  TYakkoContextWindowManager = class
  public
    procedure AddMessage(AWindow: TYakkoContextWindow; AMessage: TYakkoMessage);
    procedure TrimToLimit(AWindow: TYakkoContextWindow);
    function ValidateWindow(AWindow: TYakkoContextWindow; out AReason: string): Boolean;
  end;

implementation

procedure CloneStringDictionary(ASource, ADest: TYakkoContextWindowMetadata);
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

{ TYakkoContextWindow }

constructor TYakkoContextWindow.Create;
begin
  inherited Create;
  FMaxMessages := 32;
  FRecentMessages := TYakkoMessageList.Create(True);
  FSummaryPlaceholders := TList<string>.Create;
  FMetadata := TYakkoContextWindowMetadata.Create;
end;

destructor TYakkoContextWindow.Destroy;
begin
  FreeAndNil(FMetadata);
  FreeAndNil(FSummaryPlaceholders);
  FreeAndNil(FRecentMessages);
  inherited;
end;

procedure TYakkoContextWindow.Clear;
begin
  FMaxMessages := 32;
  FRecentMessages.Clear;
  FSummaryPlaceholders.Clear;
  FMetadata.Clear;

  { TODO: add deterministic summary compaction slots. }
  { TODO: add semantic compression placeholders for future context optimization. }
end;

function TYakkoContextWindow.Clone: TYakkoContextWindow;
var
  LMessage: TYakkoMessage;
  LSummary: string;
begin
  Result := TYakkoContextWindow.Create;
  try
    Result.FMaxMessages := FMaxMessages;
    for LMessage in FRecentMessages do
      Result.FRecentMessages.Add(LMessage.Clone);
    for LSummary in FSummaryPlaceholders do
      Result.FSummaryPlaceholders.Add(LSummary);
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoContextWindow.ToDebugString: string;
begin
  Result := Format(
    'TYakkoContextWindow(MaxMessages=%d, RecentMessages=%d, Summaries=%d, Metadata=%d)',
    [FMaxMessages, FRecentMessages.Count, FSummaryPlaceholders.Count, FMetadata.Count]
  );
end;

{ TYakkoContextWindowManager }

procedure TYakkoContextWindowManager.AddMessage(AWindow: TYakkoContextWindow;
  AMessage: TYakkoMessage);
begin
  if not Assigned(AWindow) then
    raise EArgumentNilException.Create('AWindow must be assigned.');
  if not Assigned(AMessage) then
    raise EArgumentNilException.Create('AMessage must be assigned.');

  AWindow.RecentMessages.Add(AMessage.Clone);
  TrimToLimit(AWindow);
end;

procedure TYakkoContextWindowManager.TrimToLimit(AWindow: TYakkoContextWindow);
begin
  if not Assigned(AWindow) then
    raise EArgumentNilException.Create('AWindow must be assigned.');

  while AWindow.RecentMessages.Count > AWindow.MaxMessages do
    AWindow.RecentMessages.Delete(0);
end;

function TYakkoContextWindowManager.ValidateWindow(AWindow: TYakkoContextWindow;
  out AReason: string): Boolean;
begin
  AReason := '';

  if not Assigned(AWindow) then
  begin
    AReason := 'Context window must be assigned.';
    Exit(False);
  end;

  if AWindow.MaxMessages <= 0 then
  begin
    AReason := 'MaxMessages must be positive.';
    Exit(False);
  end;

  if AWindow.RecentMessages.Count > AWindow.MaxMessages then
  begin
    AReason := 'Context window exceeds max messages.';
    Exit(False);
  end;

  Result := True;
end;

end.
