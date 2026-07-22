@echo off
REM Signify/Philips Hue Bridge fw2 Firmware Unpacker
REM Requires: openssl.exe und tar.exe (beide in Windows 10/11 enthalten)
REM
REM fw2 Format:
REM   Offset  0-5:   Magic "BSB002"
REM   Offset 60-75:  AES-256-CBC IV (16 bytes)
REM   Offset 76+:    gzip-compressed TAR (kernel.bin + root.bin)
REM
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

REM Ausgabe-Ordner erstellen
if not exist "%OUTDIR%" mkdir "%OUTDIR%"

REM Python prüfen (für IV-Extraktion und Payload-Extraktion)
python --version >nul 2>&1
if errorlevel 1 (
    echo Fehler: Python nicht gefunden. Bitte Python installieren.
    exit /b 1
)

REM openssl prüfen
openssl version >nul 2>&1
if errorlevel 1 (
    echo Fehler: openssl nicht gefunden.
    exit /b 1
)

echo fw2 Unpacker - Signify/Philips Hue Bridge
echo ==========================================

REM Python-Script inline ausführen um IV zu extrahieren und Payload zu schreiben
python -c "
import sys, struct, os

fw2_path = r'%FW2%'
outdir = r'%OUTDIR%'

with open(fw2_path, 'rb') as f:
    data = f.read()

# Magic prüfen
magic = data[0:6]
if magic != b'BSB002':
    print(f'Fehler: Ungültiges Magic: {magic}')
    sys.exit(1)

# Metadaten lesen
num_files = data[7]
total_size = struct.unpack('>I', data[8:12])[0]
builder = data[12:28].rstrip(b'\x00').decode('ascii', errors='replace')
version = data[40:52].rstrip(b'\x00').decode('ascii', errors='replace')

print(f'Builder:  {builder}')
print(f'Version:  {version}')
print(f'Dateien:  {num_files}')
print(f'Groesse:  {total_size} bytes')

# IV extrahieren (Bytes 60-75)
iv = data[60:76]
iv_hex = iv.hex()
print(f'IV:       {iv_hex}')

# IV in Datei schreiben für openssl
with open(os.path.join(outdir, 'iv.txt'), 'w') as f:
    f.write(iv_hex)

# Payload extrahieren (ab Offset 76, Länge = total_size)
payload = data[76:76+total_size]
payload_path = os.path.join(outdir, 'payload.enc')
with open(payload_path, 'wb') as f:
    f.write(payload)

print(f'Payload:  {len(payload)} bytes -> {payload_path}')
print('OK')
"

if errorlevel 1 (
    echo Fehler beim Lesen der fw2-Datei
    exit /b 1
)

REM IV lesen
set /p IV=<"%OUTDIR%\iv.txt"
echo IV: %IV%

echo Entschluessele Payload...
openssl enc -d -aes-256-cbc ^
    -in "%OUTDIR%\payload.enc" ^
    -out "%OUTDIR%\payload.tar.gz" ^
    -K %KEY% ^
    -iv %IV% ^
    -nosalt 2>nul

if errorlevel 1 (
    REM Fehler ignorieren (trailing garbage von RSA-Signatur)
    echo Hinweis: Trailing garbage ignoriert (RSA-Signatur am Ende)
)

REM Prüfen ob die Ausgabe sinnvoll ist
python -c "
with open(r'%OUTDIR%\payload.tar.gz', 'rb') as f:
    magic = f.read(2)
if magic == b'\x1f\x8b':
    print('gzip Magic OK')
else:
    print(f'Fehler: Ungültiges gzip Magic: {magic.hex()}')
    exit(1)
"

if errorlevel 1 (
    echo Fehler: Entschluesselung fehlgeschlagen - falscher Key oder IV
    exit /b 1
)

echo Extrahiere Dateien...
tar -xzf "%OUTDIR%\payload.tar.gz" -C "%OUTDIR%" 2>nul

REM Temporäre Dateien aufräumen
del "%OUTDIR%\iv.txt" 2>nul
del "%OUTDIR%\payload.enc" 2>nul
del "%OUTDIR%\payload.tar.gz" 2>nul

echo.
echo Extrahierte Dateien:
dir "%OUTDIR%\*.bin" 2>nul

echo.
echo Fertig! Dateien in: %OUTDIR%
goto end

:usage
echo.
echo Nutzung: unpack_fw2.bat ^<fw2_datei^> ^<key_hex^> [ausgabe_ordner]
echo.
echo  fw2_datei:     Pfad zur .fw2 Firmware-Datei
echo  key_hex:       AES-256 Key als Hex-String (64 Zeichen)
echo  ausgabe_ordner: Ausgabe-Ordner (Standard: .\output)
echo.
echo Beispiel:
echo  unpack_fw2.bat BSB002_1978074000.fw2 5590016d6789ec5c6fb36d79b327b2c2541b62f893788831cca14ae5f1fe7ad2
echo.
echo Benoetigt: Python 3, openssl (beide in Windows 10/11 enthalten)
exit /b 1

:end
endlocal
