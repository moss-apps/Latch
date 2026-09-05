# Desktop Backup & Restore (Web)

## Overview

The vault has three persistence paths today: the on-device store (legacy
JSON or embedded PocketBase), the manual *decrypted* ZIP export
(`BackupService`), and WebDAV sync to a server the user operates. What is
missing is the case the 2026-09-05 incident exposed: a direct, restorable
backup of the whole vault onto storage the user physically controls — an
external USB drive or a desktop machine — without a server to set up and
without plaintext ever leaving the phone in transit.

This document specifies **P6**: a desktop companion process (`latchd`)
that the phone pairs with over Wi-Fi or USB. **The companion creates the
pairing credentials** — it runs a token-gated LAN receiver while a pairing
session is active and shows a QR code in its web UI; the phone scans (or
enters the address + code by hand) and **pushes** the encrypted snapshot
to it. The companion stores it on any local path, verifies it, and can
restore it back — including into a fresh install that has no vault set up
yet. The companion's primary interface is a web UI served on the desktop's
loopback interface.

> **2026-09 revision — pairing direction flipped.** The original P6.1/P6.2
> had the phone host the transfer server and latchd pull. User decision:
> the desktop creates the credentials, the phone scans. The phone-side
> `TransferServer` was removed and replaced by a push client; the
> phone-hosted model is gone.

Status: **P6.0 + P6.1r + P6.2r done** (flipped model). P6.3/P6.4 remain
planned.

Relationship to the existing paths:

| Path | Sees plaintext | Restorable | Needs server setup | Survives app uninstall |
|---|---|---|---|---|
| `BackupService` ZIP (kept, unchanged) | Yes — on local export | Manual, by hand | No | Yes (wherever written) |
| WebDAV sync | No | Yes | Yes (WebDAV host) | Yes |
| **Desktop backup (this doc)** | **No — in transit** | **Yes, one click** | No | Yes |

## Goals

- One-click encrypted full-vault backup from the phone to a
  user-chosen directory on the desktop or an external drive mounted on it
  (e.g. `/run/media/…/backups`).
- One-click restore, including the disaster case: fresh install after an
  uninstall, no vault configured yet.
- Ciphertext-only transfer; the companion decrypts locally, only after
  the user enters the vault password in its UI.
- Optional explicit "export decrypted" in the companion, writing readable
  files to the target directory (decryption happens on the desktop, after
  transfer — plaintext still never crosses the network).
- Wi-Fi and USB transports, same pairing model.
- No server setup, no accounts, no cloud.

## Non-goals

- **Sync.** This is snapshot backup/restore, not reconcile. The WebDAV
  engine (`SyncService`) stays the sync answer; this path reuses its
  formats, not its diff logic.
- **Receiver beyond the session.** The pairing receiver exists only while
  a pairing session is active in the companion web UI (and, on the phone,
  only inside the visible Desktop Backup screen). No background service
  in v1.
- **Decoy vault.** Out of scope, per the standing rule in both prior docs.
- **Remote access.** The companion web UI binds loopback only; the pairing
  receiver binds the LAN only while a session is active and requires a
  256-bit session token. Neither is reachable from outside the LAN/USB
  pair.
- **Incremental snapshots / retention management.** Content addressing
  already avoids re-transferring unchanged blobs; dated-snapshot retention
  and pruning are P6.5.

## Security model

| Asset | Where | Exposure if the backup drive / desktop is compromised |
|---|---|---|
| Media ciphertext | Backup dir (`ab/cd/<sha256>.enc`) | Safe. AES-256-GCM/CTR, per-file keys from the master key. Identical blobs to the sync layout. |
| Manifest (names, albums, tags, folders) | Backup dir, `manifest.enc` | Safe. Encrypted with the vault master key (same envelope as the sync manifest, v2). |
| Wrapped master key + Argon2id salt/IV + KDF params | Backup dir, `keybundle.json` | Safe by construction: it is the same material `flutter_secure_storage` holds on the phone; unwrapping still requires the vault password (Argon2id + AES-GCM unwrap). Losing the drive loses nothing but ciphertext. |
| Pairing token | Companion memory + web UI QR | One-time, per-session, regenerates on every pairing session. A stolen old token is useless once the session stops (completion, cancel, or idle timeout). |
| Vault password | Typed in the companion web UI; held in memory only | Never written to disk by the companion; never sent to the phone. |

