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
that the phone pairs with over Wi-Fi or USB, which pulls an encrypted
full-vault snapshot through a temporary on-app transfer server and stores
it on any local path, and can restore it back — including into a fresh
install that has no vault set up yet. The companion's primary interface is
a web UI served on the desktop's loopback interface.

Status: **Planned**. P6.0 is this document. Nothing is implemented.

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
- **Phone-as-server beyond the session.** The transfer server exists only
  while its screen is open and the vault unlocked. No background service
  in v1.
- **Decoy vault.** Out of scope, per the standing rule in both prior docs.
- **Remote access.** The companion binds loopback only on the desktop;
  the transfer server binds the LAN only during pairing and requires a
  session token. Neither is reachable from outside the LAN/USB pair.
- **Incremental snapshots / retention management.** Content addressing
  already avoids re-transferring unchanged blobs; dated-snapshot retention
  and pruning are P6.5.

## Security model

| Asset | Where | Exposure if the backup drive / desktop is compromised |
|---|---|---|
| Media ciphertext | Backup dir (`ab/cd/<sha256>.enc`) | Safe. AES-256-GCM/CTR, per-file keys from the master key. Identical blobs to the sync layout. |
| Manifest (names, albums, tags, folders) | Backup dir, `manifest.enc` | Safe. Encrypted with the vault master key (same envelope as the sync manifest, v2). |
| Wrapped master key + Argon2id salt/IV + KDF params | Backup dir, `keybundle.json` | Safe by construction: it is the same material `flutter_secure_storage` holds on the phone; unwrapping still requires the vault password (Argon2id + AES-GCM unwrap). Losing the drive loses nothing but ciphertext. |
| Pairing token | Phone screen + companion memory | One-time, per-session, regenerates on every pairing. A stolen old token is useless once the session screen closes. |
| Vault password | Typed in the companion web UI; held in memory only | Never written to disk by the companion; never sent to the phone. |

Hard rules:

- **Plaintext never crosses the network.** Both directions move
  ciphertext only; decryption happens in the companion process after
  transfer. This extends the standing rule in `local_server_sync.md`.
- **The PB sidecar stays loopback-only.** The transfer server is a
  separate Dart `HttpServer`, not the PocketBase process; the
  `embedded_pocketbase.md` rule ("never `0.0.0.0`") applies to the sidecar
  and is not relaxed.
- **The transfer server exists only inside an unlocked, visible screen.**
  Closed screen, locked vault, backgrounded app → server down, token dead.
- **Plain HTTP on the LAN is allowed only with an explicit in-app
  warning** (same stance as WebDAV sync: warn, never silently downgrade).
  v1 has no per-pair TLS; the token gates the session, the crypto gates
  the content.
- **Restore verifies before it trusts.** Every restored blob's sha256
  must match the manifest's `contentHash`, and the manifest's GCM tag
  must verify under the master key, before anything is imported.
- **The companion binds `127.0.0.1` only.** The web UI is not reachable
  from other machines.

## Architecture

```
Phone (Latch, vault unlocked)                Desktop
┌────────────────────────────────┐          ┌─────────────────────────────────┐
│ DesktopBackupScreen            │          │ latchd (Go static binary)       │
│  • starts TransferServer       │  Wi-Fi   │  • HTTP client  → phone endpoints│
│  • shows QR: http://ip:port    │◄────────►│  • loopback web UI :7800        │
│    + one-time session token    │  or USB  │  • Argon2id/PBKDF2/AES-GCM in   │
│                                │ adb rev. │    Go (golang.org/x/crypto)    │
│ TransferServer (dart:io)       │          │  • writes backup dir:           │
│  GET  /info /manifest          │          │    <target>/latch-backup/       │
│  GET  /blob/<sha256>           │          │      manifest.enc               │
│  GET  /keybundle (paired only) │          │      keybundle.json             │
│  PUT  /manifest /blob/<sha>    │          │      ab/cd/<sha256>.enc         │
│  PUT  /keybundle (restore)     │          │  • reads same dir on restore    │
│  Bearer <session token> on all │          │  • "export decrypted" writes    │
└────────────────────────────────┘          │    plaintext locally, post-pull │
                                            └─────────────────────────────────┘
```

