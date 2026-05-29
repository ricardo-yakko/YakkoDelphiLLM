unit Yakko.RAG.KnowledgeMemory;

{ Deterministic knowledge memory for first RAG layer.

  Responsibilities:
  - store knowledge documents and chunks with explicit ownership;
  - register aliases;
  - perform simple retrieval by name/category/tags/alias/text.

  This unit intentionally does not implement embeddings or semantic ranking. }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Yakko.RAG.Types;

type
  TYakkoKnowledgeMemory = class
  private
    FDocuments: TYakkoKnowledgeDocumentList;
    FChunks: TYakkoKnowledgeChunkList;
    FAliases: TYakkoStringMap;
    function FindDocumentByIdInternal(const ADocumentId: string): TYakkoKnowledgeDocument;
    class function Normalize(const AValue: string): string; static;
    class function TextContains(const AText, ATerm: string): Boolean; static;
    class function ListContainsText(AList: TYakkoStringList; const AValue: string): Boolean; static;
  public
    constructor Create;
    destructor Destroy; override;

    procedure RegisterDocument(ADocument: TYakkoKnowledgeDocument);
    procedure RegisterChunk(AChunk: TYakkoKnowledgeChunk);
    procedure RegisterAlias(const AAlias, ADocumentId: string);

    function SearchDocumentsByName(const AName: string): TYakkoKnowledgeDocumentList;
    function SearchDocumentsByCategory(const ACategory: string): TYakkoKnowledgeDocumentList;
    function SearchDocumentsByTags(const ATags: TArray<string>; AMatchAll: Boolean = False): TYakkoKnowledgeDocumentList;
    function SearchDocumentsByAlias(const AAlias: string): TYakkoKnowledgeDocumentList;
    function SearchDocumentsByText(const AText: string): TYakkoKnowledgeDocumentList;
    function SearchChunksByText(const AText: string): TYakkoKnowledgeChunkList;

    function DocumentCount: Integer;
    function ChunkCount: Integer;
    function AliasCount: Integer;
    function ToDebugString: string;
  end;

implementation

constructor TYakkoKnowledgeMemory.Create;
begin
  inherited Create;
  FDocuments := TYakkoKnowledgeDocumentList.Create(True);
  FChunks := TYakkoKnowledgeChunkList.Create(True);
  FAliases := TYakkoStringMap.Create;
end;

destructor TYakkoKnowledgeMemory.Destroy;
begin
  FreeAndNil(FAliases);
  FreeAndNil(FChunks);
  FreeAndNil(FDocuments);
  inherited;
end;

class function TYakkoKnowledgeMemory.Normalize(const AValue: string): string;
begin
  Result := Trim(LowerCase(AValue));
end;

class function TYakkoKnowledgeMemory.TextContains(const AText, ATerm: string): Boolean;
begin
  Result := Pos(Normalize(ATerm), Normalize(AText)) > 0;
end;

class function TYakkoKnowledgeMemory.ListContainsText(AList: TYakkoStringList;
  const AValue: string): Boolean;
var
  LItem: string;
begin
  Result := False;
  if not Assigned(AList) then
    Exit;

  for LItem in AList do
  begin
    if SameText(Trim(LItem), Trim(AValue)) then
      Exit(True);
  end;
end;

function TYakkoKnowledgeMemory.FindDocumentByIdInternal(
  const ADocumentId: string): TYakkoKnowledgeDocument;
var
  LDocument: TYakkoKnowledgeDocument;
begin
  Result := nil;
  for LDocument in FDocuments do
  begin
    if SameText(Trim(LDocument.Id), Trim(ADocumentId)) then
      Exit(LDocument);
  end;
end;

procedure TYakkoKnowledgeMemory.RegisterDocument(ADocument: TYakkoKnowledgeDocument);
begin
  if not Assigned(ADocument) then
    raise EArgumentNilException.Create('ADocument must be assigned.');

  if Trim(ADocument.Id) = '' then
    raise EArgumentException.Create('ADocument.Id must not be empty.');

  if Assigned(FindDocumentByIdInternal(ADocument.Id)) then
    raise EInvalidOpException.CreateFmt('Knowledge document "%s" already exists.', [ADocument.Id]);

  ADocument.UpdatedAt := Now;

  { Ownership is transferred to TYakkoKnowledgeMemory once the document is added. }
  FDocuments.Add(ADocument);
end;

procedure TYakkoKnowledgeMemory.RegisterChunk(AChunk: TYakkoKnowledgeChunk);
begin
  if not Assigned(AChunk) then
    raise EArgumentNilException.Create('AChunk must be assigned.');

  if Trim(AChunk.ChunkId) = '' then
    raise EArgumentException.Create('AChunk.ChunkId must not be empty.');

  if Trim(AChunk.DocumentId) = '' then
    raise EArgumentException.Create('AChunk.DocumentId must not be empty.');

  if not Assigned(FindDocumentByIdInternal(AChunk.DocumentId)) then
    raise EInvalidOpException.CreateFmt('Document "%s" not found for chunk "%s".', [AChunk.DocumentId, AChunk.ChunkId]);

  { Ownership is transferred to TYakkoKnowledgeMemory once the chunk is added. }
  FChunks.Add(AChunk);
