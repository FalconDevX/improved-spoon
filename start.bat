@echo off
rem Uruchamia gre Black Meridian.
rem   start.bat         - gra
rem   start.bat edytor  - otwiera projekt w edytorze Godota
rem Silnik (Godot_v...._win64.exe) musi lezec w tym samym folderze co ten plik.

set "PROJECT=%~dp0."
set "GODOT="

rem dowolna wersja Godota w folderze gry (bez wersji _console)
for %%F in ("%~dp0Godot_v*_win64.exe") do (
    if not defined GODOT set "GODOT=%%~fF"
)

if not defined GODOT (
    echo Nie znaleziono Godota w folderze gry:
    echo   %~dp0
    echo Wrzuc tu plik Godot_v4.7.2-stable_win64.exe ^(lub nowszy^) obok start.bat.
    pause
    exit /b 1
)

if /i "%~1"=="edytor" (
    start "" "%GODOT%" --path "%PROJECT%" --editor
) else (
    start "" "%GODOT%" --path "%PROJECT%"
)
