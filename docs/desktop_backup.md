# Desktop backup & restore (latchd)

## Where it stands

`latchd` is built through the core backup, restore, and USB work. Retention and
polish are deferred, and nobody has signed it off on real hardware yet. It's the
"get my vault onto a computer I control" path: back up the whole vault, then
restore it later, including on a fresh install with no vault.

Follow the approval and isolation steps in the
[stable release checklist](stable_release_checklist.md) before any install,
upgrade, restore, or wipe. Don't test against a live vault or your only backup.

## What it is

`latchd` is a Go companion that runs on a desktop or laptop. It serves a loopback
web UI, opens a short-lived token-gated receiver on the LAN only while a pairing
session is active, and stores the backup wherever you tell it to. The phone
pushes the snapshot; the companion verifies it and writes it down. Restore works
both ways, including before first-run setup.

This is **not sync**. WebDAV ([local_server_sync.md](local_server_sync.md)) is
still the reconcile path. Desktop backup is a snapshot of active files plus the
key bundle. It doesn't include Recently Deleted, folder/album definitions, smart
collections, or all settings.

| Path | Sees plaintext | Restorable | Needs server setup | Survives uninstall |
|---|---|---|---|---|
| `BackupService` ZIP export | Yes, on local export | Manually | No | Yes |
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
2. Open `http://127.0.0.1:7800` and start a pairing session. The UI shows a QR,
   an address, and a 256-bit code.
3. On the phone: **Settings → Storage → Desktop Backup**, scan the QR or enter
   the address and code, then push.
4. The phone sends the key bundle, any missing blobs, and the manifest last. The
   receiver verifies everything, reaps unreferenced blobs, closes the session,
   and lets the UI unlock browsing.

USB instead: connect the phone, run the `adb reverse` command shown in the web
UI, choose **Connect via USB** on the phone, then tap **Allow** once on the
desktop. No address or code needed. The reverse mapping proves you have an
adb-authorized device; the tap binds the session.

Restore:

- **Existing vault:** pull the backup into the unlocked vault. Matching file IDs
  are replaced, new IDs are added, and unrelated local entries stay. The current
  master key is kept.
- **Fresh install:** choose **Restore from desktop backup**, pull blobs +
  manifest + `keybundle.json`, then enter the **original** vault password. The
  phone unwraps the bundle to verify it. This is the only path that installs a
  received key bundle. Normal setup picks up after the restore.

## Security model

| Asset | Where it lives | What happens if the drive or desktop is compromised |
|---|---|---|
| File payloads | `latch-backup/ab/cd/<sha256>.enc` | As stored: encrypted files need the key; hidden-only files are readable. The `.enc` suffix doesn't prove encryption. |
| Manifest | `manifest.enc` | AES-GCM under the vault master key. |
| Wrapped key + Argon2id params | `keybundle.json` | Unwrapping needs the original credential. Protect it from offline guessing; a stolen drive may contain more than ciphertext. |
| Pairing token | Companion memory + QR | One-time, per session. Dies on completion, cancel, or idle timeout. |
| Vault password | Companion memory only | `latchd` never writes it to disk and never sends it to the phone. |

What keeps this safe:

- **Never claim hiding is encryption.** Payload bytes are preserved in both
  directions. Hidden-only files can cross HTTP as plaintext; encrypt them first
  if that matters.
- **Keep the PocketBase sidecar on loopback.** The pairing receiver is a separate
  listener; the embedded-PocketBase rule still applies.
- **The receiver only exists during a pairing session.** No session, no listener,
  and the token is dead. It never runs all the time.
- **Plain HTTP on the LAN needs an explicit warning.** v1 has no per-pair TLS.
  The token gates access, not confidentiality. A network observer may read
  hidden-only payloads and capture the token.
- **The web UI binds `127.0.0.1` only.** The token-gated receiver is the only
  thing reachable from the LAN, and only while pairing.
- **The phone verifies what it receives.** Blob SHA-256 is checked before use, the
  manifest swap is atomic and happens only after every referenced blob is
  present, and the post-write verify pass re-hashes everything.

## How it works

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

The backup directory uses the same layout as a WebDAV sync directory plus
`keybundle.json`, so a future `RemoteStore` could read a mounted backup directly.

```
<target>/latch-backup/
  manifest.enc        # sync-manifest v2: IV + AES-GCM(master key)
  keybundle.json      # wrappedKey, wrapSalt, wrapIv, argon2 {t,m,p}
  ab/cd/<sha256>.enc  # verbatim vault bytes, content-addressed as stored
```

A backup is complete only when `manifest.enc` decrypts, its GCM tag verifies, and
every `contentHash` it references exists with a matching SHA-256. The receiver
runs that check when the manifest uploads; `latchd verify` runs it again on
demand.

## Protocol

Receiver endpoints (bearer-gated; anything else gets 401):

| Endpoint | Direction | Purpose |
|---|---|---|
| `GET /info` | phone → desktop | `{app, protocol, hasManifest, hasKeybundle, hashes[]}` for diffing |
| `PUT /keybundle` | push | Install or refresh the wrapped key bundle |
| `PUT /blob/<sha256>` | push | One as-stored blob; SHA-256 checked before publication (422 on mismatch) |
| `PUT /manifest` | push | Completion signal: atomic swap, verify, reap; 200 only if the backup verifies |
| `POST /usb-hello` | USB | Tap-to-approve handshake; loopback only, LAN callers get 404 |

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

The crypto is a Go reimplementation of the phone stack using
`golang.org/x/crypto`: Argon2id unwraps the master key, AES-GCM decrypts the
manifest, and PBKDF2-HMAC-SHA256 + AES-256-GCM/CTR decrypts each file with the
parameters carried in manifest v2.

## Limits and deferred work

- **Snapshot only.** Entries deleted on the phone disappear from the next backup;
  superseded blobs are reaped after the manifest swap.
- **Active files only.** No Recently Deleted, collection definitions, or full
  settings.
- **No folder tree in the UI.** Files carry `folderId`, but folder rows live only
  on the phone, so the UI offers type views. A manifest v3 with folder records is
  a follow-up.
- **No retention.** There's one mutable `latch-backup/`. Dated snapshots and
  pruning are still deferred.
- **Memory:** desktop snapshot construction buffers payloads in memory. Large
  snapshots need hardware measurement before anyone calls them safe.
- **ZIP export still exists:** `BackupService` remains, and its
  `_passwords_index.json` inclusion is a hardening item to revisit.
- **Receiver idle timeout:** 5 minutes without a successful authenticated
  request.

## How it's tested

For each piece, we have one check that should pass and one security path that
should fail:

- `test/desktop_push_test.dart`: push against a stub receiver; unauthenticated
  requests abort; only missing blobs and the manifest-last sequence are sent.
- `latchd` receiver tests: bearer-gated round trip; tampered blob → 422 with
  nothing written; manifest completes and verifies.
- `test/desktop_restore_test.dart`: push → wipe → restore → unlock.
- Manual acceptance is still required: fresh install, restore from the USB
  drive, open with the original password.

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

`latchd` credentials come from `--password` or `LATCHD_PASSWORD`. They are never
stored.
