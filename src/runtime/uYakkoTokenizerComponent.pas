unit uYakkoTokenizerComponent;

{ Componente de tokenizacao/detokenizacao.
  Responsabilidades:
  - converter texto <-> tokens
  - estimativas de tokens para prompts/mensagens
  - encapsular detalhes de vocab/backend
  Ownership:
  - Modelo e referencia borrowed fornecida pelo Engine. }

interface

uses
  System.Classes,
  System.SysUtils,
  uYakkoModeloComponent,
  uYakkoFullExportsComponent,
  uYakkoLlamaTypes;

type
  EYakkoTokenizerError = class(Exception);

  TYakkoTokenizer = class(TComponent)
  private
    FModelo: TYakkoModelo; { referencia externa sem ownership }
    FDestruindo: Boolean;

    function Utf8Ptr(const AValue: UTF8String): PAnsiChar;
    function GetModeloDisponivel: Boolean;
    procedure EnsurePodeTokenizar;
  protected
    function BackendTokenizeUtf8(const ATextoUtf8: UTF8String): TLlamaTokenArray; virtual;
    function BackendTokenToPiece(const AToken: TLlamaToken): RawByteString; virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    function PodeTokenizar: Boolean;
    function ModeloDisponivel: Boolean;

    function CountTokens(const ATexto: string): Integer;
    function Tokenize(const ATexto: string): TLlamaTokenArray;
    function TokenizeUtf8(const ATextoUtf8: UTF8String): TLlamaTokenArray;
    function Detokenize(const ATokens: TLlamaTokenArray): string;
    function DetokenizeToken(const AToken: TLlamaToken): RawByteString;
    function TruncateToFit(const ATexto: string; AMaxTokens: Integer): string;

    property Modelo: TYakkoModelo read FModelo write FModelo;
  end;

implementation

type
  TFnTokenize = function(vocab: TLlamaVocabHandle; text: PAnsiChar; text_len: Int32; tokens: PLlamaToken; n_tokens_max: Int32; add_special: Boolean; parse_special: Boolean): Int32; cdecl;
  TFnTokenToPiece = function(vocab: TLlamaVocabHandle; token: TLlamaToken; buf: PAnsiChar; length: Int32; lstrip: Int32; special: Boolean): Int32; cdecl;

constructor TYakkoTokenizer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FModelo := nil;
  FDestruindo := False;
end;

destructor TYakkoTokenizer.Destroy;
begin
  if FDestruindo then
    Exit;

  FDestruindo := True;
  FModelo := nil;
  inherited;
end;

function TYakkoTokenizer.Utf8Ptr(const AValue: UTF8String): PAnsiChar;
begin
  if AValue = '' then
    Result := nil
  else
    Result := PAnsiChar(Pointer(AValue));
end;

function TYakkoTokenizer.GetModeloDisponivel: Boolean;
begin
  Result := Assigned(FModelo)
    and FModelo.EstaCarregado
    and (FModelo.Handle <> nil)
    and (FModelo.Vocab <> nil);
end;

function TYakkoTokenizer.ModeloDisponivel: Boolean;
begin
  Result := GetModeloDisponivel;
end;

function TYakkoTokenizer.PodeTokenizar: Boolean;
begin
  Result := (not FDestruindo) and GetModeloDisponivel;
end;

procedure TYakkoTokenizer.EnsurePodeTokenizar;
begin
  if FDestruindo then
    raise EYakkoTokenizerError.Create('Tokenizer em destruicao. Operacao nao permitida.');

  if not Assigned(FModelo) then
    raise EYakkoTokenizerError.Create('Modelo nao configurado no tokenizer.');

  if not FModelo.EstaCarregado then
    raise EYakkoTokenizerError.Create('Modelo nao carregado.');

  if FModelo.Vocab = nil then
    raise EYakkoTokenizerError.Create('Vocab do modelo nao disponivel.');

  if not Assigned(llama_tokenize) then
    raise EYakkoTokenizerError.Create('Export llama_tokenize nao disponivel.');

  if not Assigned(llama_token_to_piece) then
    raise EYakkoTokenizerError.Create('Export llama_token_to_piece nao disponivel.');
end;


function TYakkoTokenizer.BackendTokenizeUtf8(const ATextoUtf8: UTF8String): TLlamaTokenArray;
var
  LNeeded: Integer;
  LCount: Integer;
begin
  EnsurePodeTokenizar;

  Result := nil;
  LNeeded := TFnTokenize(llama_tokenize)(FModelo.Vocab, Utf8Ptr(ATextoUtf8), Length(ATextoUtf8), nil, 0, True, True);
  if LNeeded >= 0 then
    raise EYakkoTokenizerError.Create('Falha ao calcular o tamanho da tokenizacao.');

  SetLength(Result, Abs(LNeeded));
  if Length(Result) = 0 then
    Exit;

  LCount := TFnTokenize(llama_tokenize)(FModelo.Vocab, Utf8Ptr(ATextoUtf8), Length(ATextoUtf8), @Result[0], Length(Result), True, True);
  if LCount < 0 then
    raise EYakkoTokenizerError.Create('Falha ao tokenizar o texto.');

  if LCount <> Length(Result) then
    SetLength(Result, LCount);
end;

function TYakkoTokenizer.BackendTokenToPiece(const AToken: TLlamaToken): RawByteString;
var
  LBuffer: array of AnsiChar;
  LPieceLength: Integer;
  LCapacity: Integer;
begin
  EnsurePodeTokenizar;

  Result := '';
  LCapacity := 32;

  repeat
    SetLength(LBuffer, LCapacity);
    LPieceLength := TFnTokenToPiece(llama_token_to_piece)(FModelo.Vocab, AToken, PAnsiChar(@LBuffer[0]), LCapacity, 0, True);
    if LPieceLength >= 0 then
    begin
      SetString(Result, PAnsiChar(@LBuffer[0]), LPieceLength);
      Exit;
    end;
    LCapacity := Abs(LPieceLength);
  until False;
end;

function TYakkoTokenizer.CountTokens(const ATexto: string): Integer;
begin
  Result := Length(Tokenize(ATexto));
end;

function TYakkoTokenizer.Tokenize(const ATexto: string): TLlamaTokenArray;
begin
  Result := TokenizeUtf8(UTF8String(ATexto));
end;

function TYakkoTokenizer.TokenizeUtf8(const ATextoUtf8: UTF8String): TLlamaTokenArray;
begin
  Result := BackendTokenizeUtf8(ATextoUtf8);
end;

function TYakkoTokenizer.Detokenize(const ATokens: TLlamaTokenArray): string;
var
  LUtf8: UTF8String;
  LToken: TLlamaToken;
begin
  LUtf8 := '';
  for LToken in ATokens do
    LUtf8 := LUtf8 + UTF8String(BackendTokenToPiece(LToken));
  Result := UTF8ToString(LUtf8);
end;

function TYakkoTokenizer.DetokenizeToken(const AToken: TLlamaToken): RawByteString;
begin
  Result := BackendTokenToPiece(AToken);
end;

function TYakkoTokenizer.TruncateToFit(const ATexto: string; AMaxTokens: Integer): string;
var
  LTokens: TLlamaTokenArray;
begin
  if AMaxTokens < 0 then
    raise EYakkoTokenizerError.Create('AMaxTokens deve ser >= 0.');

  LTokens := Tokenize(ATexto);
  if Length(LTokens) > AMaxTokens then
    SetLength(LTokens, AMaxTokens);

  Result := Detokenize(LTokens);
end;

initialization
  System.Classes.RegisterClass(TYakkoTokenizer);

end.

