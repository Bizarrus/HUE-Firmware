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

REM Python-Script als echte Datei schreiben (eine Zeile pro echo)
set PYSCRIPT=%TEMP%\fw2unpack.py
set INFOFILE=%TEMP%\fw2info.txt

echo import sys, struct > "%PYSCRIPT%"
echo fw2 = sys.argv[1] >> "%PYSCRIPT%"
echo payload_out = sys.argv[2] >> "%PYSCRIPT%"
echo info_out = sys.argv[3] >> "%PYSCRIPT%"
echo data = open(fw2, 'rb').read() >> "%PYSCRIPT%"
echo if data[0:6] != b'BSB002': >> "%PYSCRIPT%"
echo     print('Fehler: Ungültiges Magic'); sys.exit(1) >> "%PYSCRIPT%"
echo builder = data[12:28].rstrip(b'\x00').decode('ascii', errors='replace') >> "%PYSCRIPT%"
echo version = data[40:52].rstrip(b'\x00').decode('ascii', errors='replace') >> "%PYSCRIPT%"
echo total = struct.unpack_from('!I', data, 8)[0] >> "%PYSCRIPT%"
echo iv = data[60:76].hex() >> "%PYSCRIPT%"
echo f = open(info_out, 'w') >> "%PYSCRIPT%"
echo f.write('BUILDER=' + builder + '\n') >> "%PYSCRIPT%"
echo f.write('VERSION=' + version + '\n') >> "%PYSCRIPT%"
echo f.write('TOTAL=' + str(total) + '\n') >> "%PYSCRIPT%"
echo f.write('IV=' + iv + '\n') >> "%PYSCRIPT%"
echo f.close() >> "%PYSCRIPT%"
echo open(payload_out, 'wb').write(data[76:76+total]) >> "%PYSCRIPT%"
echo print('OK') >> "%PYSCRIPT%"

python "%PYSCRIPT%" "%FW2%" "%OUTDIR%\payload.enc" "%INFOFILE%"
if errorlevel 1 (
    echo Fehler beim Lesen der fw2-Datei
    goto cleanup
)

REM Info-Datei lesen
for /f "tokens=1,2 delims==" %%a in (%INFOFILE%) do (
    if "%%a"=="BUILDER" echo   Builder: %%b
    if "%%a"=="VERSION" echo   Version: %%b
    if "%%a"=="IV"      set IV=%%b
)
echo   IV: %IV%
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
