# Local Server Sync (WebDAV)

## Overview

The vault is device-local, with a manual *decrypted* ZIP backup
(`BackupService`). This document specifies encrypted-at-rest sync to a
user-chosen server (NAS, home server, or self-hosted cloud), push and pull.
The server never sees plaintext: it is dumb encrypted blob storage.

Status: **Complete (S0–S3)**. S0 (transport + credentials), S1 (manifest
crypto), S2 (push-only backup: reconcile, `runSync`, provider, connectivity
guard, UI), and S3 (two-way pull/restore: manifest v2, pull path, conflict
flagging, tombstone propagation) are implemented and unit-tested. S0.5
(live-server roundtrip) and S3.4 (two-device two-way roundtrip) are covered
by the env-gated `test/live_webdav_test.dart` (run against a real server via
`LOCKER_LIVE_WEBDAV_URL`; skipped otherwise). 102 tests pass in the default
hermetic `flutter test` run; the gated live suite adds 3 (S0.5 + S3.4)
against a real server. S0.5 surfaced and fixed a real bug: spec-strict servers
(rclone, plain mod_dav) return **409 Conflict** on a nested PUT whose parent
collection doesn't exist — `WebDAVStore` now `MKCOL`s parents idempotently
before every write (`_ensureParent`); Nextcloud masked the need.

## Goals

- Push the vault to a user-chosen server and pull it back on a new device
  or after a wipe.
- The server sees opaque encrypted bytes only.
- Manual sync first; scheduled/background sync later.
- Reuse the existing encrypted file format and key model — no new crypto.

## Non-goals

- Real-time collaborative sync / CRDT (last-write-wins per file suffices).
- A hosted cloud account; sync is local / self-hosted only.
- Multiple simultaneous servers (one remote per vault).
- Streaming media playback from the server (sync, not remote mount).

## Security model

| Asset | Where | Exposure if server is compromised |
|---|---|---|
| Media ciphertext | Server | Safe. AES-256-GCM/CTR, per-file key derived via PBKDF2 from the master key. Server sees blobs only. |
| Manifest (index, names, tags, albums, folders) | Server, encrypted | Safe if encrypted with the master key before upload. The raw `vault_file_index` JSON must never be uploaded. |
| Server credentials (URL, user, app password) | `flutter_secure_storage` → Android Keystore | Safe; same path as the PIN/master-key wrap. |
| Thumbnails | Local only (v1) | Re-derivable on pull from the decrypted blob; not synced. |

Hard rules:

- **Plaintext never crosses the network.** The decrypted-ZIP behavior of
  `BackupService` stays limited to local export; it is not a sync
  transport.
- **The manifest is encrypted** with the vault master key (the same one
  wrapped by Argon2id on-device). The server holds `manifest.enc`.
- **Credentials live in `flutter_secure_storage`**, never in
  `VaultSettings` JSON.
- **TLS by default**; WebDAV over plain HTTP on the LAN (self-signed
  certs, `.local` hostnames) is allowed only with an explicit warning, and
  never by silent downgrade.
- **No implicit trust of server state.** Pull verifies GCM auth tags on
  every blob before trusting it.
- **Decoy vault is out of scope for sync** (leaks its existence, doubles
  the surface). Main vault only.

## Architecture

```
UI ── Riverpod ── SyncProvider (Notifier: status idle/uploading/downloading/error, lastSync)
                     │
                     ▼
               SyncService
               reconcile(): diff local vs remote manifest → plan → execute
               • push encrypted blobs (new/changed local)
               • pull encrypted blobs (new/changed remote)
               • tombstone deletes
               • write encrypted manifest last (commit point)
        ┌──────────┴───────────┐
        ▼                      ▼
  VaultStore             RemoteStore
  (local files,          (WebDAV transport)
   local index)          getManifest / putManifest /
                         getBlob / putBlob / deleteBlob / listBlobs
                                 │ HTTP
                                 ▼
                          WebDAV server (NAS / cloud)
```

`SyncService` is the brain; `RemoteStore` is a thin transport abstraction
(one interface, one WebDAV implementation) so SFTP/SMB can slot in later
behind the same `SyncService`.

### Server layout

```
<basePath>/                     # SyncProfile.basePath, default /locker
  manifest.enc                  # encrypted index + metadata + tombstones
  ab/cd/abcd1234…enc            # content-addressed encrypted media (sha256 of ciphertext)
  ef/01/ef019876…enc
```

Blobs are content-addressed by hash of the **ciphertext**: dedupe
(identical ciphertext across devices), easy diff (manifest lists hashes,
not paths), and trivial rename/move (metadata-only change). GCM tags
already authenticate the manifest; a separate signature is YAGNI for v1.

