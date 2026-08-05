# Embedded PocketBase Local Store

## Overview

The vault currently stores metadata as a flat JSON index in
`FlutterSecureStorage`, with media kept as encrypted files on disk. This
document specifies embedding a PocketBase instance on the device itself as a
structured, queryable local datastore for vault metadata. Media blobs remain
on-disk encrypted files; PocketBase indexes and relates them. The WebDAV
sync path (`docs/local_server_sync.md`) is unaffected: PocketBase is the
local layer, WebDAV remains the remote transport.

Status: **Planning**. No code exists. Phase P0 is a go/no-go feasibility
gate (can a Go binary run inside the APK and serve HTTP on loopback from
Dart); no later phase begins until it passes. If P0 fails, the plan falls
back to `sqflite`.

## Goals

- Structured, queryable, relational local storage for metadata.
- One embedded PocketBase instance per install; no hosted server.
- Sensitive columns encrypted at the app layer before insert. PocketBase
  never sees plaintext; at-rest security matches the current encrypted
  manifest.
- WebDAV remote sync stays untouched; the two backends coexist.
- No new cryptography: reuse `AesGcmCipher` and the vault master key.

## Non-goals

- **Local-PB ↔ remote-PB replication.** PocketBase has no native
  replication; building it is out of scope. Remote sync stays WebDAV.
- **Multi-user operation.** Single-user, single-device instance.
- **iOS.** The design depends on process spawning, which the iOS sandbox
  forbids. Android only.
- **Media blobs in PocketBase.** PB holds metadata and blob references only;
  storing blobs would double storage and break the end-to-end model.
- **PB admin UI and user accounts.** Unused in a single-user embedded role.

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
        │ loopback HTTP, 127.0.0.1:<ephemeral port> + auth token
        ▼
  libpocketbase.so (Go wrapper, bundled in jniLibs)
  wrapper main() → PocketBase core → JS migrations → serve HTTP
        │
        ▼
  SQLite (modernc, pure-Go) in app-private data dir
  vault_files / albums / tags / folders — encrypted columns

Media blobs ──► on-disk encrypted files (unchanged), referenced via blob_ref
```

`PocketBaseStore` implements the same `LocalStore` surface `VaultStore`
exposes, so the rest of the app (including `SyncService.buildManifest`) is
indifferent to where the index lives. The Go side is deliberately thin: a
wrapper `main()` around `pocketbase.NewWithConfig` plus JS migrations
defining the collections. No business logic in Go.

### Device layout

```
<app-data>/pocketbase/
  data.db                        # SQLite: encrypted columns + non-secret fields
  data.db-wal
  migrations/                    # versioned JS schema migrations
<app-data>/vault/                # unchanged: encrypted media blobs
  ab/cd/abcd1234…enc
android/app/src/main/jniLibs/
  arm64-v8a/libpocketbase.so     # Go binary, renamed so Android extracts it
