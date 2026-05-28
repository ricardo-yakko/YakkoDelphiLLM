program YakkoStudio;

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  uYakkoStudioMain in 'uYakkoStudioMain.pas' {Form1};

{$R *.res}

function IsCliRagMode: Boolean;
var
  I: Integer;
  LParam: string;
  LLog: TStringList;
begin
  Result := False;
  if ParamCount <= 0 then
    Exit;

  LLog := TStringList.Create;
  try
    LLog.Add('ParamCount=' + IntToStr(ParamCount));
  for I := 1 to ParamCount do
  begin
    LParam := LowerCase(Trim(ParamStr(I)));
      LLog.Add(Format('Param[%d]=%s', [I, LParam]));
      if Pos('rag-test', LParam) > 0 then
        Result := True;
    end;

    LLog.Add('DetectedCli=' + BoolToStr(Result, True));
    try
      LLog.SaveToFile(ExtractFilePath(ParamStr(0)) + 'cli_args_debug.txt', TEncoding.UTF8);
    except
    end;
  finally
    LLog.Free;
  end;
end;

begin
  if IsCliRagMode then
  begin
    ExecuteCliRagFromParams;
    Halt(0);
  end;

  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TYakkoStudioMainForm, Form1);
  Application.Run;
end.




