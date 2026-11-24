# Desktop Backup & Restore (latchd)

## Status

**Implemented through P6.4; P6.5 (retention/polish) deferred; hardware
acceptance pending.** This is the snapshot path for the 2026-09-05 incident:
back up the whole vault to storage the user controls, then restore it — even
into a fresh install with no vault yet.

Hardware sign-off is not recorded. Follow the approval and isolation preflight
in the [Stable release checklist](stable_release_checklist.md) before any
install, upgrade, restore, or wipe. Do not test against a live vault or an
existing backup.

## What it is

`latchd` is a Go companion that runs on a desktop or laptop. It serves a
loopback web UI, opens a short-lived token-gated receiver on the LAN while a
pairing session is active, and stores the backup on a user-chosen path. The
phone pushes the snapshot; the companion verifies and stores it. Restore works
in both directions, including before first-run setup.

This is **not sync**. WebDAV ([local_server_sync.md](local_server_sync.md))
remains the reconcile path. Desktop backup is a snapshot of active files and
the key bundle; it does not carry Recently Deleted, folder/album definitions,
smart collections, or all settings.

| Path | Sees plaintext | Restorable | Needs server setup | Survives uninstall |
|---|---|---|---|---|
| `BackupService` ZIP export | Yes, on local export | Manual | No | Yes |
| WebDAV sync | Hidden-only payloads; use HTTPS | With the original key | Yes | Remote data survives; key continuity required |
| **Desktop backup** | **Hidden-only payloads, including HTTP transit** | **With a valid backup and original credential** | No | Yes; verify before relying on it |

## Quick start

Build or install:

```bash
make latchd                     # source build: latchd/latchd
scripts/install-latchd.sh       # Linux installer (releases)
```

Prebuilt `latchd-linux-amd64`, `latchd-linux-arm64`, and
`latchd-windows-amd64.exe` are published by
`.github/workflows/release-latchd.yml` on app-version tags.

Back up:

1. Run `latchd serve` (defaults: `127.0.0.1:7800`, `latch-backup/`).
2. Open `http://127.0.0.1:7800` and start a pairing session. The UI shows a
   QR, address, and 256-bit code.
3. On the phone: **Settings → Storage → Desktop Backup**, scan the QR or enter
   the address and code, then push.
4. The phone sends the key bundle, missing blobs, and the manifest last. The
   receiver verifies, reaps unreferenced blobs, closes the session, and the UI
   can unlock browsing.

USB variant: connect the phone, run the `adb reverse` command shown in the web
UI, choose **Connect via USB** on the phone, and tap **Allow** once on the
desktop. No address or code is needed. The reverse mapping proves possession of
an adb-authorized device; the tap binds the session.

Restore:

- **Existing vault:** pull the backup into the unlocked vault. Matching file
  IDs are replaced, new IDs are added, and unrelated local entries stay.
  The current master key is kept.
- **Fresh install:** choose **Restore from desktop backup**, pull blobs +
  manifest + `keybundle.json`, then enter the **original** vault password. The
  phone unwraps the bundle to verify it; this is the only path that installs a
  received key bundle. Normal setup resumes after the restore.

## Security model

| Asset | Where | Exposure if the drive or desktop is compromised |
|---|---|---|
| File payloads | `latch-backup/ab/cd/<sha256>.enc` | As stored: encrypted files need the key; hidden-only files are readable. The `.enc` suffix is not proof of encryption. |
| Manifest | `manifest.enc` | AES-GCM under the vault master key. |
| Wrapped key + Argon2id params | `keybundle.json` | Unwrapping requires the original credential. Protect against offline guessing; a lost drive may not contain only ciphertext. |
| Pairing token | Companion memory + QR | One-time, per session, dies on completion, cancel, or idle timeout. |
| Vault password | Companion memory only | Never written to disk by `latchd`; never sent to the phone. |

Hard rules:

- **Never claim hiding is encryption.** Payload bytes are preserved in both
  directions. Hidden-only files can cross HTTP as plaintext; encrypt files
  first when that protection is required.
- **The PocketBase sidecar stays loopback-only.** The pairing receiver is a
  separate listener; the embedded-PocketBase rule still applies.
- **The receiver exists only during an active pairing session.** No session
  means no listener and a dead token. It is never long-running.
- **Plain HTTP on the LAN is allowed only with an explicit warning.** v1 has no
  per-pair TLS; the token gates access, not confidentiality. A network observer
  may read hidden-only payloads and capture the token.
- **The web UI binds `127.0.0.1` only.** Only the token-gated receiver is
  reachable from the LAN, and only while pairing.
- **The phone verifies what it receives.** Blob sha256 is checked before use;
  the manifest swap is atomic and happens only after all referenced blobs are
  present; the post-write verify pass re-hashes everything.

## Architecture

