#!/bin/bash
# Signify/Philips Hue Bridge fw2 Firmware Unpacker
# Discovered through reverse engineering of BSB002 (Hue Bridge 2.1)
#
# fw2 Format:
#   Offset  0-5:   Magic "BSB002" (6 bytes)
#   Offset  6:     Format version (1 byte)
#   Offset  7:     Number of files (1 byte)
#   Offset  8-11:  Total size (4 bytes, big-endian)
#   Offset 12-27:  Builder string (16 bytes, null-padded)
#   Offset 28-33:  Unknown (6 bytes)
#   --- Section Header (26 bytes, ab Offset 34) ---
#   Offset 34-35:  Section type + options (2 bytes)
#   Offset 36-39:  Unknown (4 bytes)
#   Offset 40-51:  Version string (12 bytes, null-padded)
#   Offset 52-59:  Unknown/padding (8 bytes)
#   Offset 60-75:  AES-256-CBC IV (16 bytes)
#   --- Encrypted Payload (ab Offset 76) ---
#   Payload:       gzip-compressed TAR archive containing kernel.bin + root.bin
#   End:           RSA signature (451 bytes PEM public key)
#
# Encryption: AES-256-CBC
# Key: /home/swupdate/certs/enc.k (32 bytes raw, on the bridge)
# IV:  Bytes 60-75 of the fw2 file

set -e

usage() {
    echo "Usage: $0 <fw2_file> <key_hex> [output_dir]"
    echo ""
    echo "  fw2_file:   Path to .fw2 firmware file"
    echo "  key_hex:    AES-256 key as hex string (64 hex chars)"
    echo "  output_dir: Output directory (default: current dir)"
    echo ""
    echo "Example:"
    echo "  $0 BSB002_1978074000.fw2 5590016d6789ec5c6fb36d79b327b2c2541b62f893788831cca14ae5f1fe7ad2"
    exit 1
}

if [ $# -lt 2 ]; then
    usage
fi

FW2="$1"
KEY="$2"
OUTDIR="${3:-.}"

if [ ! -f "$FW2" ]; then
    echo "Error: File not found: $FW2"
    exit 1
fi

if [ ${#KEY} -ne 64 ]; then
    echo "Error: Key must be 64 hex characters (32 bytes)"
    exit 1
fi

mkdir -p "$OUTDIR"

# Validate magic
MAGIC=$(dd if="$FW2" bs=1 count=6 2>/dev/null | xxd -p)
if [ "$MAGIC" != "425342303032" ]; then
    echo "Error: Invalid magic (expected BSB002, got $(echo $MAGIC | xxd -r -p))"
    exit 1
fi

# Read metadata
FILES=$(dd if="$FW2" bs=1 skip=7 count=1 2>/dev/null | xxd -p)
VERSION=$(dd if="$FW2" bs=1 skip=40 count=12 2>/dev/null | strings | head -1)
BUILDER=$(dd if="$FW2" bs=1 skip=12 count=16 2>/dev/null | strings | head -1)

echo "fw2 Info:"
echo "  Builder: $BUILDER"
echo "  Version: $VERSION"
echo "  Files:   $((16#$FILES))"

# Extract IV (bytes 60-75)
IV=$(dd if="$FW2" bs=1 skip=60 count=16 2>/dev/null | xxd -p | tr -d '\n')
echo "  IV:      $IV"

# Payload size from header (bytes 8-11, big-endian) minus headers
TOTAL_SIZE=$(dd if="$FW2" bs=1 skip=8 count=4 2>/dev/null | xxd -p | tr -d '\n')
PAYLOAD_SIZE=$((16#${TOTAL_SIZE}))
echo "  Payload: $PAYLOAD_SIZE bytes"

echo ""
echo "Decrypting and extracting..."

# Extract and decrypt payload, then untar
tail -c +77 "$FW2" | head -c $PAYLOAD_SIZE | \
    openssl enc -d -aes-256-cbc \
        -K "$KEY" \
        -iv "$IV" \
        -nosalt \
        2>/dev/null | \
    tar -xzf - -C "$OUTDIR" 2>/dev/null || true

# List extracted files
echo "Extracted files:"
ls -lh "$OUTDIR"/*.bin 2>/dev/null || echo "No .bin files found"

echo ""
echo "Done! Files extracted to: $OUTDIR"
