unit Yakko.Message.LegacyAdapter;

{ Temporary adapter layer between legacy TLlamaMensagem records and the new
  TYakkoMessage domain model.

  Architectural intent:
  - support gradual migration without changing current runtime behavior;
  - keep legacy and new message models decoupled;
  - provide a single temporary conversion boundary that can be removed later.

  This unit intentionally does not modify inference flow, session behavior,
  llama.cpp bindings or UI layers. }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  uYakkoLlamaTypes,
  Yakko.Message;

type
  TYakkoLegacyMessageAdapter = class sealed
  private
    class function LegacyRoleToYakkoRole(ARole: TLlamaMensagemRole): TYakkoMessageRole; static;
    class function YakkoRoleToLegacyRole(ARole: TYakkoMessageRole): TLlamaMensagemRole; static;
  public
    class function ToYakkoMessage(const AMessage: TLlamaMensagem): TYakkoMessage; static;
    class function ToLegacyMessage(const AMessage: TYakkoMessage): TLlamaMensagem; static;

    class procedure ConvertListToYakko(
      const ASource: TArray<TLlamaMensagem>;
      ADest: TYakkoMessageList
    ); static;

    class procedure ConvertListToLegacy(
      const ASource: TYakkoMessageList;
      ADest: TList<TLlamaMensagem>
    ); static;
  end;

implementation

{ TYakkoLegacyMessageAdapter }

class procedure TYakkoLegacyMessageAdapter.ConvertListToLegacy(
  const ASource: TYakkoMessageList; ADest: TList<TLlamaMensagem>);
var
  LMessage: TYakkoMessage;
begin
  if not Assigned(ADest) then
    raise EArgumentNilException.Create('ADest must be assigned.');

  if not Assigned(ASource) then
    Exit;

  { Ownership remains with the caller:
    - ASource owns TYakkoMessage instances according to its OwnsObjects setting;
    - ADest receives value-type TLlamaMensagem copies only. }
  for LMessage in ASource do
    ADest.Add(ToLegacyMessage(LMessage));
end;

class procedure TYakkoLegacyMessageAdapter.ConvertListToYakko(
  const ASource: TArray<TLlamaMensagem>; ADest: TYakkoMessageList);
var
  LIndex: Integer;
begin
  if not Assigned(ADest) then
    raise EArgumentNilException.Create('ADest must be assigned.');

  { Ownership remains with the caller:
    - this adapter allocates new TYakkoMessage instances;
    - ownership is transferred to ADest when they are added. }
  for LIndex := 0 to High(ASource) do
    ADest.Add(ToYakkoMessage(ASource[LIndex]));
end;

class function TYakkoLegacyMessageAdapter.LegacyRoleToYakkoRole(
  ARole: TLlamaMensagemRole): TYakkoMessageRole;
begin
  case ARole of
    TLlamaMensagemRole.mrSystem:
      Result := TYakkoMessageRole.mrSystem;
    TLlamaMensagemRole.mrUser:
      Result := TYakkoMessageRole.mrUser;
    TLlamaMensagemRole.mrAssistant:
      Result := TYakkoMessageRole.mrAssistant;
  else
    Result := TYakkoMessageRole.mrAssistant;
  end;
end;

class function TYakkoLegacyMessageAdapter.ToLegacyMessage(
  const AMessage: TYakkoMessage): TLlamaMensagem;
begin
  if not Assigned(AMessage) then
    raise EArgumentNilException.Create('AMessage must be assigned.');

  Result.Role := YakkoRoleToLegacyRole(AMessage.Role);
  Result.Conteudo := AMessage.Content;

  { Legacy TLlamaMensagem has no timestamp or metadata fields.
    Those values cannot be preserved in the current legacy structure.
    TODO: preserve CreatedAt once legacy transport accepts message envelopes.
    TODO: preserve Metadata once legacy conversation storage is upgraded.
    TODO: preserve ReasoningBlocks once legacy model supports hidden reasoning.
    TODO: preserve ToolCalls and tool results once legacy roles are extended.
    TODO: preserve structured outputs and multimodal parts in a future payload type. }
end;

class function TYakkoLegacyMessageAdapter.ToYakkoMessage(
  const AMessage: TLlamaMensagem): TYakkoMessage;
begin
  Result := TYakkoMessage.Create;
  try
    Result.Role := LegacyRoleToYakkoRole(AMessage.Role);
    Result.Content := AMessage.Conteudo;

    { Legacy TLlamaMensagem does not expose timestamp information.
      A zero timestamp is used to mark the value as unknown instead of inventing one. }
    Result.CreatedAt := 0;

    { Legacy TLlamaMensagem does not expose metadata, tool calls, reasoning blocks,
      multimodal parts or structured output fields.
      Safe defaults keep migration behavior deterministic and side-effect free. }
    Result.Metadata.AddOrSetValue('legacy.adapter', 'TLlamaMensagem');
    Result.Metadata.AddOrSetValue('legacy.role', IntToStr(Ord(AMessage.Role)));
  except
    Result.Free;
    raise;
  end;
end;

class function TYakkoLegacyMessageAdapter.YakkoRoleToLegacyRole(
  ARole: TYakkoMessageRole): TLlamaMensagemRole;
begin
  case ARole of
    TYakkoMessageRole.mrSystem:
      Result := TLlamaMensagemRole.mrSystem;
    TYakkoMessageRole.mrUser:
      Result := TLlamaMensagemRole.mrUser;
    TYakkoMessageRole.mrAssistant:
      Result := TLlamaMensagemRole.mrAssistant;
    TYakkoMessageRole.mrTool,
    TYakkoMessageRole.mrReasoning:
      begin
        { The legacy role model cannot represent tool or reasoning messages.
          The temporary fallback is mrAssistant to preserve old runtime contracts.
          TODO: extend TLlamaMensagemRole or replace TLlamaMensagem usage entirely.
          TODO: map tool results separately once tool messages become first-class.
          TODO: preserve hidden reasoning semantics outside of assistant text.
          TODO: add structured output transport for machine-readable responses. }
        Result := TLlamaMensagemRole.mrAssistant;
      end;
  else
    Result := TLlamaMensagemRole.mrAssistant;
  end;
end;

end.
