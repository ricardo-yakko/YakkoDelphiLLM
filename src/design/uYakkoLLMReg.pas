unit uYakkoLLMReg;

interface

procedure Register;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.TypInfo,
  DesignIntf,
  DesignEditors,
  Vcl.Dialogs,
  uYakkoLLM;

type
  TYakkoBaseFolderProperty = class(TStringProperty)
  protected
    function GetDialogTitle: string; virtual; abstract;
  public
    function GetAttributes: TPropertyAttributes; override;
    procedure Edit; override;
  end;

  TYakkoDllsFolderProperty = class(TYakkoBaseFolderProperty)
  protected
    function GetDialogTitle: string; override;
  end;

  TYakkoModelosFolderProperty = class(TYakkoBaseFolderProperty)
  protected
    function GetDialogTitle: string; override;
  end;

  TYakkoModelPathListProperty = class(TStringProperty)
  public
    function GetAttributes: TPropertyAttributes; override;
    procedure GetValues(Proc: TGetStrProc); override;
    procedure SetValue(const Value: string); override;
  end;

function FindYakkoPathsComponent(ARoot: TComponent): TComponent;
var
  I: Integer;
begin
  Result := nil;
  if ARoot = nil then
    Exit;

  for I := 0 to ARoot.ComponentCount - 1 do
    if SameText(ARoot.Components[I].ClassName, 'TYakkoPaths') then
      Exit(ARoot.Components[I]);
end;

function TryGetStringPropValue(AComponent: TPersistent; const APropName: string; out AValue: string): Boolean;
begin
  Result := Assigned(AComponent) and IsPublishedProp(AComponent, APropName);
  if Result then
    AValue := Trim(GetStrProp(AComponent, APropName))
  else
    AValue := '';
end;

function TYakkoBaseFolderProperty.GetAttributes: TPropertyAttributes;
begin
  Result := inherited GetAttributes + [paDialog];
end;

procedure TYakkoBaseFolderProperty.Edit;
var
  LDir: string;
  LDialog: TFileOpenDialog;
begin
  LDir := Trim(GetValue);
  if (LDir = '') or not DirectoryExists(LDir) then
    LDir := GetCurrentDir;

  LDialog := TFileOpenDialog.Create(nil);
  try
    LDialog.Title := GetDialogTitle;
    LDialog.Options := [fdoPickFolders, fdoPathMustExist, fdoForceFileSystem];
    LDialog.FileName := LDir;

    if LDialog.Execute then
      SetValue(ExcludeTrailingPathDelimiter(LDialog.FileName));
  finally
    LDialog.Free;
  end;
end;

function TYakkoDllsFolderProperty.GetDialogTitle: string;
begin
  Result := 'Selecionar pasta das DLLs';
end;

function TYakkoModelosFolderProperty.GetDialogTitle: string;
begin
  Result := 'Selecionar pasta dos modelos';
end;

function TYakkoModelPathListProperty.GetAttributes: TPropertyAttributes;
begin
  Result := inherited GetAttributes + [paValueList];
end;

procedure TYakkoModelPathListProperty.GetValues(Proc: TGetStrProc);
var
  LPathsObj: TComponent;
  LModelPath: string;
  LFolder: string;
  LFiles: TArray<string>;
  LFile: string;
begin
  if not Assigned(Proc) then
    Exit;

  LFolder := '';
  LPathsObj := FindYakkoPathsComponent(TComponent(GetComponent(0)).Owner);
  if Assigned(LPathsObj) then
    LFolder := Trim(GetStrProp(LPathsObj, 'Modelos'));

  TryGetStringPropValue(GetComponent(0), 'ModelPath', LModelPath);

  if LFolder = '' then
  begin
    if DirectoryExists(LModelPath) then
      LFolder := LModelPath
    else if ExtractFilePath(LModelPath) <> '' then
      LFolder := ExtractFilePath(LModelPath)
    else
      LFolder := GetCurrentDir;
  end;

  if not DirectoryExists(LFolder) then
    Exit;

  LFiles := TDirectory.GetFiles(LFolder, '*.gguf', TSearchOption.soTopDirectoryOnly);
  for LFile in LFiles do
    Proc(ExtractFileName(LFile));
end;

