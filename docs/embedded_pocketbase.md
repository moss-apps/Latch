# Embedded PocketBase Local Store

## Overview

The vault currently stores metadata as a flat JSON index in
`FlutterSecureStorage`, with media kept as encrypted files on disk. This
document specifies embedding a PocketBase instance on the device itself as a
structured, queryable local datastore for vault metadata. Media blobs remain
on-disk encrypted files; PocketBase indexes and relates them. The WebDAV
sync path (`docs/local_server_sync.md`) is unaffected: PocketBase is the
local layer, WebDAV remains the remote transport.

Status: **In progress**. The P0 go/no-go gate **passed** (host-verified: the
pure-Go build cross-compiles for android/arm64 with `CGO_ENABLED=0`, serves
loopback HTTP, and the token gate + collection CRUD were exercised on a
linux host). P1 is complete. P2 is complete in code (runtime + client +
lifecycle wiring; the P0 spike screen is deleted — its on-device job now
rides on the `[PB] …` debug logs from `PocketBaseRuntime`). Outstanding
before P3 is exercised on real hardware: unlock a debug build (with
`make pb` run first) and confirm `[PB] sidecar up: pid=… port=…` in
logcat. If the sidecar proves broken on device, fall back to `sqflite`.
Per-task status lives in the phase tables below.

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
  migrations/                    # JS schema migrations, extracted from the
                                 # binary's go:embed at every boot
<app-data>/vault/                # unchanged: encrypted media blobs
  ab/cd/abcd1234…enc
android/app/src/main/jniLibs/
  arm64-v8a/libpocketbase.so     # Go binary, renamed so Android extracts it
