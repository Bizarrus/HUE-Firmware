# Signify/Philips Hue Bridge fw2 Firmware Unpacker
# Benoetigt: PowerShell 5.1+, openssl, tar (Windows 10/11 built-in)
#
# Nutzung:
#   .\unpack_fw2.ps1 ..\firmware.fw2 5590016d...
#   .\unpack_fw2.ps1 ..\firmware.fw2 5590016d... C:\output

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Fw2Path,

    [Parameter(Mandatory=$true, Position=1)]
    [string]$KeyHex,

    [Parameter(Mandatory=$false, Position=2)]
    [string]$OutDir = ".\output"
)

Write-Host ""
Write-Host "fw2 Unpacker - Signify/Philips Hue Bridge" -ForegroundColor White
Write-Host "==========================================" -ForegroundColor White
Write-Host ""

# Pfad absolut machen
$absPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Fw2Path)
if (-not (Test-Path $absPath)) {
    Write-Host "Fehler: Datei nicht gefunden: $absPath" -ForegroundColor Red
    exit 1
}
if ($KeyHex.Length -ne 64) {
    Write-Host "Fehler: Key muss 64 Hex-Zeichen haben (aktuell: $($KeyHex.Length))" -ForegroundColor Red
    exit 1
}

$absOut = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutDir)
if (-not (Test-Path $absOut)) {
    New-Item -ItemType Directory -Path $absOut | Out-Null
}

# fw2 lesen
Write-Host "Lese: $absPath" -ForegroundColor Cyan
$data = [System.IO.File]::ReadAllBytes($absPath)

# Magic pruefen
$magic = [System.Text.Encoding]::ASCII.GetString($data[0..5])
if ($magic -ne "BSB002") {
    Write-Host "Fehler: Ungueltige Magic: $magic" -ForegroundColor Red
    exit 1
}

# Metadaten
$numFiles = $data[7]
$totalSize = [uint32]$data[8] * 16777216 + [uint32]$data[9] * 65536 + [uint32]$data[10] * 256 + [uint32]$data[11]
$builder = [System.Text.Encoding]::ASCII.GetString($data[12..27]).TrimEnd([char]0)
$version = [System.Text.Encoding]::ASCII.GetString($data[40..51]).TrimEnd([char]0)
$ivBytes = $data[60..75]
$ivHex = ($ivBytes | ForEach-Object { $_.ToString("x2") }) -join ""

Write-Host "  Builder:  $builder"
Write-Host "  Version:  $version"
Write-Host "  Dateien:  $numFiles"
Write-Host "  Groesse:  $totalSize bytes"
Write-Host "  IV:       $ivHex"
Write-Host ""

# Payload speichern
$payloadPath = Join-Path $absOut "payload.enc"
$payload = $data[76..(76 + $totalSize - 1)]
[System.IO.File]::WriteAllBytes($payloadPath, $payload)
Write-Host "Payload: $($payload.Length) bytes gespeichert" -ForegroundColor Cyan

# Entschluesseln mit openssl
Write-Host "Entschluessele mit AES-256-CBC..." -ForegroundColor Cyan
$decryptedPath = Join-Path $absOut "payload.tar.gz"
$errFile = Join-Path $absOut "openssl.err"

& openssl enc -d -aes-256-cbc -in $payloadPath -out $decryptedPath -K $KeyHex -iv $ivHex -nosalt 2>$errFile
Write-Host "  (Trailing garbage / RSA-Signatur am Ende wird ignoriert)" -ForegroundColor Yellow

# gzip Magic pruefen
$gz = [System.IO.File]::ReadAllBytes($decryptedPath)
if ($gz[0] -eq 0x1f -and $gz[1] -eq 0x8b) {
    Write-Host "  gzip Magic OK (1f 8b)" -ForegroundColor Green
} else {
    Write-Host "  Fehler: Kein gzip - falscher Key oder IV?" -ForegroundColor Red
    Remove-Item $payloadPath, $decryptedPath, $errFile -ErrorAction SilentlyContinue
    exit 1
}

# Extrahieren
Write-Host "Extrahiere TAR..." -ForegroundColor Cyan
& tar -xzf $decryptedPath -C $absOut 2>$null

# Aufraeumen
Remove-Item $payloadPath -ErrorAction SilentlyContinue
Remove-Item $decryptedPath -ErrorAction SilentlyContinue
Remove-Item $errFile -ErrorAction SilentlyContinue

# Ergebnis
Write-Host ""
Write-Host "Fertig! Extrahierte Dateien:" -ForegroundColor Green
Get-ChildItem -Path $absOut -Filter "*.bin" | ForEach-Object {
    $mb = [math]::Round($_.Length / 1MB, 2)
    Write-Host "  $($_.Name)  ($mb MB)"
}

# kernel.bin validieren
$kernelPath = Join-Path $absOut "kernel.bin"
if (Test-Path $kernelPath) {
    $kb = [System.IO.File]::ReadAllBytes($kernelPath)
    if ($kb[0] -eq 0x27 -and $kb[1] -eq 0x05 -and $kb[2] -eq 0x19 -and $kb[3] -eq 0x56) {
        $kname = [System.Text.Encoding]::ASCII.GetString($kb[32..63]).TrimEnd([char]0)
        Write-Host "  Kernel: $kname" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Ausgabe-Ordner: $absOut"
