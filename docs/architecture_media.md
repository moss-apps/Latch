# Architecture: Media Encryption & Compression

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Interface                          │
│   Gallery / Explorer / Viewer / Note & Password editors         │
└──────────────────────────────┬──────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────┐
│                     Riverpod Providers                          │
│   VaultNotifier · AlbumsNotifier · FoldersNotifier · etc.       │
└──────────────────────────────┬──────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────┐
│                        Service Layer                            │
│  VaultService ── FileImportService ── CompressionService        │
│       │                              │            │             │
│       │                   EncryptionService (facade)            │
│       │                              │            │             │
│       ▼                              ▼            ▼             │
│  CryptoIsolatePool            lib/crypto/ (pure)                │
│  (2 background workers)       AesGcmCipher · AesCtrCipher       │
│                               KeyDerivation · HeaderCodec       │
│                               KeyWrap                           │
└─────────────────────────────────────────────────────────────────┘
```

`EncryptionService` is a facade: it owns key storage (secure storage I/O),
key caching, and file-streaming orchestration, and delegates the actual
crypto to the pure, independently-tested modules in `lib/crypto/`.
Heavy encrypt/decrypt runs on a 2-worker `CryptoIsolatePool` so the UI
thread stays responsive.

## Import Pipeline

```
1. User selects file(s) from gallery / documents / camera
        ↓
2. FileImportService orchestrates:
   ├─ Duplicate detection (MediaScannerService)
   ├─ Compression (optional, see below)
   ├─ Encryption (streaming, via CryptoIsolatePool)
   └─ Index update (VaultService)
        ↓
3. VaultedFile metadata written to vault_file_index
```

## Compression

Compression is opt-in per import and handled by `CompressionService`:

- **Images** — bicubic resize (max 4096×4096) via `flutter_bicubic_resize`,
  JPEG quality 95. PNGs passed through uncompressed.
- **Video** — shells out to an external `ffmpeg` binary (`libx264`, CRF 18,
  fast preset, AAC 192k). **Note:** no FFmpeg Flutter package is bundled;
  this path only works on devices with a system `ffmpeg` binary and is
  effectively a no-op on stock Android. `video_compress` is used as the
  primary video compression path elsewhere.

> The earlier revision of this document described an `ImprovedCompressionService`
> with an isolate-managed FFmpeg pipeline, progress parsing, and a rollback
> stack. That design was never implemented and has been removed from this
> document.

---

## Encryption Modes

Latch supports two AES-256 encryption modes, selectable via the Encryption
Settings screen:

### AES-256-GCM (Galois/Counter Mode) — default
- **Speed**: Slightly slower due to authentication overhead
- **Integrity**: Authenticated encryption with a 16-byte auth tag
- **Magic bytes**: `0x4C4B5232` (v2 header)
- **Use case**: Default for new media; recommended for security-sensitive vaults

### AES-256-CTR (Counter Mode)
- **Speed**: Fast, no integrity verification
- **Parallelizable**: Encryption and decryption can be parallelized
- **Magic bytes**: `0x4C4B5253`
- **Use case**: Opt-in for performance

```
┌──────────────────────────────────────────────────────────────┐
│                     Encryption Flow                          │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐                                            │
│  │ Source File  │                                            │
│  └──────┬───────┘                                            │
│         ↓                                                    │
│  ┌──────────────────────────────────────────────────┐       │
│  │              Algorithm Selection                  │       │
│  │  ┌─────────────────┐   ┌─────────────────────┐   │       │
│  │  │   AES-256-CTR   │   │    AES-256-GCM      │   │       │
│  │  │  16-byte IV     │   │   16-byte IV        │   │       │
│  │  │  No auth tag    │   │   16-byte auth tag  │   │       │
│  │  └────────┬────────┘   └──────────┬──────────┘   │       │
│  └───────────┼───────────────────────┼──────────────┘       │
│              ↓                       ↓                       │
│  ┌─────────────────┐   ┌─────────────────────────┐         │
│  │ Stream encrypt  │   │ Encrypt + auth tag      │         │
│  │ in 1MB chunks   │   │ appended to each file   │         │
│  └────────┬────────┘   └────────────┬────────────┘         │
│           ↓                          ↓                      │
│  ┌────────────────────────────────────────────────┐         │
│  │              Vault Storage                     │         │
│  │  [magic][IV][ciphertext][auth tag (GCM)]      │         │
│  └────────────────────────────────────────────────┘         │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## Key Derivation

### Master key wrapping (H1)

The vault master key is wrapped by an Argon2id-derived key-wrapping key (KWK)
from the user's credential:

```
User Password/PIN
        │
        ↓
┌──────────────────────────────┐
│  Argon2id                    │
│  • iterations: 3             │
│  • memory: 2^14 KiB          │
│  • salt: 32-byte random      │
│  • key length: 32 bytes      │
└──────────────┬───────────────┘
               ↓
        256-bit Key-Wrapping Key (KWK)
               │
               ↓
┌──────────────────────────────┐
│  AES-256-GCM (KeyWrap)       │
│  wraps the master key        │
└──────────────────────────────┘
```

Legacy vaults (raw master key) are transparently migrated on next unlock:
the raw key is read, wrapped, then deleted.

### Per-file key derivation (PBKDF2)

Each encrypted file derives a per-file key from the master key via PBKDF2:

```
Master Key
        │
        ↓
┌──────────────────────────────┐
│  PBKDF2-HMAC-SHA256          │
│  • Iteration count: 600,000  │
│  • Salt: 32-byte random      │
│  • Key length: 32 bytes      │
│  • Configurable iterations   │
└──────────────┬───────────────┘
               ↓
        Per-file 256-bit Key
```

### Salt Generation
- Each credential and file gets a unique 32-byte random salt
- Salt is stored alongside the derived hash for verification
- Prevents rainbow table attacks across vaults

### Legacy Migration
- Pre-PBKDF2 vaults stored passwords using plain SHA-256
- On unlock, legacy hashes are detected and automatically migrated to PBKDF2
- Decoy credentials migrated with separate salted hashing

---

## Re-Encryption (Algorithm Migration)

When the user changes the encryption algorithm (e.g., CTR → GCM), existing
vault files are re-encrypted:

```
┌──────────────────────────────────────────────────────────────┐
│                  Re-Encryption Flow                          │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Select new algorithm in Encryption Settings              │
│              ↓                                               │
│  2. Decrypt each vault file with old algorithm               │
│              ↓                                               │
│  3. Encrypt plaintext with new algorithm                     │
│              ↓                                               │
│  4. Verify integrity (GCM auth tag validation)              │
│              ↓                                               │
│  5. Replace vault file with new-format file                  │
│              ↓                                               │
│  6. Update vault index metadata                              │
│              ↓                                               │
│  7. Secure-delete temporary plaintext                        │
│                                                              │
│  Rollback: If any file fails, operation is aborted           │
│  and original files are preserved.                           │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### ReEncryptNotifier
- Manages re-encryption state across all vault files
- Provides progress tracking per file
- Reports success, failure, and progress to UI

### Security Guarantees
- Plaintext intermediates are written to app-private temp
  (`getApplicationDocumentsDirectory()/.locker_temp/`), not system temp,
  and `secureDelete`d on completion or failure
- Small files use the in-memory GCM path (no plaintext on disk at all)
- On cancellation or failure, the original vault files are untouched
- GCM auth tag validation catches corruption during migration
