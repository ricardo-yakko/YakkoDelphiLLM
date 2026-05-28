unit Yakko.ConversationState;

{ Conversational state domain model for YakkoDelphiLLM runtime.
  Architectural intent:
  - separate conversation history from low-level session lifecycle state;
  - provide a cohesive boundary for modern LLM message history management;
  - prepare the runtime for future summaries, tools, reasoning, RAG injection and
    conversation compaction without changing current behavior;
  - keep the state container domain-oriented and free from inference, UI and
    backend-specific responsibilities.

  This unit is intentionally independent from TYakkoSessao for gradual adoption.
  The current runtime may continue using legacy history structures until the
  migration boundary is introduced. }

interface

uses
  System.SysUtils,
  Yakko.Message;

type
  TYakkoConversationState = class
  private
    FMessages: TYakkoMessageList;
    FConversationId: string;
    FCreatedAt: TDateTime;
    FUpdatedAt: TDateTime;
    FSystemPrompt: string;
    procedure Touch;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;

    procedure AddMessage(AMessage: TYakkoMessage);

    procedure AddSystemMessage(const AContent: string);
    procedure AddUserMessage(const AContent: string);
    procedure AddAssistantMessage(const AContent: string);

    function MessageCount: Integer;
    function GetMessages: TYakkoMessageList;
    function GetLastMessage: TYakkoMessage;
    function GetRecentMessages(ACount: Integer): TYakkoMessageList;
    function Clone: TYakkoConversationState;
    function ToDebugString: string;

    property ConversationId: string read FConversationId write FConversationId;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
    property UpdatedAt: TDateTime read FUpdatedAt write FUpdatedAt;
    property SystemPrompt: string read FSystemPrompt write FSystemPrompt;
  end;

implementation

function CreateConversationId: string;
var
  LGuid: TGuid;
begin
  if CreateGuid(LGuid) = 0 then
    Result := GuidToString(LGuid)
  else
    Result := FormatDateTime('yyyymmddhhnnsszzz', Now);
end;

{ TYakkoConversationState }

constructor TYakkoConversationState.Create;
begin
  inherited Create;
  FMessages := TYakkoMessageList.Create(True);
  FConversationId := CreateConversationId;
  FCreatedAt := Now;
  FUpdatedAt := FCreatedAt;
  FSystemPrompt := '';
end;

destructor TYakkoConversationState.Destroy;
begin
  FreeAndNil(FMessages);
  inherited;
end;

procedure TYakkoConversationState.Touch;
begin
  FUpdatedAt := Now;
end;

procedure TYakkoConversationState.Clear;
begin
  FMessages.Clear;
  Touch;

  { TODO: keep optional summary snapshots when summary support is introduced. }
  { TODO: keep token budget bookkeeping once trimming is implemented. }
  { TODO: preserve semantic compression state when compaction becomes available. }
  { TODO: preserve injected RAG evidence when retrieval state becomes explicit. }
end;

procedure TYakkoConversationState.AddMessage(AMessage: TYakkoMessage);
begin
  if not Assigned(AMessage) then
    raise EArgumentNilException.Create('AMessage must be assigned.');

  { Ownership is transferred to TYakkoConversationState once the message is added. }
  FMessages.Add(AMessage);
  Touch;

  { TODO: mark hidden reasoning segments separately from visible history. }
  { TODO: attach tool result envelopes once tool execution becomes first-class. }
  { TODO: attach structured outputs once message payloads support typed content. }
end;

procedure TYakkoConversationState.AddAssistantMessage(const AContent: string);
var
  LMessage: TYakkoMessage;
begin
  LMessage := TYakkoMessage.Create;
  try
    LMessage.Role := mrAssistant;
    LMessage.Content := AContent;
    AddMessage(LMessage);
  except
    LMessage.Free;
    raise;
  end;
end;

procedure TYakkoConversationState.AddSystemMessage(const AContent: string);
var
  LMessage: TYakkoMessage;
begin
  LMessage := TYakkoMessage.Create;
  try
    LMessage.Role := mrSystem;
    LMessage.Content := AContent;
    AddMessage(LMessage);
  except
    LMessage.Free;
    raise;
  end;
end;

procedure TYakkoConversationState.AddUserMessage(const AContent: string);
var
  LMessage: TYakkoMessage;
begin
  LMessage := TYakkoMessage.Create;
  try
    LMessage.Role := mrUser;
    LMessage.Content := AContent;
    AddMessage(LMessage);
  except
    LMessage.Free;
    raise;
  end;
end;

function TYakkoConversationState.MessageCount: Integer;
begin
  Result := FMessages.Count;
end;

function TYakkoConversationState.GetMessages: TYakkoMessageList;
begin
  { Returns the owned internal list as a borrowed reference.
    Callers must not free the list or take ownership of contained messages. }
  Result := FMessages;
end;

function TYakkoConversationState.GetLastMessage: TYakkoMessage;
begin
  if FMessages.Count = 0 then
    Exit(nil);

  Result := FMessages.Last;
end;

function TYakkoConversationState.GetRecentMessages(ACount: Integer): TYakkoMessageList;
var
  LStartIndex: Integer;
  LIndex: Integer;
begin
  Result := TYakkoMessageList.Create(True);
  try
    if ACount <= 0 then
      Exit;

    LStartIndex := FMessages.Count - ACount;
    if LStartIndex < 0 then
      LStartIndex := 0;

    for LIndex := LStartIndex to FMessages.Count - 1 do
      Result.Add(FMessages[LIndex].Clone);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoConversationState.Clone: TYakkoConversationState;
var
  LMessage: TYakkoMessage;
begin
  Result := TYakkoConversationState.Create;
  try
    Result.FConversationId := FConversationId;
    Result.FCreatedAt := FCreatedAt;
    Result.FUpdatedAt := FUpdatedAt;
    Result.FSystemPrompt := FSystemPrompt;

    for LMessage in FMessages do
      Result.FMessages.Add(LMessage.Clone);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoConversationState.ToDebugString: string;
begin
  Result := Format(
    'TYakkoConversationState(Id=%s, CreatedAt=%s, UpdatedAt=%s, MessageCount=%d, SystemPromptLength=%d)',
    [
      FConversationId,
      DateTimeToStr(FCreatedAt),
      DateTimeToStr(FUpdatedAt),
      FMessages.Count,
      Length(FSystemPrompt)
    ]
  );
end;

end.
