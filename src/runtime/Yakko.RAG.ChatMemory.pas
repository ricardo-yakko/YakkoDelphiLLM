unit Yakko.RAG.ChatMemory;

{ Deterministic chat memory for first RAG layer.

  Responsibilities:
  - store recent conversational history;
  - track important messages;
  - keep summary candidates for future compression;
  - expose relevant and persistent context maps.

  This unit intentionally avoids compression and async processing. }

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Yakko.Message,
  Yakko.RAG.Types;

type
  TYakkoChatMemoryEntry = class
  private
    FMessageId: string;
    FRole: TYakkoMessageRole;
    FContent: string;
    FCreatedAt: TDateTime;
    FImportant: Boolean;
    FMetadata: TYakkoStringMap;
  public
    constructor Create;
    destructor Destroy; override;

    function Clone: TYakkoChatMemoryEntry;
    function ToDebugString: string;

    property MessageId: string read FMessageId write FMessageId;
    property Role: TYakkoMessageRole read FRole write FRole;
    property Content: string read FContent write FContent;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
    property Important: Boolean read FImportant write FImportant;
    property Metadata: TYakkoStringMap read FMetadata;
  end;

  TYakkoChatMemoryEntryList = TObjectList<TYakkoChatMemoryEntry>;

  TYakkoChatSummaryItem = class
  private
    FSummaryText: string;
    FCreatedAt: TDateTime;
    FMetadata: TYakkoStringMap;
  public
    constructor Create;
    destructor Destroy; override;

    function Clone: TYakkoChatSummaryItem;
    function ToDebugString: string;

    property SummaryText: string read FSummaryText write FSummaryText;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
    property Metadata: TYakkoStringMap read FMetadata;
  end;

  TYakkoChatSummaryItemList = TObjectList<TYakkoChatSummaryItem>;

  TYakkoChatMemory = class
  private
    FRecentHistory: TYakkoChatMemoryEntryList;
    FImportantMessages: TYakkoChatMemoryEntryList;
    FSummaryBacklog: TYakkoChatSummaryItemList;
    FRelevantContext: TYakkoStringMap;
    FPersistentContext: TYakkoStringMap;
    FMaxRecentMessages: Integer;
    procedure EnforceRecentWindow;
    class function BuildMapText(AMap: TYakkoStringMap): string; static;
  public
    constructor Create;
    destructor Destroy; override;

    procedure AddMessage(AMessage: TYakkoMessage; AImportant: Boolean = False);
    procedure AddRawMessage(ARole: TYakkoMessageRole; const AContent: string; AImportant: Boolean = False);
    procedure AddSummaryCandidate(const ASummaryText: string);

    procedure SetRelevantContext(const AKey, AValue: string);
    procedure SetPersistentContext(const AKey, AValue: string);

    function GetRecentHistory(ACount: Integer): TYakkoChatMemoryEntryList;
    function GetImportantMessages: TYakkoChatMemoryEntryList;
    function GetSummaryBacklog: TYakkoChatSummaryItemList;

    function BuildRelevantContextText: string;
    function BuildPersistentContextText: string;
    function ToDebugString: string;

    property MaxRecentMessages: Integer read FMaxRecentMessages write FMaxRecentMessages;
  end;

implementation

{ TYakkoChatMemoryEntry }

constructor TYakkoChatMemoryEntry.Create;
begin
  inherited Create;
  FMessageId := '';
  FRole := mrUser;
  FContent := '';
  FCreatedAt := Now;
  FImportant := False;
  FMetadata := TYakkoStringMap.Create;
end;

destructor TYakkoChatMemoryEntry.Destroy;
begin
  FreeAndNil(FMetadata);
  inherited;
end;

function TYakkoChatMemoryEntry.Clone: TYakkoChatMemoryEntry;
var
  LPair: TPair<string, string>;
begin
  Result := TYakkoChatMemoryEntry.Create;
  try
    Result.FMessageId := FMessageId;
    Result.FRole := FRole;
    Result.FContent := FContent;
    Result.FCreatedAt := FCreatedAt;
    Result.FImportant := FImportant;

    Result.FMetadata.Clear;
    for LPair in FMetadata do
      Result.FMetadata.AddOrSetValue(LPair.Key, LPair.Value);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoChatMemoryEntry.ToDebugString: string;
