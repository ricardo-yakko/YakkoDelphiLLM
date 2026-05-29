unit InventoryLab.JsonLoader;

{ JSON loader for real inventory/component data. }

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.IOUtils,
  System.Types,
  System.Generics.Collections,
  InventoryLab.Models;

type
  TInventoryLabJsonLoader = class
  private
    class procedure FlattenJsonValue(
      AValue: TJSONValue;
      const APath: string;
      AScalars: TInventoryLabStringMap;
      AArrayLines: TInventoryLabStringList
    ); static;
    class function ExtractByPriority(AMap: TInventoryLabStringMap;
      const AKeys: array of string): string; static;
  public
    class function LoadFromDirectory(const ADirectory: string;
      ADiagnostics: TInventoryLabStringMap): TInventoryLabRawRecordList; static;
  end;

implementation

class procedure TInventoryLabJsonLoader.FlattenJsonValue(AValue: TJSONValue;
  const APath: string; AScalars: TInventoryLabStringMap;
  AArrayLines: TInventoryLabStringList);
var
  LPair: TJSONPair;
  LArray: TJSONArray;
  LItem: TJSONValue;
  LIndex: Integer;
  LPath: string;
begin
  if not Assigned(AValue) then
    Exit;

  if AValue is TJSONObject then
  begin
    for LPair in TJSONObject(AValue) do
    begin
      if APath = '' then
        LPath := LPair.JsonString.Value
      else
        LPath := APath + '.' + LPair.JsonString.Value;
      FlattenJsonValue(LPair.JsonValue, LPath, AScalars, AArrayLines);
    end;
    Exit;
  end;

  if AValue is TJSONArray then
  begin
    LArray := TJSONArray(AValue);
    for LIndex := 0 to LArray.Count - 1 do
    begin
      LItem := LArray.Items[LIndex];
      if (LItem is TJSONObject) or (LItem is TJSONArray) then
        FlattenJsonValue(LItem, APath + '[' + IntToStr(LIndex) + ']', AScalars, AArrayLines)
      else
        AArrayLines.Add(APath + '=' + LItem.Value);
    end;
    Exit;
  end;

  AScalars.AddOrSetValue(APath, AValue.Value);
end;

class function TInventoryLabJsonLoader.ExtractByPriority(AMap: TInventoryLabStringMap;
  const AKeys: array of string): string;
var
  LKey: string;
begin
  Result := '';
  if not Assigned(AMap) then
    Exit;

  for LKey in AKeys do
  begin
    if AMap.ContainsKey(LKey) then
      Exit(Trim(AMap[LKey]));
  end;
end;

class function TInventoryLabJsonLoader.LoadFromDirectory(const ADirectory: string;
  ADiagnostics: TInventoryLabStringMap): TInventoryLabRawRecordList;
var
  LFiles: TArray<string>;
  LFileName: string;
  LJsonText: string;
  LJsonValue: TJSONValue;
  LRecord: TInventoryLabRawRecord;
  LLoaded: Integer;
  LFailed: Integer;
begin
  if not DirectoryExists(ADirectory) then
    raise Exception.CreateFmt('Directory not found: %s', [ADirectory]);

  Result := TInventoryLabRawRecordList.Create(True);
  LLoaded := 0;
  LFailed := 0;

  LFiles := TDirectory.GetFiles(ADirectory, '*.json', TSearchOption.soTopDirectoryOnly);
  for LFileName in LFiles do
  begin
    LJsonValue := nil;
    try
      LJsonText := TFile.ReadAllText(LFileName, TEncoding.UTF8);
      LJsonValue := TJSONObject.ParseJSONValue(LJsonText, False, True);
      if not Assigned(LJsonValue) then
        raise Exception.Create('Invalid JSON content.');

      LRecord := TInventoryLabRawRecord.Create;
      try
        LRecord.SourceFile := LFileName;
        FlattenJsonValue(LJsonValue, '', LRecord.FlatScalars, LRecord.ArrayLines);

        LRecord.PartNumber := ExtractByPriority(LRecord.FlatScalars,
          ['componente.part_number', 'componente.sku_etiqueta', 'componente.codigo']);
        LRecord.DisplayName := ExtractByPriority(LRecord.FlatScalars,
          ['componente.nome_comum', 'componente.descricao_comercial', 'componente.part_number']);
        LRecord.Brand := ExtractByPriority(LRecord.FlatScalars,
          ['componente.fabricante', 'componente.fabricante_original', 'componente.marca']);
        LRecord.Category := ExtractByPriority(LRecord.FlatScalars,
          ['componente.categoria']);
        LRecord.Subcategory := ExtractByPriority(LRecord.FlatScalars,
          ['componente.subcategoria']);
        LRecord.Description := ExtractByPriority(LRecord.FlatScalars,
          ['componente.descricao_comercial', 'componente.estado']);

        if Trim(LRecord.PartNumber) = '' then
          LRecord.PartNumber := ChangeFileExt(ExtractFileName(LFileName), '');

        if Trim(LRecord.DisplayName) = '' then
          LRecord.DisplayName := LRecord.PartNumber;

        Result.Add(LRecord);
        LRecord := nil;
        Inc(LLoaded);
      finally
        LRecord.Free;
      end;
    except
      Inc(LFailed);
      if Assigned(ADiagnostics) then
        ADiagnostics.AddOrSetValue('json.error.' + ExtractFileName(LFileName), 'failed_to_parse_or_load');
    end;

    LJsonValue.Free;
  end;

  if Assigned(ADiagnostics) then
  begin
    ADiagnostics.AddOrSetValue('json.files_total', IntToStr(Length(LFiles)));
    ADiagnostics.AddOrSetValue('json.files_loaded', IntToStr(LLoaded));
    ADiagnostics.AddOrSetValue('json.files_failed', IntToStr(LFailed));
  end;
end;

end.
