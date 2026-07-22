# Signify/Philips Hue Bridge fw2 Firmware Unpacker
# Requires: PowerShell 5.1+ (Windows 10/11 built-in)
#           openssl.exe (Windows 10/11 built-in)
#           tar.exe (Windows 10/11 built-in)
#
# fw2 Format:
#   Offset  0-5:   Magic "BSB002"
#   Offset  6:     Format version
#   Offset  7:     Number of files
#   Offset  8-11:  Total size (big-endian)
#   Offset 12-27:  Builder string (null-padded)
#   Offset 34-59:  Section header
#   Offset 60-75:  AES-256-CBC IV (16 bytes)
#   Offset 76+:    gzip-compressed TAR (kernel.bin + root.bin)
#
# Nutzung:
#   .\unpack_fw2.ps1 -Fw2Path "BSB002_1978074000.fw2" -KeyHex "5590016d..."
#   .\unpack_fw2.ps1 -Fw2Path "BSB002_1978074000.fw2" -KeyHex "5590016d..." -OutDir "C:\output"

param(
    [Parameter(Mandatory=$true)]
    [string]$Fw2Path,

    [Parameter(Mandatory=$true)]
    [ValidateLength(64,64)]
    [string]$KeyHex,

    [Parameter(Mandatory=$false)]
    [string]$OutDir = ".\output"
)

# Farben für Output
function Write-Info  { param($msg) Write-Host $msg -ForegroundColor Cyan }
function Write-OK    { param($msg) Write-Host $msg -ForegroundColor Green }
function Write-Fail  { param($msg) Write-Host $msg -ForegroundColor Red }
function Write-Warn  { param($msg) Write-Host $msg -ForegroundColor Yellow }

Write-Host ""
Write-Host "fw2 Unpacker - Signify/Philips Hue Bridge" -ForegroundColor White
Write-Host "==========================================" -ForegroundColor White
Write-Host ""

# Datei prüfen
if (-not (Test-Path $Fw2Path)) {
    Write-Fail "Fehler: Datei nicht gefunden: $Fw2Path"
    exit 1
}

# Ausgabe-Ordner erstellen
if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}
$OutDir = Resolve-Path $OutDir

# fw2 Datei lesen
Write-Info "Lese fw2-Datei: $Fw2Path"
$data = [System.IO.File]::ReadAllBytes($Fw2Path)

# Magic prüfen
$magic = [System.Text.Encoding]::ASCII.GetString($data[0..5])
if ($magic -ne "BSB002") {
    Write-Fail "Fehler: Ungültiges Magic: '$magic' (erwartet: BSB002)"
    exit 1
}

# Metadaten lesen
$numFiles = $data[7]
# Total size: big-endian uint32 ab Offset 8
$totalSize = ($data[8] -shl 24) -bor ($data[9] -shl 16) -bor ($data[10] -shl 8) -bor $data[11]
$builder = [System.Text.Encoding]::ASCII.GetString($data[12..27]).TrimEnd([char]0)
$version = [System.Text.Encoding]::ASCII.GetString($data[40..51]).TrimEnd([char]0)

Write-Info "fw2 Informationen:"
Write-Host "  Builder:  $builder"
Write-Host "  Version:  $version"
Write-Host "  Dateien:  $numFiles"
Write-Host "  Groesse:  $totalSize bytes"

# IV extrahieren (Bytes 60-75)
$ivBytes = $data[60..75]
$ivHex = ($ivBytes | ForEach-Object { $_.ToString("x2") }) -join ""
Write-Host "  IV:       $ivHex"
Write-Host ""

# Payload extrahieren (ab Offset 76)
Write-Info "Extrahiere verschlüsselte Payload..."
$payloadPath = Join-Path $OutDir "payload.enc"
$payload = $data[76..(76 + $totalSize - 1)]
[System.IO.File]::WriteAllBytes($payloadPath, $payload)
Write-Host "  Payload:  $($payload.Length) bytes -> $payloadPath"

# Entschlüsseln mit openssl
Write-Info "Entschlüssele mit AES-256-CBC..."
$decryptedPath = Join-Path $OutDir "payload.tar.gz"

$opensslArgs = @(
    "enc", "-d", "-aes-256-cbc",
    "-in", $payloadPath,
    "-out", $decryptedPath,
    "-K", $KeyHex,
    "-iv", $ivHex,
    "-nosalt"
)

$result = & openssl @opensslArgs 2>&1
if ($LASTEXITCODE -ne 0) {
    # Trailing garbage von RSA-Signatur wird ignoriert
    Write-Warn "  Hinweis: Trailing garbage ignoriert (RSA-Signatur am Ende - normal)"
}

# gzip Magic prüfen
$decBytes = [System.IO.File]::ReadAllBytes($decryptedPath)
if ($decBytes[0] -eq 0x1f -and $decBytes[1] -eq 0x8b) {
    Write-OK "  gzip Magic OK (0x1f 0x8b)"
} else {
    Write-Fail "  Fehler: Ungültiges gzip Magic: $($decBytes[0].ToString('x2')) $($decBytes[1].ToString('x2'))"
    Write-Fail "  Falscher Key oder IV!"
    Remove-Item $payloadPath -ErrorAction SilentlyContinue
    Remove-Item $decryptedPath -ErrorAction SilentlyContinue
    exit 1
}

# TAR extrahieren
Write-Info "Extrahiere TAR-Archiv..."
$tarResult = & tar -xzf $decryptedPath -C $OutDir 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Warn "  Hinweis: tar Warnung (trailing garbage ignoriert)"
}

# Temporäre Dateien aufräumen
Remove-Item $payloadPath -ErrorAction SilentlyContinue
Remove-Item $decryptedPath -ErrorAction SilentlyContinue

# Ergebnis anzeigen
Write-Host ""
Write-OK "Fertig! Extrahierte Dateien:"
Get-ChildItem -Path $OutDir -Filter "*.bin" | ForEach-Object {
    $size = "{0:N0}" -f $_.Length
    Write-Host "  $($_.Name) ($size bytes)"
}

# kernel.bin validieren
$kernelPath = Join-Path $OutDir "kernel.bin"
if (Test-Path $kernelPath) {
    $kernelBytes = [System.IO.File]::ReadAllBytes($kernelPath)
    # U-Boot Magic: 0x27051956
    if ($kernelBytes[0] -eq 0x27 -and $kernelBytes[1] -eq 0x05 -and
        $kernelBytes[2] -eq 0x19 -and $kernelBytes[3] -eq 0x56) {
        Write-OK "  kernel.bin: gültiges U-Boot uImage ✓"
        # Kernel-Name aus Header lesen (Offset 32, 32 bytes)
        $kernelName = [System.Text.Encoding]::ASCII.GetString($kernelBytes[32..63]).TrimEnd([char]0)
        Write-Host "  Kernel:     $kernelName"
    } else {
        Write-Warn "  kernel.bin: Unbekanntes Format"
    }
}

Write-Host ""
Write-Host "Ausgabe-Ordner: $OutDir" -ForegroundColor White
