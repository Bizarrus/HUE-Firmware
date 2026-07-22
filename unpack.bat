@echo off
REM Signify/Philips Hue Bridge fw2 Firmware Unpacker
REM Benoetigt: Python 3, openssl, tar (Windows 10/11 enthalten)
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

REM Python-Script als separate Datei erzeugen (kein Inline-Escaping)
set PYSCRIPT=%TEMP%\fw2unpack_%RANDOM%.py
set INFOFILE=%TEMP%\fw2info_%RANDOM%.txt

python -c "
script = '''
import sys, struct

fw2 = sys.argv[1]
payload_out = sys.argv[2]
info_out = sys.argv[3]

with open(fw2, 'rb') as f:
    data = f.read()

if data[0:6] != b'BSB002':
    print('ERROR:Ungültiges Magic')
    sys.exit(1)

builder = data[12:28].rstrip(b'\\x00').decode('ascii', errors='replace')
version = data[40:52].rstrip(b'\\x00').decode('ascii', errors='replace')
total = struct.unpack('>I', data[8:12])[0]
iv = data[60:76].hex()

with open(info_out, 'w') as f:
    f.write('BUILDER=' + builder + '\\n')
    f.write('VERSION=' + version + '\\n')
    f.write('TOTAL=' + str(total) + '\\n')
    f.write('IV=' + iv + '\\n')

with open(payload_out, 'wb') as f:
    f.write(data[76:76+total])

print('OK')
'''
open(r'%PYSCRIPT%', 'w').write(script)
"

python "%PYSCRIPT%" "%FW2%" "%OUTDIR%\payload.enc" "%INFOFILE%"
if errorlevel 1 (
    echo Fehler beim Lesen der fw2-Datei
    goto cleanup
)

REM Info-Datei lesen
for /f "tokens=1,2 delims==" %%a in (%INFOFILE%) do (
    if "%%a"=="BUILDER" echo   Builder: %%b
    if "%%a"=="VERSION" set VER=%%b
    if "%%a"=="TOTAL"   set TOTAL=%%b
    if "%%a"=="IV"      set IV=%%b
)
echo   Version: %VER%
echo   IV:      %IV%
echo.

echo Entschluessele Payload...
openssl enc -d -aes-256-cbc -in "%OUTDIR%\payload.enc" -out "%OUTDIR%\payload.tar.gz" -K %KEY% -iv %IV% -nosalt 2>nul
echo   (Trailing garbage/RSA-Signatur ignoriert)

echo Extrahiere TAR...
tar -xzf "%OUTDIR%\payload.tar.gz" -C "%OUTDIR%" 2>nul

echo.
echo Fertig! Extrahierte Dateien:
dir /b "%OUTDIR%\*.bin" 2>nul
echo.
echo Ausgabe-Ordner: %OUTDIR%

:cleanup
del "%OUTDIR%\payload.enc" 2>nul
del "%OUTDIR%\payload.tar.gz" 2>nul
del "%PYSCRIPT%" 2>nul
del "%INFOFILE%" 2>nul
goto end

:usage
echo Nutzung: unpack_fw2.bat ^<fw2_datei^> ^<key_hex^> [ausgabe_ordner]
echo Beispiel: unpack_fw2.bat firmware.fw2 5590016d...
exit /b 1

:end
endlocal
