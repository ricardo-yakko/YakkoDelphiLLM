unit uYakkoDllComponent;

{ Componente utilitario para carga/liberacao de DLL.
  Responsabilidades:
  - encapsular handle e estado de biblioteca nativa
  - isolar erros de carga em uma API Delphi segura. }

interface

uses
  System.Classes,
  System.SysUtils,
  uYakkoFullExportsComponent;

type
  ELlamaDllError = class(Exception);

  TYakkoDll = class(TComponent)
  private
    FPath: string;
    FCarregado: Boolean;
  public
    destructor Destroy; override;

    procedure Carregar(const ACaminho: string = '');
    procedure Descarregar;
    function EstaCarregado: Boolean;
    property Caminho: string read FPath;
  published
  end;

implementation

destructor TYakkoDll.Destroy;
begin
  Descarregar;
  inherited;
end;

procedure TYakkoDll.Carregar(const ACaminho: string);
var
  LPath: string;
begin
  LPath := Trim(ACaminho);
  if LPath = '' then
    raise ELlamaDllError.Create('Informe o caminho da llama.dll.');

  if FCarregado and SameText(FPath, LPath) then
    Exit;

  if FCarregado then
    Descarregar;

  LoadLlamaExports(LPath);
  FPath := LPath;
  FCarregado := True;
end;

procedure TYakkoDll.Descarregar;
begin
  if not FCarregado then
    Exit;

  UnloadLlamaExports;
  FCarregado := False;
  FPath := '';
end;

function TYakkoDll.EstaCarregado: Boolean;
begin
  Result := FCarregado;
end;

initialization
  System.Classes.RegisterClass(TYakkoDll);

end.
