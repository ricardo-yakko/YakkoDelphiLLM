unit uYakkoToolManagerComponent;

{ Subsistema de tool calling.
  Responsabilidades:
  - registrar ferramentas e executar chamadas
  - parsear payloads de tool call via estrategia
  - retornar resultado estruturado de sucesso/falha
  Ownership:
  - ToolManager e owner dos tools registrados. }

interface

uses
  System.Classes,
  System.SysUtils,
  System.JSON,
  System.Generics.Collections;

type
  EYakkoToolManagerError = class(Exception);

  TYakkoToolCall = record
    Nome: string;
    ParametrosJson: string;
  end;

  TYakkoToolResult = record
    Sucesso: Boolean;
    ResultadoTexto: string;
    Erro: string;
  end;

  TYakkoTool = class
  private
    FEnabled: Boolean;
  public
    constructor Create; virtual;
    function Nome: string; virtual;
    function Descricao: string; virtual;
    function Execute(const AParametrosJson: string): string; virtual;

    property Enabled: Boolean read FEnabled write FEnabled;
  end;

  IYakkoToolCallParser = interface
    ['{583DD4F8-7A35-4F47-A6B1-275F5C0E8282}']
    function TryParse(const ARawPayload: string; out AToolCall: TYakkoToolCall): Boolean;
  end;

  TYakkoJsonToolParser = class(TInterfacedObject, IYakkoToolCallParser)
  private
    function JsonValueToText(AValue: TJSONValue): string;
  public
    function TryParse(const ARawPayload: string; out AToolCall: TYakkoToolCall): Boolean;
  end;

  TYakkoToolManager = class(TComponent)
  private
    FTools: TObjectList<TYakkoTool>;
    FParser: IYakkoToolCallParser;
    FDestruindo: Boolean;
    function InternalFindTool(const ANome: string): TYakkoTool;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure RegistrarTool(ATool: TYakkoTool);
    function EncontrarTool(const ANome: string): TYakkoTool;
    function ExecutarToolCall(const AToolCall: TYakkoToolCall): TYakkoToolResult;
    function TryParseToolCall(const ARawPayload: string; out AToolCall: TYakkoToolCall): Boolean;
    function TryProcessRawPayload(const ARawPayload: string; out AToolCall: TYakkoToolCall; out AResult: TYakkoToolResult): Boolean;
    function BuildToolEventPayload(const APhase: string; const AToolCall: TYakkoToolCall; const AResult: TYakkoToolResult): string;

    property Parser: IYakkoToolCallParser read FParser write FParser;
  end;

implementation

{ TYakkoTool }

constructor TYakkoTool.Create;
begin
  inherited Create;
  FEnabled := True;
end;

function TYakkoTool.Descricao: string;
begin
  Result := '';
end;

function TYakkoTool.Execute(const AParametrosJson: string): string;
begin
  Result := '';
end;

function TYakkoTool.Nome: string;
begin
  Result := ClassName;
end;

{ TYakkoJsonToolParser }

function TYakkoJsonToolParser.JsonValueToText(AValue: TJSONValue): string;
begin
  if not Assigned(AValue) then
    Exit('');

  if AValue is TJSONString then
    Exit(TJSONString(AValue).Value);

  Result := AValue.ToJSON;
end;

function TYakkoJsonToolParser.TryParse(const ARawPayload: string; out AToolCall: TYakkoToolCall): Boolean;
var
  LRoot: TJSONValue;
  LObj: TJSONObject;
  LToolObj: TJSONObject;
  LName: string;
  LArgs: string;
  LValue: TJSONValue;
begin
  AToolCall.Nome := '';
  AToolCall.ParametrosJson := '{}';
  Result := False;

  if Trim(ARawPayload) = '' then
    Exit;

  LRoot := TJSONObject.ParseJSONValue(ARawPayload);
  try
    if not (LRoot is TJSONObject) then
      Exit;

    LObj := TJSONObject(LRoot);
    LName := '';
    LArgs := '{}';

    if LObj.TryGetValue<TJSONValue>('tool_call', LValue) and (LValue is TJSONObject) then
    begin
      LToolObj := TJSONObject(LValue);
      if LToolObj.TryGetValue<string>('name', LName) then
      begin
        if LToolObj.TryGetValue<TJSONValue>('arguments', LValue) then
          LArgs := JsonValueToText(LValue);
      end;
    end;

    if (LName = '') and LObj.TryGetValue<string>('tool', LName) then
      if LObj.TryGetValue<TJSONValue>('arguments', LValue) then
        LArgs := JsonValueToText(LValue);

    if (LName = '') and LObj.TryGetValue<string>('name', LName) then
      if LObj.TryGetValue<TJSONValue>('arguments', LValue) then
        LArgs := JsonValueToText(LValue)
      else if LObj.TryGetValue<TJSONValue>('params', LValue) then
        LArgs := JsonValueToText(LValue);

    if Trim(LName) = '' then
      Exit;

    AToolCall.Nome := Trim(LName);
    AToolCall.ParametrosJson := LArgs;
    Result := True;
  finally
    LRoot.Free;
  end;
