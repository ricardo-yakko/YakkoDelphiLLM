unit InventoryLab.KnowledgeMemory;

{ Knowledge/document memory builder from real inventory JSON records. }

interface

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  InventoryLab.Models,
  InventoryLab.DocumentChunker,
  Yakko.RAG.Types,
  Yakko.RAG.KnowledgeMemory;

type
  TInventoryLabKnowledgeMemory = class
  private
    FKnowledgeMemory: TYakkoKnowledgeMemory;
    FChunker: TInventoryLabDocumentChunker;

    class function BuildDocumentText(ARaw: TInventoryLabRawRecord): string; static;
  public
    constructor Create;
    destructor Destroy; override;

    procedure RegisterRawRecord(ARaw: TInventoryLabRawRecord);

    function ToDebugString: string;

    property KnowledgeMemory: TYakkoKnowledgeMemory read FKnowledgeMemory;
  end;

implementation

function MakeSafeIdToken(const AValue: string): string;
var
  LChar: Char;
begin
  Result := '';
  for LChar in LowerCase(AValue) do
  begin
    if CharInSet(LChar, ['a'..'z', '0'..'9']) then
      Result := Result + LChar
    else if CharInSet(LChar, [' ', '-', '_', '.']) then
      Result := Result + '_';
  end;

  while Pos('__', Result) > 0 do
    Result := StringReplace(Result, '__', '_', [rfReplaceAll]);

  while (Result <> '') and (Result[1] = '_') do
    Delete(Result, 1, 1);
  while (Result <> '') and (Result[Length(Result)] = '_') do
    Delete(Result, Length(Result), 1);

  if Result = '' then
    Result := 'unknown';
end;

constructor TInventoryLabKnowledgeMemory.Create;
begin
  inherited Create;
  FKnowledgeMemory := TYakkoKnowledgeMemory.Create;
  FChunker := TInventoryLabDocumentChunker.Create;
end;

destructor TInventoryLabKnowledgeMemory.Destroy;
begin
  FreeAndNil(FChunker);
  FreeAndNil(FKnowledgeMemory);
  inherited;
end;

class function TInventoryLabKnowledgeMemory.BuildDocumentText(
  ARaw: TInventoryLabRawRecord): string;
var
  LPair: TPair<string, string>;
  LLine: string;
begin
  Result := '';
  Result := Result + 'PartNumber: ' + ARaw.PartNumber + sLineBreak;
  Result := Result + 'Name: ' + ARaw.DisplayName + sLineBreak;
  Result := Result + 'Brand: ' + ARaw.Brand + sLineBreak;
  Result := Result + 'Category: ' + ARaw.Category + sLineBreak;
  Result := Result + 'Subcategory: ' + ARaw.Subcategory + sLineBreak;
  Result := Result + 'Description: ' + ARaw.Description + sLineBreak;

  for LPair in ARaw.FlatScalars do
  begin
    if (Pos('inventario.', LPair.Key) = 1)
      or ContainsText(LPair.Key, 'especificacoes_')
      or ContainsText(LPair.Key, 'compatibilidade')
      or ContainsText(LPair.Key, 'aplicacoes_')
    then
      Result := Result + LPair.Key + ': ' + LPair.Value + sLineBreak;
  end;

  for LLine in ARaw.ArrayLines do
    Result := Result + LLine + sLineBreak;

  Result := Trim(Result);
end;

procedure TInventoryLabKnowledgeMemory.RegisterRawRecord(ARaw: TInventoryLabRawRecord);
var
  LDoc: TYakkoKnowledgeDocument;
  LText: string;
  LChunks: TInventoryLabStringList;
  LChunkText: string;
  LChunkIndex: Integer;
  LChunk: TYakkoKnowledgeChunk;
  LDocId: string;
  LSourceToken: string;
begin
  if not Assigned(ARaw) then
    raise EArgumentNilException.Create('ARaw must be assigned.');

  LSourceToken := MakeSafeIdToken(ChangeFileExt(ExtractFileName(ARaw.SourceFile), ''));
  LDocId := 'doc_' + LowerCase(StringReplace(ARaw.PartNumber, ' ', '_', [rfReplaceAll])) + '__' + LSourceToken;

  LDoc := TYakkoKnowledgeDocument.Create;
  try
    LDoc.Id := LDocId;
    LDoc.Source := ARaw.SourceFile;
    LDoc.Title := ARaw.DisplayName;
    LDoc.Content := BuildDocumentText(ARaw);
    LDoc.Category := 'inventory-json';
    LDoc.Tags.Add('real-json');
    LDoc.Tags.Add('component');
    LDoc.Metadata.AddOrSetValue('source_file', ARaw.SourceFile);

    FKnowledgeMemory.RegisterDocument(LDoc);
    LDoc := nil;
  finally
    LDoc.Free;
  end;

  LText := BuildDocumentText(ARaw);
  LChunks := FChunker.ChunkText(LText);
  try
    for LChunkIndex := 0 to LChunks.Count - 1 do
    begin
      LChunkText := LChunks[LChunkIndex];
      LChunk := TYakkoKnowledgeChunk.Create;
      try
        LChunk.ChunkId := Format('chunk_%s__%s_%d', [LowerCase(ARaw.PartNumber), LSourceToken, LChunkIndex]);
        LChunk.DocumentId := LDocId;
        LChunk.Text := LChunkText;
        LChunk.ChunkIndex := LChunkIndex;
        LChunk.Tags.Add('inventory-json');
        FKnowledgeMemory.RegisterChunk(LChunk);
        LChunk := nil;
      finally
        LChunk.Free;
      end;
    end;
  finally
    LChunks.Free;
  end;
end;

function TInventoryLabKnowledgeMemory.ToDebugString: string;
begin
  Result := FKnowledgeMemory.ToDebugString;
end;

end.
