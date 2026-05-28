unit uYakkoChatTemplateComponent;

{ Componente de formatacao de prompt/chat template.
  Responsabilidades:
  - montar prompts a partir de mensagens
  - abstrair formato de chat do backend
  Ownership:
  - Modelo e referencia borrowed fornecida pelo Engine. }

interface

uses
  System.Classes,
  System.SysUtils,
  uYakkoModeloComponent,
  uYakkoLlamaTypes;

type
  EYakkoChatTemplateError = class(Exception);

  { Roles estruturadas para expansao futura (tool/developer/reasoning). }
  TYakkoTemplateRole = (
    trSystem,
    trUser,
    trAssistant,
    trTool,
    trDeveloper,
    trReasoning
  );

  { Estrutura preparatoria para templates/tool-calling/multimodal. }
  TYakkoTemplateMessage = record
    Role: TYakkoTemplateRole;
    Content: string;
    Name: string;
    ToolCallId: string;
  end;

  TYakkoTemplateMessageArray = TArray<TYakkoTemplateMessage>;

  TYakkoChatTemplate = class(TComponent)
  private
    FModelo: TYakkoModelo; { referencia externa sem ownership }
    FDestruindo: Boolean;
    function RoleToTag(ARole: TYakkoTemplateRole): string;
    function LegacyRoleToTemplateRole(ARole: TLlamaMensagemRole): TYakkoTemplateRole;
  protected
    function BuildPromptInternal(const AMensagens: TYakkoTemplateMessageArray; const APromptSistema: string): UTF8String; virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    function ModeloDisponivel: Boolean;
    function PodeMontarPrompt: Boolean;

    function BuildPrompt(const AMensagens: TYakkoTemplateMessageArray; const APromptSistema: string): UTF8String;

    { Adaptador para mensagens TLlamaMensagem usadas pelo gerador. }
    function BuildPromptFromLegacy(const APrompt: string; const APromptSistema: string; const AMensagens: TArray<TLlamaMensagem>): UTF8String;

    function NomeTemplate: string; virtual;
    function SupportsTools: Boolean; virtual;
    function SupportsReasoning: Boolean; virtual;

    property Modelo: TYakkoModelo read FModelo write FModelo;
  end;

implementation

constructor TYakkoChatTemplate.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FModelo := nil;
  FDestruindo := False;
end;

destructor TYakkoChatTemplate.Destroy;
begin
  if FDestruindo then
    Exit;
  FDestruindo := True;
  FModelo := nil;
  inherited;
end;

function TYakkoChatTemplate.ModeloDisponivel: Boolean;
begin
  Result := Assigned(FModelo) and FModelo.EstaCarregado;
end;

function TYakkoChatTemplate.PodeMontarPrompt: Boolean;
begin
  Result := (not FDestruindo) and ModeloDisponivel;
end;

function TYakkoChatTemplate.RoleToTag(ARole: TYakkoTemplateRole): string;
begin
  case ARole of
    trSystem: Result := 'system';
    trUser: Result := 'user';
    trAssistant: Result := 'assistant';
    trTool: Result := 'tool';
    trDeveloper: Result := 'developer';
    trReasoning: Result := 'reasoning';
  else
    Result := 'user';
  end;
end;

function TYakkoChatTemplate.LegacyRoleToTemplateRole(ARole: TLlamaMensagemRole): TYakkoTemplateRole;
begin
  case ARole of
    mrSystem: Result := trSystem;
    mrUser: Result := trUser;
    mrAssistant: Result := trAssistant;
  else
    Result := trUser;
  end;
end;

function TYakkoChatTemplate.BuildPromptInternal(const AMensagens: TYakkoTemplateMessageArray; const APromptSistema: string): UTF8String;
var
  LMsg: TYakkoTemplateMessage;
  LTag: string;
begin
  Result := '';

  if APromptSistema <> '' then
    Result := Result +
      UTF8String('<start_of_turn>system' + #10) +
      UTF8String(APromptSistema) +
      UTF8String(#10 + '<end_of_turn>' + #10);

  for LMsg in AMensagens do
  begin
    if Trim(LMsg.Content) = '' then
      Continue;

    LTag := RoleToTag(LMsg.Role);
    Result := Result +
      UTF8String('<start_of_turn>' + LTag + #10) +
      UTF8String(LMsg.Content) +
      UTF8String(#10 + '<end_of_turn>' + #10);
  end;
end;

function TYakkoChatTemplate.BuildPrompt(const AMensagens: TYakkoTemplateMessageArray; const APromptSistema: string): UTF8String;
begin
  if FDestruindo then
    raise EYakkoChatTemplateError.Create('ChatTemplate em destruicao.');

  if not Assigned(FModelo) then
    raise EYakkoChatTemplateError.Create('Modelo nao configurado no ChatTemplate.');

  if not FModelo.EstaCarregado then
    raise EYakkoChatTemplateError.Create('Modelo nao carregado para montagem de prompt.');

  Result := BuildPromptInternal(AMensagens, APromptSistema);
end;

function TYakkoChatTemplate.BuildPromptFromLegacy(const APrompt: string; const APromptSistema: string; const AMensagens: TArray<TLlamaMensagem>): UTF8String;
var
  LCompat: TYakkoTemplateMessageArray;
  I: Integer;
begin
  SetLength(LCompat, Length(AMensagens) + 1);

  for I := 0 to High(AMensagens) do
  begin
    LCompat[I].Role := LegacyRoleToTemplateRole(AMensagens[I].Role);
    LCompat[I].Content := AMensagens[I].Conteudo;
    LCompat[I].Name := '';
    LCompat[I].ToolCallId := '';
  end;

  LCompat[High(LCompat)].Role := trUser;
  LCompat[High(LCompat)].Content := APrompt;
  LCompat[High(LCompat)].Name := '';
  LCompat[High(LCompat)].ToolCallId := '';

  Result := BuildPrompt(LCompat, APromptSistema);
  Result := Result + UTF8String('<start_of_turn>assistant' + #10);
end;

function TYakkoChatTemplate.NomeTemplate: string;
begin
  Result := 'yakko-default-chat-template';
end;

function TYakkoChatTemplate.SupportsTools: Boolean;
begin
  Result := False;
end;

function TYakkoChatTemplate.SupportsReasoning: Boolean;
begin
  Result := False;
end;

initialization
  System.Classes.RegisterClass(TYakkoChatTemplate);

end.

