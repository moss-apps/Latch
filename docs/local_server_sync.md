# WebDAV sync

## What it does

The vault lives on your device. Latch can also sync it to a WebDAV server you
choose: a NAS, a home server, or self-hosted cloud. You can run push-only
backups or two-way sync.

The manifest is encrypted, but payloads go over the wire **as stored**. Encrypted
files stay encrypted. Hidden files that were never encrypted stay plaintext on
the server. If that matters, turn on file encryption before importing, and use
HTTPS.

Sync is built and working: streaming transfers, encrypted sync state,
review-first conflict recovery, byte progress, and scoped cancellation. The
Flutter suite and analysis pass, and debug APKs build. The live suite and the
physical-device pass are still user-run; see
[local_server_testing.md](local_server_testing.md). Hardware sign-off is pending.

## Goals

- Push the vault to a server you choose, and pull it back on another device or
  after a wipe, without losing a version to a race.
- Keep the manifest encrypted and preserve each file's encryption state.
- Manual sync first; scheduled or background sync later.
- Reuse the existing file format, manifest schema, and key model. No new crypto,
  and older manifests still work.

## What it doesn't do

- Real-time collaborative sync or CRDT. Diverged files go to explicit user
  review, not automatic merge.
- Hosted cloud accounts. Sync is local or self-hosted only.
- Multiple servers at once. One remote per vault.
- Streaming media from the server. This is sync, not a remote mount.
- Remote payload garbage collection. Superseded and deleted remote blobs are
  kept. Explicit local deletions follow Recently Deleted; see *Retention* below.
- Carrying the vault master key over WebDAV. Key continuity is separate; see
  *Key continuity and reinstall*.

## Security model

| Asset | Where it lives | What happens if the server is compromised |
|---|---|---|
| Media ciphertext | Server | Safe. AES-256-GCM/CTR, with a per-file key derived by PBKDF2 from the master key. The server sees blobs only. |
| Hidden, unencrypted payloads | Server, as stored | Readable by the server. Hiding isn't encryption, and HTTPS protects transit, not server storage. |
| Manifest (index, names, tags, albums, folders) | Server, encrypted | Safe: GCM-encrypted with the master key. The raw `vault_file_index` JSON is never uploaded. |
| Server credentials (URL, user, app password) | `flutter_secure_storage` → Android Keystore | Safe; same path as the PIN/master-key wrap. |
| Sync baseline + write-ahead journal | `<vault>/.sync-state/`, encrypted | Safe: AES-GCM with the master key. Contains manifest entries and hashes, no credentials. |
| Explicit deletion records | `flutter_secure_storage` (`locker_sync_deletions`) | Safe: platform-encrypted, IDs and timestamps only. |
| Thumbnails | Local only | Re-derivable from the decrypted blob; not synced. |

What keeps this safe:

- **Sync doesn't decrypt or encrypt payloads.** Hidden, unencrypted files cross
  the network as plaintext unless TLS protects them. `BackupService`'s decrypted
  ZIP is a local export, not a sync transport.
- **The manifest and local sync state are encrypted** with the vault master key.
  The server holds `manifest.enc` plus content-addressed blobs.
- **Credentials live in `flutter_secure_storage`**, never in `VaultSettings` JSON
  or the profile JSON.
- **TLS by default.** WebDAV over plain HTTP on a LAN (self-signed certs, `.local`
  hostnames) is allowed only with an explicit warning. No silent downgrade.
- **Don't trust the server.** Pulls verify the SHA-256 of the stored payload
  against the authenticated manifest before anything enters the vault.
- **Don't publish unsafely.** If the server doesn't actually honor revision
  preconditions, sync stops with a plain-language error instead of risking a lost
  update.
- **The decoy vault is out of scope.** It leaks its existence and doubles the
  attack surface. Main vault only.

## How the pieces fit

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

`SyncEngine` is pure and parameter-driven, so it can be tested with a fake
store. `SyncService` owns persistence and UI-facing orchestration.
`SyncProvider` owns status, progress, and cancellation. The old byte-array
`RemoteStore` interface stays for older callers and tests; production sync uses
`StreamingRemoteStore`.

