unit Yakko.Runtime.Capabilities;

{ Explicit runtime capability layer for YakkoDelphiLLM.

  Architectural intent:
  - declare what a model, provider, template, pipeline or tool supports;
  - keep capability knowledge explicit instead of inferred from RTTI or strings;
  - prepare multi-model and multi-provider evolution without auto-negotiation;
  - avoid spreading capability checks across the codebase.

  Registry vs Capability System:
  - a registry answers "what items exist?";
  - a capability system answers "what can an item do?";
  - this unit intentionally stays on the capability side only and does not
    resolve dependencies, auto-route, scan RTTI or perform negotiation.

  This unit is intentionally synchronous and explicit in this phase:
  no auto-routing, no AI planning, no provider negotiation, no plugin loading,
  no reflection scanning and no real inference integration here. }

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Generics.Collections;

type
  TYakkoRuntimeCapability =
  (
    rcChatCompletion,
    rcStreaming,
    rcToolCalling,
    rcReasoning,
    rcJsonMode,
    rcGrammarConstraints,
    rcEmbeddings,
    rcVision,
    rcMultimodal,
    rcSpeculativeDecoding
  );

  TYakkoRuntimeCapabilityHelper = record helper for TYakkoRuntimeCapability
  public
    function ToString: string;
  end;

  TYakkoRuntimeCapabilities = class
  private
    FCapabilities: TList<TYakkoRuntimeCapability>;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Add(ACapability: TYakkoRuntimeCapability);
    procedure Remove(ACapability: TYakkoRuntimeCapability);
    function Supports(ACapability: TYakkoRuntimeCapability): Boolean;
    function Clone: TYakkoRuntimeCapabilities;
    function ToDebugString: string;
  end;

implementation

{ TYakkoRuntimeCapabilityHelper }

function TYakkoRuntimeCapabilityHelper.ToString: string;
begin
  case Self of
    rcChatCompletion:
      Result := 'chat-completion';
    rcStreaming:
      Result := 'streaming';
    rcToolCalling:
      Result := 'tool-calling';
    rcReasoning:
      Result := 'reasoning';
    rcJsonMode:
      Result := 'json-mode';
    rcGrammarConstraints:
      Result := 'grammar-constraints';
    rcEmbeddings:
      Result := 'embeddings';
    rcVision:
      Result := 'vision';
    rcMultimodal:
      Result := 'multimodal';
    rcSpeculativeDecoding:
      Result := 'speculative-decoding';
  else
    Result := 'chat-completion';
  end;
end;

{ TYakkoRuntimeCapabilities }

constructor TYakkoRuntimeCapabilities.Create;
begin
  inherited Create;
  FCapabilities := TList<TYakkoRuntimeCapability>.Create;

  { TODO: add capability negotiation policies. }
  { TODO: add provider compatibility matrix support. }
  { TODO: add dynamic routing guards without auto-routing. }
  { TODO: add adaptive fallback metadata for safe future selection. }
end;

destructor TYakkoRuntimeCapabilities.Destroy;
begin
  FreeAndNil(FCapabilities);
  inherited;
end;

procedure TYakkoRuntimeCapabilities.Add(ACapability: TYakkoRuntimeCapability);
begin
  if not Supports(ACapability) then
    FCapabilities.Add(ACapability);

  { Explicit capability registration keeps support data visible and testable. }
end;

procedure TYakkoRuntimeCapabilities.Remove(ACapability: TYakkoRuntimeCapability);
var
  LIndex: Integer;
begin
  LIndex := FCapabilities.IndexOf(ACapability);
  if LIndex >= 0 then
    FCapabilities.Delete(LIndex);
end;

function TYakkoRuntimeCapabilities.Supports(ACapability: TYakkoRuntimeCapability): Boolean;
begin
  Result := FCapabilities.Contains(ACapability);
end;

function TYakkoRuntimeCapabilities.Clone: TYakkoRuntimeCapabilities;
var
  LCapability: TYakkoRuntimeCapability;
begin
  Result := TYakkoRuntimeCapabilities.Create;
  try
    for LCapability in FCapabilities do
      Result.Add(LCapability);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoRuntimeCapabilities.ToDebugString: string;
var
  LCapability: TYakkoRuntimeCapability;
  LBuilder: TStringBuilder;
  LFirst: Boolean;
begin
  LBuilder := TStringBuilder.Create;
  try
    LFirst := True;
    LBuilder.Append('TYakkoRuntimeCapabilities(Count=').Append(FCapabilities.Count).Append(', Items=[');
    for LCapability in FCapabilities do
    begin
      if not LFirst then
        LBuilder.Append(', ')
      else
        LFirst := False;
      LBuilder.Append(LCapability.ToString);
    end;
    LBuilder.Append('])');
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

end.
