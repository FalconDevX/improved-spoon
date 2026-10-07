@echo off
rem Uruchamia gre Black Meridian.
rem   start.bat         - gra
rem   start.bat edytor  - otwiera projekt w edytorze Godota

set "GODOT=%USERPROFILE%\Downloads\Godot_v4.7.2-stable_win64.exe"
set "PROJECT=%~dp0."

if not exist "%GODOT%" (
    echo Nie znaleziono Godota: %GODOT%
    echo Popraw sciezke w zmiennej GODOT w tym pliku.
    pause
    exit /b 1
)

if /i "%~1"=="edytor" (
    start "" "%GODOT%" --path "%PROJECT%" --editor
) else (
    start "" "%GODOT%" --path "%PROJECT%"
)