### Server layout

```
<basePath>/                     # SyncProfile.basePath, default /locker
  manifest.enc                  # encrypted index + metadata + tombstones
  ab/cd/<64-hex>.enc            # sha256 of stored payload; suffix does not imply encryption
  ef/01/<64-hex>.enc
```

Blobs are content-addressed by the hash of the stored payload, which dedupes
across devices, makes diffs easy (the manifest lists hashes, not paths), and
turns renames and moves into metadata-only changes. Transfers temporarily add
`<name>.<uuid>.partial` staging objects between the canonical paths; a compatible
server never exposes a partial body at a canonical name.

### Local layout

```
<vaultRoot>/.sync-state/<targetId>.state     # encrypted baseline + saved conflict choices
<vaultRoot>/.sync-state/<targetId>.journal   # encrypted write-ahead record of a pending commit
```

`targetId = sha256(serverUrl | basePath | username)`, with trailing slashes
normalized. Editing or replacing the server profile resets the baseline cleanly.
Local payload paths are per file ID
(`<type>/<sha256(id)>_<contentHash>.<ext>`), so two vault entries can't share one
file and deleting a copy can't break another.

## Publication checks

WebDAV is still the only transport. Before the first read or publish on a
profile, `WebDAVStore` probes the server with probe objects only, never live vault
files:

1. `OPTIONS` must answer `DAV:`. Parents are created with idempotent `MKCOL`.
2. A probe file must expose a **strong ETag**. Weak or absent ETags are rejected.
3. A `MOVE` must **honor `Overwrite: F`**, so a collision fails with 412/423.
   That's the atomic first-creation guard for both modes.
4. The server must pass **one** of two guarding probes:
   - **ETag preconditions:** a tagged `MOVE` with the matching `If: <etag>`
     succeeds, and a mismatched `If` fails 412/423; or
   - **Exclusive locks:** an exclusive `LOCK` blocks a token-less `MOVE` (423)
     and authorizes a token-tagged one. Publication then serializes as
     `LOCK → re-read ETag → guarded MOVE → UNLOCK`, with a 60 s lock timeout so
     a crashed client clears itself.

The manifest is published as `PUT <temp>` then `MOVE` to the canonical name:
`Overwrite: F` for first creation, and the matching ETag `If` guard or the lock
guard for replacement. Anything else raises `UnsafeRemotePublication` with a
reason such as `missing-dav-capability`, `missing-strong-etag`,
`ignored-publication-precondition`, or `unsupported-publication-guard`, or
`RemoteRevisionChanged` on a real race. `readManifest` rejects a manifest with no
strong ETag, and only a confirmed 404 means "no manifest yet"; transport, auth,
and server errors propagate instead of looking like a first sync.

rclone, and every Go `x/net/webdav` server, never honors ETag `If` conditions:
they parse bracketed conditions as lock tokens and return 412. The probe catches
that (the matching-ETag test fails) and falls back to the verified lock path. If a
`LOCK` creates an empty stub because the manifest vanished mid-sync, the stub is
deleted under the lock before the sync reports the revision race.

## How sync decides

**Three-way, fingerprint-based. The manifest is the commit point.**

- Each side is a map `id → entry` (v2 metadata, including `contentHash` and
  `deleted` tombstones). The encrypted baseline holds the last state both sides
  agreed on.
- Entries are compared by a **content fingerprint**: SHA-256 of the canonical
  entry JSON, excluding `id`, `modifiedAt`, and `dateModified`. Tombstones are
  `"deleted"`. Wall clocks never decide an outcome, so clock skew can't silently
  pick a winner.
- Per ID:
  - unchanged against the baseline, one side changed → take the changed side
    (push, pull, or tombstone).
  - both sides changed the same way → agree.
  - both sides changed differently → **conflict**. Nothing is written for that
    ID until the user decides.
  - unknown ID only on the remote → pull in two-way mode, preserve untouched in
    push-only backup.
  - local ID missing **and** a recorded deletion exists → push a tombstone. A
    missing file with no deletion record is not a deletion; the remote entry and
    payload are preserved.
