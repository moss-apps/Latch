# Local Server / Local Cloud Sync — Plan

Born from the request to add a self-hosted sync target (NAS, home server, or
self-hosted cloud) to Latch. Today the vault is device-local with a manual
*decrypted* ZIP backup (`BackupService`). This plan defines an
**encrypted-at-rest** sync to a server on the LAN or internet.

Status: **IN PROGRESS** — S0 (transport + creds), S1 (manifest crypto), and the
S2.1 reconcile engine are implemented and unit-tested (90 tests green).
Pending: S0.4 connection UI, S1.4/S2.2 sync execution (`runSync`), S2.3–S2.5
provider/guard/UI. Locked decisions are marked **[LOCKED]**; open ones are
marked **[OPEN]** and listed again at the bottom.

---

## Goals

- Push the vault to a user-chosen server (NAS / home server / self-hosted cloud)
  and pull it back on a new device or after a wipe.
- The server **never** sees plaintext. It is dumb encrypted blob storage.
- Manual sync first; optional scheduled/background sync later.
- Reuse the existing encrypted file format and key model — **no new crypto**.

## Non-goals (YAGNI)

- Real-time collaborative sync / CRDT. (Last-write-wins per file is enough.)
- A Latch-hosted cloud account. (This is *local* / self-hosted only.)
- Syncing to multiple servers simultaneously. (One remote per vault, for now.)
- Streaming media playback *from* the server. (Sync, not remote mount.)

---

## Locked decisions

1. **[LOCKED] End-to-end encrypted on the server.** Files already live in the
   vault as `[magic][IV][ciphertext][auth tag]`. We sync those exact encrypted
   blobs. The manifest (index + metadata) is encrypted with the vault master
   key before upload. The server sees opaque bytes only. This is the opposite
   of the current `BackupService`, which builds a **decrypted** ZIP — that
   behavior must **not** be carried over to the server path.

2. **[LOCKED] WebDAV is the only protocol in v1.** It is plain HTTP, every
   NAS / Nextcloud / Synology / ownCloud / Seafile exposes it, and it needs
   one package. SMB and SFTP are deferred (see "Protocol choice").

3. **[LOCKED] Server is dumb blob storage.** A thin sync client in the app
   does all the logic. No server-side app to build or ship.

4. **[LOCKED] Reuse `connectivity_plus`** (already a dep, used in
   `update_service.dart`) for the "only on Wi-Fi / only when connected"
   guard. No new network-detection code.

5. **[LOCKED] Sync service lands as Riverpod-native**, not a new singleton.
   Per the refactor roadmap, Phase 4 (Riverpod modernization, drops the 12
   `instance` singletons) is pending. This service should land **after** (or
   alongside) Phase 4 so we don't add a 13th singleton we then have to remove.
   It takes `VaultStore` + `EncryptionService` via constructor, like the
   Phase 2 services.

   Current state: `SyncService` exists but holds only **pure static logic**
   (`blobNameFor`, `reconcile`, `buildManifest`, manifest encrypt/decrypt). It
   is not registered anywhere — no singleton, no provider — so the locked
   decision stands for the stateful `runSync` orchestration.

---

## Threat model & security

This is the part that matters most for a vault.

| Asset | Where | Exposure if server is compromised |
|---|---|---|
| Media ciphertext | Server | **Safe.** AES-256-GCM/CTR, per-file key derived via PBKDF2 from the master key. Server sees blobs only. |
| Manifest (index + names + tags + albums + folders) | Server (encrypted) | **Safe if** encrypted with master key before upload. **Critical:** never upload the raw `vault_file_index` JSON. |
| Server credentials (URL, user, app password) | `flutter_secure_storage` → Android Keystore | Safe (same path as the PIN/master-key wrap). |
| Thumbnails | **Local only** v1 | Re-derivable on pull from the decrypted blob. Not synced. |

Hard rules:

- **Plaintext never crosses the network.** No "decrypted ZIP to server" path.
  (Contrast: `BackupService` today decrypts to a ZIP — keep that for the
  *local export* feature only; it must not be reused as the sync transport.)
- **The manifest is encrypted** with the vault master key (the same one
  wrapped by Argon2id on-device). The server holds `manifest.enc`.
- **Credentials in `flutter_secure_storage`, never in `VaultSettings` JSON**
  (which is itself stored in secure storage but should stay settings, not
  secrets).