```

`lib*.so` naming makes Android extract the binary into the native lib dir,
discoverable at runtime via `applicationInfo.nativeLibraryDir`.

### Bridge

| Option | Verdict | Rationale |
|---|---|---|
| Sidecar subprocess + loopback HTTP | **v1** | PocketBase is an HTTP server by design; spawn the binary, parse the bound port, call its REST API from Dart via `package:http`. Simple, debuggable, PB runs as designed. |
| FFI (`dart:ffi` → c-shared Go lib) | Alternative | Loads the Go runtime into the Flutter process; buys nothing in the data path (still HTTP) and adds Android friction. Considered only if sidecar lifecycle proves unworkable. |
| Pure-Dart rewrite | Rejected | Not PocketBase. |
| `sqflite` | Fallback | Covers "structured local storage" with one dependency and no binary; used only if P0 fails. |

Dependency: a custom Go binary wrapping PocketBase core (one `main.go`,
~100–300 lines), plus `package:http` on the Dart side (already available
transitively). PocketBase version pinned in `go.mod`.

## Security model

| Asset | Where | Exposure if device is compromised |
|---|---|---|
| Media ciphertext | On-disk encrypted files (unchanged) | Safe. AES-256-GCM/CTR, per-file key from master key. PB never touches the bytes. |
| Structured metadata (names, tags, albums, folders) | PB SQLite, app-encrypted columns | Safe: a dump yields ciphertext envelopes only, same as the current manifest. |
| Indexable fields (`modified_at`, `deleted`, `blob_ref`) | PB SQLite, plaintext | Low risk: timestamps, booleans, content hashes. |
| PB SQLite file | App-private storage | Readable on a rooted device; contains no plaintext secrets. |
| Localhost PB API | Loopback only, not exposed to network | Co-resident apps could probe it; mitigated by ephemeral random port + auth token held in Dart memory. |
| Master key | In memory after unlock; Argon2id-wrapped on disk | Unchanged; required to decrypt any column. |
| Go binary | Shipped in APK | Static, auditable, version-pinned; listens on loopback only. |

Hard rules:

- **Plaintext never leaves the app process.** PB stores ciphertext
  envelopes for secret fields. The Go binary never holds the master key and
  cannot decrypt anything it stores.
- **Loopback only.** PB binds `127.0.0.1` on an ephemeral random port
  chosen at start — never `0.0.0.0`, never a fixed port. Dart learns the
  port from the binary's stdout. A random auth token (emitted by the Go
  side, held only in Dart memory) gates every request.
- **Encrypt any field that could be secret.** A field is plaintext only if
  it is non-secret by definition (timestamp, tombstone flag, content
  hash). When in doubt, encrypt.
- **The master key is the single root of confidentiality**, for both
  on-disk blobs and PB columns — identical to today.
- **Decoy vault out of scope** (mirrors `local_server_sync.md`).

## Data model

Collections are defined as versioned JS migrations on the Go side:

- **`vault_files`** — `id` (text PK), `blob_ref` (text, on-disk shard path /
  content hash; non-secret), `cipher_meta` (blob, app-encrypted JSON: tags,
  albumIds, folderId, originalName, dateAdded, dateModified),
  `modified_at` (number, plaintext for sorting), `deleted` (bool tombstone).
- **`albums`** — `id`, `cipher_meta` (encrypted: name, cover ref, order),
  `modified_at`, `deleted`.
- **`tags`** — `id`, `cipher_name` (encrypted), `modified_at`, `deleted`.
- **`folders`** — `id`, `cipher_meta` (encrypted: name, parent_id),
  `modified_at`, `deleted`.

**Encrypted-column convention:** one AES-GCM envelope per secret field —
`[16-byte IV][ciphertext+tag]`, key = vault master key, via
`AesGcmCipher`. Encode/decode lives in a single Dart helper shared by all
DAOs. Sortable/filterable columns (`modified_at`, `deleted`, `blob_ref`)
are deliberately non-secret, so PB query power survives.

**Migration (one-time):** on first PB boot after unlock, read the existing
`FlutterSecureStorage` `vault_file_index` JSON and bulk-insert into
`vault_files`, encrypting `cipher_meta`. Guarded by a settings flag so it
runs once. The legacy store is retained as a fallback, not deleted.

## Phased plan

Phases are ordered by dependency. **P0 is a go/no-go gate.**

### P0 — Spike / de-risk (1–2 days)

| # | Task | Location |
|---|---|---|
| P0.1 | Trivial Go HTTP server, cross-compile `GOOS=android GOARCH=arm64 CGO_ENABLED=0`; verify PocketBase's pure-Go `modernc.org/sqlite` backend means no CGO/NDK | `pocketbase/` (new Go module) |
| P0.2 | Bundle as `jniLibs/arm64-v8a/libpocketbase.so`; from a throwaway Dart screen locate via `applicationInfo.nativeLibraryDir`, `Process.start`, parse port | `android/app/src/main/jniLibs/` |
| P0.3 | Hit `/api/health` over loopback, assert 200 | throwaway screen |

**Verify:** the binary runs, serves HTTP on loopback, and Dart reaches it.
If this fails, stop and fall back to `sqflite`.

### P1 — Go wrapper `locker-pb` (3–5 days)

| # | Task | Location |
|---|---|---|
| P1.1 | `main.go` wrapping `pocketbase.NewWithConfig`: `--dir`, `--http=127.0.0.1:0` (ephemeral port printed to stdout), `--auth-token` (random, printed to stdout), `--hooks` | `pocketbase/cmd/locker-pb/main.go` |
| P1.2 | JS migrations for `vault_files`, `albums`, `tags`, `folders` | `pocketbase/migrations/*.js` |
| P1.3 | Cross-compile per chosen ABI (open decision 2); strip symbols | `Makefile` |
| P1.4 | Pin PocketBase version in `go.mod` and document it | `pocketbase/go.mod` |

### P2 — Dart runtime + bridge (3–4 days)

| # | Task | Location |
|---|---|---|
| P2.1 | `PocketBaseRuntime`: binary discovery → exec → parse port+token → health-wait → graceful stop on teardown | `lib/services/pb/pocketbase_runtime.dart` |
| P2.2 | Authenticated `http` client (token header) to localhost | `lib/services/pb/pb_client.dart` |
| P2.3 | Lifecycle: start after unlock (needs master key), stop on lock/exit | app bootstrap |

### P3 — Encrypted-column DAO layer (4–6 days)

| # | Task | Location |
|---|---|---|
| P3.1 | `cipher_codec`: envelope/unwrap via `AesGcmCipher` + master key | `lib/services/pb/cipher_codec.dart` |
| P3.2 | DAOs: `VaultFileDao`, `AlbumDao`, `TagDao`, `FolderDao` (CRUD against PB collections, encrypting secret fields) | `lib/services/pb/daos/*.dart` |
| P3.3 | `PocketBaseStore implements LocalStore` (same surface `VaultStore` exposes) | `lib/services/pb/pocketbase_store.dart` |
| P3.4 | One-time legacy → PB migration, guarded by settings flag | `lib/services/pb/migrate_legacy_index.dart` |
| P3.5 | Behavioral test: round-trip a `VaultedFile` through the DAO; assert `cipher_meta` is ciphertext in the row and plaintext after read | `test/pb_store_test.dart` |

### P4 — Wire-in + sync integration (3–4 days)

| # | Task | Location |
|---|---|---|
| P4.1 | Introduce `LocalStore` interface; `VaultStore` and `PocketBaseStore` both implement it | `lib/services/local_store.dart` |
| P4.2 | `VaultService` reads/writes through `LocalStore` (PB preferred, legacy fallback) | `lib/services/vault_service.dart` |
| P4.3 | `SyncService.buildManifest` reads from the active `LocalStore` instead of `cachedFiles`; `runSync` unchanged | `lib/services/sync_service.dart` |
| P4.4 | End-to-end: seed vault → PB rows appear → `runSync` pushes blobs + encrypted manifest (WebDAV path unchanged) | manual + scripted |

### P5 — Polish (deferred)

PB-vs-legacy toggle in settings, recovery UI if the binary fails to start,
size optimization (`upx` / symbol strip), CI for the Go cross-compile,
foreground Service for background PB survival. Ship P4 first; build P5 only
if the feature gets used.

## Files

New:

```
pocketbase/                                Go module (custom PB wrapper)
  cmd/locker-pb/main.go                    wrapper main()
  migrations/*.js                          schema
  go.mod                                   pinned pocketbase version
lib/services/local_store.dart              LocalStore interface
lib/services/pb/pocketbase_runtime.dart    binary discovery + exec + lifecycle
lib/services/pb/pb_client.dart             authenticated localhost client
lib/services/pb/cipher_codec.dart          column envelope/unwrap (reuse AesGcm)
lib/services/pb/daos/*.dart                per-entity DAOs
lib/services/pb/pocketbase_store.dart      LocalStore impl over PB
lib/services/pb/migrate_legacy_index.dart  one-time FlutterSecureStorage → PB
test/pb_store_test.dart                    encrypted-column round-trip
Makefile                                   `make pb` cross-compile + place .so
```

Changed:

```
android/app/src/main/jniLibs/<abi>/libpocketbase.so   bundled Go binary
pubspec.yaml                                          + http (Dart client)
lib/services/vault_service.dart                       read/write via LocalStore
lib/services/sync_service.dart                        buildManifest reads LocalStore
lib/models/vault_settings.dart                        + pbEnabled flag
```

## Dependencies

- **Add (Go):** `pocketbase` (pinned; pure-Go `modernc.org/sqlite` so
  `CGO_ENABLED=0` cross-compile works — no NDK).
- **Add (Dart):** `http` (localhost client; already available transitively,
  pin explicitly).
- **Reuse:** `lib/crypto/` (`AesGcmCipher`, master key) — no new crypto.
  `flutter_secure_storage` retained for credentials and the legacy
  fallback index.

## Build pipeline

`make pb` → cross-compile per ABI (`GOOS=android GOARCH=<arm64|arm|386>
CGO_ENABLED=0`) → strip symbols → copy to
`android/app/src/main/jniLibs/<abi>/libpocketbase.so` → `flutter build apk`.
One command, version-pinned, reproducible.

## Verification discipline

Per the refactor roadmap's test rules: no per-method suites, one happy-path
test per phase, one failure path for anything security-touching. P0 is the
make-or-break check; P3.5 is the security-touching check (ciphertext at
rest, plaintext on read). Manual end-to-end in P4.4 is the acceptance test.

## Open decisions

1. **Bridge style: sidecar + HTTP vs FFI.** Recommended: sidecar + HTTP
   (data path is HTTP either way; FFI only adds Go-runtime friction).
2. **ABIs: `arm64-v8a` only, or also `armeabi-v7a` + `x86_64`?**
   Recommended: arm64 only for v1 (~10–12 MB stripped). Add others only if
   emulator/old-device support matters.
3. **Media blobs in PB, or metadata + refs only?** Recommended: metadata +
   refs only (see Security model).
4. **Schema source: Go JS migrations vs Dart-created at first run?**
   Recommended: Go migrations (versioned with PB, reproducible).
5. **Background PB survival (foreground Service) now or later?**
   Recommended: later; foreground-only for v1.
6. **APK size budget.** arm64-only stripped PB adds ~10–12 MB.
7. **Remote replication scope.** If local-PB ↔ remote-PB replication is
   the end goal, it becomes a new phase here and a meaningful scope
   addition; the plan assumes WebDAV remains the only remote path.