Hard rules:

- **Plaintext never crosses the network.** Both directions move
  ciphertext only; decryption happens in the companion process after
  transfer. This extends the standing rule in `local_server_sync.md`.
- **The PB sidecar stays loopback-only.** The pairing receiver is a
  separate Go listener, not the PocketBase process; the
  `embedded_pocketbase.md` rule ("never `0.0.0.0`") applies to the sidecar
  and is not relaxed.
- **The receiver exists only inside an active pairing session.** No
  session (user cancelled, push completed and verified, or idle timeout
  elapsed) → listener closed, token dead. The receiver is never
  long-running.
- **Plain HTTP on the LAN is allowed only with an explicit warning** in
  both UIs (same stance as WebDAV sync: warn, never silently downgrade).
  v1 has no per-pair TLS; the token gates the session, the crypto gates
  the content.
- **The companion web UI binds `127.0.0.1` only.** The UI is not
  reachable from other machines; only the token-gated receiver is, and
  only while a session is active.
- **The phone never trusts the receiver blindly.** A pushed blob whose
  sha256 mismatches its address is rejected (422) before touching disk;
  the manifest swap is atomic and only happens after every referenced
  blob is present; the post-write verify pass re-hashes everything.

## Architecture

```
Phone (Latch, vault unlocked)                Desktop
┌────────────────────────────────┐          ┌─────────────────────────────────┐
│ DesktopBackupScreen            │          │ latchd (Go static binary)       │
│  • scans QR / enters addr+code │  Wi-Fi   │  • loopback web UI :7800        │
│  • DesktopPushClient pushes    │─────────►│  • pairing receiver (LAN, only │
│    snapshot while screen open  │  or USB  │    while a session is active): │
│                                │ adb fwd. │      token-gated, PUT set      │
│ DesktopPushClient (dart:io)    │          │  • Argon2id/PBKDF2/AES-GCM in  │
│  GET  /info (diff hashes)      │          │    Go (golang.org/x/crypto)    │
│  PUT  /keybundle               │          │  • writes backup dir:           │
│  PUT  /blob/<sha256>           │          │    <target>/latch-backup/       │
│  PUT  /manifest (last = done)  │          │      manifest.enc               │
│  Bearer <session token> on all │          │      keybundle.json             │
│                                │          │      ab/cd/<sha256>.enc         │
│                                │          │  • QR + creds in web UI         │
│                                │          │  • "export decrypted" writes    │
│                                │          │    plaintext locally, post-push │
└────────────────────────────────┘          └─────────────────────────────────┘
```

The companion hosts the credentials and the storage; the phone holds all
vault intelligence (what constitutes the vault, manifest format, crypto) —
shared with the sync engine: the backup directory is intentionally the
same layout as a WebDAV sync directory plus `keybundle.json`, so a future
`RemoteStore` implementation could read a mounted backup directory
verbatim.

### Backup directory layout

```
<target>/latch-backup/
  manifest.enc        # sync-manifest v2 envelope: IV + AES-GCM(master key)
  keybundle.json      # { wrappedKey, wrapSalt, wrapIv, argon2: {t, m, p} }
  ab/cd/<sha256>.enc  # verbatim vault blobs, content-addressed by ciphertext
```

A backup is "complete" iff `manifest.enc` decrypts, its GCM tag verifies,
and every `contentHash` it references exists on disk with a matching
sha256. The receiver runs exactly this check when the phone PUTs the
manifest (the completion signal); the companion's `verify` re-runs it on
demand.

### Pairing

1. User opens the companion web UI (`latchd serve` →
   `http://127.0.0.1:7800`) and the pairing view starts a session: the
   receiver binds `0.0.0.0:7801` (fixed port, so a single firewall rule
   covers every session; falls back to an ephemeral port if taken),
   generates a 256-bit session token, and the UI renders a QR:
   `http://<lan-ip>:7801/#<token>` (plus the address + code in readable
   form, with copy buttons).
   On Linux hosts running ufw, inbound pairing traffic needs one rule:
   `sudo ufw allow from <lan-subnet> to any port 7801 proto tcp` —
   latchd detects ufw and prints the exact command at session start.