- **TLS by default**, but WebDAV over plain HTTP on the LAN must be
  explicitly allowed (self-hosted, self-signed certs, `.local` hostnames).
  Present a clear "unencrypted connection" warning, do not silently downgrade.
- **No implicit trust of server state.** Pull must verify GCM auth tags on
  every blob before trusting it (corruption / tampering detection we already
  have for re-encryption).
- **Decoy vault is out of scope for v1 sync.** Syncing the decoy would leak
  its existence and double the surface. Main vault only. Revisit later.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                          UI                                   │
│   Sync Settings screen · Sync Status chip · Sync Now button  │
└──────────────────────────┬────────────────────────────────────┘
                           │ Riverpod
┌──────────────────────────▼────────────────────────────────────┐
│                    SyncProvider (Notifier)                     │
│   exposes status (idle/uploading/downloading/error) + lastSync │
└──────────────────────────┬────────────────────────────────────┘
                           │
┌──────────────────────────▼────────────────────────────────────┐
│                      SyncService                               │
│  reconcile(): diff local vs remote manifest → plan → execute   │
│  • push encrypted blobs (new/changed local)                    │
│  • pull encrypted blobs (new/changed remote)                   │
│  • tombstone deletes                                           │
│  • write encrypted manifest last (commit point)                │
└──────┬───────────────────────┬─────────────────────────────────┘
       │                       │
       ▼                       ▼
┌──────────────┐      ┌────────────────────┐
│ VaultStore   │      │ RemoteStore        │
│ (exists)     │      │ (WebDAV transport) │
│ local files, │      │ getManifest /      │
│ local index  │      │ putManifest /      │
│              │      │ getBlob / putBlob /│
│              │      │ deleteBlob /       │
│              │      │ listBlobs         │
└──────────────┘      └─────────┬──────────┘
                                │ HTTP
                         ┌──────▼──────┐
                         │ WebDAV server│
                         │ (NAS/cloud)  │
                         └──────────────┘
```

`SyncService` is the brain; `RemoteStore` is a thin transport abstraction
(one interface, one WebDAV impl). The interface exists so SFTP/SMB can be
added later behind the same `SyncService` — but only one impl ships now.

### Server layout (what the user's NAS holds)

```
<basePath>/                     # SyncProfile.basePath, default /locker
  manifest.enc                  # encrypted index + metadata + tombstones
  ab/cd/abcd1234…enc            # content-addressed encrypted media (sha256 of ciphertext)
  ef/01/ef019876…enc
  manifest.enc.sig              # [OPEN] GCM tag already authenticates; separate sig = YAGNI for v1