The phone is a dumb file server for one session; the companion is a dumb
puller/pusher with a UI. All vault intelligence (what constitutes the
vault, manifest format, crypto) is shared with the sync engine: the
backup directory is intentionally the same layout as a WebDAV sync
directory plus `keybundle.json`, so a future `RemoteStore`
implementation could read a mounted backup directory verbatim.

### Backup directory layout

```
<target>/latch-backup/
  manifest.enc        # sync-manifest v2 envelope: IV + AES-GCM(master key)
  keybundle.json      # { wrappedKey, wrapSalt, wrapIv, argon2: {t, m, p} }
  ab/cd/<sha256>.enc  # verbatim vault blobs, content-addressed by ciphertext
```

A backup is "complete" iff `manifest.enc` decrypts, its GCM tag verifies,
and every `contentHash` it references exists on disk with a matching
sha256. The companion's `verify` runs exactly this check after writing
(backup) or before offering restore.

### Pairing

1. User opens **Settings → Storage → Desktop Backup** (vault unlocked).
2. Screen starts `TransferServer` on `0.0.0.0:<ephemeral>`, generates a
   256-bit session token, renders a QR: `http://<lan-ip>:<port>/#<token>`
   (plus a manual `ip:port` + code fallback).
3. User enters the URL (or runs `latchd pair <url>`) on the desktop;
   `latchd` proves reachability via `GET /info` with the bearer token.
4. Session dies when the screen closes or the app backgrounds.

USB variant (P6.4): `adb reverse tcp:<port> tcp:<port>` makes the phone's
loopback server reachable at `127.0.0.1:<port>` on the desktop over the
cable; same token, entered manually or via QR still shown on-screen.

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

| Endpoint | Dir | Purpose |
|---|---|---|
| `GET /info` | pull | App version, blob count/bytes, vault stats (counts only — no names) |
| `GET /manifest` | pull | `manifest.enc` bytes |
| `GET /blob/<sha256>` | pull | One ciphertext blob, streamed |
| `GET /keybundle` | pull | Key bundle JSON (session-gated) |
| `PUT /manifest` | push | Restore: replace manifest |
| `PUT /blob/<sha256>` | push | Restore: one blob |
| `PUT /keybundle` | push | Restore: install key bundle |

All requests carry `Authorization: Bearer <session token>`; anything else
is 401. Backup = `GET` set; restore = `PUT` set. The phone never interprets
companion state; a restore is told, not asked.

## Sync model — none; snapshot semantics

- A backup is a **full snapshot**: the companion fetches the manifest,
  diffs its hash list against what the target directory already contains,
  transfers only missing/changed blobs (content addressing makes this
  free), then atomically replaces `manifest.enc` and refreshes
  `keybundle.json`. Semantically it is always "the whole vault as of now".
- No tombstones, no LWW, no conflict UI. Restoring a snapshot over an
  existing vault replaces it wholesale (explicit confirmation in the UI).
- Deleted-on-phone since last backup simply disappears from the new
  snapshot; superseded blobs are reaped from the backup dir during the
  post-write `verify` pass (they are unreferenced after the manifest
  swap).

## Restore semantics

Two modes, same data:

1. **Into an existing unlocked vault** (device-to-device or undo): the
   phone's restore handler writes blobs into the vault directory, imports
   manifest v2 entries through the same path as the WebDAV pull
   (GCM-tag + `contentHash` verification per file), and commits. The
   existing master key is kept; entries whose blobs are absent from the
   snapshot are left untouched.
2. **Restore-before-setup** (the incident case): a fresh install, no
   vault yet. First-run offers "Restore from desktop backup"; the
   transfer server starts in a restricted pre-vault mode (PUT-only), the
   companion pushes blobs + manifest + `keybundle.json`, the user then
   types the **original** vault password on the phone; the phone unwraps
   the bundle to verify (Argon2id unwrap success = correct password),
   installs the key material as the vault's own, and imports the
   manifest. Setup (PIN/biometric choice) resumes around it. This is the
   only path that accepts a `keybundle` PUT.

