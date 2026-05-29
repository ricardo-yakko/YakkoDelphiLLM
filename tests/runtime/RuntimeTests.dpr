program RuntimeTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  RuntimeTests.Core in 'RuntimeTests.Core.pas';

begin
  try
    RunAllRuntimeTests;
    Writeln('OK: runtime tests passed');
    ExitCode := 0;
  except
    on E: Exception do
    begin
      Writeln('FAIL: ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
