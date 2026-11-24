# Embedded PocketBase Local Store

## Status

**Implemented (P0–P4); on-device validation pending.** PocketBase runs as an
Android sidecar and stores vault metadata locally. The legacy
`FlutterSecureStorage` JSON index remains as a fallback. P5 polish
(foreground service, further size work) is deferred.

The remaining release gate is real-hardware confirmation: unlock a debug build
after `make pb` and confirm `[PB] sidecar up: pid=… port=…` in logcat, then run
the checks in [PocketBase testing](pb_testing.md) and
[Stable release checklist](stable_release_checklist.md). Do not treat
build-only checks as hardware acceptance.

## Why

The vault used a flat JSON metadata index in secure storage. PocketBase gives
it a structured, queryable, relational local store without introducing a hosted
server. Media blobs stay as encrypted files on disk; PocketBase indexes and
relates them. WebDAV remains the only remote sync transport
([local_server_sync.md](local_server_sync.md)).

Non-goals: local-to-remote PocketBase replication, multi-user operation, iOS,
media blobs inside PocketBase, and the PocketBase admin UI.

## Architecture

```
UI ── Riverpod ── VaultService
                     │
                     ▼
               LocalStore
        ┌────────────┴────────────┐
        ▼                         ▼
  PocketBaseStore          FlutterSecureStorage
  (preferred)              JSON index (legacy fallback,
                           migration source)
        │
        │ 127.0.0.1:<ephemeral>, X-Locker-Token
        ▼
  libpocketbase.so (Go wrapper in jniLibs)
  main() → PocketBase core → JS migrations → HTTP
        │
        ▼
  SQLite (modernc, pure Go) in app-private data
  vault_files / albums / tags / folders
```

`PocketBaseStore` implements the same `LocalStore` surface as `VaultStore`.
`VaultService` routes non-decoy loads, saves, and wipes through PocketBase and
falls back to the legacy store on failure. The sidecar starts after unlock
(never for the decoy vault), not at app launch, and stops when the activity
detaches. `VaultSettings.pbEnabled` defaults to true.

### Device layout

```
<app-data>/pocketbase/
  data.db                        SQLite: encrypted columns + index fields
  data.db-wal
  migrations/                    JS migrations extracted from the binary at boot
  sidecar.pid                    orphan sweep marker
<app-data>/vault/                unchanged encrypted media blobs
  ab/cd/<hash>.enc
android/app/src/main/jniLibs/arm64-v8a/libpocketbase.so
```

`libpocketbase.so` is a Go executable renamed as a native library. Android
must extract it to disk before `execve`, so Gradle sets
`jniLibs.useLegacyPackaging = true`. The old
`android:extractNativeLibs="true"` manifest attribute is not used on the
current AGP toolchain (AGP 9 removed it).

### Bridge

The sidecar is a subprocess reached over loopback HTTP. The Go binary is a thin
wrapper around `pocketbase.NewWithConfig`; schema lives in versioned JS
migrations embedded with `go:embed`. No business logic lives in Go. The
rejected alternatives were FFI (no data-path benefit) and a pure-Dart rewrite
(no longer PocketBase); `sqflite` remains the documented fallback if the
sidecar proves unworkable on device.

## Security model

| Asset | Where | Exposure if the device is compromised |
|---|---|---|
| Media payloads | On-disk files | Encryption is opt-in: hidden-only files are plaintext. PocketBase never touches payload bytes. |
| Names, tags, albums, folders | PocketBase SQLite, app-encrypted columns | Ciphertext envelopes; confidentiality depends on the vault key. |
| `modified_at`, `deleted`, `blob_ref` | PocketBase SQLite, plaintext | Low risk: timestamps, tombstones, content hashes. |
| PocketBase database | App-private storage | Readable on a rooted device; no plaintext secrets. |
| Local HTTP API | Loopback only | Ephemeral random port plus a 256-bit token held in Dart memory. |
| Master key | Memory after unlock; Argon2id-wrapped on disk | Required to decrypt columns. |

Hard rules:

- **Secret fields are encrypted before insert.** PocketBase stores AES-GCM
  envelopes and never receives the master key.
- **Loopback only.** Bind `127.0.0.1` on an ephemeral port; never `0.0.0.0`
  and never a fixed port.
- **Encrypt when in doubt.** Only non-secret fields (`modified_at`,
  `deleted`, `blob_ref`) are plaintext.
- **The vault master key remains the single root of confidentiality** for both
  blobs and metadata.
- **The decoy vault never starts the sidecar.**

This protects metadata at rest; it does not claim that user-directed exports or
transfers cannot contain plaintext.

## Data model

Four collections, each with encrypted secret columns and plaintext index
columns:

- `vault_files` — `id`, `blob_ref`, `cipher_meta` (tags, albumIds, folderId,
  originalName, dates), `modified_at`, `deleted`.
- `albums` — `id`, `cipher_meta` (name, cover, order), `modified_at`,
  `deleted`.
- `tags` — `id`, `cipher_name`, `modified_at`, `deleted`.
- `folders` — `id`, `cipher_meta` (name, parentId), `modified_at`, `deleted`.

Encrypted columns use one `[16-byte IV][ciphertext+tag]` AES-GCM envelope per
field, via `AesGcmCipher` and the vault master key. Migration from the legacy
JSON indexes runs once after unlock, guarded by `pb_legacy_index_migrated`;
the legacy index is retained, not deleted.

## Build and verification

```bash
make pb          # cross-compile arm64 → jniLibs (version-stamped)
make pb-linux    # host sidecar for local checks
make pb-types    # vendor PocketBase JS editor types
```

PocketBase is pinned at `v0.40.4` in `pocketbase/go.mod`; builds use
`CGO_ENABLED=0` with the pure-Go `modernc.org/sqlite` backend. Release
artifacts are checked by `python3 scripts/pocketbase_artifact.py verify …`.

Automated coverage includes the stdout handshake parser, ciphertext-at-rest
round trips, DAO/store reconcile behavior, migration, and the PB-to-sync wire
path. See [pb_testing.md](pb_testing.md) for host, debug-build, and on-device
procedures.

## Remaining work

1. Confirm the sidecar on real arm64 hardware (unlock, health, all four
   collections, lock/restart lifecycle, no silent legacy fallback).
2. Decide whether to keep the 32 MB arm64 binary as-is or shrink it (drop JS
   migrations or add compression) before stable.
3. P5 polish only if needed: foreground service, recovery UI, size work.

Open product decisions: arm64 remains the only ABI for v1; remote replication
is out of scope; WebDAV stays the remote path.
