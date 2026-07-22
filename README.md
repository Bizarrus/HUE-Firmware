# Hue `.fw2` Format

## Format
### Overview

```
+------------------+
|   fw2 Header     |  34 Bytes
+------------------+
|  Section Header  |  26 Bytes
+------------------+
|   AES-256 IV     |  16 Bytes  ← Offset 60
+------------------+
|  Encrypted       |
|  Payload         |  N Bytes   ← Offset 76
|  (gzip TAR)      |
+------------------+
|  RSA Signature   |  451 Bytes (PEM Public Key)
+------------------+
```

### Header (34 Bytes)

| Offset | Length | Content |
|---|---|---|
| 0 | 6 | Magic: `BSB002` |
| 6 | 1 | Format-Version |
| 7 | 1 | File Count |
| 8 | 4 | Total Size (Big-Endian uint32) |
| 12 | 16 | Builder-String (null-padded) |
| 28 | 6 | Unknown |

### Section Header (26 Bytes, ab Offset 34)

| Offset | Length | Content |
|---|---|---|
| 34 | 2 | Section-Typ + Options |
| 36 | 4 | Unknown |
| 40 | 12 | Versions-String (null-padded) |
| 52 | 8 | Padding/Unbekannt |

### IV + Payload

| Offset | Length | Content |
|---|---|---|
| 60 | 16 | AES-256-CBC IV |
| 76 | N | Encrypted Payload |

### Cryption
- **Algorithm:** AES-256-CBC
- **Library:** mbedTLS
- **Key:** 32-Byte raw bytes from `/home/swupdate/certs/enc.k`
- **IV:** Bytes 60–75 from the `.fw2`-File

### Payload-Content
After decryption the Payload is a **gzip'ped TAR-Archiv** with:
- `kernel.bin` — U-Boot uImage (MIPS, lzma)
- `root.bin` — UBI Image (squashfs RootFS)

---

## fw2 entschlüsseln (Kommandozeile)

```bash
# Extract IV
IV=$(dd if=firmware.fw2 bs=1 skip=60 count=16 2>/dev/null | xxd -p | tr -d '\n')

# Extraxt Payload & decrypt
tail -c +77 firmware.fw2 | head -c <PAYLOAD_SIZE> | \
  openssl enc -d -aes-256-cbc \
    -K <KEY_HEX> \
    -iv $IV \
    -nosalt 2>/dev/null | \
  tar -xzf - 2>/dev/null
```

> `PAYLOAD_SIZE` = Bytes 8–11 from `.fw2` (Big-Endian uint32)

---

## AES-Key from one of the bridge
```
5590016d6789ec5c6fb36d79b327b2c2541b62f893788831cca14ae5f1fe7ad2
```

> The key is from `/home/swupdate/certs/enc.k` (32 Bytes raw, hex-output)
---
