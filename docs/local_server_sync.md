# Local Server Sync (WebDAV)

## Overview

The vault is device-local. This document specifies encrypted-at-rest sync to a
user-chosen WebDAV server (NAS, home server, self-hosted cloud), push-only or
two-way. The server never sees plaintext: it is dumb encrypted blob storage.

Status: **Phase 3 complete** (2026-10-06). Streaming transfers, durable
encrypted sync state, review-first conflict recovery, byte progress, and
scoped cancellation land on top of the S0–S3 transport/manifest work. Hermetic
checks: 219 tests passing, `flutter analyze` clean, debug APK builds. The
env-gated live suite and physical-device hardware pass are user-run; see
[`docs/local_server_testing.md`](local_server_testing.md) for server setup and
the Phase 3 hardware guide.

## Goals

- Push the vault to a user-chosen server and pull it back on another device
  or after a wipe, without losing a version to a race.
- The server sees opaque encrypted bytes only.
- Manual sync first; scheduled/background sync later.
- Reuse the existing encrypted file format, manifest schema, and key model —
  no new crypto, and older manifests stay readable.

## Non-goals

- Real-time collaborative sync / CRDT. Diverged files are resolved by explicit
  user review, not automatic merge.
- A hosted cloud account; sync is local / self-hosted only.
- Multiple simultaneous servers (one remote per vault).
- Streaming media playback from the server (sync, not remote mount).
- Payload GC / reaping. Superseded and deleted payloads are retained on both
  sides for recovery; the manifest is the source of truth (see *Retention*).
- Carrying the vault master key through WebDAV. Key continuity is a separate
  concern; see *Key continuity and reinstall*.

## Security model

| Asset | Where | Exposure if server is compromised |
|---|---|---|
| Media ciphertext | Server | Safe. AES-256-GCM/CTR, per-file key derived via PBKDF2 from the master key. Server sees blobs only. |
| Manifest (index, names, tags, albums, folders) | Server, encrypted | Safe: GCM-encrypted with the master key. The raw `vault_file_index` JSON is never uploaded. |
| Server credentials (URL, user, app password) | `flutter_secure_storage` → Android Keystore | Safe; same path as the PIN/master-key wrap. |
| Sync baseline + write-ahead journal | `<vault>/.sync-state/`, encrypted | Safe: AES-GCM with the master key. Contains manifest entries + hashes, no credentials. |
| Explicit deletion records | `flutter_secure_storage` (`locker_sync_deletions`) | Safe: platform-encrypted; ids + timestamps only. |
| Thumbnails | Local only | Re-derivable from the decrypted blob; not synced. |

Hard rules:

- **Plaintext never crosses the network.** `BackupService`'s decrypted ZIP
  stays a local export; it is not a sync transport.
- **The manifest and local sync state are encrypted** with the vault master
  key. The server holds `manifest.enc` plus content-addressed blobs.
- **Credentials live in `flutter_secure_storage`**, never in `VaultSettings`
  JSON or the profile JSON.
- **TLS by default**; WebDAV over plain HTTP on the LAN (self-signed certs,
  `.local` hostnames) is allowed only with an explicit warning, never by
  silent downgrade.
- **No implicit trust in the server.** Pulls verify sha256 of the ciphertext
  against the authenticated manifest before anything enters the vault.
- **No silent unsafe publication.** If the server does not actually honor
  revision preconditions, sync stops with a plain-language error instead of
  risking a lost update.
- **Decoy vault is out of scope** (it leaks its existence, doubles the
  surface). Main vault only.

## Architecture

```
UI ── Riverpod ── SyncProvider (idle · syncing · cancelling · cancelled · success · needsReview · error)
                     │
                     ▼
              SyncService  (instance glue: journal recovery, worker lifecycle,
              │             applying results, persisting baseline/conflicts)
              │  _workerTask (primitive-only capture) → SensitiveIsolate
              ▼
         SyncEngine.run  (three-way reconcile)
         • hash local payloads as streams
         • verify/reuse remote blobs; upload via staging + verify + MOVE
         • pull to temp file + hash verify + atomic move into vault
         • publish encrypted manifest last, with revision precondition
              ┌──────────┴───────────┐
              ▼                      ▼
        VaultStore              StreamingRemoteStore
        local files + index     WebDAVStore (streamed PUT/GET, ETag + MOVE)
```