```
Phone (vault unlocked)                    Desktop
┌──────────────────────────────┐          ┌────────────────────────────────┐
│ DesktopBackupScreen          │          │ latchd (Go static binary)      │
│  scan QR / enter addr+code   │  Wi-Fi   │  loopback web UI :7800         │
│  DesktopPushClient           │─────────►│  pairing receiver :7801 (LAN)  │
│   GET  /info (diff hashes)   │  or USB  │   token-gated PUT/GET sets     │
│   PUT  /keybundle            │ adb rev. │  Argon2id / PBKDF2 / AES-GCM   │
│   PUT  /blob/<sha256>        │          │  <target>/latch-backup/        │
│   PUT  /manifest (last)      │          │   manifest.enc                 │
│  Bearer <session token>      │          │   keybundle.json               │
│                              │          │   ab/cd/<sha256>.enc           │
└──────────────────────────────┘          └────────────────────────────────┘
```

The backup directory is the same layout as a WebDAV sync directory plus
`keybundle.json`, so a future `RemoteStore` could read a mounted backup
directly.

```
<target>/latch-backup/
  manifest.enc        # sync-manifest v2: IV + AES-GCM(master key)
  keybundle.json      # wrappedKey, wrapSalt, wrapIv, argon2 {t,m,p}
  ab/cd/<sha256>.enc  # verbatim vault bytes, content-addressed as stored
```

A backup is complete only when `manifest.enc` decrypts, its GCM tag verifies,
and every `contentHash` it references exists with a matching sha256. The
receiver runs this check on manifest upload; `latchd verify` re-runs it on
demand.

## Protocol

Receiver endpoints (bearer-gated; anything else is 401):

| Endpoint | Direction | Purpose |
|---|---|---|
| `GET /info` | phone → desktop | `{app, protocol, hasManifest, hasKeybundle, hashes[]}` for diffing |
| `PUT /keybundle` | push | Install/refresh the wrapped key bundle |
| `PUT /blob/<sha256>` | push | One as-stored blob; sha256 checked before publication (422 on mismatch) |
| `PUT /manifest` | push | Completion signal: atomic swap, verify, reap; 200 only if the backup verifies |
| `POST /usb-hello` | USB | Tap-to-approve handshake; loopback-only, LAN callers get 404 |

Loopback web UI API (`127.0.0.1:7800`, session-gated):

| Endpoint | Purpose |
|---|---|
| `GET /api/status` | `{unlocked, files, dir, hasLocal, lastBackup}` |
| `GET /api/browse` | Manifest entries when unlocked (409 otherwise) |
| `GET /api/file/<id>` | Decrypt in memory and serve plaintext with Range support; `?dl=1` forces download |
| `GET /api/thumb/<id>` | In-memory JPEG thumbnail for images; plaintext never touches disk |
| `POST /api/unlock` / `lock` | Load/drop the master key and clear thumbnails |
| `POST /api/verify` / `export` | Hash-verify all blobs / decrypt to `~/latchd-exports/<subdir>` |
| `POST /api/pair/start` / `stop` / `allow`; `GET /api/pair/status` | Pairing lifecycle and USB approval polling |

Crypto is a Go reimplementation of the phone stack with
`golang.org/x/crypto`: Argon2id unwraps the master key, AES-GCM decrypts the
manifest, and PBKDF2-HMAC-SHA256 + AES-256-GCM/CTR decrypts each file using the
parameters carried in manifest v2.

## Limits and deferred work

- **Snapshot only.** Deleted-on-phone entries disappear from the next backup;
  superseded blobs are reaped after the manifest swap.
- **Active files only.** No Recently Deleted, collection definitions, or full
  settings.
- **No folder tree in the UI.** Files carry `folderId`, but folder rows live
  only on the phone; the UI offers type views. A manifest v3 with folder
  records is a follow-up.
- **No retention.** Single mutable `latch-backup/`; dated snapshots and pruning
  are P6.5.
- **Memory:** desktop snapshot construction buffers payloads in memory. Large
  snapshots need hardware measurement before being treated as safe.
- **ZIP export coexistence:** `BackupService` remains; revisit its
  `_passwords_index.json` inclusion as a hardening item.
- **Receiver idle timeout:** 5 minutes without a successful authenticated
  request.

## Verification

Per phase, one runnable check plus one security failure path:

- `test/desktop_push_test.dart` — push against a stub receiver; unauthenticated
  requests abort; only missing blobs and the manifest-last sequence are sent.
- `latchd` receiver tests — bearer-gated round trip; tampered blob → 422 with
  nothing written; manifest completes and verifies.
- `test/desktop_restore_test.dart` — push → wipe → restore → unlock.
- Manual acceptance still required: fresh install, restore from the USB drive,
  open with the original password.

## Key paths

```
latchd/cmd/latchd/                    serve / verify / export-decrypted CLI
latchd/internal/receiver/             pairing receiver, restore sessions
latchd/internal/backup/               snapshot store, verify, reap
latchd/internal/cryptoutil/           Argon2id, AES-GCM, PBKDF2
latchd/internal/webui/                loopback UI and file/thumb API
latchd/web-src/                       React + Vite source (dist committed)
lib/services/desktop_link/            push, USB, and restore clients
lib/screens/desktop_backup_screen.dart
lib/screens/restore_setup_screen.dart
```

`latchd` credentials come from `--password` or `LATCHD_PASSWORD`; they are
never stored.