```

`lib*.so` naming makes Android extract the binary into the native lib dir,
discoverable at runtime via `applicationInfo.nativeLibraryDir`. The manifest
sets `android:extractNativeLibs="true"`: modern AGP defaults keep libs
unextracted inside the APK mount, where they are dlopen-able but typically
not exec-able — the sidecar is spawned with `execve`, so it needs real
extracted files on disk.

### Bridge

| Option | Verdict | Rationale |
|---|---|---|
| Sidecar subprocess + loopback HTTP | **v1** | PocketBase is an HTTP server by design; spawn the binary, parse the bound port, call its REST API from Dart via `package:http`. Simple, debuggable, PB runs as designed. |
| FFI (`dart:ffi` → c-shared Go lib) | Alternative | Loads the Go runtime into the Flutter process; buys nothing in the data path (still HTTP) and adds Android friction. Considered only if sidecar lifecycle proves unworkable. |
| Pure-Dart rewrite | Rejected | Not PocketBase. |
| `sqflite` | Fallback | Covers "structured local storage" with one dependency and no binary; used only if P0 fails. |

Dependency: a custom Go binary wrapping PocketBase core (`main.go`, ~150
lines), plus `package:http` on the Dart side (it was NOT available
transitively — added explicitly in P0). PocketBase pinned at `v0.39.10` in
`pocketbase/go.mod`.

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

| # | Task | Location | Status |
|---|---|---|---|
| P0.1 | Trivial Go HTTP server, cross-compile `GOOS=android GOARCH=arm64 CGO_ENABLED=0`; verify PocketBase's pure-Go `modernc.org/sqlite` backend means no CGO/NDK | `pocketbase/` (new Go module) | done — `modernc.org/sqlite` confirmed pure-Go; arm64 ELF (`/system/bin/linker64` interpreter) builds clean |
| P0.2 | Bundle as `jniLibs/arm64-v8a/libpocketbase.so`; from a throwaway Dart screen locate via `applicationInfo.nativeLibraryDir`, `Process.start`, parse port | `android/app/src/main/jniLibs/` | done — `make pb` bundles (gitignored artifact); spike screen `lib/screens/pb_spike_screen.dart` + `pb` method channel in `MainActivity.kt`; `extractNativeLibs="true"` set. on-device run pending |
| P0.3 | Hit `/api/health` over loopback, assert 200 | throwaway screen | done on host — 401 without token / 200 with. on-device run pending |

**Verify:** the binary runs, serves HTTP on loopback, and Dart reaches it.
If this fails, stop and fall back to `sqflite`.

**Result: PASS on host.** A linux run of the wrapper prints the
`LOCKER_PB_PORT` / `LOCKER_PB_TOKEN` / `LOCKER_PB_READY=1` handshake on
stdout, gates every route with `X-Locker-Token` (401 without, 200 with),
auto-creates all four collections via the JS migrations, round-trips a
record, and stores `cipher_meta` as an opaque blob. PB's first-run
superuser installer is disabled (no-op `InstallerFunc`), so stdout carries
only the handshake — no superuser-creation JWT is ever printed.

### P1 — Go wrapper `locker-pb` (3–5 days)

| # | Task | Location | Status |
|---|---|---|---|
| P1.1 | `main.go` wrapping `pocketbase.NewWithConfig`: `--dir`, `--http=127.0.0.1:0` (ephemeral port printed to stdout), `--auth-token` (random, printed to stdout), `--hooks` | `pocketbase/cmd/locker-pb/main.go` | done — uses `app.Execute()` (not `Start()`) so PB's default `serve`/`superuser` commands (0.0.0.0:8090) are never registered; listener pre-bound in an OnServe hook for a race-free ephemeral port; `--auth-token` optional (random 256-bit default); `--hooks` dropped as unused |
| P1.2 | JS migrations for `vault_files`, `albums`, `tags`, `folders` | `pocketbase/migrations/*.js` | done — `0001`–`0004`; embedded via `go:embed` (`migrations/embed.go`) and extracted to `<dir>/migrations` at every boot, so the `.so` is self-contained; `make pb-types` vendors the canonical editor `types.d.ts` (gitignored) |
| P1.3 | Cross-compile per chosen ABI (open decision 2); strip symbols | `Makefile` | done — `make pb` (arm64-v8a only, `-ldflags "-s -w" -trimpath`, 32 MB); host `strip` can't read arm64 ELF so symbols are dropped at link time; `make pb-linux` + `make pb-types` targets too |
| P1.4 | Pin PocketBase version in `go.mod` and document it | `pocketbase/go.mod` | done — `github.com/pocketbase/pocketbase v0.39.10` (+ `modernc.org/sqlite v1.55.0` indirect) |

#### Findings from P0/P1 (review before P2)

- **Size budget blown (decision 6 reopened).** Stripped arm64 binary is
  **32 MB**, not the estimated 10–12 MB: core PocketBase alone is 23 MB and
  `jsvm`/`goja` (the JS runtime for JS migrations) adds ~9 MB. Options:
  accept 32 MB, add `upx` (P5, ~3× → ~10 MB, but AV false-positive risk on
  Android), or rewrite migrations in Go and drop jsvm (−9 MB, changes P1.2's
  JS-file deliverable). Needs a call before P2 locks the artifact shape.
- **Stdout handshake protocol (contract for P2).** The binary prints
  `LOCKER_PB_PORT=<n>`, `LOCKER_PB_TOKEN=<64-hex>`, `LOCKER_PB_READY=1` on
  stdout, nothing else. Dart parses by prefix and must ignore any other
  lines defensively.
- **`extractNativeLibs="true"` is required.** Modern AGP keeps `.so` files
  unextracted inside the APK mount (dlopen-able, typically not exec-able);
  the sidecar needs exec, so the manifest now forces extraction.
- **Collection rules are `""` (public) by design.** The token gate at the
  HTTP layer is the only access control; PB-level rules would only block
  our own token-bearing client (no user accounts in the embedded role).
  `/api/collections` metadata stays superuser-only regardless of rules —
  use `/api/collections/{name}/records` for existence checks.
- **Editor types.** `/// <reference path="../pb_data/types.d.ts" />` in the
  migration files resolves via `make pb-types` (vendors the canonical
  787 KB `types.d.ts` from the pinned module; gitignored, regenerable).

### P2 — Dart runtime + bridge (3–4 days)

| # | Task | Location | Status |
|---|---|---|---|
| P2.1 | `PocketBaseRuntime`: binary discovery → exec → parse port+token → health-wait → graceful stop on teardown | `lib/services/pb/pocketbase_runtime.dart` | done — singleton; `PbHandshakeParser` is a pure, tested class (ignores non-handshake stdout lines defensively); health-wait polls `/api/health` (5 s); orphaned sidecars from a hard app kill are swept on next start via `<pbDir>/sidecar.pid` (kill stale pid, then respawn) |
| P2.2 | Authenticated `http` client (token header) to localhost | `lib/services/pb/pb_client.dart` | done — `PbClient(port, token)` with get/post/patch/delete + `health()`; token header `X-Locker-Token`; throws on ≥400 |
| P2.3 | Lifecycle: start after unlock (needs master key), stop on lock/exit | app bootstrap | done — started fire-and-forget from `UnlockScreen._openVault` (non-decoy only; failure logs, never blocks unlock — recovery UI is P5). Stop: `AppLifecycleListener.onDetach` (activity finish / auto-kill) does a graceful SIGTERM + wait; hard process kills are covered by the pid-file sweep since Android delivers no Dart exit callback |

P2 notes for P3: the running `PbClient` is exposed as
`PocketBaseRuntime.instance.client` (null while stopped/starting). The
autofill entry point never opens the vault UI, so it never starts the
sidecar. One happy-path test per phase lives in `test/pb_runtime_test.dart`
(handshake parsing, incl. garbage-port and junk-line cases).

### P3 — Encrypted-column DAO layer (4–6 days)

| # | Task | Location | Status |
|---|---|---|---|
| P3.1 | `cipher_codec`: envelope/unwrap via `AesGcmCipher` + master key | `lib/services/pb/cipher_codec.dart` | pending |
| P3.2 | DAOs: `VaultFileDao`, `AlbumDao`, `TagDao`, `FolderDao` (CRUD against PB collections, encrypting secret fields) | `lib/services/pb/daos/*.dart` | pending |
| P3.3 | `PocketBaseStore implements LocalStore` (same surface `VaultStore` exposes) | `lib/services/pb/pocketbase_store.dart` | pending |
| P3.4 | One-time legacy → PB migration, guarded by settings flag | `lib/services/pb/migrate_legacy_index.dart` | pending |
| P3.5 | Behavioral test: round-trip a `VaultedFile` through the DAO; assert `cipher_meta` is ciphertext in the row and plaintext after read | `test/pb_store_test.dart` | pending |

### P4 — Wire-in + sync integration (3–4 days)

| # | Task | Location | Status |
|---|---|---|---|
| P4.1 | Introduce `LocalStore` interface; `VaultStore` and `PocketBaseStore` both implement it | `lib/services/local_store.dart` | pending |
| P4.2 | `VaultService` reads/writes through `LocalStore` (PB preferred, legacy fallback) | `lib/services/vault_service.dart` | pending |
| P4.3 | `SyncService.buildManifest` reads from the active `LocalStore` instead of `cachedFiles`; `runSync` unchanged | `lib/services/sync_service.dart` | pending |
| P4.4 | End-to-end: seed vault → PB rows appear → `runSync` pushes blobs + encrypted manifest (WebDAV path unchanged) | manual + scripted | pending |

### P5 — Polish (deferred)

Status: deferred entirely. PB-vs-legacy toggle in settings, recovery UI
if the binary fails to start, size optimization (`upx` / symbol strip), CI
for the Go cross-compile, foreground Service for background PB survival.
Ship P4 first; build P5 only if the feature gets used.

## Files

New — **built (P0 + P1 + P2)**:

```
pocketbase/                                Go module (custom PB wrapper)
  cmd/locker-pb/main.go                    wrapper main()
  migrations/0001–0004_*.js                schema (4 collections)
  migrations/embed.go                      go:embed bundle → self-contained .so
  pb_data/types.d.ts                       editor types (gitignored, `make pb-types`)
  go.mod / go.sum                          pocketbase pinned at v0.39.10
Makefile                                   `make pb` (cross-compile → jniLibs),
                                           `make pb-linux`, `make pb-types`
lib/services/pb/pocketbase_runtime.dart    sidecar lifecycle (discovery, exec,
                                           handshake, health-wait, pid-file
                                           orphan sweep, graceful stop)
lib/services/pb/pb_client.dart             authenticated localhost client
test/pb_runtime_test.dart                  handshake-parser checks
```

Deleted in P2 (per plan): `lib/screens/pb_spike_screen.dart` and its
debug-only settings tile — superseded by `PocketBaseRuntime`'s `[PB]` logs.

Changed — **built**:

```
android/app/src/main/AndroidManifest.xml   + android:extractNativeLibs="true"
android/.../MainActivity.kt                + `pb` method channel (getNativeLibraryDir)
pubspec.yaml                                + http ^1.2.2
lib/screens/unlock_screen.dart              + fire-and-forget PB start on real
                                            vault open (P2.3)
lib/screens/vault_settings_screen.dart      spike tile removed again in P2
```

New — **planned (P3–P4)**:

```
lib/services/local_store.dart              LocalStore interface
lib/services/pb/cipher_codec.dart          column envelope/unwrap (reuse AesGcm)
lib/services/pb/daos/*.dart                per-entity DAOs
lib/services/pb/pocketbase_store.dart      LocalStore impl over PB
lib/services/pb/migrate_legacy_index.dart  one-time FlutterSecureStorage → PB
test/pb_store_test.dart                    encrypted-column round-trip
```

Changed — **planned**: `lib/services/vault_service.dart`,
`lib/services/sync_service.dart`, `lib/models/vault_settings.dart` (+pbEnabled
flag) in P4.

Build artifacts (gitignored, regenerated): `jniLibs/<abi>/libpocketbase.so`,
`pocketbase/pb_data/`.

## Dependencies

- **Add (Go):** `pocketbase` (added — pinned `v0.39.10`; pure-Go
  `modernc.org/sqlite` so `CGO_ENABLED=0` cross-compile works — verified, no
  NDK).
- **Add (Dart):** `http` (added — `^1.2.2`; the doc originally assumed it was
  available transitively, which was wrong).
- **Reuse:** `lib/crypto/` (`AesGcmCipher`, master key) — no new crypto.
  `flutter_secure_storage` retained for credentials and the legacy
  fallback index.

## Build pipeline

`make pb` → cross-compile per ABI (`GOOS=android GOARCH=<arm64|arm|386>
CGO_ENABLED=0`) → strip symbols (`-ldflags "-s -w"` at link time — host
`strip` can't read arm64 ELF) → copy to
`android/app/src/main/jniLibs/<abi>/libpocketbase.so` → `flutter build apk`.
One command, version-pinned, reproducible. Companion targets: `make
pb-linux` (host binary for desktop verification), `make pb-types` (JS
editor types).

## Verification discipline

Per the refactor roadmap's test rules: no per-method suites, one happy-path
test per phase, one failure path for anything security-touching. P0 is the
make-or-break check; P3.5 is the security-touching check (ciphertext at
rest, plaintext on read). Manual end-to-end in P4.4 is the acceptance test.

Track record so far: **P0 passed on host** — health 401-without/200-with
token (that pair doubles as the token-gate failure path), 4 collections
migrated, record CRUD round-trip, `cipher_meta` opaque at rest; `go vet`,
`go build`, and `flutter analyze` clean. **P2 checked** —
`test/pb_runtime_test.dart` covers the stdout-handshake parser (happy path
plus junk-line and garbage-port failure paths); `flutter analyze` and the
full `flutter test` suite pass. Outstanding: on-device run
(P0.2/P0.3/P2.3 hardware confirmation — unlock a debug apk built after
`make pb` and look for `[PB] sidecar up` in logcat) before P3 relies on
the sidecar.

## Open decisions

1. **Bridge style: sidecar + HTTP vs FFI.** Resolved → sidecar + HTTP
   (implemented; the data path is HTTP either way).
2. **ABIs: `arm64-v8a` only, or also `armeabi-v7a` + `x86_64`?** Resolved
   → arm64 only for v1 (32 MB stripped). The Makefile has the ABI→GOARCH
   map ready if emulator/old-device support is needed later.
3. **Media blobs in PB, or metadata + refs only?** Resolved per design →
   metadata + refs only (see Security model).
4. **Schema source: Go JS migrations vs Dart-created at first run?**
   Resolved → a hybrid: JS migration files (versioned with PB) embedded
   into the Go binary via `go:embed` and extracted at boot — reproducible,
   no Dart-side schema code, self-contained `.so`.
5. **Background PB survival (foreground Service) now or later?** Later;
   foreground-only for v1. P2 must still handle orphaned sidecars after a
   hard app kill.
6. **APK size budget.** **Reopened with data.** arm64-only stripped PB is
   32 MB, not the estimated 10–12 MB (core 23 MB + goja ~9 MB). Options:
   accept, `upx` in P5, or Go-defined collections to drop jsvm (−9 MB).
   Decide before P2.
7. **Remote replication scope.** If local-PB ↔ remote-PB replication is
   the end goal, it becomes a new phase here and a meaningful scope
   addition; the plan assumes WebDAV remains the only remote path.
   (Unchanged.)
