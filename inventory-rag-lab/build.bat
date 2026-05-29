@echo off
setlocal

set ROOT=%~dp0
pushd "%ROOT%"

if exist "C:\Progra~2\Embarcadero\Studio\37.0\bin\rsvars.bat" (
  call "C:\Progra~2\Embarcadero\Studio\37.0\bin\rsvars.bat"
)

if not exist "build" mkdir "build"
if not exist "build\dcu" mkdir "build\dcu"

set COMMON_UNIT_PATH=..\src\runtime;models;data;memory;relationships;retrieval;context

echo Building console...
dcc32 -B -Q -N0"build\dcu" -E"build" -U"%COMMON_UNIT_PATH%" "console\InventoryRagLabConsole.dpr"
if errorlevel 1 goto :error

echo Building tests...
dcc32 -B -Q -N0"build\dcu" -E"build" -U"%COMMON_UNIT_PATH%" "tests\InventoryLab.Tests.dpr"
if errorlevel 1 goto :error

echo Build completed.
popd
exit /b 0

:error
echo Build failed.
popd
exit /b 1
