@echo off
REM Signify/Philips Hue Bridge fw2 Firmware Unpacker
REM Benoetigt: Python 3, openssl, tar (alle in Windows 10/11 enthalten)
REM Nutzung: unpack_fw2.bat <fw2_datei> <key_hex> [ausgabe_ordner]

setlocal enabledelayedexpansion

if "%~1"=="" goto usage
if "%~2"=="" goto usage

set FW2=%~1
set KEY=%~2
set OUTDIR=%~3
if "%OUTDIR%"=="" set OUTDIR=.\output

if not exist "%FW2%" (
    echo Fehler: Datei nicht gefunden: %FW2%
    exit /b 1
)

if not exist "%OUTDIR%" mkdir "%OUTDIR%"

echo fw2 Unpacker - Signify/Philips Hue Bridge
echo ==========================================

REM Python-Script in temporaere Datei schreiben
set PYSCRIPT=%TEMP%\fw2unpack.py
(
echo import sys, struct
echo data = open(sys.argv[1], 'rb'^).read(^)
echo if data[0:6] != b'BSB002':
echo     print('Fehler: Ungültiges Magic'); sys.exit(1^)
echo builder = data[12:28].rstrip(b'\x00'^).decode('ascii', errors='replace'^)
echo version = data[40:52].rstrip(b'\x00'^).decode('ascii', errors='replace'^)
echo total = struct.unpack('^>I', data[8:12]^)[0]
echo iv = data[60:76].hex(^)
echo print('Builder:', builder^)
echo print('Version:', version^)
echo print('Total:', total^)
echo print('IV:', iv^)
echo open(sys.argv[2], 'wb'^).write(data[76:76+total]^)
) > "%PYSCRIPT%"

REM Python ausfuehren
for /f "tokens=1,2,3,4 delims=: " %%a in ('python "%PYSCRIPT%" "%FW2%" "%OUTDIR%\payload.enc" 2^>^&1') do (
    if "%%a"=="Builder" echo   Builder: %%b %%c %%d
    if "%%a"=="Version" set VER=%%b
    if "%%a"=="Total"   set TOTAL=%%b
    if "%%a"=="IV"      set IV=%%b
    if "%%a"=="Fehler"  echo FEHLER: %%b %%c && exit /b 1
)

echo   Version: %VER%
echo   IV:      %IV%
echo.

echo Entschluessele Payload...
openssl enc -d -aes-256-cbc -in "%OUTDIR%\payload.enc" -out "%OUTDIR%\payload.tar.gz" -K %KEY% -iv %IV% -nosalt 2>nul
echo   Hinweis: Trailing garbage (RSA-Signatur) ignoriert

echo Extrahiere TAR...
tar -xzf "%OUTDIR%\payload.tar.gz" -C "%OUTDIR%" 2>nul

del "%OUTDIR%\payload.enc" 2>nul
del "%OUTDIR%\payload.tar.gz" 2>nul
del "%PYSCRIPT%" 2>nul

echo.
echo Fertig! Extrahierte Dateien:
dir /b "%OUTDIR%\*.bin" 2>nul
echo.
echo Ausgabe-Ordner: %OUTDIR%
goto end

:usage
echo Nutzung: unpack_fw2.bat ^<fw2_datei^> ^<key_hex^> [ausgabe_ordner]
echo Beispiel: unpack_fw2.bat firmware.fw2 5590016d6789ec5c...
exit /b 1

:end
endlocal
