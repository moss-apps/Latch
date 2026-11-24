# Latch Documentation

`docs/` holds the design, operational, and test references for Latch. The
root [README](../README.md) is the product overview; [CONTRIBUTING](../CONTRIBUTING.md)
is the setup and pull-request guide.

## Current

| Document | Use it for |
|---|---|
| [Stable release checklist](stable_release_checklist.md) | Release gates, no-install build checks, and the recorded hardware sign-off. Start here before any release or hardware test. |
| [Embedded PocketBase](embedded_pocketbase.md) | How the local metadata sidecar works, its security boundary, and its on-device validation gate. |
| [Desktop backup & restore](desktop_backup.md) | `latchd` companion setup, pairing, backup layout, restore modes, and security limits. |
| [WebDAV sync](local_server_sync.md) | Sync model, server requirements, conflict handling, and key continuity. |
| [WebDAV test runbook](local_server_testing.md) | Local WebDAV fixture, live tests, and hardware verification steps. |
| [PocketBase test runbook](pb_testing.md) | Host and on-device sidecar checks and failure triage. |
| [Media encryption & compression](architecture_media.md) | Import pipeline, encryption choices, compression, and file operations. |
| [Recently Deleted](recently_deleted.md) | Retention, permanent deletion, backup, and sync policy. |
| [Unlock Autofill](unlock_autofill.md) | Unlock credential autofill and its security model. |
| [Flick integration](flick_integration.md) | Playback handoff contract with Flick. |
| [Phase 5 device checks](phase5_testing.md) | Recovery, autofill, backup, and gallery regression checklist. |

## Archived

Completed plans and one-off reports live in [archive/](archive/README.md).
They are kept for history and are not maintained against the current code.
Use the documents above for current behavior.
