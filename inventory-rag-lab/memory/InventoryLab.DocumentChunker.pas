unit InventoryLab.DocumentChunker;

{ Simple deterministic chunker for technical document memory. }

interface

uses
  System.SysUtils,
  System.Classes,
  InventoryLab.Models;

type
  TInventoryLabDocumentChunker = class
  private
    FMaxChunkLength: Integer;
  public
    constructor Create;

    function ChunkText(const AText: string): TInventoryLabStringList;

    property MaxChunkLength: Integer read FMaxChunkLength write FMaxChunkLength;
  end;

implementation

constructor TInventoryLabDocumentChunker.Create;
begin
  inherited Create;
  FMaxChunkLength := 480;
end;

function TInventoryLabDocumentChunker.ChunkText(
  const AText: string): TInventoryLabStringList;
var
  LRemaining: string;
  LChunk: string;
  LBreakPos: Integer;
begin
  Result := TInventoryLabStringList.Create;
  LRemaining := Trim(AText);

  while LRemaining <> '' do
  begin
    if Length(LRemaining) <= FMaxChunkLength then
    begin
      Result.Add(LRemaining);
      Break;
    end;

    LBreakPos := LastDelimiter('.;:,' + sLineBreak + ' ', Copy(LRemaining, 1, FMaxChunkLength));
    if LBreakPos <= 0 then
      LBreakPos := FMaxChunkLength;

    LChunk := Trim(Copy(LRemaining, 1, LBreakPos));
    if LChunk <> '' then
      Result.Add(LChunk);

    LRemaining := Trim(Copy(LRemaining, LBreakPos + 1, MaxInt));
  end;
end;

end.
