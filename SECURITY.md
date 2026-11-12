# Security Policy

Latch hides photos, videos, and documents in a local Android vault. **File
encryption is opt-in; hiding does not encrypt bytes.** There is no project-run
backend, account system, or telemetry. Network surfaces include loopback
PocketBase, the optional `latchd` desktop companion (loopback web UI plus a
temporary LAN/USB pairing receiver), user-configured sync, and explicit update
checks or external-app actions.

## Supported versions

Only the latest Google Play release and the latest `0.*` GitHub release
(including `latchd`) are supported. Beta builds are not.

## Reporting a vulnerability

**Do not open a public issue for security problems.**

- Preferred: use GitHub's private vulnerability reporting —
  [Report a vulnerability](https://github.com/moss-apps/Latch/security/advisories/new).
- Or email **fyketonel@gmail.com** with steps to reproduce.

You should get a response within a few days. Please include the app version,
device/Android version, install source (Google Play, GitHub APK, or built from
source), and as much detail as you can without exposing real credentials or
private media.

## In scope

- Leakage of vault passwords, PINs, or keys into logs, crash output, prefs,
  thumbnails, or the UI
- Weaknesses in vault encryption (AES-256-GCM/CTR, Argon2id key wrapping,
  per-file key derivation) or in `flutter_secure_storage` usage
- Bypasses of the decoy vault, auto-kill, or screenshot protection that expose
  vault contents
- Unexpected network traffic or misleading encryption/transfer disclosures
- `latchd` issues: pairing token bypass, non-loopback exposure of the web UI,
  backup archive or manifest weaknesses
- Vulnerabilities in the Android surface (exported components, `locker://`
  deep links, permissions)

## Out of scope

- Issues in third-party apps or SDKs (Flick, WebDAV/SMB servers, …)
- Compromised, rooted, or physically accessed devices
- Denial of service from large files or user-chosen inputs
- Social engineering

## Design guarantees we aim to uphold

- Credentials and local key material use `flutter_secure_storage` (Android
  Keystore). Never log secrets or put them in ordinary prefs/error messages.
  Desktop backup intentionally exports a **wrapped**, not plaintext, master-key
  bundle; restoring it requires the original credential. Decrypted exports are
  explicitly outside the vault's protection.
- File encryption follows each file's chosen policy. Desktop backup and WebDAV
  preserve payloads **as stored**, including plaintext hidden-only files. Their
  manifests are encrypted; this does not encrypt the payloads. Desktop pairing
  uses token-gated HTTP, not TLS; tokens are access control, not transport
  confidentiality. Use trusted LAN/USB; prefer HTTPS for WebDAV.
- `latchd`'s web UI binds loopback only (`127.0.0.1:7800`); pairing is
  token-gated and exists only while a session is active.
- No analytics, external crash reporting, or project-operated cloud storage.
  User-directed backup, sync, sharing, and exports may copy data off the device.

Thank you for helping keep users safe.