2. User opens **Settings → Storage → Desktop Backup** on the phone
   (vault unlocked) and scans the QR — or types the address + code by
   hand (the USB variant path).
3. The phone's push client proves the pairing with `GET /info` (bearer
   token), diffs its blob set against the desktop's existing hashes, and
   pushes `keybundle` + missing blobs + `manifest` (always last).
4. The receiver verifies the manifest, reaps orphans, marks the session
   **complete**, and closes. The web UI prompts for the vault password
   to unlock browsing (`/api/unlock`).

The session (and its listener + token) dies on completion, on cancel in
the web UI, or after an idle timeout with no successful requests.

USB variant (P6.4): `adb forward tcp:<port> tcp:<port>` makes the
desktop's receiver reachable at `127.0.0.1:<port>` **on the phone** over
the cable; same token, entered manually (the phone can still scan the QR,
but over USB the wired reachability is the reliable one).

### Crypto on the desktop

No new crypto anywhere; the companion re-implements the existing phone
stack with `golang.org/x/crypto`:

- unwrap: password → Argon2id(keybundle params) → AES-GCM-unwrap master
  key (mirrors `EncryptionService.initialize`)
- manifest: AES-GCM decrypt under master key (same envelope as
  `RemoteManifest`)
- per-file: PBKDF2-HMAC-SHA256(master key, per-file salt, iterations) →
  AES-256-GCM/CTR decrypt (mirrors `lib/crypto/key_derivation.dart`; all
  per-file params travel in the manifest v2 entries, which already carry
  `encryptionIv`, `keyDerivationSalt`, `kdfIterations`)

## Protocol

Receiver endpoints (all bearer-gated; anything else is 401):

| Endpoint | Dir | Purpose |
|---|---|---|
| `GET /info` | phone→desktop | `{app, protocol, hasManifest, hasKeybundle, hashes[]}` — the blob digests the desktop already holds, so the phone can diff |
| `PUT /keybundle` | push | Install/refresh key bundle JSON (validated shape) |
| `PUT /blob/<sha256>` | push | One ciphertext blob, streamed; sha256 checked before it touches disk (422 on mismatch) |
| `PUT /manifest` | push | Completion signal: atomic swap, then verify + reap; 200 only if the resulting backup verifies |

Backup = the phone's `PUT` set against a session the desktop started.
Restore (P6.3) = the same receiver serving the `GET` set (`/manifest`,
`/blob/<sha>`, `/keybundle`) in a restore-authorized session; the phone
pulls. The desktop never interprets phone state; a restore is offered,
not pushed.

### Loopback web UI API

Served on `127.0.0.1:7800` for the companion's own UI (session-gated, not
bearer-gated). The UI must not assume endpoints beyond this table.

| Endpoint | Purpose |
|---|---|
| `GET /api/status` | `{unlocked, files, dir, hasLocal, lastBackup}` |
| `GET /api/browse` | Unlocked only (409 otherwise). `{files: [{id, name, type, size, favorite, mimeType, dateAdded, dateModified}]}` over live manifest entries |
| `GET /api/file/<id>` | Unlocked only. Decrypts the blob in memory and serves plaintext with Range support (`http.ServeContent`); `Content-Type` from the manifest `mimeType` with extension fallback; `?dl=1` switches to attachment. Entries with `isEncrypted: false` (unencrypted vault files) are served as stored. Legacy pre-GCM blob → 422; missing/corrupt blob → 404 |
| `GET /api/thumb/<id>` | Unlocked only. Server-generated JPEG thumbnail (~320px, q75) for image entries; in-memory LRU, ETag + 304 — plaintext never touches disk. Non-images → 404 (UI falls back to a type glyph) |
| `POST /api/unlock` / `POST /api/lock` | Vault password → master key in memory / drop it (also clears thumbnails) |
| `POST /api/verify` / `POST /api/export` | Hash-verify every blob / decrypt snapshot to `~/latchd-exports/<subdir>` |
| `POST /api/pair/start` / `stop` · `GET /api/pair/status` | Pairing receiver lifecycle + 1.5s poll state |

