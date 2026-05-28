unit Yakko.Message;

{ Conversational message domain entity for YakkoDelphiLLM runtime.
  Architectural intent:
  - isolate message concerns from session state and inference orchestration;
  - provide a stable domain model for future tools, reasoning, RAG and multimodal flows;
  - preserve runtime compatibility by introducing the new structure without integrating it yet;
  - keep the entity lightweight, side-effect free and ready for gradual adoption.

  This unit intentionally contains no inference logic, no llama.cpp bindings,
  no session dependency and no UI dependency. }

interface

uses
  System.Classes,
  System.SysUtils,
  System.Generics.Collections;

type
  TYakkoMessageRole =
  (
    mrSystem,
    mrUser,
    mrAssistant,
    mrTool,
    mrReasoning
  );

  TYakkoMessageRoleHelper = record helper for TYakkoMessageRole
  public
    function ToString: string;
    class function FromString(const AValue: string): TYakkoMessageRole; static;
  end;

  TYakkoToolCall = record
    Id: string;
    Name: string;
    ArgumentsJson: string;
  end;

  TYakkoReasoningBlock = record
    Content: string;
    Hidden: Boolean;
  end;

  TYakkoMetadata = TDictionary<string, string>;

  TYakkoMessage = class
  private
    FId: string;
    FRole: TYakkoMessageRole;
    FContent: string;
    FCreatedAt: TDateTime;
    FMetadata: TYakkoMetadata;
    FToolCalls: TArray<TYakkoToolCall>;
    FReasoningBlocks: TArray<TYakkoReasoningBlock>;
    FModalities: TArray<string>;
  public
    constructor Create;
    destructor Destroy; override;

    function IsUser: Boolean;
    function IsAssistant: Boolean;
    function IsSystem: Boolean;
    function IsTool: Boolean;
    function IsReasoning: Boolean;

    function Clone: TYakkoMessage;
    function ToDebugString: string;

    property Id: string read FId write FId;
    property Role: TYakkoMessageRole read FRole write FRole;
    property Content: string read FContent write FContent;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
    property Metadata: TYakkoMetadata read FMetadata;
    property ToolCalls: TArray<TYakkoToolCall> read FToolCalls write FToolCalls;
    property ReasoningBlocks: TArray<TYakkoReasoningBlock> read FReasoningBlocks write FReasoningBlocks;
    property Modalities: TArray<string> read FModalities write FModalities;
  end;

  TYakkoMessageList = TObjectList<TYakkoMessage>;

implementation

function CreateMessageId: string;
var
  LGuid: TGuid;
begin
  if CreateGuid(LGuid) = 0 then
    Result := GuidToString(LGuid)
  else
    Result := IntToHex(TThread.Current.ThreadID, 8) + '-' + FormatDateTime('yyyymmddhhnnsszzz', Now);
end;

{ TYakkoMessageRoleHelper }

class function TYakkoMessageRoleHelper.FromString(const AValue: string): TYakkoMessageRole;
var
  LValue: string;
begin
  LValue := Trim(LowerCase(AValue));

  if (LValue = '') or (LValue = 'system') or (LValue = 'mrsystem') then
    Exit(mrSystem);
  if (LValue = 'user') or (LValue = 'mruser') then
    Exit(mrUser);
  if (LValue = 'assistant') or (LValue = 'mrassistant') then
    Exit(mrAssistant);
  if (LValue = 'tool') or (LValue = 'mrtool') then
    Exit(mrTool);
  if (LValue = 'reasoning') or (LValue = 'mrreasoning') then
    Exit(mrReasoning);

  raise EConvertError.CreateFmt('Unknown TYakkoMessageRole value: %s', [AValue]);
end;

function TYakkoMessageRoleHelper.ToString: string;
begin
  case Self of
    mrSystem: Result := 'system';
    mrUser: Result := 'user';
    mrAssistant: Result := 'assistant';
    mrTool: Result := 'tool';
    mrReasoning: Result := 'reasoning';
  else
    Result := 'system';
  end;
end;

{ TYakkoMessage }

constructor TYakkoMessage.Create;
begin
  inherited Create;
  FId := CreateMessageId;
  FRole := mrUser;
  FContent := '';
  FCreatedAt := Now;
  FMetadata := TYakkoMetadata.Create;
  FToolCalls := [];
  FReasoningBlocks := [];
  FModalities := [];
end;

destructor TYakkoMessage.Destroy;
begin
  FreeAndNil(FMetadata);
  FToolCalls := nil;
  FReasoningBlocks := nil;
  FModalities := nil;
  inherited;
end;

function TYakkoMessage.IsAssistant: Boolean;
begin
  Result := FRole = mrAssistant;
end;

function TYakkoMessage.IsReasoning: Boolean;
begin
  Result := FRole = mrReasoning;
end;

function TYakkoMessage.IsSystem: Boolean;
begin
  Result := FRole = mrSystem;
end;

function TYakkoMessage.IsTool: Boolean;
begin
  Result := FRole = mrTool;
end;

function TYakkoMessage.IsUser: Boolean;
begin
  Result := FRole = mrUser;
end;

function TYakkoMessage.Clone: TYakkoMessage;
var
  LPair: TPair<string, string>;
  I: Integer;
begin
  Result := TYakkoMessage.Create;
  try
    Result.FId := FId;
    Result.FRole := FRole;
    Result.FContent := FContent;
    Result.FCreatedAt := FCreatedAt;

    Result.FMetadata.Clear;
    for LPair in FMetadata do
      Result.FMetadata.AddOrSetValue(LPair.Key, LPair.Value);

    SetLength(Result.FToolCalls, Length(FToolCalls));
    for I := 0 to High(FToolCalls) do
      Result.FToolCalls[I] := FToolCalls[I];

    SetLength(Result.FReasoningBlocks, Length(FReasoningBlocks));
    for I := 0 to High(FReasoningBlocks) do
      Result.FReasoningBlocks[I] := FReasoningBlocks[I];

    SetLength(Result.FModalities, Length(FModalities));
    for I := 0 to High(FModalities) do
      Result.FModalities[I] := FModalities[I];
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoMessage.ToDebugString: string;
begin
  Result := Format(
    'TYakkoMessage(Id=%s, Role=%s, CreatedAt=%s, ContentLength=%d, Metadata=%d, ToolCalls=%d, ReasoningBlocks=%d, Modalities=%d)',
    [
      FId,
      FRole.ToString,
      DateTimeToStr(FCreatedAt),
      Length(FContent),
      FMetadata.Count,
      Length(FToolCalls),
      Length(FReasoningBlocks),
      Length(FModalities)
    ]
  );
end;

end.