end;

{ TYakkoToolManager }

constructor TYakkoToolManager.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTools := TObjectList<TYakkoTool>.Create(True);
  FParser := TYakkoJsonToolParser.Create;
  FDestruindo := False;
end;

destructor TYakkoToolManager.Destroy;
begin
  if FDestruindo then
    Exit;

  FDestruindo := True;
  FParser := nil;
  FreeAndNil(FTools);
  inherited;
end;

function TYakkoToolManager.InternalFindTool(const ANome: string): TYakkoTool;
var
  LTool: TYakkoTool;
begin
  Result := nil;
  for LTool in FTools do
    if SameText(Trim(LTool.Nome), Trim(ANome)) then
      Exit(LTool);
end;

procedure TYakkoToolManager.RegistrarTool(ATool: TYakkoTool);
begin
  if FDestruindo then
    raise EYakkoToolManagerError.Create('ToolManager em destruicao.');

  if not Assigned(ATool) then
    raise EYakkoToolManagerError.Create('Tool invalida para registro.');

  if Trim(ATool.Nome) = '' then
    raise EYakkoToolManagerError.Create('Nome da tool nao pode ser vazio.');

  if Assigned(InternalFindTool(ATool.Nome)) then
    raise EYakkoToolManagerError.CreateFmt('Tool ja registrada: %s', [ATool.Nome]);

  FTools.Add(ATool);
end;

function TYakkoToolManager.EncontrarTool(const ANome: string): TYakkoTool;
begin
  Result := InternalFindTool(ANome);
end;

function TYakkoToolManager.ExecutarToolCall(const AToolCall: TYakkoToolCall): TYakkoToolResult;
var
  LTool: TYakkoTool;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Sucesso := False;

  LTool := EncontrarTool(AToolCall.Nome);
  if not Assigned(LTool) then
  begin
    Result.Erro := Format('Tool nao encontrada: %s', [AToolCall.Nome]);
    Exit;
  end;

  if not LTool.Enabled then
  begin
    Result.Erro := Format('Tool desabilitada: %s', [AToolCall.Nome]);
    Exit;
  end;

  try
    Result.ResultadoTexto := LTool.Execute(AToolCall.ParametrosJson);
    Result.Sucesso := True;
  except
    on E: Exception do
    begin
      Result.Sucesso := False;
      Result.Erro := E.Message;
    end;
  end;
end;

function TYakkoToolManager.TryParseToolCall(const ARawPayload: string; out AToolCall: TYakkoToolCall): Boolean;
begin
  if not Assigned(FParser) then
    Exit(False);

  Result := FParser.TryParse(ARawPayload, AToolCall);
end;

function TYakkoToolManager.TryProcessRawPayload(const ARawPayload: string; out AToolCall: TYakkoToolCall; out AResult: TYakkoToolResult): Boolean;
begin
  FillChar(AToolCall, SizeOf(AToolCall), 0);
  FillChar(AResult, SizeOf(AResult), 0);
  Result := TryParseToolCall(ARawPayload, AToolCall);
  if not Result then
    Exit;

  AResult := ExecutarToolCall(AToolCall);
end;

function TYakkoToolManager.BuildToolEventPayload(const APhase: string; const AToolCall: TYakkoToolCall; const AResult: TYakkoToolResult): string;
var
  LObj: TJSONObject;
begin
  LObj := TJSONObject.Create;
  try
    LObj.AddPair('phase', APhase);
    LObj.AddPair('tool', AToolCall.Nome);
    LObj.AddPair('arguments', AToolCall.ParametrosJson);
    LObj.AddPair('success', TJSONBool.Create(AResult.Sucesso));
    LObj.AddPair('result', AResult.ResultadoTexto);
    LObj.AddPair('error', AResult.Erro);
    Result := LObj.ToJSON;
  finally
    LObj.Free;
  end;
end;

initialization
  System.Classes.RegisterClass(TYakkoToolManager);

end.