> **Follow-up — folder records.** The manifest carries `folderId` per file,
> but folder rows live only in the phone's PocketBase, so the web UI offers
> type views (Photos/Videos/Songs/Documents/Favorites), not a folder tree.
> A manifest v3 with folder records would enable a real tree; tracked as an
> open follow-up, not part of P6.2r.


## Sync model — none; snapshot semantics

- A backup is a **full snapshot**: the phone builds the manifest from the
  live vault, diffs its content hashes against the desktop's `/info`
  hash list, transfers only missing/changed blobs (content addressing
  makes this free), then PUTs the manifest last. Semantically it is
  always "the whole vault as of now".
- No tombstones, no LWW, no conflict UI. Restoring a snapshot over an
  existing vault replaces it wholesale (explicit confirmation in the UI).
- Deleted-on-phone since last backup simply disappears from the new
  snapshot; superseded blobs are reaped from the backup dir during the
  receiver's post-manifest `verify` pass (they are unreferenced after
  the manifest swap).

## Restore semantics

Two modes, same data:

1. **Into an existing unlocked vault** (device-to-device or undo): the
   desktop opens a restore session; the phone pulls blobs + manifest,
   imports manifest v2 entries through the same path as the WebDAV pull
   (GCM-tag + `contentHash` verification per file), and commits. The
   existing master key is kept; entries whose blobs are absent from the
   snapshot are left untouched.
2. **Restore-before-setup** (the incident case): a fresh install, no
   vault yet. First-run offers "Restore from desktop backup"; the user
   scans the desktop's QR (or enters address + code), the phone pulls
   blobs + manifest + `keybundle.json` over the session, then the user
   types the **original** vault password on the phone; the phone unwraps
   the bundle to verify (Argon2id unwrap success = correct password),
   installs the key material as the vault's own, and imports the
   manifest. Setup (PIN/biometric choice) resumes around it. This is the
   only path that installs a received `keybundle`.

## Phased plan

| Phase | Deliverable | Location | Status |
|---|---|---|---|
| P6.0 | This document | `docs/desktop_backup.md` | Done |
| P6.1 | ~~Phone: `TransferServer` + QR screen~~ → **r**: phone push client + scanner screen | `lib/services/desktop_link/transfer_client.dart`, `lib/screens/desktop_backup_screen.dart`, `pubspec.yaml` (−`qr_flutter`, +`mobile_scanner`) | Done (flipped) |
| P6.2 | ~~Companion puller~~ → **r**: companion pairing receiver + QR web UI + unlock-after-push, `verify`, browse-after-unlock, export-decrypted | `latchd/` (Go module: `cmd/latchd`, `internal/{receiver,backup,cryptoutil,webui}`, React web UI built from `web-src/` into `web/` via `go:embed`, vendored QR encoder) | Done (flipped) |
| P6.3 | Restore both modes (GET set + restore sessions; phone-side pre-vault pull); first-run entry point | `latchd/internal/receiver` (GET set), phone `desktop_link/restore_controller.dart`, first-run flow | Planned |
| P6.4 | USB transport: `adb forward` hint in web UI + manual-code path on phone | web UI copy, phone manual entry | Planned |
| P6.5 | Polish: snapshot retention (dated manifests), scheduled backup reminders, orphan reaping report | `latchd/`, phone settings | Deferred |

Each phase keeps the repo's verification discipline: one runnable check
plus one security failure path (401 without token; tampered blob
sha mismatch → 422; wrong password fails Argon unwrap with a
constant-time indistinguishable error).

## Files

