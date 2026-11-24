# Latch documentation

`docs/` holds the design, operations, and test references for Latch. The root
[README](../README.md) is the product overview. [CONTRIBUTING](../CONTRIBUTING.md)
covers setup and pull requests.

## Current docs

| Doc | What it's for |
|---|---|
| [Stable release checklist](stable_release_checklist.md) | Release gates, build-only checks, and the hardware sign-off. Read it before any release or device test. |
| [Embedded PocketBase](embedded_pocketbase.md) | How the local metadata sidecar works, what it protects, and what still needs a real phone. |
| [Desktop backup & restore](desktop_backup.md) | Setting up `latchd`, pairing, backup layout, restore modes, and limits. |
| [WebDAV sync](local_server_sync.md) | How sync works, what the server must support, conflicts, and key continuity. |
| [WebDAV test runbook](local_server_testing.md) | Local WebDAV fixture, live tests, and the hardware checklist. |
| [PocketBase test runbook](pb_testing.md) | Host and on-device sidecar checks, plus failure triage. |
| [Media encryption & compression](architecture_media.md) | Import pipeline, encryption choices, compression, and file operations. |
| [Recently Deleted](recently_deleted.md) | Retention, permanent deletion, backups, and sync behavior. |
| [Unlock Autofill](unlock_autofill.md) | Letting a password manager fill the vault unlock field. |
| [Flick integration](flick_integration.md) | Playback handoff contract with Flick. |
| [Device checks](phase5_testing.md) | Recovery, autofill, backup, and gallery regression checklist for a real device. |

## Archived docs

Completed plans and one-off reports are in [archive/](archive/README.md). They're
kept for history and aren't maintained against the current code. Use the docs
above for current behavior.
