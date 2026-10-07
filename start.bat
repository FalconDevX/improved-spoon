@echo off
rem Uruchamia gre Black Meridian.
rem   start.bat         - gra
rem   start.bat edytor  - otwiera projekt w edytorze Godota
rem Silnik (Godot_v...._win64.exe) jest szukany w tym samym folderze co ten plik.
rem Jesli go nie ma, zostanie pobrany raz z oficjalnej strony Godota (GitHub godotengine, ok. 86 MB).

set "PROJECT=%~dp0."
set "GODOT_VER=4.7.2-stable"
set "GODOT="

call :find_godot
if not defined GODOT (
    echo Nie ma Godota w folderze gry - pobieram Godot %GODOT_VER% ^(jednorazowo, ok. 86 MB^)...
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue';" ^
        "$zip=Join-Path $env:TEMP 'godot_%GODOT_VER%.zip';" ^
        "Invoke-WebRequest -Uri 'https://github.com/godotengine/godot/releases/download/%GODOT_VER%/Godot_v%GODOT_VER%_win64.exe.zip' -OutFile $zip;" ^
        "Expand-Archive -Path $zip -DestinationPath '%~dp0.' -Force; Remove-Item $zip"
    if errorlevel 1 (
        echo Nie udalo sie pobrac Godota. Pobierz recznie Godot %GODOT_VER% ^(Windows, wersja standardowa^)
        echo ze strony https://godotengine.org/download i wrzuc plik .exe do folderu:
        echo   %~dp0
        pause
        exit /b 1
    )
    call :find_godot
)

if not defined GODOT (
    echo Nie znaleziono Godota w folderze gry: %~dp0
    pause
    exit /b 1
)

rem import zasobow (modele, tekstury) przy kazdym starcie: po aktualizacji gry (git pull)
rem nowe modele musza sie zaimportowac; gdy nic sie nie zmienilo, trwa to kilka sekund
if not exist "%~dp0.godot\imported" echo Pierwsze uruchomienie - importuje zasoby gry, to potrwa chwile...
"%GODOT%" --headless --path "%PROJECT%" --import

if /i "%~1"=="edytor" (
    start "" "%GODOT%" --path "%PROJECT%" --editor
) else (
    start "" "%GODOT%" --path "%PROJECT%"
)
exit /b 0


:find_godot
rem dowolna wersja Godota w folderze gry (bez wersji _console)
for %%F in ("%~dp0Godot_v*_win64.exe") do (
    if not defined GODOT set "GODOT=%%~fF"
)
exit /b 0