## Protocol

| Protocol | Verdict | Rationale |
|---|---|---|
| **WebDAV** | **v1** | Plain HTTP; every NAS/Nextcloud/Synology/ownCloud/Seafile exposes it; one package. `MKCOL`/`PUT`/`GET`/`DELETE`/`PROPFIND` is the whole API. |
| SFTP | Deferred | Heavy SSH client package (`dartssh2`), key management. Add only if asked. |
| SMB | Deferred | jCIFS on Android is fragile. |
| Custom HTTP server | Rejected | Server stays dumb. |

Dependency: `webdav_client` (pub.dev), v1.2.2. Falls back to raw
`package:http` + `PROPFIND` if its API is awkward.

## Sync model

**Last-write-wins per file; manifest as commit point.**

- Each `VaultedFile` has a UUID `id` plus `modifiedAt` / `syncRev`.
  The manifest maps `id → {hash, modifiedAt, deleted}`.
- **Reconcile** compares local vs remote manifest by id:
  - remote has id, local doesn't, not tombstoned → pull
  - local has id, remote doesn't → push
  - both have it, hashes differ → newer `modifiedAt` wins; loser is
    overwritten (no three-way merge in v1; a conflict note is flagged in
    the UI if both sides changed since last sync)
  - either side tombstoned → propagate delete
- **Manifest is the commit point.** Blobs are uploaded/downloaded first;
  the manifest write (PUT replaces the whole file) commits. A mid-sync
  crash leaves the old manifest describing a consistent older state; the
  next run resumes. Re-running sync is idempotent.
- **No partial-file sync.** Files are atomic units; an encrypted video is
  fully re-pushed on change (no delta possible).

Direction is a setting: **push-only** (backup, recommended default) or
**two-way** (enable after push-only is proven).

## Data & config changes

- **`SyncProfile`** (URL, username, base path, lastSyncAt, syncDirection,
  wifiOnly) — stored in `flutter_secure_storage` as JSON, kept out of
  `VaultSettings`. Done, plus `SyncProfileService` CRUD with per-profile
  password keys (`sync_profile_pw_<id>`); passwords never live in the
  profile JSON.
- **`VaultSettings` additions:** `syncEnabled` (bool, default false),
  `syncProfileId` (String?). Done.
- **`VaultedFile` additions:** `modifiedAt`, `remoteHash`, `syncedDeleted`
  (tombstone flag). Done. No load-time migration: `runSync` backfills
  `modifiedAt` lazily (sync completion time when missing);
  `buildManifest` falls back to `dateModified` → `dateAdded`.
- **`RemoteManifest`** model (`version`, `deviceId`, `generatedAt`,
  `entries: [{id, contentHash, modifiedAt, deleted}]`). Done.
- **`SyncService`** is Riverpod-native: instance ctor
  `SyncService(VaultStore, EncryptionService)` via `syncServiceProvider`
  (no singleton). Pure diff/manifest logic is static; `runSync` is static
  and param-driven (testable with a fake `RemoteStore`); `syncNow` is the
  thin instance glue. S3 bumped the manifest to **v2**: `ManifestEntry`
  now carries the full per-file metadata (name, type, mime, size, dates,
  encryption fields, tags, favorite, album/folder ids) so a fresh device
  can restore files. v1 manifests still deserialize (missing keys default).

## Phased plan

### S0 — Transport + credentials (1–2 days)

| # | Task | Location | Status |
|---|---|---|---|
| S0.1 | Add `webdav_client` dep (1.2.2) | `pubspec.yaml` | Done |
| S0.2 | `RemoteStore` interface + WebDAV impl: `ping`, `getManifest`, `putManifest`, `getBlob`, `putBlob`, `deleteBlob`, `listBlobs` | `lib/services/remote/` | Done |
| S0.3 | `SyncProfile` model + secure-storage CRUD | `lib/models/sync_profile.dart`, `lib/services/sync_profile_service.dart` | Done |
| S0.4 | Connection settings UI: URL/user/password, "Test connection", TLS warning for plain HTTP | `lib/screens/sync_settings_screen.dart` | Done |
| S0.5 | Live-server roundtrip: connect to a real WebDAV URL, put/get a tiny blob, assert roundtrip | `test/live_webdav_test.dart` (env-gated) | Done — also surfaced+fixed the nested-PUT 409 bug |

**Verify:** connect to a real WebDAV server (Nextcloud demo or
`rclone serve webdav`), roundtrip a blob; credentials persist across
restart. — Covered by `test/live_webdav_test.dart` (env-gated; see
"Running the live tests" below).

