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
  Winapi.Windows,
  Yakko.ConversationState,
  Yakko.Message,
  Yakko.Message.LegacyAdapter,
  Yakko.Prompt.Builder,
  Yakko.Template.Provider,
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
    function BuildLegacyRoleSignature(const APrompt: string; const AMensagens: TArray<TLlamaMensagem>): string;
    function BuildYakkoRoleSignature(AConversation: TYakkoConversationState): string;
    procedure EmitShadowPromptDiagnostics(
      const APromptLegado: UTF8String;
      const APromptNovoSemantico: string;
      const APromptNovoChatML: string;
      const APrompt: string;
      const APromptSistema: string;
      const AMensagens: TArray<TLlamaMensagem>;
      AConversation: TYakkoConversationState
    );
    procedure RunShadowPromptPipeline(
      const APrompt: string;
      const APromptSistema: string;
      const AMensagens: TArray<TLlamaMensagem>;
      const APromptLegado: UTF8String
    );
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

function TYakkoChatTemplate.BuildLegacyRoleSignature(const APrompt: string;
  const AMensagens: TArray<TLlamaMensagem>): string;
var
  LBuilder: TStringBuilder;
  LIndex: Integer;
  LRole: string;
begin
  LBuilder := TStringBuilder.Create;
  try
    for LIndex := 0 to High(AMensagens) do
    begin
      case AMensagens[LIndex].Role of
        mrSystem:
          LRole := 'system';
        mrUser:
          LRole := 'user';
        mrAssistant:
          LRole := 'assistant';
      else
        LRole := 'assistant';
      end;

      if LBuilder.Length > 0 then
        LBuilder.Append('>');
      LBuilder.Append(LRole);
    end;

    if Trim(APrompt) <> '' then
    begin
      if LBuilder.Length > 0 then
        LBuilder.Append('>');
      LBuilder.Append('user');
    end;

    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

function TYakkoChatTemplate.BuildYakkoRoleSignature(
  AConversation: TYakkoConversationState): string;
var
  LBuilder: TStringBuilder;
  LMessage: TYakkoMessage;
begin
  if not Assigned(AConversation) then
    Exit('');

  LBuilder := TStringBuilder.Create;
  try
    for LMessage in AConversation.GetMessages do
    begin
      if LBuilder.Length > 0 then
        LBuilder.Append('>');
      LBuilder.Append(LMessage.Role.ToString);
    end;
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

procedure TYakkoChatTemplate.EmitShadowPromptDiagnostics(
  const APromptLegado: UTF8String; const APromptNovoSemantico,
  APromptNovoChatML, APrompt, APromptSistema: string;
  const AMensagens: TArray<TLlamaMensagem>;
  AConversation: TYakkoConversationState);
var
  LDiagnostic: TStringBuilder;
  LLegacyRoleSignature: string;
  LNewRoleSignature: string;
begin
  LLegacyRoleSignature := BuildLegacyRoleSignature(APrompt, AMensagens);
  LNewRoleSignature := BuildYakkoRoleSignature(AConversation);

  LDiagnostic := TStringBuilder.Create;
  try
    LDiagnostic.Append('[YakkoPromptShadow] ');
    LDiagnostic.Append('Migration=PassiveDiagnostic; ');
    LDiagnostic.Append('LegacyChars=').Append(Length(UTF8ToString(APromptLegado))).Append('; ');
    LDiagnostic.Append('NewBuilderChars=').Append(Length(APromptNovoSemantico)).Append('; ');
    LDiagnostic.Append('NewTemplateChars=').Append(Length(APromptNovoChatML)).Append('; ');
    LDiagnostic.Append('LegacyMessageCount=').Append(Length(AMensagens) + Ord(Trim(APrompt) <> '')).Append('; ');
    LDiagnostic.Append('NewMessageCount=').Append(AConversation.MessageCount).Append('; ');
    LDiagnostic.Append('LegacyRoles=').Append(LLegacyRoleSignature).Append('; ');
    LDiagnostic.Append('NewRoles=').Append(LNewRoleSignature).Append('; ');
    LDiagnostic.Append('LegacyHasSystem=').Append(Ord(Trim(APromptSistema) <> '')).Append('; ');
    LDiagnostic.Append('NewHasSystem=').Append(Ord(Trim(AConversation.SystemPrompt) <> '')).Append('; ');
    LDiagnostic.Append('LegacyTools=0; NewTools=0; ');
    LDiagnostic.Append('LegacyRAG=0; NewRAG=0; ');
    LDiagnostic.Append('LegacyAssistantPreamble=1; NewAssistantPreamble=0; ');
    LDiagnostic.Append('BuilderFormat=semantic-neutral; TemplateFormat=chatml');
    OutputDebugString(PChar(LDiagnostic.ToString));
  finally
    LDiagnostic.Free;
  end;
end;

procedure TYakkoChatTemplate.RunShadowPromptPipeline(const APrompt,
  APromptSistema: string; const AMensagens: TArray<TLlamaMensagem>;
  const APromptLegado: UTF8String);
var
  LConversation: TYakkoConversationState;
  LRequest: TYakkoPromptBuildRequest;
  LBuilder: TYakkoPromptBuilder;
  LResult: TYakkoPromptBuildResult;
  LTemplateProvider: IYakkoTemplateProvider;
  LPromptNovoSemantico: string;
  LPromptNovoChatML: string;
begin
  { Shadow execution is intentionally best-effort.
    The legacy prompt remains authoritative while the new pipeline runs in
    parallel only for migration diagnostics and architectural validation. }
  LConversation := TYakkoConversationState.Create;
  try
    LConversation.SystemPrompt := APromptSistema;
    TYakkoLegacyMessageAdapter.ConvertListToYakko(AMensagens, LConversation.GetMessages);

    if Trim(APrompt) <> '' then
      LConversation.AddUserMessage(APrompt);

    LRequest := TYakkoPromptBuildRequest.Create;
    try
      LRequest.ConversationState := LConversation;
      LRequest.IncludeSystemPrompt := True;
      LRequest.IncludeTools := False;
      LRequest.IncludeRAG := False;
      LRequest.IncludeReasoning := False;
      LRequest.TemplateName := 'shadow-chatml';

      LBuilder := TYakkoPromptBuilder.Create;
      try
        LResult := LBuilder.Build(LRequest);
        try
          LPromptNovoSemantico := LResult.PromptText;

          { The template provider runs alongside the semantic builder so the team
            can compare semantic assembly and concrete serialization separately. }
          LTemplateProvider := TYakkoTemplateProviderFactory.CreateChatML;
          LPromptNovoChatML := LTemplateProvider.BuildPrompt(LConversation);

          EmitShadowPromptDiagnostics(
            APromptLegado,
            LPromptNovoSemantico,
            LPromptNovoChatML,
            APrompt,
            APromptSistema,
            AMensagens,
            LConversation
          );
        finally
          LResult.Free;
        end;
      finally
        LBuilder.Free;
      end;
    finally
      LRequest.Free;
    end;
  except
    on E: Exception do
      OutputDebugString(PChar(
        '[YakkoPromptShadow] Migration=PassiveDiagnostic; Status=Failed; Error=' +
        E.ClassName + ': ' + E.Message
      ));
  end;
  LConversation.Free;
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

  { Shadow execution keeps the legacy prompt authoritative while the new
    architecture is validated in parallel. This reduces migration risk and keeps
    runtime behavior stable until prompt parity is proven. }
  RunShadowPromptPipeline(APrompt, APromptSistema, AMensagens, Result);
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

