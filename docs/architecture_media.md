# Media Encryption & Compression

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
key caching, and file-streaming orchestration, delegating crypto to the
pure modules in `lib/crypto/`. Heavy encrypt/decrypt runs on a 2-worker
`CryptoIsolatePool` to keep the UI thread responsive.

## Import Pipeline

1. User selects file(s) from gallery / documents / camera
2. `FileImportService` orchestrates: duplicate detection (`MediaScannerService`) → optional compression → streaming encryption (`CryptoIsolatePool`) → index update (`VaultService`)
3. `VaultedFile` metadata written to `vault_file_index`

## Compression

Opt-in per import, handled by `CompressionService`:

- **Images**: bicubic resize (max 4096×4096) via `flutter_bicubic_resize`, JPEG quality 95. PNGs pass through uncompressed.
- **Video**: `video_compress` is the primary path. An `ffmpeg` shell-out (`libx264`, CRF 18, AAC 192k) exists but only works where a system `ffmpeg` binary is present, and is effectively a no-op on stock Android.

## Encryption Modes

Selectable via the Encryption Settings screen:

### AES-256-GCM (default)
- 16-byte IV + 16-byte auth tag
- Magic bytes: `0x4C4B5232` (v2 header)
- Authenticated encryption; default for new media

### AES-256-CTR
- 16-byte IV, no auth tag
- Magic bytes: `0x4C4B5253`
- Opt-in for performance

```
┌──────────────────────────────────────────────────────────────┐
│                     Encryption Flow                          │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐                                            │
│  │ Source File  │                                            │
│  └──────┬───────┘                                            │
│         ↓                                                    │
│  ┌──────────────────────────────────────────────────────────┐│
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

## Key Derivation

### Master key wrapping (H1)

The vault master key is wrapped by an Argon2id-derived key-wrapping key
(KWK) from the user's credential:

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

Legacy vaults (raw master key) migrate transparently on next unlock: raw
key is read, wrapped, then deleted.

### Per-file key derivation (PBKDF2)

Each encrypted file derives a per-file key from the master key:

```
Master Key
         │
         ↓
┌──────────────────────────────┐
│  PBKDF2-HMAC-SHA256          │
│  • Iterations: 600,000       │
│  • Salt: 32-byte random      │
│  • Key length: 32 bytes      │
│  • Configurable iterations   │
└──────────────┬───────────────┘
               ↓
       Per-file 256-bit Key
```

- Each credential and file gets a unique 32-byte random salt, stored alongside the derived hash, preventing rainbow-table attacks across vaults.
- Pre-PBKDF2 vaults stored passwords as plain SHA-256; on unlock these are detected and auto-migrated to PBKDF2 (decoy credentials migrated with separate salted hashing).

## Re-Encryption (Algorithm Migration)

Changing the encryption algorithm (e.g., CTR → GCM) re-encrypts existing
vault files:

1. Select new algorithm in Encryption Settings.
2. Decrypt each vault file with the old algorithm.
3. Encrypt plaintext with the new algorithm.
4. Verify integrity (GCM auth tag).
5. Replace the vault file with the new-format file.
6. Update vault index metadata.
7. Secure-delete the temporary plaintext.

`ReEncryptNotifier` tracks per-file progress and reports success/failure to
the UI. On any failure the operation aborts and original files are
untouched.

### Security guarantees
- Plaintext intermediates go to app-private temp (`getApplicationDocumentsDirectory()/.locker_temp/`), never system temp, and are `secureDelete`d on completion or failure.
- Small files use the in-memory GCM path (no plaintext on disk).
- On cancellation or failure, original vault files are untouched.
- GCM auth-tag validation catches corruption during migration.
