# Media encryption and compression

This is the short version of how files get into the vault, get compressed, and
get encrypted.

## How it fits together

```
UI (gallery, explorer, viewer, note/password editors)
        │
        ▼
Riverpod providers (VaultNotifier, AlbumsNotifier, FoldersNotifier, …)
        │
        ▼
Service layer
  VaultService ── FileImportService ── CompressionService
                        │
                 EncryptionService (facade)
                        │
              CryptoIsolatePool (2 workers)
                        │
          lib/crypto/ (pure crypto code)
          AesGcmCipher · AesCtrCipher
          KeyDerivation · HeaderCodec · KeyWrap
```

`EncryptionService` is a facade. It handles key storage in secure storage, key
caching, and file-streaming orchestration, and hands the actual crypto to the
pure modules in `lib/crypto/`. Heavy encrypt/decrypt work runs on a two-worker
`CryptoIsolatePool` so the UI doesn't freeze.

## Import pipeline

1. You pick files from the gallery, documents, or camera.
2. `FileImportService` runs duplicate detection (`MediaScannerService`), optional
   compression, streaming encryption on the isolate pool, then updates the index
   through `VaultService`.
3. `VaultedFile` metadata is written through `LocalStore` — PocketBase first,
   with the legacy secure-storage index as fallback.

## Compression

Compression is opt-in per import and handled by `CompressionService`.

- **Images:** bicubic resize (max 4096×4096) using `flutter_bicubic_resize`,
  JPEG quality 95. PNGs pass through unchanged.
- **Video:** `video_compress` is the main path. There's also an `ffmpeg`
  shell-out (`libx264`, CRF 18, AAC 192k), but it only works when a system
  `ffmpeg` binary exists, which effectively means it does nothing on stock
  Android.

## Encryption modes

You choose the mode in Encryption Settings.

### AES-256-GCM (default)

- 16-byte IV + 16-byte auth tag
- Magic bytes: `0x4C4B5232` (v2 header)
- Authenticated encryption, and the default for new media

### AES-256-CTR

- 16-byte IV, no auth tag
- Magic bytes: `0x4C4B5253`
- Opt-in, mainly for performance

Encrypted files are laid out as:

```
[magic][IV][ciphertext][auth tag (GCM only)]
```

Files are stream-encrypted in 1 MB chunks.

## Key derivation

### Wrapping the master key

The vault master key is wrapped by a key-wrapping key (KWK) derived from your
PIN or password:

```
PIN/password
    → Argon2id (3 iterations, 2^14 KiB memory, 32-byte random salt, 32-byte key)
    → 256-bit KWK
    → AES-256-GCM KeyWrap around the master key
```

Legacy vaults that stored a raw master key migrate on the next unlock: Latch
reads the raw key, wraps it, then deletes the raw copy.

### Per-file keys

Each encrypted file gets its own key derived from the master key:

```
master key
    → PBKDF2-HMAC-SHA256 (600,000 iterations, 32-byte random salt, 32-byte key)
    → per-file 256-bit key
```

Every credential and file gets its own 32-byte random salt, stored next to the
derived hash, so rainbow tables don't help across vaults. Pre-PBKDF2 vaults
stored passwords as plain SHA-256; those are detected on unlock and migrated
automatically (decoy credentials get separate salted hashing too).

## Re-encryption

Switching algorithms (say CTR → GCM) re-encrypts existing vault files:

1. Pick the new algorithm in Encryption Settings.
2. Decrypt each vault file with the old algorithm.
3. Encrypt the plaintext with the new one.
4. Verify integrity (GCM auth tag).
5. Replace the vault file with the new-format file.
6. Update the vault index metadata.
7. Secure-delete the temporary plaintext.

`ReEncryptNotifier` tracks per-file progress and reports success/failure to the
UI. If anything fails, the operation aborts and the original files are left
alone.

## What this protects

- Plaintext intermediates go to app-private temp
  (`getApplicationDocumentsDirectory()/.locker_temp/`), never system temp, and
  are `secureDelete`d on completion or failure.
- Small files use the in-memory GCM path, so no plaintext touches disk.
- On cancellation or failure, original vault files are untouched.
- GCM auth-tag validation catches corruption during migration.