end;

procedure TYakkoKnowledgeMemory.RegisterAlias(const AAlias, ADocumentId: string);
begin
  if Trim(AAlias) = '' then
    raise EArgumentException.Create('AAlias must not be empty.');

  if Trim(ADocumentId) = '' then
    raise EArgumentException.Create('ADocumentId must not be empty.');

  if not Assigned(FindDocumentByIdInternal(ADocumentId)) then
    raise EInvalidOpException.CreateFmt('Document "%s" not found for alias "%s".', [ADocumentId, AAlias]);

  FAliases.AddOrSetValue(Normalize(AAlias), Trim(ADocumentId));
end;

function TYakkoKnowledgeMemory.SearchDocumentsByName(
  const AName: string): TYakkoKnowledgeDocumentList;
var
  LDocument: TYakkoKnowledgeDocument;
begin
  Result := TYakkoKnowledgeDocumentList.Create(True);
  try
    if Trim(AName) = '' then
      Exit;

    for LDocument in FDocuments do
    begin
      if TextContains(LDocument.Title, AName)
        or TextContains(LDocument.Source, AName)
        or SameText(Trim(LDocument.Id), Trim(AName)) then
        Result.Add(LDocument.Clone);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoKnowledgeMemory.SearchDocumentsByCategory(
  const ACategory: string): TYakkoKnowledgeDocumentList;
var
  LDocument: TYakkoKnowledgeDocument;
begin
  Result := TYakkoKnowledgeDocumentList.Create(True);
  try
    if Trim(ACategory) = '' then
      Exit;

    for LDocument in FDocuments do
    begin
      if SameText(Trim(LDocument.Category), Trim(ACategory)) then
        Result.Add(LDocument.Clone);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoKnowledgeMemory.SearchDocumentsByTags(const ATags: TArray<string>;
  AMatchAll: Boolean): TYakkoKnowledgeDocumentList;
var
  LDocument: TYakkoKnowledgeDocument;
  LTag: string;
  LMatchCount: Integer;
begin
  Result := TYakkoKnowledgeDocumentList.Create(True);
  try
    if Length(ATags) = 0 then
      Exit;

    for LDocument in FDocuments do
    begin
      LMatchCount := 0;
      for LTag in ATags do
      begin
        if ListContainsText(LDocument.Tags, LTag) then
          Inc(LMatchCount);
      end;

      if (not AMatchAll and (LMatchCount > 0))
        or (AMatchAll and (LMatchCount = Length(ATags))) then
        Result.Add(LDocument.Clone);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoKnowledgeMemory.SearchDocumentsByAlias(
  const AAlias: string): TYakkoKnowledgeDocumentList;
var
  LDocumentId: string;
  LDocument: TYakkoKnowledgeDocument;
begin
  Result := TYakkoKnowledgeDocumentList.Create(True);
  try
    if Trim(AAlias) = '' then
      Exit;

    if FAliases.TryGetValue(Normalize(AAlias), LDocumentId) then
    begin
      LDocument := FindDocumentByIdInternal(LDocumentId);
      if Assigned(LDocument) then
        Result.Add(LDocument.Clone);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoKnowledgeMemory.SearchDocumentsByText(
  const AText: string): TYakkoKnowledgeDocumentList;
var
  LDocument: TYakkoKnowledgeDocument;
  LChunk: TYakkoKnowledgeChunk;
begin
  Result := TYakkoKnowledgeDocumentList.Create(True);
  try
    if Trim(AText) = '' then
      Exit;

    for LDocument in FDocuments do
    begin
      if TextContains(LDocument.Content, AText)
        or TextContains(LDocument.Title, AText)
        or TextContains(LDocument.Source, AText)
        or TextContains(LDocument.Category, AText)
      then
      begin
        Result.Add(LDocument.Clone);
        Continue;
      end;

      for LChunk in FChunks do
      begin
        if not SameText(Trim(LChunk.DocumentId), Trim(LDocument.Id)) then
          Continue;

        if TextContains(LChunk.Text, AText) then
        begin
          Result.Add(LDocument.Clone);
          Break;
        end;
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoKnowledgeMemory.SearchChunksByText(
  const AText: string): TYakkoKnowledgeChunkList;
var
  LChunk: TYakkoKnowledgeChunk;
begin
  Result := TYakkoKnowledgeChunkList.Create(True);
  try
    if Trim(AText) = '' then
      Exit;

    for LChunk in FChunks do
    begin
      if TextContains(LChunk.Text, AText) then
        Result.Add(LChunk.Clone);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoKnowledgeMemory.DocumentCount: Integer;
begin
  Result := FDocuments.Count;
end;

function TYakkoKnowledgeMemory.ChunkCount: Integer;
begin
  Result := FChunks.Count;
end;

function TYakkoKnowledgeMemory.AliasCount: Integer;
begin
  Result := FAliases.Count;
end;

function TYakkoKnowledgeMemory.ToDebugString: string;
begin
  Result := Format(
    'TYakkoKnowledgeMemory(Documents=%d, Chunks=%d, Aliases=%d)',
    [FDocuments.Count, FChunks.Count, FAliases.Count]
  );
end;

end.