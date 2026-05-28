unit uYakkoVectorStoreSQLite;

interface

uses
  System.SysUtils,
  FireDAC.Comp.Client;

type
  TYakkoVectorSearchResult = record
    SourceFile: string;
    ChunkIndex: Integer;
    Content: string;
    Similaridade: Single;
  end;

  TYakkoVectorStoreSQLite = class
  private
    FConnection: TFDConnection;
    FQuery: TFDQuery;
    FVecExtensionPath: string;
    FVecEnabled: Boolean;
    class function SingleArrayToBytes(const AValues: TArray<Single>): TBytes; static;
    class function SingleArrayToJson(const AValues: TArray<Single>): string; static;
    function ResolveVecExtensionPath: string;
    function TableExists(const ATableName: string): Boolean;
    function GetVecTableDimension: Integer;
    procedure EnsureVecSchema(ADimensao: Integer);
    function EnsureChunkRowId(const ASourceFile: string; AChunkIndex: Integer): Int64;
    procedure InicializarSchema;
  public
    constructor Create(const ADatabasePath: string);
    destructor Destroy; override;

    procedure DeleteSourceChunks(const ASourceFile: string);
    procedure SaveChunk(const ASourceFile: string; AChunkIndex: Integer; const AContent: string;
      const AVector: TArray<Single>);
    function HasRealVectorBackend: Boolean;
    function SearchSimilar(const AQueryVector: TArray<Single>; ATopK: Integer;
      const AQueryText: string; const ASourceFilters: TArray<string>; AMinSimilaridade: Single = 0.20): TArray<TYakkoVectorSearchResult>;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.Math,
  System.StrUtils,
  System.Generics.Collections,
  FireDAC.Stan.Param,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.Stan.Async,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.ExprFuncs,
  FireDAC.DApt,
  FireDAC.DApt.Intf,
  FireDAC.Phys.Intf,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Phys.SQLiteWrapper,
  FireDAC.Phys.SQLiteWrapper.Stat,
  Data.DB;