- **Push-only backup never deletes or overwrites remote-only content.** Remote-only
  and remotely changed entries are preserved; local additions and changes are
  pushed. It's additive backup, not a merge.
- **Conflicts are review-first.** A conflict stores both fingerprints and shows
  local/remote metadata and previews. The choices:
  - **Local wins** → push the local version.
  - **Remote wins** → pull the remote version.
  - **Keep both** (only when both sides are live) → the remote version stays at
    the original ID; the local bytes are copied and hash-verified into a separate
    per-ID path, and a new entry gets a deterministic UUIDv5 derived from
    `id:local-fingerprint:remote-fingerprint` and a `(local copy)` name.
  - **Later** → leave it unresolved; the next run reminds you.
  A saved choice only applies if both current fingerprints still match the ones
  from decision time; otherwise the conflict comes back. If the local ID is in
  Recently Deleted, restore it or permanently delete the retained copy before
  choosing Remote or Keep both. Sync can't quietly pull a same-ID version behind
  the recovery receipt.
- **Deletion recording.** A local delete saves a recovery receipt first, then
  records the ID in `locker_sync_deletions` before moving payloads or removing
  index/editor records. An interrupted operation stays hidden behind that receipt
  and retries on unlock/resume. Sync also uses receipt timestamps as deletion
  evidence if the separate tombstone write was interrupted. If the first receipt
  can't be saved, the active entry and bytes stay untouched. A remote-only ID
  with deletion evidence but no agreed baseline goes to review instead of being
  silently re-imported or deleted.
- **Commit ordering and recovery.** Every transfer finishes before commit. The
  journal (checkpoint, affected local/refreshed entries, expected manifest hash)
  is encrypted to disk, then `manifest.enc` is published with the revision guard.
  The local index is applied snapshot-aware and saved **strictly**: if the index
  write fails, the baseline doesn't advance and the journal stays. On the next
  `syncNow`, if the remote manifest still matches the journal hash, the journal is
  replayed exactly. Otherwise it's left until the next worker run rewrites it,
  and the conservative baseline plus retained payloads keep both versions safe.
- **Cancellation** is cooperative between files and mid-transfer (network token
  plus hash/stream checks). Cancel is ignored only during the brief commit step;
  locking the vault still hard-kills the worker. A cancelled or killed run leaves
  the previous manifest and every payload intact. A retry resumes and reuses
  already-verified blobs. Download scratch lives under `<vault>/temp` and is
  cleaned up; locking the vault clears leftover scratch too.

### Progress