`SyncEngine` is pure/param-driven and testable with a fake store.
`SyncService` owns persistence and UI-facing orchestration; `SyncProvider`
owns status/progress and cancellation. The legacy byte-array `RemoteStore`
interface remains for older callers/tests; production sync uses
`StreamingRemoteStore`.

### Server layout

```
<basePath>/                     # SyncProfile.basePath, default /locker
  manifest.enc                  # encrypted index + metadata + tombstones
  ab/cd/<64-hex>.enc            # content-addressed encrypted media (sha256 of ciphertext)
  ef/01/<64-hex>.enc
```

Blobs stay content-addressed by ciphertext hash: dedupe across devices, easy
diff (the manifest lists hashes, not paths), and renames/moves are
metadata-only. Transfers temporarily add `<name>.<uuid>.partial` staging
objects between the canonical paths; a compatible server never exposes a
partial body at a canonical name.

### Local layout

```
<vaultRoot>/.sync-state/<targetId>.state     # encrypted baseline + saved conflict choices
<vaultRoot>/.sync-state/<targetId>.journal   # encrypted write-ahead record of a pending commit
```

`targetId = sha256(serverUrl | basePath | username)` (trailing slashes
normalized). Editing or replacing the server/profile resets the baseline
cleanly. Local payload paths are per-file-id
(`<type>/<sha256(id)>_<contentHash>.<ext>`), so two vault entries can never
share one file and deleting a copy cannot break another.

## Protocol and publication safety

WebDAV remains the only transport. Before the first read/publish on a profile,
`WebDAVStore` probes the server (probe objects only — never live vault files):

1. `OPTIONS` must answer `DAV:`; parents are created with idempotent `MKCOL`.
2. A probe file must expose a **strong ETag** (weak/absent is rejected).
3. A `MOVE` must **honor `Overwrite: F`** (collision fails 412/423) — the
   atomic first-creation guard for both publication modes.
4. The server must pass **one** of two guarding probes:
   - **ETag preconditions**: a tagged `MOVE` with the matching
     `If: <etag>` succeeds **and** a mismatched `If` fails 412/423; or
   - **Exclusive locks**: an exclusive `LOCK` excludes a token-less `MOVE`
     (423) and authorizes a token-tagged one. Publication then serializes as
     `LOCK → re-read ETag → guarded MOVE → UNLOCK`, with a 60 s lock timeout
     so a crashed client clears itself.

The manifest is then published as `PUT <temp>` followed by `MOVE` to the
canonical name: `Overwrite: F` for first creation; on replacement the
matching ETag-`If` guard, or the lock guard above. Anything else raises
`UnsafeRemotePublication` (with a safe reason like `missing-dav-capability`,
`missing-strong-etag`, `ignored-publication-precondition`,
`unsupported-publication-guard`) or `RemoteRevisionChanged` on a genuine
race. `readManifest` rejects a manifest with no strong ETag, and only a
confirmed 404 is treated as "no manifest yet"; transport/auth/server errors
propagate instead of being mistaken for a first sync.

rclone — and every Go `x/net/webdav` server — never honors ETag `If`
conditions: it parses bracketed conditions as lock tokens and 412s them. The
probe catches this (the matching-ETag test fails) and falls back to the
verified lock path. If a `LOCK` materializes an empty stub because the
manifest vanished mid-sync, the stub is deleted under the lock before the
sync reports the revision race.

## Sync model

**Three-way, fingerprint-based. The manifest is the commit point.**

- Each side is a map `id → entry` (v2 metadata, including `contentHash` and
  `deleted` tombstones). The encrypted baseline holds the last state both
  sides agreed on.