### S1 — Encrypted manifest (1–2 days)

| # | Task | Location | Status |
|---|---|---|---|
| S1.1 | `RemoteManifest` model + JSON (de)serialize | `lib/models/remote_manifest.dart` | Done |
| S1.2 | Build manifest from `VaultStore` index; encrypt with master key; decrypt on read | `SyncService.buildManifest` / `runSync` | Done |
| S1.3 | Content-addressed blob naming (sha256 of ciphertext, sharded `ab/cd/`) | `SyncService.blobNameFor` | Done |
| S1.4 | Push/pull manifest only (no blobs yet) — proves crypto + transport glue | extends S0 | Done |

**Verify:** upload encrypted manifest, wipe local, pull manifest back,
decrypt, assert it equals the original index; inspect the server to
confirm no plaintext left the device.

### S2 — Push-only backup (2–3 days)

| # | Task | Location | Status |
|---|---|---|---|
| S2.1 | `reconcile()` diff engine (local vs remote manifest) → plan (push/pull/delete lists), covers tombstone deletion and two-way pull cases | `SyncService.reconcile` | Done |
| S2.2 | Execute push plan: upload new/changed blobs, then commit manifest (static `runSync`, manifest last, idempotent) | `SyncService.runSync` | Done |
| S2.3 | `SyncProvider` (Riverpod Notifier): status enum, progress, `syncNow()` | `lib/providers/sync_provider.dart` | Done |
| S2.4 | `connectivity_plus` guard (wifiOnly / connected) in `SyncNotifier.syncNow()`; keeps `runSync` pure | `SyncNotifier` | Done |
| S2.5 | UI: status card + "Sync now" in settings, progress reporting, drawer entry via vault settings "Server Sync" | `sync_settings_screen.dart`, `vault_settings_screen.dart` | Done |
| S2.6 | Behavioral test: seed vault, sync, assert every local file has a remote blob and the manifest lists it; plus tombstone reaping and idempotent re-run (`_MemStore` fake `RemoteStore`) | `test/sync_service_test.dart` | Done |

**Verify:** fill vault, push to server, inspect server (all opaque `.enc`),
wipe app data, reinstall → pull restores the vault intact (decrypt +
auth-tag verify per file).

### S3 — Two-way sync (2–3 days)

| # | Task | Location | Status |
|---|---|---|---|
| S3.1 | Pull path: download missing/changed blobs, verify GCM auth tag, import into `VaultStore` | `SyncService` pull branch | Done |
| S3.2 | Last-write-wins resolution + conflict UI note when both sides changed | `reconcile` | Done |
| S3.3 | Tombstone propagation (delete on one device → delete on other, with confirmation) | `reconcile` + UI | Done |
| S3.4 | Two-device roundtrip test | `test/live_webdav_test.dart` (env-gated, two-way) | Done |

**Verify:** device A adds files → sync → device B pulls them; device B
edits → sync → device A sees the edit; delete on A propagates to B.
Covered by simulated two-device tests in `test/sync_service_test.dart`
(in-memory `RemoteStore`) **and** the live two-device run in
`test/live_webdav_test.dart` (env-gated, real server). The live suite
also asserts pull rejects a tampered blob (sha256 mismatch → `StateError`).

**S3 ceilings (deliberate simplifications):**

- **Pull integrity** is satisfied transitively: the manifest is
  GCM-authenticated (root of trust) and each pulled blob's sha256 must
  equal the manifest's `contentHash`. A tampered/swapped blob breaks the
  hash. A full decrypt-to-verify-the-tag is redundant (pushed files are
  always decryptable); add it only if a non-vault blob could enter the
  store.
- **Conflict detection** flags only the local-newer-and-remote-diverged
  case. The remote-newer direction can't be detected without hashing
  local content, so a stale local edit overwritten by a pull is silent.
  LWW still resolves both; three-way merge is an explicit non-goal.
- **Tombstones** propagate automatically under LWW (no blocking
  confirmation dialog); the reaped/deleted count is surfaced in the sync
  summary. A pre-delete confirmation prompt is S4 polish.
- **Albums/folders** collection definitions are not synced (S4); file-
  level `albumIds`/`folderId` are carried, and the UI already tolerates
  dangling references.
- **Orphan blob GC** is deferred. When a file's content changes, the new
  blob is uploaded and the manifest points at it, but the *old* blob is
  left on the server (the manifest no longer references it, so nothing
  reaps it). `runSync` never calls `listBlobs`; there is no GC pass yet.
  Add one (reconcile server blobs vs manifest hashes) only if storage
  growth from superseded blobs becomes a real complaint.

### S4 — Polish / scheduling (optional, deferred)