`SyncProgress` carries the phase, current file name, per-file and overall byte
counts (`-1` when the server doesn't report a length), and file counts. The UI
shows a per-file bar or a file ratio, whichever the server supports, and says
"checking files" or "finishing safely" during hash and commit phases.

### Retention

Remote deletes are logical manifest tombstones. Nothing in the sync path calls
`DELETE` on a canonical remote blob; superseded remote versions stick around
until there's a separate safe GC policy. A server-originated tombstone also keeps
the previous local payload under the current policy; it doesn't automatically go
into Recently Deleted.

Explicit **local user deletions** follow the
[Recently Deleted policy](recently_deleted.md): 30 days by default, configurable
to 7/30/90 days or immediate deletion. Local expiry and permanent deletion remove
the retained local payload and thumbnail, not remote blobs or existing backups.
Cleanup runs while unlocked and on unlock/resume; it isn't a guaranteed OS
background job. Restoring clears local deletion evidence, keeps bytes and key
metadata, and records restore intent for the next manual sync. Divergence against
a remote edit or deletion still goes to review.

## Key continuity and reinstall

The vault master key is random per device and WebDAV never uploads it. The
PIN/password only wraps it. So:

- **The server alone can't restore the vault to a fresh device.** Two devices with
  the same password still have different master keys.
- To use sync on a new device, restore key continuity first with **Restore from
  desktop** (the desktop snapshot carries a key bundle, and the **original**
  credential unlocks it), or move the vault with a desktop backup. After the key
  is installed, server sync pulls and decrypts normally.
- **Uninstall and "clear app data" are controlled by the OS.** The app can't block
  them. They delete the app-private vault, the wrapped key in secure storage, and
  the local sync baseline. Your safety net is an external copy (desktop backup,
  a local ZIP kept outside app-private storage, and the encrypted server copy)
  plus the original credential. Settings → Storage and Settings → Server sync
  repeat this, and the app steers backups away from app-private directories.

## Running the live tests

`test/live_webdav_test.dart` covers the raw transport round trip and the full
two-device two-way run against a real server, including retained payloads,
manifest tombstones, and tampered-blob rejection. It's **skipped by default** and
only runs when `LOCKER_LIVE_WEBDAV_URL` is set, so normal `flutter test` stays
hermetic. Server setup, expected behavior, and the hardware checklist are in
[local_server_testing.md](local_server_testing.md).

A clean run prints `[Latch] {...}` JSON diagnostics for sync commits. Failures
print `[Latch][<error-id>] ...` lines you can copy into a bug report. Credentials,
URLs, and filenames are never logged.

## Files

Core sync path:

```
lib/models/sync_profile.dart                 profile (creds in secure storage)
lib/models/remote_manifest.dart              manifest schema (v2, v1-compatible)
lib/models/sync_conflict.dart                conflict model + fingerprint
lib/services/remote/remote_store.dart        RemoteStore + StreamingRemoteStore interfaces
lib/services/remote/webdav_store.dart        WebDAV impl (streaming, ETag/MOVE, capability probe)
lib/services/remote/server_errors.dart       plain-language error mapping
lib/services/sync_service.dart               glue: journal recovery, apply, persistence
lib/services/sync_engine.dart                three-way reconcile + transfer engine
lib/services/sync_state_store.dart           encrypted baseline/journal/deletions
lib/services/sync_control.dart               cancellation token wrapper
lib/services/diagnostics.dart                copyable, redacted release diagnostics
lib/services/sync_profile_service.dart       secure-storage CRUD for profiles
lib/providers/sync_provider.dart             Riverpod status/progress/cancel Notifier
lib/screens/sync_settings_screen.dart        connection + sync + conflict-review UI
```

Tests:

```
test/sync_service_test.dart          reconcile + manifest + two-device behavior
test/phase3_sync_test.dart           conflict/interruption/recovery/worker coverage
test/webdav_streaming_test.dart      loopback WebDAV fixture + full syncNow/worker test
test/sync_state_store_test.dart      encrypted state + deletions coverage
test/webdav_store_test.dart          transport path-logic self-check
test/live_webdav_test.dart           env-gated live roundtrip + two-device + tamper
```

## Dependencies

`webdav_client` v1.2.2, `dio`, `crypto`, `flutter_secure_storage`, and
`connectivity_plus`. No new packages, and no new crypto beyond the existing
AES-GCM envelope.

## How it's tested

Hermetic coverage is the default: streamed transfers, publication preconditions,
cancellation, conflict outcomes, journaled recovery, and worker isolation all run
in `flutter test`. The env-gated `test/live_webdav_test.dart` uses a real server
but stays out of the default run. A physical-device pass (large files,
cancel/retry, lock mid-sync, conflict review, real-server capability probing) is
still the release sign-off, and it's scripted in
[local_server_testing.md](local_server_testing.md).

## Still open

1. **Protocol scope:** WebDAV only for v1, or SFTP too? WebDAV covers almost every
   NAS/cloud case; SFTP roughly doubles the transport work.
2. **Public WebDAV providers:** allow paid hosts or self-hosted only? Technically
   the same; it's a wording call for the settings screen.
3. **GC design:** payload retention is intentional. If storage growth becomes a
   complaint, design a reviewable reap pass (manifest-aware, never touching
   tombstoned or baseline-referenced blobs) rather than an automatic delete.
4. **Album/folder definitions** still don't sync. File-level IDs are carried;
   dangling references are tolerated.