- Entries are compared by a **content fingerprint** (sha256 of the canonical
  entry JSON, excluding `id`/`modifiedAt`/`dateModified`; tombstones are
  `"deleted"`). Wall-clock timestamps never decide an outcome, so clock skew
  cannot silently pick a winner.
- Reconcile per id:
  - unchanged vs baseline, one side changed → take the changed side
    (push, pull, or tombstone).
  - both sides changed identically → agree.
  - both sides changed differently → **conflict**, nothing written for that
    id until the user resolves it.
  - unknown id only on remote → pull (two-way) / preserve untouched
    (push-only backup).
  - local id missing **and** a recorded deletion exists → push tombstone.
    A missing file with no recorded deletion is *not* a deletion; the remote
    entry (and payload) is preserved.
- **Push-only backup mode** never deletes or overwrites remote-only content:
  remote-only and remotely-changed entries are preserved, and local
  additions/changes are pushed. It is additive backup, not a merge.
- **Conflicts are review-first.** A conflict stores both fingerprints and is
  shown with local/remote metadata and previews. Choices:
  - **Local wins** → push the local version.
  - **Remote wins** → pull the remote version.
  - **Keep both** (only when both sides are live) → the remote version stays
    at the original id; the local bytes are copied, hash-verified, into a
    separate per-id path and a new entry gets a deterministic UUIDv5 derived
    from `id:local-fingerprint:remote-fingerprint` and a `(local copy)` name.
  - **Later** → leave unresolved; the next run reports it again.
  A saved choice is honored only if both current fingerprints still match the
  ones recorded at decision time; otherwise the conflict is re-raised.
- **Deletion recording.** A successful delete in the vault registers the id
  in `locker_sync_deletions` before the index entry is removed. Failed
  deletions keep their entry (Phase 0 behavior) and register nothing.
- **Commit ordering and recovery.** Every transfer finishes before commit;
  the journal (with the checkpoint, affected local/refreshed entries, and the
  expected manifest hash) is encrypted to disk, then `manifest.enc` is
  published with the revision guard. The local index is applied
  snapshot-aware and saved **strictly**: if the index write fails, the
  baseline is not advanced and the journal stays. On the next `syncNow`, if
  the remote manifest still matches the journal's hash, the journal is
  replayed exactly; otherwise the journal is left until the next worker run
  rewrites it, and the conservative baseline plus retained payloads keep
  both versions safe.
- **Cancellation** is cooperative between files and mid-transfer (network
  token + hash/stream checks). Cancel is ignored only during the brief commit
  step; locking the vault still hard-kills the worker. A cancelled or killed
  run leaves the previous manifest and every payload intact; a retry resumes
  and reuses already-verified blobs. Download scratch lives under
  `<vault>/temp` and is cleaned up; vault lock clears leftover scratch too.

### Progress

`SyncProgress` carries the phase, current file name, per-file and overall byte
counts (or `-1` when the server does not report a length), and file counts.
The UI renders a per-file bar or a file ratio, whichever the server supports,
and shows "checking files" / "finishing safely" for hash and commit phases.

### Retention

Superseded blobs and tombstones keep their payloads on both sides. Remote
deletes are logical (manifest tombstones); local deletes remove the index
entry but the file is only removed by an explicit user delete. Nothing in the
sync path calls `DELETE` on a canonical blob. This is a deliberate
data-recovery trade-off; reclaiming space is out of scope until a safe GC
design exists.

## Key continuity and reinstall

The vault master key is random per device and is **not** uploaded by WebDAV.
The PIN/password only wraps it. Therefore:

- **The server alone cannot restore the vault to a fresh device.** Two
  devices with the same password still have different master keys.
- To use sync on a new device, restore key continuity first with **Restore
  from desktop** (the desktop snapshot carries a key bundle; the *original*
  vault credential unlocks it) or port the vault via a Desktop backup.
  After the key is installed, server sync pulls and decrypts normally.