begin
  Result := Format(
    'TYakkoChatMemoryEntry(MessageId=%s, Role=%s, CreatedAt=%s, Important=%s, Metadata=%d, ContentLength=%d)',
    [
      FMessageId,
      FRole.ToString,
      DateTimeToStr(FCreatedAt),
      BoolToStr(FImportant, True),
      FMetadata.Count,
      Length(FContent)
    ]
  );
end;

{ TYakkoChatSummaryItem }

constructor TYakkoChatSummaryItem.Create;
begin
  inherited Create;
  FSummaryText := '';
  FCreatedAt := Now;
  FMetadata := TYakkoStringMap.Create;
end;

destructor TYakkoChatSummaryItem.Destroy;
begin
  FreeAndNil(FMetadata);
  inherited;
end;

function TYakkoChatSummaryItem.Clone: TYakkoChatSummaryItem;
var
  LPair: TPair<string, string>;
begin
  Result := TYakkoChatSummaryItem.Create;
  try
    Result.FSummaryText := FSummaryText;
    Result.FCreatedAt := FCreatedAt;

    Result.FMetadata.Clear;
    for LPair in FMetadata do
      Result.FMetadata.AddOrSetValue(LPair.Key, LPair.Value);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoChatSummaryItem.ToDebugString: string;
begin
  Result := Format(
    'TYakkoChatSummaryItem(CreatedAt=%s, Metadata=%d, SummaryLength=%d)',
    [DateTimeToStr(FCreatedAt), FMetadata.Count, Length(FSummaryText)]
  );
end;

{ TYakkoChatMemory }

constructor TYakkoChatMemory.Create;
begin
  inherited Create;
  FRecentHistory := TYakkoChatMemoryEntryList.Create(True);
  FImportantMessages := TYakkoChatMemoryEntryList.Create(True);
  FSummaryBacklog := TYakkoChatSummaryItemList.Create(True);
  FRelevantContext := TYakkoStringMap.Create;
  FPersistentContext := TYakkoStringMap.Create;
  FMaxRecentMessages := 20;
end;

destructor TYakkoChatMemory.Destroy;
begin
  FreeAndNil(FPersistentContext);
  FreeAndNil(FRelevantContext);
  FreeAndNil(FSummaryBacklog);
  FreeAndNil(FImportantMessages);
  FreeAndNil(FRecentHistory);
  inherited;
end;

procedure TYakkoChatMemory.EnforceRecentWindow;
begin
  if FMaxRecentMessages <= 0 then
    Exit;

  while FRecentHistory.Count > FMaxRecentMessages do
    FRecentHistory.Delete(0);
end;

procedure TYakkoChatMemory.AddMessage(AMessage: TYakkoMessage;
  AImportant: Boolean);
var
  LEntry: TYakkoChatMemoryEntry;
  LPair: TPair<string, string>;
begin
  if not Assigned(AMessage) then
    raise EArgumentNilException.Create('AMessage must be assigned.');

  LEntry := TYakkoChatMemoryEntry.Create;
  try
    LEntry.MessageId := AMessage.Id;
    LEntry.Role := AMessage.Role;
    LEntry.Content := AMessage.Content;
    LEntry.CreatedAt := AMessage.CreatedAt;
    LEntry.Important := AImportant;

    for LPair in AMessage.Metadata do
      LEntry.Metadata.AddOrSetValue(LPair.Key, LPair.Value);

    FRecentHistory.Add(LEntry.Clone);
    if AImportant then
      FImportantMessages.Add(LEntry.Clone);

    EnforceRecentWindow;
  finally
    LEntry.Free;
  end;
end;

procedure TYakkoChatMemory.AddRawMessage(ARole: TYakkoMessageRole;
  const AContent: string; AImportant: Boolean);
var
  LEntry: TYakkoChatMemoryEntry;
