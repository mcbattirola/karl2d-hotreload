:: Inspired by
:: https://github.com/karl-zylinski/odin-raylib-hot-reload-game-template/blob/main/build_hot_reload.bat
@echo off
setlocal

set "GAME_RUNNING=false"
set "OUT_DIR=out\hotreload"
set "APP_NAME=game"
set "GAME_PDBS_DIR=%OUT_DIR%\%APP_NAME%_pdbs"
set "EXE=%APP_NAME%_hotreload.exe"

REM Check if game is running
tasklist /NH /FI "IMAGENAME eq %EXE%" | find /I "%EXE%" >NUL && set "GAME_RUNNING=true"

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

if "%GAME_RUNNING%"=="false" (
    if exist "%OUT_DIR%" rmdir /s /q "%OUT_DIR%"
    mkdir "%OUT_DIR%"
    if not exist "%GAME_PDBS_DIR%" mkdir "%GAME_PDBS_DIR%"
    echo 0 > "%GAME_PDBS_DIR%\pdb_number"
)

if not exist "%GAME_PDBS_DIR%\pdb_number" echo 0 >>%GAME_PDBS_DIR%\pdb_number
set /p PDB_NUMBER=<"%GAME_PDBS_DIR%\pdb_number"
set /a PDB_NUMBER=%PDB_NUMBER%+1
echo %PDB_NUMBER% > "%GAME_PDBS_DIR%\pdb_number"

echo Building game.dll
odin build src -debug -build-mode:dll ^
  -out:"%OUT_DIR%\%APP_NAME%.dll" ^
  -pdb-name:"%GAME_PDBS_DIR%\%APP_NAME%_%PDB_NUMBER%.pdb"
IF %ERRORLEVEL% NEQ 0 exit /b 1

if "%GAME_RUNNING%"=="true" (
    echo Hot reloading...
    exit /b 0
)

echo Building %EXE%
odin build src\hotreload -strict-style -vet -debug ^
  -out:"%EXE%" ^
  -pdb-name:"%OUT_DIR%\hotreload.pdb"
IF %ERRORLEVEL% NEQ 0 exit /b 1

if /I "%~1"=="run" (
    echo Running %EXE%...
    start "" "%EXE%"
)