Background sync via WorkManager, conflict-resolution UX, per-album sync
filters, restore-from-server onboarding. Ship S3 first; build S4 only if
the feature gets used.

## Running the live tests

`test/live_webdav_test.dart` covers S0.5 (raw transport: ping, manifest,
nested sharded blob roundtrip, delete, list) and S3.4 (full two-device
two-way `runSync` against the real server, plus tampered-blob rejection).
It is **skipped by default** — it only runs when `LOCKER_LIVE_WEBDAV_URL`
is set, so the normal `flutter test` suite stays hermetic.

To set up a local server (rclone, on all interfaces for physical-device
testing) and the full expected-output reference, see
[`docs/local_server_testing.md`](local_server_testing.md). Quick run against
its canonical `:8080` server:

```sh
LOCKER_LIVE_WEBDAV_URL=http://127.0.0.1:8080 \
LOCKER_LIVE_WEBDAV_USER=locker \
LOCKER_LIVE_WEBDAV_PASS=locker \
flutter test test/live_webdav_test.dart
```

Each run uses a unique `basePath` (`/locker-live-<micros>`) for isolation
and best-effort deletes its blobs after. The `Not Found` debug lines during
the run are expected (absent-blob → null, and the first-sync "no remote
manifest yet" path). A plain `flutter test` (no env) reports the suite
skipped. Expected green run + full per-test breakdown live in
`local_server_testing.md` → *Automated two-way verification (S3.4)*.

## Files

New:

```
lib/models/sync_profile.dart            sync profile (creds in secure storage)    [done]
lib/models/remote_manifest.dart         encrypted manifest schema                 [done]
lib/services/remote/remote_store.dart   transport interface                       [done]
lib/services/remote/webdav_store.dart   WebDAV impl (MKCOLs parent dirs on write) [done]
lib/services/sync_profile_service.dart  secure-storage CRUD for profiles          [done]
lib/services/sync_service.dart          reconcile + runSync (push + two-way pull) [done]
lib/providers/sync_provider.dart        Riverpod status Notifier                  [done]
lib/screens/sync_settings_screen.dart   connection + sync UI                      [done]
test/sync_service_test.dart             behavioral net (reconcile + manifest crypto, 29 tests) [done]
test/webdav_store_test.dart             transport path-logic self-check           [done]
test/live_webdav_test.dart              env-gated live roundtrip: S0.5 + S3.4     [done]
```


Changed:

```
pubspec.yaml                              + webdav_client (1.2.2)                [done]
lib/models/vault_settings.dart            + syncEnabled, syncProfileId           [done]
lib/models/vaulted_file.dart              + modifiedAt, remoteHash, syncedDeleted [done]
lib/services/vault_service.dart           + `store` getter (shares VaultStore w/ Riverpod services) [done]
lib/providers/sync_provider.dart          wires syncServiceProvider + syncProvider [done]
lib/screens/vault_settings_screen.dart    + "Server Sync" entry in Storage section [done]
```

## Dependencies

- **Add:** `webdav_client` v1.2.2 (done).
- **Reuse:** `connectivity_plus`, `flutter_secure_storage`, existing
  `lib/crypto/` — no new crypto code.

## Verification discipline

Per the refactor roadmap's test rules: no per-method suites, one happy-path
test per phase, one failure path for anything security-touching. Each
phase leaves one runnable check (assert-based self-check or a `test_*.dart`)
that fails if the phase's logic breaks. The two-device roundtrip acceptance
test for S3 is `test/live_webdav_test.dart` (env-gated, see above) —
previously a manual step, now scripted; a human spot-check against the real
target NAS is still the final sign-off.

## Open decisions

1. **Protocol scope:** WebDAV only for v1, or SFTP too? WebDAV covers
   ~all NAS/cloud cases; SFTP roughly doubles the transport work.
2. ~~**Staging:** push-only (S2) before two-way (S3), or two-way as the
   first deliverable?~~ **Resolved:** push-only shipped first, two-way
   (S3) layered on top — both now live.
3. **Decoy vault sync:** excluded in v1; confirm the decoy stays
   device-local.
4. **Public WebDAV providers** (e.g. paid WebDAV hosts) allowed, or
   self-hosted only? Technically identical; a wording call for the
   settings screen.
5. **Timing vs. refactor Phase 4:** sync lands Riverpod-native after
   Phase 4. If needed sooner it ships as a singleton and is migrated in
   Phase 4 — slightly more churn.
6. **Orphan blob GC** (new): superseded content blobs linger on the
   server; add a manifest-vs-`listBlobs` reap pass if storage growth
   becomes a complaint (see S3 ceilings).