begin
  LEntry := TYakkoChatMemoryEntry.Create;
  try
    LEntry.Role := ARole;
    LEntry.Content := AContent;
    LEntry.Important := AImportant;
    FRecentHistory.Add(LEntry.Clone);
    if AImportant then
      FImportantMessages.Add(LEntry.Clone);
    EnforceRecentWindow;
  finally
    LEntry.Free;
  end;
end;

procedure TYakkoChatMemory.AddSummaryCandidate(const ASummaryText: string);
var
  LSummary: TYakkoChatSummaryItem;
begin
  if Trim(ASummaryText) = '' then
    Exit;

  LSummary := TYakkoChatSummaryItem.Create;
  try
    LSummary.SummaryText := Trim(ASummaryText);

    { Ownership is transferred to TYakkoChatMemory once summary candidate is added. }
    FSummaryBacklog.Add(LSummary);
    LSummary := nil;
  finally
    LSummary.Free;
  end;
end;

procedure TYakkoChatMemory.SetRelevantContext(const AKey, AValue: string);
begin
  if Trim(AKey) = '' then
    raise EArgumentException.Create('AKey must not be empty.');

  FRelevantContext.AddOrSetValue(Trim(AKey), AValue);
end;

procedure TYakkoChatMemory.SetPersistentContext(const AKey, AValue: string);
begin
  if Trim(AKey) = '' then
    raise EArgumentException.Create('AKey must not be empty.');

  FPersistentContext.AddOrSetValue(Trim(AKey), AValue);
end;

function TYakkoChatMemory.GetRecentHistory(
  ACount: Integer): TYakkoChatMemoryEntryList;
var
  LStartIndex: Integer;
  LIndex: Integer;
begin
  Result := TYakkoChatMemoryEntryList.Create(True);
  try
    if ACount <= 0 then
      Exit;

    LStartIndex := FRecentHistory.Count - ACount;
    if LStartIndex < 0 then
      LStartIndex := 0;

    for LIndex := LStartIndex to FRecentHistory.Count - 1 do
      Result.Add(FRecentHistory[LIndex].Clone);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoChatMemory.GetImportantMessages: TYakkoChatMemoryEntryList;
var
  LEntry: TYakkoChatMemoryEntry;
begin
  Result := TYakkoChatMemoryEntryList.Create(True);
  try
    for LEntry in FImportantMessages do
      Result.Add(LEntry.Clone);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoChatMemory.GetSummaryBacklog: TYakkoChatSummaryItemList;
var
  LSummary: TYakkoChatSummaryItem;
begin
  Result := TYakkoChatSummaryItemList.Create(True);
  try
    for LSummary in FSummaryBacklog do
      Result.Add(LSummary.Clone);
  except
    Result.Free;
    raise;
  end;
end;

class function TYakkoChatMemory.BuildMapText(AMap: TYakkoStringMap): string;
var
  LKeys: TStringList;
  LKey: string;
begin
  Result := '';
  if not Assigned(AMap) or (AMap.Count = 0) then
    Exit;

  { Key sorting keeps output deterministic for diagnostics and audits. }
  LKeys := TStringList.Create;
  try
    LKeys.Sorted := True;
    LKeys.Duplicates := dupIgnore;

    for LKey in AMap.Keys do
      LKeys.Add(LKey);

    for LKey in LKeys do
      Result := Result + LKey + '=' + AMap[LKey] + sLineBreak;
  finally
    LKeys.Free;
  end;
end;

function TYakkoChatMemory.BuildRelevantContextText: string;
begin
  Result := Trim(BuildMapText(FRelevantContext));
end;

function TYakkoChatMemory.BuildPersistentContextText: string;
begin
  Result := Trim(BuildMapText(FPersistentContext));
end;

function TYakkoChatMemory.ToDebugString: string;
begin
  Result := Format(
    'TYakkoChatMemory(RecentHistory=%d, ImportantMessages=%d, SummaryBacklog=%d, RelevantContext=%d, PersistentContext=%d, MaxRecentMessages=%d)',
    [
      FRecentHistory.Count,
      FImportantMessages.Count,
      FSummaryBacklog.Count,
      FRelevantContext.Count,
      FPersistentContext.Count,
      FMaxRecentMessages
    ]
  );
end;

end.