## Phased plan

| Phase | Deliverable | Location | Status |
|---|---|---|---|
| P6.0 | This document | `docs/desktop_backup.md` | Done |
| P6.1 | Phone: `TransferServer` (dart:io, bearer token, session lifecycle) + `DesktopBackupScreen` with QR + LAN warning | `lib/services/desktop_link/`, `lib/screens/desktop_backup_screen.dart`, `pubspec.yaml` (+`qr_flutter`) | Planned |
| P6.2 | Companion core: `latchd serve` (loopback web UI), pair, full-snapshot backup with incremental transfer, `verify`, browse-after-unlock, export-decrypted | `latchd/` (new Go module: `cmd/latchd`, `internal/{link,backup,cryptoutil}`, `web/` static UI via `go:embed`) | Planned |
| P6.3 | Restore both modes; phone-side pre-vault restricted mode; first-run entry point | `latchd/internal/restore`, phone `desktop_link/restore_controller.dart`, first-run flow | Planned |
| P6.4 | USB transport: `adb reverse` auto-detect in `latchd`, manual-code fallback on phone | `latchd/internal/link/usb.go` | Planned |
| P6.5 | Polish: snapshot retention (dated manifests), scheduled backup reminders, orphan reaping report | `latchd/`, phone settings | Deferred |

Each phase keeps the repo's verification discipline: one happy-path test
plus one security failure path (401 without token; tampered blob
`contentHash` mismatch; wrong password fails Argon2 unwrap with a
constant-time indistinguishable error).

## Files

New:

```
docs/desktop_backup.md                          this spec                    [P6.0]
lib/services/desktop_link/transfer_server.dart  session HTTP server           [P6.1]
lib/services/desktop_link/restore_controller.dart  restore + pre-vault mode  [P6.3]
lib/screens/desktop_backup_screen.dart          QR + status + warnings       [P6.1]
latchd/go.mod                                   standalone Go module         [P6.2]
latchd/cmd/latchd/main.go                       serve / pair / backup / restore CLI under the UI [P6.2]
latchd/internal/link/                           phone client (HTTP + token)  [P6.2]
latchd/internal/backup/                         snapshot pull, verify, reap  [P6.2]
latchd/internal/cryptoutil/                     argon2id unwrap, GCM, PBKDF2 [P6.2]
latchd/web/                                     static UI (go:embed, no build toolchain) [P6.2]
test/desktop_link_test.dart                     transfer server auth + endpoints [P6.1]
```

Changed:

```
pubspec.yaml                          + qr_flutter                       [P6.1]
lib/screens/vault_settings_screen.dart + "Desktop Backup" entry (Storage) [P6.1]
lib/services/backup_service.dart      unchanged — ZIP export stays as-is
Makefile                              + latchd / clean-latchd targets    [P6.2]
```

## Dependencies

- **Add (Flutter):** `qr_flutter` (QR rendering; only new mobile dep).
- **Add (Go, `latchd/go.mod`):** `golang.org/x/crypto` (argon2, pbkdf2,
  aes, hkdf-not-needed) — stdlib `net/http` for both servers.
- **Reuse:** sync manifest v2 format + blob layout (`SyncService`), key
  wrap format (`EncryptionService` / `lib/crypto/`), cleartext-LAN
  warning UX pattern (`sync_settings_screen.dart`).

## Verification discipline

Per the repo's test rules: no per-method suites. Per phase one runnable
check:

- P6.1: `test/desktop_link_test.dart` — unauthenticated request → 401;
  authenticated `/manifest` roundtrip against a seeded in-memory vault.
- P6.2: `latchd` integration test — pull a fixture backup directory,
  `verify` passes; flip one byte in a blob → `verify` fails naming the
  hash.
- P6.3: end-to-end on host — build a backup from a test vault via the
  transfer server, wipe the vault, restore via pre-vault mode, unlock
  with the original password, index matches.
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