procedure TYakkoModelPathListProperty.SetValue(const Value: string);
var
  LPathsObj: TComponent;
  LModelPath: string;
  LFolder: string;
  LCandidatePath: string;
begin
  LFolder := '';
  LPathsObj := FindYakkoPathsComponent(TComponent(GetComponent(0)).Owner);
  if Assigned(LPathsObj) then
    LFolder := Trim(GetStrProp(LPathsObj, 'Modelos'));

  TryGetStringPropValue(GetComponent(0), 'ModelPath', LModelPath);

  if LFolder = '' then
  begin
    if DirectoryExists(LModelPath) then
      LFolder := LModelPath
    else if ExtractFilePath(LModelPath) <> '' then
      LFolder := ExtractFilePath(LModelPath);
  end;

  LCandidatePath := Trim(Value);
  if (LCandidatePath <> '') and (not FileExists(LCandidatePath)) and (LFolder <> '') then
    LCandidatePath := TPath.Combine(LFolder, LCandidatePath);

  inherited SetValue(LCandidatePath);
end;

procedure Register;
var
  LYakkoChatClass: TComponentClass;
  LYakkoContextoClass: TComponentClass;
  LYakkoPathsClass: TComponentClass;
  LYakkoDllClass: TComponentClass;
  LYakkoEngineClass: TComponentClass;
  LYakkoFullExportsClass: TComponentClass;
  LYakkoGeradorClass: TComponentClass;
  LYakkoModeloClass: TComponentClass;
  LYakkoAgenteClass: TComponentClass;
begin
  LYakkoChatClass := TComponentClass(GetClass('TYakkoChat'));
  LYakkoContextoClass := TComponentClass(GetClass('TYakkoContexto'));
  LYakkoPathsClass := TComponentClass(GetClass('TYakkoPaths'));
  LYakkoDllClass := TComponentClass(GetClass('TYakkoDll'));
  LYakkoEngineClass := TComponentClass(GetClass('TYakkoEngine'));
  LYakkoFullExportsClass := TComponentClass(GetClass('TYakkoFullExports'));
  LYakkoGeradorClass := TComponentClass(GetClass('TYakkoGerador'));
  LYakkoModeloClass := TComponentClass(GetClass('TYakkoModelo'));
  LYakkoAgenteClass := TComponentClass(GetClass('TYakkoAgente'));

  if Assigned(LYakkoChatClass) then
    RegisterComponents('uYakkoLLM', [LYakkoChatClass]);
  if Assigned(LYakkoContextoClass) then
    RegisterComponents('uYakkoLLM', [LYakkoContextoClass]);
  if Assigned(LYakkoPathsClass) then
    RegisterComponents('uYakkoLLM', [LYakkoPathsClass]);
  if Assigned(LYakkoDllClass) then
    RegisterComponents('uYakkoLLM', [LYakkoDllClass]);
  if Assigned(LYakkoEngineClass) then
    RegisterComponents('uYakkoLLM', [LYakkoEngineClass]);
  if Assigned(LYakkoFullExportsClass) then
    RegisterComponents('uYakkoLLM', [LYakkoFullExportsClass]);
  if Assigned(LYakkoGeradorClass) then
    RegisterComponents('uYakkoLLM', [LYakkoGeradorClass]);
  if Assigned(LYakkoModeloClass) then
    RegisterComponents('uYakkoLLM', [LYakkoModeloClass]);
  if Assigned(LYakkoAgenteClass) then
    RegisterComponents('uYakkoLLM', [LYakkoAgenteClass]);

  if Assigned(LYakkoPathsClass) then
  begin
    RegisterPropertyEditor(TypeInfo(string), LYakkoPathsClass, 'Dlls', TYakkoDllsFolderProperty);
    RegisterPropertyEditor(TypeInfo(string), LYakkoPathsClass, 'Modelos', TYakkoModelosFolderProperty);
    RegisterPropertyEditor(TypeInfo(string), LYakkoPathsClass, 'ModeloEmbeddings', TYakkoModelPathListProperty);
  end;

  if Assigned(LYakkoModeloClass) then
    RegisterPropertyEditor(TypeInfo(string), LYakkoModeloClass, 'ModelPath', TYakkoModelPathListProperty);
end;

end.

