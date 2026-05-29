unit InventoryLab.EntityNormalizer;

{ Canonical entity normalization from raw JSON records. }

interface

uses
  System.SysUtils,
  System.StrUtils,
  System.Character,
  System.Generics.Collections,
  InventoryLab.Models,
  Yakko.RAG.Types;

type
  TInventoryLabEntityNormalizer = class
  private
    class function NormalizeText(const AValue: string): string; static;
    class function RemoveDiacritics(const AValue: string): string; static;
    class function CanonicalizeToken(const AValue: string): string; static;
    class function GuessCanonicalCategory(const ACategory, ASubcategory, AName: string): string; static;
    class function BuildCanonicalId(const APartNumber, AName, ACategory, ASubcategory: string): string; static;
  public
    class function NormalizeToEntity(ARaw: TInventoryLabRawRecord): TYakkoInventoryEntity; static;
    class procedure CollectAliases(ARaw: TInventoryLabRawRecord;
      AEntity: TYakkoInventoryEntity; AOutAliases: TInventoryLabStringList); static;
  end;

implementation

class function TInventoryLabEntityNormalizer.RemoveDiacritics(
  const AValue: string): string;
const
  CFrom = 'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ';
  CTo   = 'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN';
var
  I: Integer;
  LChar: Char;
  LPos: Integer;
begin
  Result := AValue;
  for I := 1 to Length(Result) do
  begin
    LChar := Result[I];
    LPos := Pos(string(LChar), CFrom);
    if LPos > 0 then
      Result[I] := CTo[LPos];
  end;
end;

class function TInventoryLabEntityNormalizer.NormalizeText(const AValue: string): string;
begin
  Result := Trim(LowerCase(RemoveDiacritics(AValue)));
end;

class function TInventoryLabEntityNormalizer.CanonicalizeToken(
  const AValue: string): string;
var
  LChar: Char;
  LBuilder: string;
begin
  LBuilder := '';
  for LChar in NormalizeText(AValue) do
  begin
    if LChar.IsLetterOrDigit then
      LBuilder := LBuilder + LChar
    else if CharInSet(LChar, [' ', '-', '/', '.', '_']) then
      LBuilder := LBuilder + '_';
  end;

  while Pos('__', LBuilder) > 0 do
    LBuilder := StringReplace(LBuilder, '__', '_', [rfReplaceAll]);

  Result := LBuilder;
  while (Result <> '') and (Result[1] = '_') do
    Delete(Result, 1, 1);
  while (Result <> '') and (Result[Length(Result)] = '_') do
    Delete(Result, Length(Result), 1);
end;

class function TInventoryLabEntityNormalizer.GuessCanonicalCategory(
  const ACategory, ASubcategory, AName: string): string;
var
  LText: string;
begin
  LText := NormalizeText(ACategory + ' ' + ASubcategory + ' ' + AName);

  if ContainsText(LText, 'cpu') or ContainsText(LText, 'processador') then
    Exit('cpu');
  if ContainsText(LText, 'gpu') or ContainsText(LText, 'video') or ContainsText(LText, 'rtx') then
    Exit('gpu');
  if ContainsText(LText, 'placa mae') or ContainsText(LText, 'motherboard') then
    Exit('motherboard');
  if ContainsText(LText, 'ram') or ContainsText(LText, 'memoria') then
    Exit('ram');
  if ContainsText(LText, 'ssd') then
    Exit('ssd');
  if ContainsText(LText, 'fonte') or ContainsText(LText, 'psu') then
    Exit('psu');
  if ContainsText(LText, 'cooler') then
    Exit('cooler');
  if ContainsText(LText, 'gabinete') then
    Exit('case');

  if ContainsText(LText, 'resistor') then
    Exit('resistor');
  if ContainsText(LText, 'diodo') then
    Exit('diode');
  if ContainsText(LText, 'modulo') then
    Exit('module');

  Result := 'component';
end;

class function TInventoryLabEntityNormalizer.BuildCanonicalId(const APartNumber,
  AName, ACategory, ASubcategory: string): string;
var
  LBase: string;
  LCategory: string;