```
docs/desktop_backup.md                             this spec                     [P6.0]
lib/services/desktop_link/transfer_client.dart     push client (scan → PUT set)  [P6.1r]
lib/screens/desktop_backup_screen.dart             scanner + manual entry + push [P6.1r]
test/desktop_push_test.dart                        push client auth + roundtrip  [P6.1r]
latchd/go.mod                                      standalone Go module          [P6.2]
latchd/cmd/latchd/main.go                          serve / verify / export CLI   [P6.2r]
latchd/internal/receiver/                          pairing receiver (LAN, token) [P6.2r]
latchd/internal/backup/                            snapshot store, verify, reap  [P6.2]
latchd/internal/cryptoutil/                         argon2id unwrap, GCM, PBKDF2 [P6.2]
latchd/internal/webui/                              loopback UI + file/thumb API server [P6.2r]
latchd/web-src/                                     React+Vite source for the web UI (builds into web/, dist committed) [P6.2r]
latchd/internal/webui/web/vendor/qrcode.js         vendored QR encoder (MIT, qrcode-generator) [P6.2r]
```

Removed by the flip: `lib/services/desktop_link/transfer_server.dart`,
`test/desktop_link_test.dart`, `latchd/internal/link/` (phone client),
`latchd` `pair`/`backup`/`restore-push` subcommands.

Changed:

```
pubspec.yaml                           − qr_flutter, + mobile_scanner   [P6.1r]
lib/screens/vault_settings_screen.dart  "Desktop Backup" entry (Storage) [P6.1]
lib/services/backup_service.dart       unchanged — ZIP export stays as-is
Makefile                               + latchd / clean-latchd targets   [P6.2]
```

## Dependencies

- **Add (Flutter):** `mobile_scanner` (camera QR scanning; replaces
  `qr_flutter`, which is removed — the phone no longer renders QRs).
- **Vendored (web UI):** `qrcode-generator` 1.4.4 (MIT, single file) —
  renders the pairing QR in the desktop browser; no build toolchain.
- **Add (Go, `latchd/go.mod`):** `golang.org/x/crypto` (argon2, pbkdf2,
  aes) — stdlib `net/http` for both listeners.
- **Reuse:** sync manifest v2 format + blob layout (`SyncService`), key
  wrap format (`EncryptionService` / `lib/crypto/`), cleartext-LAN
  warning UX pattern (`sync_settings_screen.dart`).

## Verification discipline

Per the repo's test rules: no per-method suites. Per phase one runnable
check:

- P6.1r: `test/desktop_push_test.dart` — push against a stub receiver:
  unauthenticated → 401 aborts; roundtrip sends only missing blobs and
  the manifest last.
- P6.2r: `latchd` receiver test — bearer-gated push roundtrip into a
  temp dir; tampered blob sha → 422, nothing written; manifest completes
  and verifies.
- P6.3: end-to-end on host — build a backup by pushing from a test
  vault, wipe the vault, restore via pre-vault pull, unlock with the
  original password, index matches.
- Acceptance (manual, once, on real hardware): the 2026-09-05 scenario —
  fresh install, restore from the USB drive, vault opens with the
  original password.

## Open decisions

1. **Snapshot retention:** single mutable `latch-backup/` (current
   design) vs dated `snapshots/<date>/manifest.enc` sharing one blob
   pool. Default: single; retention is P6.5.
2. **Companion distribution:** source + `make latchd`, or commit a
   prebuilt Linux binary. Default: Makefile-built; binary distribution
   when a non-developer user exists.
3. **Web UI tech:** hand-rolled static HTML/JS with `go:embed` (no build
   toolchain) vs a tiny framework SPA. Default: static, revisit if the
   browse UI grows.
4. **LAN discovery:** QR/manual IP (v1) vs mDNS advertisement (`_latch._tcp`).
   Default: QR/manual; mDNS adds a dependency and a discovery-attack
   surface.
5. **Where restore-before-setup lives in first-run:** replacing the
   auth-method selection flow vs a button beside it. UX call, P6.3.
6. **`BackupService` ZIP coexistence:** kept deliberately (decided). Revisit
   its `_passwords_index.json` inclusion as a hardening item — it writes
   the password-store index verbatim into the decrypted ZIP.
7. **Receiver idle timeout:** currently 5 minutes without a successful
   authenticated request. Tunable constant; revisit after real-hardware
   acceptance.
