# Signify/Philips Hue Bridge fw2 Firmware Unpacker
# Benoetigt: PowerShell 5.1+, openssl, tar (Windows 10/11 built-in)
#
# Nutzung:
#   .\unpack_fw2.ps1 -Fw2Path "firmware.fw2" -KeyHex "5590016d..."
#   .\unpack_fw2.ps1 -Fw2Path "firmware.fw2" -KeyHex "5590016d..." -OutDir "C:\output"

param(
    [Parameter(Mandatory=$true)]
    [string]$Fw2Path,

    [Parameter(Mandatory=$true)]
    [string]$KeyHex,

    [Parameter(Mandatory=$false)]
    [string]$OutDir = ".\output"
)

Write-Host ""
Write-Host "fw2 Unpacker - Signify/Philips Hue Bridge" -ForegroundColor White
Write-Host "==========================================" -ForegroundColor White
Write-Host ""

# Pruefungen
if (-not (Test-Path $Fw2Path)) {
    Write-Host "Fehler: Datei nicht gefunden: $Fw2Path" -ForegroundColor Red
    exit 1
}
if ($KeyHex.Length -ne 64) {
    Write-Host "Fehler: Key muss 64 Hex-Zeichen haben" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}
$OutDir = (Resolve-Path $OutDir).Path

# fw2 lesen
Write-Host "Lese: $Fw2Path" -ForegroundColor Cyan
$data = [System.IO.File]::ReadAllBytes($Fw2Path)

# Magic pruefen
$magic = [System.Text.Encoding]::ASCII.GetString($data[0..5])
if ($magic -ne "BSB002") {
    Write-Host "Fehler: Ungueltige Magic: $magic" -ForegroundColor Red
    exit 1
}

# Metadaten
$numFiles = $data[7]
$totalSize = ($data[8] -shl 24) -bor ($data[9] -shl 16) -bor ($data[10] -shl 8) -bor $data[11]
$builder = [System.Text.Encoding]::ASCII.GetString($data[12..27]).TrimEnd([char]0)
$version = [System.Text.Encoding]::ASCII.GetString($data[40..51]).TrimEnd([char]0)

Write-Host "  Builder:  $builder"
Write-Host "  Version:  $version"
Write-Host "  Dateien:  $numFiles"
Write-Host "  Groesse:  $totalSize bytes"

# IV extrahieren (Bytes 60-75)
$ivBytes = $data[60..75]
$ivHex = ($ivBytes | ForEach-Object { $_.ToString("x2") }) -join ""
Write-Host "  IV:       $ivHex"
Write-Host ""

# Payload speichern
$payloadPath = Join-Path $OutDir "payload.enc"
$payload = $data[76..(76 + $totalSize - 1)]
[System.IO.File]::WriteAllBytes($payloadPath, $payload)
Write-Host "Payload: $($payload.Length) bytes" -ForegroundColor Cyan

# Entschluesseln
Write-Host "Entschluessele mit AES-256-CBC..." -ForegroundColor Cyan
$decryptedPath = Join-Path $OutDir "payload.tar.gz"

$opensslArgs = "enc -d -aes-256-cbc -in `"$payloadPath`" -out `"$decryptedPath`" -K $KeyHex -iv $ivHex -nosalt"
$proc = Start-Process -FilePath "openssl" -ArgumentList $opensslArgs -Wait -PassThru -RedirectStandardError "$OutDir\openssl.err" -NoNewWindow
Write-Host "  Trailing garbage (RSA-Signatur) wird ignoriert" -ForegroundColor Yellow

# gzip Magic pruefen
$gz = [System.IO.File]::ReadAllBytes($decryptedPath)
if ($gz[0] -eq 0x1f -and $gz[1] -eq 0x8b) {
    Write-Host "  gzip Magic OK" -ForegroundColor Green
} else {
    Write-Host "  Fehler: Kein gzip gefunden - falscher Key oder IV?" -ForegroundColor Red
    Remove-Item $payloadPath, $decryptedPath -ErrorAction SilentlyContinue
    exit 1
}

# Extrahieren
Write-Host "Extrahiere TAR-Archiv..." -ForegroundColor Cyan
$tarProc = Start-Process -FilePath "tar" -ArgumentList "-xzf `"$decryptedPath`" -C `"$OutDir`"" -Wait -PassThru -NoNewWindow

# Aufraeumen
Remove-Item $payloadPath -ErrorAction SilentlyContinue
Remove-Item $decryptedPath -ErrorAction SilentlyContinue
Remove-Item "$OutDir\openssl.err" -ErrorAction SilentlyContinue

# Ergebnis
Write-Host ""
Write-Host "Fertig! Extrahierte Dateien:" -ForegroundColor Green
Get-ChildItem -Path $OutDir -Filter "*.bin" | ForEach-Object {
    $mb = [math]::Round($_.Length / 1MB, 2)
    Write-Host "  $($_.Name) ($mb MB)"
}

# kernel.bin validieren
$kernelPath = Join-Path $OutDir "kernel.bin"
if (Test-Path $kernelPath) {
    $kb = [System.IO.File]::ReadAllBytes($kernelPath)
    if ($kb[0] -eq 0x27 -and $kb[1] -eq 0x05 -and $kb[2] -eq 0x19 -and $kb[3] -eq 0x56) {
        $kname = [System.Text.Encoding]::ASCII.GetString($kb[32..63]).TrimEnd([char]0)
        Write-Host "  Kernel: $kname" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Ausgabe-Ordner: $OutDir"