```

Content-addressing the blobs by hash of the **ciphertext** gives us:
dedupe (identical ciphertext across devices), easy diff (manifest lists
hashes, not paths), and trivial rename/move (metadata-only change, blob
unchanged). This is the same trick every content-addressed backup uses.

---

## Protocol choice

| Protocol | Verdict | Why |
|---|---|---|
| **WebDAV** | **v1** | HTTP. Every NAS/cloud speaks it. One package. `MKCOL`/`PUT`/`GET`/`DELETE`/`PROPFIND` is the whole API. |
| SFTP | Deferred | Needs a heavy SSH client package (`dartssh2`); adds key management. Add only if asked. |
| SMB | Deferred | jCIFS port on Android is fragile. Not worth it. |
| Custom HTTP server | Rejected | Violates locked decision #3 (server stays dumb). |

Dependency: **`webdav_client`** (pub.dev). One package. Falls back to raw
`package:http` + `PROPFIND` if its API is awkward, but try the package first.

---

## Sync model

**Last-write-wins per file, manifest-as-commit-point.**

- Each `VaultedFile` already has a UUID `id` and we can add a `modifiedAt`
  / `syncRev` field (see data changes). The manifest maps `id → {hash,
  modifiedAt, deleted}`.
- **Reconcile** = compare local manifest vs remote manifest by id:
  - remote has id, local doesn't, not tombstoned → **pull**
  - local has id, remote doesn't → **push**
  - both have it, hashes differ → newer `modifiedAt` wins; loser is
    overwritten. (No three-way merge v1 — YAGNI. Flag a conflict note in UI
    if both changed since last sync.)
  - either side tombstoned (deleted) → propagate delete.
- **Manifest is the commit point.** Upload/download all blobs first; the
  manifest write is atomic-ish (PUT replaces the whole file). If we crash
  mid-sync, the old manifest still describes a consistent older state and
  the next run resumes. Re-running sync is always safe (idempotent).
- **No partial-file sync.** Files are atomic units. A video is fully
  re-pushed on change (it's encrypted; no delta possible anyway).

Direction control (setting):
- **Push only** (backup to server) — simplest, recommended default.
- **Two-way** (sync) — enable after push-only is proven.

---

## Data & config changes

- **New model:** `SyncProfile` (URL, username, base path, lastSyncAt,
  syncDirection, wifiOnly) — stored in `flutter_secure_storage` as JSON.
  Not in `VaultSettings` (keeps settings free of secrets). **DONE** — plus
  `SyncProfileService` CRUD with per-profile password keys
  (`sync_profile_pw_<id>`); passwords never live in the profile JSON.
- **`VaultSettings` additions:** `bool syncEnabled = false`,
  `String? syncProfileId`. **DONE** (`toJson`/`fromJson`/`copyWith`).
- **`VaultedFile` additions:** `DateTime? modifiedAt`, `String? remoteHash`,
  `bool syncedDeleted = false` (tombstone flag). **DONE**. Migration on load
  (missing `modifiedAt` → file mtime) **PENDING** — lands with the VaultStore
  manifest helpers.
- **New:** `RemoteManifest` model (`version`, `deviceId`, `generatedAt`,
  `entries: [{id, contentHash, modifiedAt, deleted}]`). **DONE**.

---

## Phased plan

Phases are ordered by dependency. Each is independently shippable.

### Phase S0 — Transport + creds (no sync logic) — ~1-2 days

| # | Task | Location |
|---|---|---|
| [x] S0.1 | Add `webdav_client` dep (1.2.2) | `pubspec.yaml` |
| [x] S0.2 | `RemoteStore` interface + WebDAV impl: `ping`, `getManifest`, `putManifest`, `getBlob`, `putBlob`, `deleteBlob`, `listBlobs` | `lib/services/remote/` |
| [x] S0.3 | `SyncProfile` model + secure-storage CRUD | `lib/models/sync_profile.dart`, `lib/services/sync_profile_service.dart` |
| [ ] S0.4 | Connection settings UI: URL/user/password, "Test connection" button, TLS warning for plain HTTP | `lib/screens/sync_settings_screen.dart` (new) |
| [~] S0.5 | One runnable self-check: connect to a WebDAV URL, put/get a tiny blob, assert roundtrip — so far only path/URL-logic unit tests (`test/webdav_store_test.dart`); live-server roundtrip pending | test or `__main__`-style check |

**Verify:** connect to a real WebDAV server (Nextcloud demo or local
`rclone serve webdav`), roundtrip a blob. Credentials persist across restart.

### Phase S1 — Encrypted manifest — ~1-2 days

| # | Task | Location |
|---|---|---|
| [x] S1.1 | `RemoteManifest` model + JSON (de)serialize | `lib/models/remote_manifest.dart` |
| [~] S1.2 | Build manifest from `VaultStore` index; encrypt with master key; decrypt on read — `buildManifest` + `encryptManifest`/`decryptManifest` done (pure, tested); VaultStore index wiring pending | `SyncService.buildManifest` / `readManifest` |
| [x] S1.3 | Content-address blob naming (sha256 of ciphertext, sharded `ab/cd/`) | `SyncService.blobNameFor` |
| [ ] S1.4 | Push/pull manifest only (no blobs yet) — proves the crypto + transport glue | extends S0 |

**Verify:** upload encrypted manifest, wipe local, pull manifest back,
decrypt, assert it equals the original index. Plaintext never leaves device
(confirmed by inspecting server).

### Phase S2 — Push-only backup — ~2-3 days

| # | Task | Location |
|---|---|---|
| [x] S2.1 | `reconcile()` diff engine (local vs remote manifest) → plan (push/pull/delete lists) — covers tombstone deletion and two-way pull cases | `SyncService.reconcile` |
| [ ] S2.2 | Execute push plan: upload new/changed blobs, then commit manifest | `SyncService.runSync` |
| [ ] S2.3 | `SyncProvider` (Riverpod Notifier): status enum, progress, `syncNow()` | `lib/providers/sync_provider.dart` |
| [ ] S2.4 | `connectivity_plus` guard: respect wifiOnly / connected; resubscribe like `update_service.dart:74` | `SyncService` / provider |
| [ ] S2.5 | UI: status chip + "Sync now" in settings; progress reporting | sync settings screen + a drawer entry |
| [~] S2.6 | One behavioral test: seed vault, sync, assert every local file has a remote blob + manifest lists it — reconcile/crypto tests in place; seed-vault behavioral test pending | `test/sync_service_test.dart` |

**Verify:** fill vault, push to server, inspect server (all opaque `.enc`),
wipe app data, reinstall → pull restores the vault intact (decrypt +
auth-tag verify per file).

### Phase S3 — Two-way sync — ~2-3 days

| # | Task | Location |
|---|---|---|
| S3.1 | Pull path: download missing/changed blobs, verify GCM auth tag, import into `VaultStore` | `SyncService` pull branch |
| S3.2 | Last-write-wins resolution + conflict UI note when both sides changed | `reconcile` |
| S3.3 | Tombstone propagation (delete on one device → delete on other, with a confirmation) | `reconcile` + UI |
| S3.4 | Two-device roundtrip test | manual + scripted |

**Verify:** device A adds files → sync → device B pulls them; device B
edits → sync → device A sees edit; delete on A → propagates to B.

### Phase S4 — Polish / scheduling (optional) — defer

Background sync via WorkManager, conflict-resolution UX, per-album sync
filters, restore-from-server onboarding flow. Ship S3 first; only build S4
if the feature gets used.

---

## New files

```
lib/models/sync_profile.dart            sync profile (creds live in secure storage)           [x]
lib/models/remote_manifest.dart         encrypted manifest schema                             [x]
lib/services/remote/remote_store.dart   transport interface                                   [x]
lib/services/remote/webdav_store.dart   WebDAV impl                                           [x]
lib/services/sync_profile_service.dart  secure-storage CRUD for profiles                      [x]
lib/services/sync_service.dart          reconcile + runSync (pure logic done, runSync pending)[~]
lib/providers/sync_provider.dart        Riverpod status Notifier                             [ ]
lib/screens/sync_settings_screen.dart   connection + sync UI                                 [ ]
test/sync_service_test.dart             behavioral net (reconcile + manifest crypto now)      [x]
test/webdav_store_test.dart             transport path-logic self-check (S0.5, partial)       [x]
```

## Files changed

```
pubspec.yaml                              + webdav_client (1.2.2)              [x]
lib/models/vault_settings.dart            + syncEnabled, syncProfileId         [x]
lib/models/vaulted_file.dart              + modifiedAt, remoteHash, syncedDeleted [x]
lib/services/vault_store.dart             manifest build/read helpers, blob hashing [ ]
lib/providers/vault_providers.dart        wire SyncProvider after Phase 4 lands [ ]
main.dart / drawer                        entry point to sync settings          [ ]
```

---

## Dependencies

- **Add:** `webdav_client` (one package) — **done**, v1.2.2.
- **Reuse:** `connectivity_plus` (already present), `flutter_secure_storage`
  (already present), existing `lib/crypto/` (no new crypto code).

## Verification discipline

Per the refactor roadmap's test rules: no per-method suites, one happy-path
test per phase, one failure path for anything security-touching. Each phase
leaves one runnable check (assert-based `__main__` or a `test_*.dart`) that
fails if the phase's logic breaks. Manual two-device roundtrip is the real
acceptance test for S3.

---

## Open questions (need your call)

1. **[OPEN] Protocol scope:** WebDAV-only for v1 (this plan), or do you want
   SFTP in scope too? WebDAV covers ~all NAS/cloud cases; SFTP roughly
   doubles the transport work.
2. **[OPEN] Push-only first vs. two-way from day one:** this plan ships
   push-only (Phase S2) before two-way (S3). OK with that staging, or do you
   want two-way as the first deliverable?
3. **[OPEN] Decoy vault sync:** explicitly excluded in v1 (security). Confirm
   you're fine leaving the decoy device-local.
4. **[OPEN] Self-hosted only, or allow a public WebDAV provider too** (e.g.,
   a paid WebDAV host)? Technically identical; just a policy / wording call
   for the settings screen.
5. **[OPEN] Timing vs. refactor Phase 4:** this plan assumes sync lands
   Riverpod-native (after Phase 4). If you want it sooner, it'll ship as a
   singleton and get migrated in Phase 4 — slightly more churn.
