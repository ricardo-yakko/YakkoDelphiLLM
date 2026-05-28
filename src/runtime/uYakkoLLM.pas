unit uYakkoLLM;

interface

uses
  System.SysUtils, System.Classes;

type
  TYakkoPaths = class(TComponent)
  private
    FModelos: string;
    FModeloEmbeddings: string;
    FDlls: string;
    procedure SetDlls(const Value: string);
    procedure SetModeloEmbeddings(const Value: string);
    procedure SetModelos(const Value: string);
  published
    property Dlls : string read FDlls write SetDlls;
    property Modelos : string read FModelos write SetModelos;
    property ModeloEmbeddings: string read FModeloEmbeddings write SetModeloEmbeddings;
  end;

implementation

{ TYakkoPaths }

procedure TYakkoPaths.SetDlls(const Value: string);
begin
  FDlls := Value;
end;

procedure TYakkoPaths.SetModelos(const Value: string);
begin
  FModelos := Value;
end;

procedure TYakkoPaths.SetModeloEmbeddings(const Value: string);
begin
  FModeloEmbeddings := Value;
end;

initialization
  RegisterClass(TYakkoPaths);

end.

