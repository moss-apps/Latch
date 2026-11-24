# Embedded PocketBase local store

## Where it stands

PocketBase runs as an Android sidecar and stores vault metadata locally. It's
built and wired up, but it hasn't been signed off on a real phone yet. The old
`FlutterSecureStorage` JSON index is still there as a fallback. Foreground-service
polish and more size work are deferred; they aren't blocking anything right now.

The last release gate is simple: unlock a debug build after `make pb`, confirm
`[PB] sidecar up: pid=… port=…` in logcat, then run the checks in
[PocketBase testing](pb_testing.md) and the
[stable release checklist](stable_release_checklist.md). A build passing is not
the same as a phone passing.

## Why it's here

The vault used to keep all metadata in one flat JSON index in secure storage.
PocketBase gives it a real local database with queries and relations, without
adding a server or an account. Media bytes stay as encrypted files on disk;
PocketBase only indexes them and connects the rows. WebDAV is still the only
remote sync path ([local_server_sync.md](local_server_sync.md)).

It does not try to be a remote PocketBase, a multi-user service, an iOS thing, a
media store, or a replacement for the PocketBase admin UI.

## How it fits

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
`VaultService` sends non-decoy loads, saves, and wipes through PocketBase, and
falls back to the legacy store if that fails. The sidecar starts after unlock,
never for the decoy vault, and stops when the activity detaches.
`VaultSettings.pbEnabled` defaults to true.

### What lands on the device

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

`libpocketbase.so` is really a Go executable renamed as a native library. Android
has to extract it to disk before it can run it, so Gradle sets
`jniLibs.useLegacyPackaging = true`. The old
`android:extractNativeLibs="true"` manifest attribute isn't used on the current
AGP toolchain; AGP 9 removed it.

### The bridge

The sidecar is a subprocess reached over loopback HTTP. The Go binary is a thin
wrapper around `pocketbase.NewWithConfig`, and the schema lives in versioned JS
migrations embedded with `go:embed`. There's no business logic in Go. We looked
at FFI (no benefit for the data path) and a pure-Dart rewrite (then it isn't
PocketBase). `sqflite` is still the documented fallback if the sidecar turns out
to be unworkable on device.

## Security model

| Asset | Where it lives | What happens if the device is compromised |
|---|---|---|
| Media payloads | On-disk files | Encryption is opt-in, so hidden-only files are plaintext. PocketBase never touches payload bytes. |
| Names, tags, albums, folders | PocketBase SQLite, app-encrypted columns | Ciphertext envelopes; confidentiality depends on the vault key. |
| `modified_at`, `deleted`, `blob_ref` | PocketBase SQLite, plaintext | Low risk: timestamps, tombstones, and content hashes. |
| PocketBase database | App-private storage | Readable on a rooted device, but there are no plaintext secrets in it. |
| Local HTTP API | Loopback only | Ephemeral random port plus a 256-bit token held in Dart memory. |
| Master key | Memory after unlock; Argon2id-wrapped on disk | Needed to decrypt the columns. |

What keeps this safe:

- **Encrypt secret fields before insert.** PocketBase stores AES-GCM envelopes
  and never gets the master key.
- **Loopback only.** Bind `127.0.0.1` on an ephemeral port. Never `0.0.0.0`,
  never a fixed port.
- **Encrypt when in doubt.** Only non-secret fields (`modified_at`, `deleted`,
  `blob_ref`) are plaintext.
- **The vault master key stays the root of confidentiality** for both blobs and
  metadata.
- **The decoy vault never starts the sidecar.**

This protects metadata at rest. It doesn't mean user-started exports or
transfers can't contain plaintext.

## Data model

Four collections, each with encrypted secret columns and plaintext index
columns:

- `vault_files`: `id`, `blob_ref`, `cipher_meta` (tags, albumIds, folderId,
  originalName, dates), `modified_at`, `deleted`.
- `albums`: `id`, `cipher_meta` (name, cover, order), `modified_at`, `deleted`.
- `tags`: `id`, `cipher_name`, `modified_at`, `deleted`.
- `folders`: `id`, `cipher_meta` (name, parentId), `modified_at`, `deleted`.

Encrypted columns use one `[16-byte IV][ciphertext+tag]` AES-GCM envelope per
field through `AesGcmCipher` and the vault master key. The legacy JSON indexes
migrate once after unlock, guarded by `pb_legacy_index_migrated`. The old index
is kept, not deleted.

## Build and test

```bash
make pb          # cross-compile arm64 → jniLibs (version-stamped)
make pb-linux    # host sidecar for local checks
make pb-types    # vendor PocketBase JS editor types
```

PocketBase is pinned at `v0.40.4` in `pocketbase/go.mod`. Builds use
`CGO_ENABLED=0` with the pure-Go `modernc.org/sqlite` backend. Release artifacts
are checked with `python3 scripts/pocketbase_artifact.py verify …`.

Automated tests cover the stdout handshake parser, ciphertext-at-rest round
trips, DAO/store reconcile behavior, migration, and the PB-to-sync wire path.
See [pb_testing.md](pb_testing.md) for host, debug-build, and on-device steps.

## What's left

1. Confirm the sidecar on real arm64 hardware: unlock, health, all four
   collections, lock/restart lifecycle, and no silent fallback to legacy.
2. Decide whether to keep the 32 MB arm64 binary as-is or shrink it (dropping JS
   migrations or adding compression) before stable.
3. Do the deferred polish only if it's needed: foreground service, recovery UI,
   size work.

The open product calls: arm64 is the only ABI for v1, remote replication is out
of scope, and WebDAV stays the remote path.
