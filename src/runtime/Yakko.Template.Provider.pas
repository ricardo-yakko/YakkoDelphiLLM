unit Yakko.Template.Provider;

{ Prompt template serialization layer for YakkoDelphiLLM runtime.
  Architectural intent:
  - separate prompt semantics from model-specific textual serialization;
  - keep PromptBuilder responsible for deciding which semantic blocks enter the prompt;
  - keep TemplateProvider responsible for how those blocks are rendered for a
    specific chat format, including roles, separators, wrappers and control tokens;
  - prepare the runtime for multiple GGUF model families without coupling model
    syntax directly into the semantic prompt assembly pipeline.

  PromptBuilder and TemplateProvider solve different problems.
  PromptBuilder performs context engineering and block selection.
  TemplateProvider performs textual serialization for a target prompt format.
  This separation prevents semantic policy from being mixed with low-level text
  rendering and makes future template growth safer.

  Strategy Pattern is used here because template syntax varies per model family.
  Each provider can evolve independently while exposing the same interface to
  higher layers. This is a better long-term fit for modern LLM runtimes than a
  single procedural formatter with branching by model name. }

interface

uses
  System.SysUtils,
  Yakko.ConversationState,
  Yakko.Message,
  Yakko.Prompt.Document;

type
  { Contract for prompt template serialization.
    The interface exists so PromptBuilder can depend on a stable abstraction while
    multiple concrete templates serialize the same conversational semantics in
    different ways. }
  IYakkoTemplateProvider = interface
    ['{A39EE5F2-6D5F-42FE-A928-9DA4A2C4A532}']
    function ProviderName: string;

    function FormatMessage(AMessage: TYakkoMessage): string;
    function FormatSystemPrompt(const AText: string): string;
    function FormatToolBlock(const AToolSchema: string): string;
    function FormatRAGBlock(const ARAGText: string): string;
    function BuildPrompt(AConversation: TYakkoConversationState): string;
    function BuildPromptDocument(ADocument: TYakkoPromptDocument): string;
  end;

  TYakkoBaseTemplateProvider = class abstract(TInterfacedObject, IYakkoTemplateProvider)
  protected
    function RoleToText(ARole: TYakkoMessageRole): string; virtual;
    function NormalizeText(const AValue: string): string; virtual;
  public
    function ProviderName: string; virtual; abstract;
    function FormatMessage(AMessage: TYakkoMessage): string; virtual; abstract;
    function FormatSystemPrompt(const AText: string): string; virtual; abstract;
    function BuildPrompt(AConversation: TYakkoConversationState): string; virtual; abstract;
    function BuildPromptDocument(ADocument: TYakkoPromptDocument): string; virtual; abstract;
    function FormatToolBlock(const AToolSchema: string): string; virtual;
    function FormatRAGBlock(const ARAGText: string): string; virtual;
  end;

  { First concrete template provider.
    This provider emits a simple ChatML-style format and serves as the initial
    serialization strategy for modern multi-turn chat prompts. }
  TYakkoChatMLTemplateProvider = class(TYakkoBaseTemplateProvider)
  public
    function ProviderName: string; override;
    function FormatMessage(AMessage: TYakkoMessage): string; override;
    function FormatSystemPrompt(const AText: string): string; override;
    function BuildPrompt(AConversation: TYakkoConversationState): string; override;
    function BuildPromptDocument(ADocument: TYakkoPromptDocument): string; override;
  end;

  TYakkoTemplateProviderFactory = class
  public
    class function CreateChatML: IYakkoTemplateProvider; static;
    class function CreateDefault: IYakkoTemplateProvider; static;
  end;

implementation

{ TYakkoBaseTemplateProvider }

function TYakkoBaseTemplateProvider.RoleToText(ARole: TYakkoMessageRole): string;
begin
  case ARole of
    mrSystem:
      Result := 'system';
    mrUser:
      Result := 'user';
    mrAssistant:
      Result := 'assistant';
    mrTool:
      Result := 'tool';
    mrReasoning:
      Result := 'reasoning';
  else
    Result := 'user';
  end;
end;

function TYakkoBaseTemplateProvider.NormalizeText(const AValue: string): string;
begin
  Result := Trim(AValue);
end;

function TYakkoBaseTemplateProvider.FormatToolBlock(const AToolSchema: string): string;
var
  LValue: string;
begin
  LValue := NormalizeText(AToolSchema);
  if LValue = '' then
    Exit('');

  Result := Format('<|im_start|>tool_schema%s%s<|im_end|>', [sLineBreak, LValue]);

  { TODO: support dedicated tool calling serialization instead of raw schema text. }
  { TODO: support model-specific stop tokens and BOS/EOS handling per template. }
end;

function TYakkoBaseTemplateProvider.FormatRAGBlock(const ARAGText: string): string;
var
  LValue: string;
begin
  LValue := NormalizeText(ARAGText);
  if LValue = '' then
    Exit('');

  Result := Format('<|im_start|>context%s%s<|im_end|>', [sLineBreak, LValue]);

  { TODO: support XML prompting and JSON schema prompting for context blocks. }
  { TODO: support multimodal formatting when retrieval contains non-text payloads. }
end;

{ TYakkoChatMLTemplateProvider }

function TYakkoChatMLTemplateProvider.ProviderName: string;
begin
  Result := 'chatml';
end;