function NormalizeSearchText(const AValue: string): string;
begin
  Result := LowerCase(Trim(AValue));
  Result := StringReplace(Result, #13, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, ',', ' ', [rfReplaceAll]);
  Result := StringReplace(Result, '.', ' ', [rfReplaceAll]);
  Result := StringReplace(Result, ';', ' ', [rfReplaceAll]);
  Result := StringReplace(Result, ':', ' ', [rfReplaceAll]);
  Result := StringReplace(Result, '(', ' ', [rfReplaceAll]);
  Result := StringReplace(Result, ')', ' ', [rfReplaceAll]);
  Result := StringReplace(Result, '/', ' ', [rfReplaceAll]);
  Result := StringReplace(Result, '-', ' ', [rfReplaceAll]);
  while Pos('  ', Result) > 0 do
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
end;

procedure ExtractSearchTokens(const AText: string; const ADestino: TStrings);
const
  CStopWords: array[0..13] of string = (
    'o', 'a', 'os', 'as', 'de', 'do', 'da', 'dos', 'das',
    'para', 'pra', 'que', 'em', 'na'
  );
var
  LParts: TArray<string>;
  LPart: string;
  LToken: string;
  LStop: string;
  LIgnorar: Boolean;
begin
  if ADestino = nil then
    Exit;

  ADestino.Clear;
  LParts := SplitString(NormalizeSearchText(AText), ' ');
  for LPart in LParts do
  begin
    LToken := Trim(LPart);
    if Length(LToken) < 2 then
      Continue;

    LIgnorar := False;
    for LStop in CStopWords do
      if SameText(LToken, LStop) then
      begin
        LIgnorar := True;
        Break;
      end;

    if LIgnorar then
      Continue;

    if ADestino.IndexOf(LToken) < 0 then
      ADestino.Add(LToken);
  end;
end;

{ TYakkoVectorStoreSQLite }

constructor TYakkoVectorStoreSQLite.Create(const ADatabasePath: string);
var
  LDbPath: string;
  LDbDir: string;
  LConnection: TFDConnection;
  LQuery: TFDQuery;
begin
  inherited Create;
  FConnection := nil;
  FQuery := nil;
  LDbPath := TPath.GetFullPath(ADatabasePath);
  LDbDir := ExtractFileDir(LDbPath);
  if LDbDir <> '' then
    TDirectory.CreateDirectory(LDbDir);

  LConnection := TFDConnection.Create(nil);
  LQuery := TFDQuery.Create(nil);
  try
    FVecExtensionPath := ResolveVecExtensionPath;
    FVecEnabled := FVecExtensionPath <> '';

    LConnection.LoginPrompt := False;
    LConnection.DriverName := 'SQLite';
    LConnection.Params.Values['Database'] := LDbPath;
    LConnection.Params.Values['OpenMode'] := 'CreateUTF8';
    LConnection.Params.Values['LockingMode'] := 'Normal';
    if FVecEnabled then
      LConnection.Params.Values['Extensions'] := FVecExtensionPath;
    LConnection.Connected := True;

    LQuery.Connection := LConnection;
    FConnection := LConnection;
    FQuery := LQuery;
    InicializarSchema;
  except
    LQuery.Free;
    LConnection.Free;
    FQuery := nil;
    FConnection := nil;
    raise;
  end;
end;

destructor TYakkoVectorStoreSQLite.Destroy;
begin
  FQuery.Free;
  FConnection.Free;
  inherited;
end;

class function TYakkoVectorStoreSQLite.SingleArrayToBytes(const AValues: TArray<Single>): TBytes;
begin
  if Length(AValues) = 0 then
    Exit(nil);

  SetLength(Result, Length(AValues) * SizeOf(Single));
  Move(AValues[0], Result[0], Length(Result));
end;

class function TYakkoVectorStoreSQLite.SingleArrayToJson(const AValues: TArray<Single>): string;
var
  I: Integer;
  LBuilder: TStringBuilder;
  LFormatSettings: TFormatSettings;
begin
  if Length(AValues) = 0 then
    Exit('[]');

  LFormatSettings := TFormatSettings.Invariant;
  LBuilder := TStringBuilder.Create;
  try
    LBuilder.Append('[');
    for I := 0 to High(AValues) do
    begin
      if I > 0 then
        LBuilder.Append(',');
      LBuilder.Append(FloatToStr(AValues[I], LFormatSettings));
    end;
    LBuilder.Append(']');
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

function TYakkoVectorStoreSQLite.ResolveVecExtensionPath: string;
var
  LCandidates: TArray<string>;
  LCandidate: string;
begin
  LCandidates := [
    TPath.Combine(ExtractFilePath(ParamStr(0)), 'vec0.dll'),
    TPath.Combine(ExtractFilePath(ParamStr(0)), 'sqlite-vec\vec0.dll'),
    TPath.Combine(TPath.GetDocumentsPath, 'harmonica.io\dlls\sqlite-vec\vec0.dll'),
    TPath.Combine(TPath.GetDocumentsPath, 'harmonica.io\dlls\vec0.dll')
  ];

  for LCandidate in LCandidates do
    if FileExists(LCandidate) then
      Exit(TPath.GetFullPath(LCandidate));

  Result := '';
end;

function TYakkoVectorStoreSQLite.TableExists(const ATableName: string): Boolean;
begin
  FQuery.Close;
  FQuery.SQL.Text :=
    'SELECT 1 FROM sqlite_master WHERE type IN (''table'', ''virtual table'') AND name = :name';
  FQuery.ParamByName('name').AsString := ATableName;
  FQuery.Open;
  try
    Result := not FQuery.Eof;
  finally
    FQuery.Close;
  end;
end;

function TYakkoVectorStoreSQLite.GetVecTableDimension: Integer;
var
  LSql: string;
  LStartPos: Integer;
  LEndPos: Integer;
  LDimText: string;
begin
  Result := 0;
  if not TableExists('rag_chunk_vec') then
    Exit;

  FQuery.Close;
  FQuery.SQL.Text :=
    'SELECT sql FROM sqlite_master WHERE name = ''rag_chunk_vec''';
  FQuery.Open;
  try
    if FQuery.Eof then
      Exit;
    LSql := FQuery.Fields[0].AsString;
  finally
    FQuery.Close;
  end;

  LStartPos := Pos('float[', LowerCase(LSql));
  if LStartPos <= 0 then
    Exit;
  Inc(LStartPos, Length('float['));
  LEndPos := PosEx(']', LSql, LStartPos);
  if LEndPos <= LStartPos then
    Exit;

  LDimText := Copy(LSql, LStartPos, LEndPos - LStartPos);
  Result := StrToIntDef(Trim(LDimText), 0);
end;

procedure TYakkoVectorStoreSQLite.EnsureVecSchema(ADimensao: Integer);
var
  LExistingDim: Integer;
begin
  if not FVecEnabled then
    Exit;

  if ADimensao <= 0 then
    raise Exception.Create('Dimensao invalida para indice vetorial.');

  if not TableExists('rag_chunk_ids') then
  begin
    FConnection.ExecSQL(
      'CREATE TABLE rag_chunk_ids (' +
      '  id INTEGER PRIMARY KEY AUTOINCREMENT,' +
      '  source_file TEXT NOT NULL,' +
      '  chunk_index INTEGER NOT NULL,' +
      '  UNIQUE(source_file, chunk_index)' +
      ')'
    );
    FConnection.ExecSQL('CREATE INDEX IF NOT EXISTS idx_rag_chunk_ids_source ON rag_chunk_ids(source_file)');
  end;

  if not TableExists('rag_chunk_vec') then
  begin
    FConnection.ExecSQL(
      Format('CREATE VIRTUAL TABLE rag_chunk_vec USING vec0(embedding float[%d])', [ADimensao])
    );
    Exit;
  end;

  LExistingDim := GetVecTableDimension;
  if (LExistingDim > 0) and (LExistingDim <> ADimensao) then
    raise Exception.CreateFmt(
      'Indice vetorial sqlite-vec com dimensao %d conflita com vetor atual %d.',
      [LExistingDim, ADimensao]
    );
end;

function TYakkoVectorStoreSQLite.EnsureChunkRowId(const ASourceFile: string; AChunkIndex: Integer): Int64;
begin
  Result := 0;
  if not FVecEnabled then
    Exit;

  FQuery.Close;
  FQuery.SQL.Text :=
    'INSERT OR IGNORE INTO rag_chunk_ids(source_file, chunk_index) VALUES (:source, :chunk_index)';
  FQuery.ParamByName('source').AsString := ASourceFile;
  FQuery.ParamByName('chunk_index').AsInteger := AChunkIndex;
  FQuery.ExecSQL;

  FQuery.Close;
  FQuery.SQL.Text :=
    'SELECT id FROM rag_chunk_ids WHERE source_file = :source AND chunk_index = :chunk_index';
  FQuery.ParamByName('source').AsString := ASourceFile;
  FQuery.ParamByName('chunk_index').AsInteger := AChunkIndex;
  FQuery.Open;
  try
    if not FQuery.Eof then
      Result := FQuery.Fields[0].AsLargeInt;
  finally
    FQuery.Close;
  end;
end;

procedure TYakkoVectorStoreSQLite.InicializarSchema;
begin
  FConnection.ExecSQL(
    'CREATE TABLE IF NOT EXISTS rag_chunks (' +
    '  source_file TEXT NOT NULL,' +
    '  chunk_index INTEGER NOT NULL,' +
    '  content TEXT NOT NULL,' +
    '  vector BLOB NOT NULL,' +
    '  dimensao INTEGER NOT NULL,' +
    '  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,' +
    '  PRIMARY KEY(source_file, chunk_index)' +
    ')'
  );

  FConnection.ExecSQL('CREATE INDEX IF NOT EXISTS idx_rag_chunks_source ON rag_chunks(source_file)');
  FConnection.ExecSQL('CREATE INDEX IF NOT EXISTS idx_rag_chunks_dim ON rag_chunks(dimensao)');

  if FVecEnabled and (not TableExists('rag_chunk_ids')) then
  begin
    FConnection.ExecSQL(
      'CREATE TABLE rag_chunk_ids (' +
      '  id INTEGER PRIMARY KEY AUTOINCREMENT,' +
      '  source_file TEXT NOT NULL,' +
      '  chunk_index INTEGER NOT NULL,' +
      '  UNIQUE(source_file, chunk_index)' +
      ')'
    );
    FConnection.ExecSQL('CREATE INDEX IF NOT EXISTS idx_rag_chunk_ids_source ON rag_chunk_ids(source_file)');
  end;
end;

procedure TYakkoVectorStoreSQLite.DeleteSourceChunks(const ASourceFile: string);
var
  LIds: TArray<Int64>;
  LId: Int64;
begin
  if FVecEnabled and TableExists('rag_chunk_vec') then
  begin
    SetLength(LIds, 0);
    FQuery.Close;
    FQuery.SQL.Text := 'SELECT id FROM rag_chunk_ids WHERE source_file = :source';
    FQuery.ParamByName('source').AsString := ASourceFile;
    FQuery.Open;
    try
      while not FQuery.Eof do
      begin
        SetLength(LIds, Length(LIds) + 1);
        LIds[High(LIds)] := FQuery.Fields[0].AsLargeInt;
        FQuery.Next;
      end;
    finally
      FQuery.Close;
    end;

    for LId in LIds do
      FConnection.ExecSQL('DELETE FROM rag_chunk_vec WHERE rowid = ?', [LId]);

    FConnection.ExecSQL('DELETE FROM rag_chunk_ids WHERE source_file = ?', [ASourceFile]);
  end;

  FQuery.Close;
  FQuery.SQL.Text := 'DELETE FROM rag_chunks WHERE source_file = :source';
  FQuery.ParamByName('source').AsString := ASourceFile;
  FQuery.ExecSQL;
end;

procedure TYakkoVectorStoreSQLite.SaveChunk(const ASourceFile: string; AChunkIndex: Integer;
  const AContent: string; const AVector: TArray<Single>);
var
  LBytes: TBytes;
  LStream: TBytesStream;
  LRowId: Int64;
  LVectorJson: string;
begin
  if Length(AVector) = 0 then
    raise Exception.Create('Nao e possivel salvar chunk com vetor vazio.');

  if FVecEnabled then
    EnsureVecSchema(Length(AVector));

  LBytes := SingleArrayToBytes(AVector);

  FQuery.Close;
  FQuery.SQL.Text :=
    'INSERT OR REPLACE INTO rag_chunks ' +
    '(source_file, chunk_index, content, vector, dimensao, updated_at) ' +
    'VALUES (:source, :chunk_index, :content, :vector, :dim, CURRENT_TIMESTAMP)';
  FQuery.ParamByName('source').AsString := ASourceFile;
  FQuery.ParamByName('chunk_index').AsInteger := AChunkIndex;
  FQuery.ParamByName('content').AsString := AContent;
  LStream := TBytesStream.Create(LBytes);
  try
    FQuery.ParamByName('vector').LoadFromStream(LStream, ftBlob);
    FQuery.ParamByName('dim').AsInteger := Length(AVector);
    FQuery.ExecSQL;
  finally
    LStream.Free;
  end;

  if FVecEnabled then
  begin
    LRowId := EnsureChunkRowId(ASourceFile, AChunkIndex);
    if LRowId > 0 then
    begin
      LVectorJson := SingleArrayToJson(AVector);
      FConnection.ExecSQL('DELETE FROM rag_chunk_vec WHERE rowid = ?', [LRowId]);
      FConnection.ExecSQL('INSERT INTO rag_chunk_vec(rowid, embedding) VALUES (?, ?)', [LRowId, LVectorJson]);
    end;
  end;
end;

function TYakkoVectorStoreSQLite.HasRealVectorBackend: Boolean;
begin
  Result := FVecEnabled;
end;

function TYakkoVectorStoreSQLite.SearchSimilar(const AQueryVector: TArray<Single>; ATopK: Integer;
  const AQueryText: string; const ASourceFilters: TArray<string>; AMinSimilaridade: Single): TArray<TYakkoVectorSearchResult>;
var
  LFilterSet: TDictionary<string, Byte>;
  LFilter: string;
  LQueryJson: string;
  LDistance: Double;
  LVectorScore: Single;
  LTextScore: Single;
  LScoreFinal: Single;
  LResultItem: TYakkoVectorSearchResult;
  LInsertPos: Integer;
  LDocumentText: string;
  LTokens: TStringList;
  LToken: string;
  LHits: Integer;
  LBonus: Single;
  LSource: string;
begin
  SetLength(Result, 0);
  if Length(AQueryVector) = 0 then
    Exit;

  if not FVecEnabled then
    raise Exception.Create('sqlite-vec nao esta disponivel. Configure vec0.dll para usar busca vetorial.');

  if not TableExists('rag_chunk_vec') then
    raise Exception.Create('Tabela vetorial rag_chunk_vec nao encontrada. Gere embeddings para inicializar o indice vetorial.');

  if ATopK <= 0 then
    ATopK := 5;

  LFilterSet := TDictionary<string, Byte>.Create;
  LTokens := TStringList.Create;
  LTokens.CaseSensitive := False;
  LTokens.Duplicates := dupIgnore;
  LTokens.Sorted := False;
  ExtractSearchTokens(AQueryText, LTokens);
  try
    for LFilter in ASourceFilters do
      if Trim(LFilter) <> '' then
        LFilterSet.AddOrSetValue(AnsiLowerCase(Trim(LFilter)), 1);

    LQueryJson := SingleArrayToJson(AQueryVector);
    FQuery.Close;
    FQuery.SQL.Text :=
      'SELECT ids.source_file, ids.chunk_index, chunks.content, hits.distance ' +
      'FROM (' +
      '  SELECT rowid, distance FROM rag_chunk_vec ' +
      '  WHERE embedding MATCH :query_vector ' +
      '  ORDER BY distance ' +
      '  LIMIT :candidate_limit' +
      ') hits ' +
      'JOIN rag_chunk_ids ids ON ids.id = hits.rowid ' +
      'JOIN rag_chunks chunks ON chunks.source_file = ids.source_file AND chunks.chunk_index = ids.chunk_index ' +
      'ORDER BY hits.distance';
    FQuery.ParamByName('query_vector').AsString := LQueryJson;
    FQuery.ParamByName('candidate_limit').AsInteger := Max(ATopK * 8, 24);
    FQuery.Open;
    try
      while not FQuery.Eof do
      begin
        LSource := FQuery.FieldByName('source_file').AsString;
        if (LFilterSet.Count > 0) and (not LFilterSet.ContainsKey(AnsiLowerCase(LSource))) then
        begin
          FQuery.Next;
          Continue;
        end;

        LDistance := FQuery.FieldByName('distance').AsFloat;
        LVectorScore := 1.0 / (1.0 + Max(LDistance, 0.0));

        LDocumentText := NormalizeSearchText(FQuery.FieldByName('content').AsString + ' ' + ExtractFileName(LSource));
        LHits := 0;
        LBonus := 0;
        for LToken in LTokens do
          if Pos(LToken, LDocumentText) > 0 then
          begin
            Inc(LHits);
            LBonus := LBonus + 0.03;
          end;

        if LTokens.Count > 0 then
          LTextScore := Min(1.0, LHits / LTokens.Count)
        else
          LTextScore := 0;

        LScoreFinal := (0.90 * LVectorScore) + (0.10 * LTextScore) + Min(LBonus, 0.10);
        if LScoreFinal > 0.999 then
          LScoreFinal := 0.999;

        if LScoreFinal >= AMinSimilaridade then
        begin
          LResultItem.SourceFile := LSource;
          LResultItem.ChunkIndex := FQuery.FieldByName('chunk_index').AsInteger;
          LResultItem.Content := FQuery.FieldByName('content').AsString;
          LResultItem.Similaridade := LScoreFinal;

          LInsertPos := Length(Result);
          SetLength(Result, Length(Result) + 1);
          while (LInsertPos > 0) and (Result[LInsertPos - 1].Similaridade < LResultItem.Similaridade) do
          begin
            Result[LInsertPos] := Result[LInsertPos - 1];
            Dec(LInsertPos);
          end;
          Result[LInsertPos] := LResultItem;

          if Length(Result) > ATopK then
            SetLength(Result, ATopK);
        end;

        FQuery.Next;
      end;
    finally
      FQuery.Close;
    end;
  finally
    LTokens.Free;
    LFilterSet.Free;
  end;
end;

end.