begin
  LCategory := GuessCanonicalCategory(ACategory, ASubcategory, AName);

  LBase := CanonicalizeToken(APartNumber);
  if LBase = '' then
    LBase := CanonicalizeToken(AName);
  if LBase = '' then
    LBase := 'unknown';

  Result := LCategory + '_' + LBase;
end;

class function TInventoryLabEntityNormalizer.NormalizeToEntity(
  ARaw: TInventoryLabRawRecord): TYakkoInventoryEntity;
var
  LPair: TPair<string, string>;
begin
  if not Assigned(ARaw) then
    raise EArgumentNilException.Create('ARaw must be assigned.');

  Result := TYakkoInventoryEntity.Create;
  try
    Result.Id := BuildCanonicalId(ARaw.PartNumber, ARaw.DisplayName, ARaw.Category, ARaw.Subcategory);
    Result.Name := ARaw.DisplayName;
    Result.Brand := ARaw.Brand;
    Result.Category := GuessCanonicalCategory(ARaw.Category, ARaw.Subcategory, ARaw.DisplayName);
    Result.Description := ARaw.Description;

    Result.Specifications.AddOrSetValue('source_file', ARaw.SourceFile);
    Result.Specifications.AddOrSetValue('part_number', ARaw.PartNumber);
    Result.Specifications.AddOrSetValue('category_raw', ARaw.Category);
    Result.Specifications.AddOrSetValue('subcategory_raw', ARaw.Subcategory);

    for LPair in ARaw.FlatScalars do
    begin
      if StartsText('especificacoes_', LPair.Key)
        or ContainsText(LPair.Key, '.especificacoes_')
        or ContainsText(LPair.Key, '.arquitetura_e_compatibilidade.')
      then
        Result.Specifications.AddOrSetValue(LPair.Key, LPair.Value);
    end;

    Result.Metadata.AddOrSetValue('source_file', ARaw.SourceFile);
    Result.Metadata.AddOrSetValue('source_part_number', ARaw.PartNumber);
    Result.Metadata.AddOrSetValue('normalizer', 'deterministic-v1');
  except
    Result.Free;
    raise;
  end;
end;

class procedure TInventoryLabEntityNormalizer.CollectAliases(
  ARaw: TInventoryLabRawRecord; AEntity: TYakkoInventoryEntity;
  AOutAliases: TInventoryLabStringList);
var
  LValue: string;
  LRawName: string;
  LCompact: string;
begin
  if not Assigned(ARaw) or not Assigned(AEntity) or not Assigned(AOutAliases) then
    raise EArgumentNilException.Create('CollectAliases arguments must be assigned.');

  AOutAliases.Clear;

  if Trim(ARaw.PartNumber) <> '' then
    AOutAliases.Add(ARaw.PartNumber);

  if Trim(ARaw.DisplayName) <> '' then
    AOutAliases.Add(ARaw.DisplayName);

  if Trim(AEntity.Name) <> '' then
    AOutAliases.Add(AEntity.Name);

  if Trim(ARaw.Brand) <> '' then
    AOutAliases.Add(ARaw.Brand + ' ' + ARaw.PartNumber);

  if ARaw.FlatScalars.ContainsKey('componente.nome_comum') then
    AOutAliases.Add(ARaw.FlatScalars['componente.nome_comum']);

  if ARaw.FlatScalars.ContainsKey('componente.sku_etiqueta') then
    AOutAliases.Add(ARaw.FlatScalars['componente.sku_etiqueta']);

  LRawName := Trim(ARaw.DisplayName);
  if LRawName <> '' then
  begin
    LCompact := StringReplace(LRawName, 'Módulo ', '', [rfIgnoreCase]);
    LCompact := StringReplace(LCompact, 'Modulo ', '', [rfIgnoreCase]);
    LCompact := StringReplace(LCompact, 'Placa ', '', [rfIgnoreCase]);
    if Trim(LCompact) <> '' then
      AOutAliases.Add(Trim(LCompact));
  end;

  for LValue in AOutAliases do
    AEntity.Aliases.Add(LValue);
end;

end.