function TYakkoChatMLTemplateProvider.FormatMessage(AMessage: TYakkoMessage): string;
var
  LRole: string;
  LContent: string;
begin
  if not Assigned(AMessage) then
    Exit('');

  LRole := RoleToText(AMessage.Role);
  LContent := NormalizeText(AMessage.Content);
  if LContent = '' then
    Exit('');

  Result := Format('<|im_start|>%s%s%s%s<|im_end|>', [LRole, sLineBreak, LContent, sLineBreak]);

  { TODO: support hidden chain-of-thought handling without leaking private reasoning. }
  { TODO: add dedicated message serializers for Llama 3, Gemma, Qwen and DeepSeek. }
end;

function TYakkoChatMLTemplateProvider.FormatSystemPrompt(const AText: string): string;
var
  LValue: string;
begin
  LValue := NormalizeText(AText);
  if LValue = '' then
    Exit('');

  Result := Format('<|im_start|>system%s%s%s<|im_end|>', [sLineBreak, LValue, sLineBreak]);
end;

function TYakkoChatMLTemplateProvider.BuildPrompt(AConversation: TYakkoConversationState): string;
var
  LDocument: TYakkoPromptDocument;
  LBlock: TYakkoPromptBlock;
  LMessage: TYakkoMessage;
begin
  if not Assigned(AConversation) then
    raise EArgumentNilException.Create('AConversation must be assigned.');

  LDocument := TYakkoPromptDocument.Create;
  try
    if Trim(AConversation.SystemPrompt) <> '' then
    begin
      LBlock := TYakkoPromptBlock.Create;
      LBlock.BlockType := pbtSystem;
      LBlock.Content := AConversation.SystemPrompt;
      LDocument.AddBlock(LBlock);
    end;

    for LMessage in AConversation.GetMessages do
    begin
      if Trim(LMessage.Content) = '' then
        Continue;

      LBlock := TYakkoPromptBlock.Create;
      LBlock.BlockType := pbtConversation;
      LBlock.Content := LMessage.Content;
      LBlock.Metadata.AddOrSetValue('role', RoleToText(LMessage.Role));
      LDocument.AddBlock(LBlock);
    end;

    Result := BuildPromptDocument(LDocument);
  finally
    LDocument.Free;
  end;
end;

function TYakkoChatMLTemplateProvider.BuildPromptDocument(
  ADocument: TYakkoPromptDocument): string;
var
  LBuilder: TStringBuilder;
  LIndex: Integer;
  LBlock: string;
  LRole: string;
begin
  if not Assigned(ADocument) then
    raise EArgumentNilException.Create('ADocument must be assigned.');

  LBuilder := TStringBuilder.Create;
  try
    for LIndex := 0 to ADocument.Blocks.Count - 1 do
    begin
      if not ADocument.Blocks[LIndex].Visible then
        Continue;

      case ADocument.Blocks[LIndex].BlockType of
        pbtSystem:
          LBlock := FormatSystemPrompt(ADocument.Blocks[LIndex].Content);
        pbtConversation:
          begin
            LRole := 'user';
            if ADocument.Blocks[LIndex].Metadata.ContainsKey('role') then
              LRole := NormalizeText(ADocument.Blocks[LIndex].Metadata['role']);

            LBlock := Format('<|im_start|>%s%s%s%s<|im_end|>',
              [LRole, sLineBreak, NormalizeText(ADocument.Blocks[LIndex].Content), sLineBreak]);
          end;
        pbtTool:
          LBlock := FormatToolBlock(ADocument.Blocks[LIndex].Content);
        pbtRAG:
          LBlock := FormatRAGBlock(ADocument.Blocks[LIndex].Content);
        pbtReasoning:
          LBlock := Format('<|im_start|>reasoning%s%s%s<|im_end|>',
            [sLineBreak, NormalizeText(ADocument.Blocks[LIndex].Content), sLineBreak]);
        pbtAssistantPrefix:
          LBlock := '<|im_start|>assistant' + sLineBreak;
      else
        LBlock := '';
      end;

      if LBlock = '' then
        Continue;

      if LBuilder.Length > 0 then
        LBuilder.AppendLine;

      LBuilder.Append(LBlock);
    end;

    Result := Trim(LBuilder.ToString);
  finally
    LBuilder.Free;
  end;

  { TODO: add final assistant preamble and stop structures per target template. }
  { TODO: support BOS/EOS handling once template-specific runtime requirements are known. }
  { TODO: support tool calling serialization based on typed block metadata. }
  { TODO: support hidden reasoning policies with visibility-aware rendering. }
end;

{ TYakkoTemplateProviderFactory }

class function TYakkoTemplateProviderFactory.CreateChatML: IYakkoTemplateProvider;
begin
  Result := TYakkoChatMLTemplateProvider.Create;
end;

class function TYakkoTemplateProviderFactory.CreateDefault: IYakkoTemplateProvider;
begin
  Result := CreateChatML;
end;

{ Future integration notes:
  - TYakkoPromptBuilder should eventually delegate text serialization to an
    IYakkoTemplateProvider after semantic prompt blocks are selected.
  - Automatic provider selection can later use model metadata, GGUF metadata or
    runtime configuration without changing prompt semantics.
  - A provider registry may become useful once the runtime supports multiple
    model families and custom templates.
  - Keeping template logic inside the builder would tightly couple context
    engineering to model syntax and make future maintenance brittle. }

end.