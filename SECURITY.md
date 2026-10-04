# Security Policy

Latch keeps photos, videos, and documents in an encrypted local vault on the
device. There is no account, no telemetry, and no cloud. The only network
surfaces are the embedded PocketBase sync layer (local), the optional
loopback-only `latchd` desktop companion, and user-configured WebDAV/SMB sync.
We want to keep it that way.

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
- Unexpected network traffic (media must leave the device only encrypted)
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

- Secrets live only in `flutter_secure_storage` (Android Keystore); never in
  logs, prefs, or error messages.
- Vault contents are encrypted at rest; desktop backups and sync carry
  ciphertext only.
- `latchd`'s web UI binds loopback only (`127.0.0.1:7800`); pairing is
  token-gated and exists only while a session is active.
- No analytics, crash reporting, or cloud sync of any kind.

Thank you for helping keep users safe.