- **Uninstall / "clear app data" is controlled by the OS and cannot be
  blocked by the app.** It deletes the app-private vault, the wrapped key in
  secure storage, and the local sync baseline. The safety net is an external
  copy — Desktop backup/restore, a local ZIP backup kept outside app-private
  storage, and the encrypted server copy — plus the original credential.
  Settings → Storage and Settings → Server sync repeat this guidance, and the
  app steers backups away from app-private directories.

## Running the live tests

`test/live_webdav_test.dart` covers the raw transport roundtrip and the full
two-device two-way run against a real server, including retained payloads,
manifest tombstones, and tampered-blob rejection. It is **skipped by
default**; it runs only when `LOCKER_LIVE_WEBDAV_URL` is set, so the normal
`flutter test` suite stays hermetic. Server setup, expected behavior, and the
Phase 3 hardware guide live in
[`docs/local_server_testing.md`](local_server_testing.md).

A clean run prints `[Latch] {...}` JSON diagnostics for sync commits; any
failure prints `[Latch][<error-id>] ...` lines that can be copied for a bug
report. Credentials, URLs, and filenames are never logged.

## Files

Core sync path (Phase 3 additions marked **new**):

```
lib/models/sync_profile.dart                 profile (creds in secure storage)
lib/models/remote_manifest.dart              manifest schema (v2, v1-compatible)
lib/models/sync_conflict.dart            new conflict model + fingerprint
lib/services/remote/remote_store.dart        RemoteStore + StreamingRemoteStore interfaces
lib/services/remote/webdav_store.dart        WebDAV impl (streaming, ETag/MOVE, capability probe)
lib/services/remote/server_errors.dart       plain-language error mapping
lib/services/sync_service.dart               glue: journal recovery, apply, persistence
lib/services/sync_engine.dart            new three-way reconcile + transfer engine
lib/services/sync_state_store.dart       new encrypted baseline/journal/deletions
lib/services/sync_control.dart           new cancellation token wrapper
lib/services/diagnostics.dart            new copyable, redacted release diagnostics
lib/services/sync_profile_service.dart       secure-storage CRUD for profiles
lib/providers/sync_provider.dart             Riverpod status/progress/cancel Notifier
lib/screens/sync_settings_screen.dart        connection + sync + conflict-review UI
```

Tests:

```
test/sync_service_test.dart          reconcile + manifest + two-device behavior
test/phase3_sync_test.dart       new conflict/interruption/recovery/worker coverage
test/webdav_streaming_test.dart  new loopback WebDAV fixture + full syncNow/worker test
test/sync_state_store_test.dart  new encrypted state + deletions coverage
test/webdav_store_test.dart          transport path-logic self-check
test/live_webdav_test.dart           env-gated live roundtrip + two-device + tamper
```

## Dependencies

- `webdav_client` v1.2.2 (existing), `dio`, `crypto`, `flutter_secure_storage`,
  `connectivity_plus` — no new packages, and no new crypto code beyond reusing
  the existing AES-GCM envelope.

## Verification discipline

Hermetic coverage is the default: streamed transfers, publication
preconditions, cancellation, conflict outcomes, journaled recovery, and
worker isolation are all asserted in `flutter test`. The env-gated
`test/live_webdav_test.dart` exercises a real server but stays out of the
default run. A physical-device pass (large files, cancel/retry, lock mid-sync,
conflict review, real-server capability probing) remains the release sign-off
and is scripted in `docs/local_server_testing.md`.

## Open decisions

1. **Protocol scope:** WebDAV only for v1, or SFTP too? WebDAV covers
   ~all NAS/cloud cases; SFTP roughly doubles the transport work.
2. **Public WebDAV providers** (paid hosts) allowed, or self-hosted only?
   Technically identical; a wording call for the settings screen.
3. **GC design:** payload retention is intentional. If storage growth
   becomes a complaint, design a reviewable reap pass (manifest-aware, never
   touching tombstoned or baseline-referenced blobs) rather than an automatic
   delete.
4. **Album/folder collection definitions** are still not synced (file-level
   ids are carried; dangling references are tolerated).
