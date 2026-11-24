# Security policy

Latch hides photos, videos, and documents in a local Android vault. **File
encryption is opt-in. Hiding does not encrypt bytes.** There is no project-run
backend, account system, or telemetry. The network surfaces are loopback
PocketBase, the optional `latchd` desktop companion (a loopback web UI plus a
temporary LAN/USB pairing receiver), sync the user configured, and explicit
update checks or actions started by another app.

## Supported versions

Only the latest Google Play release and the latest `0.*` GitHub release
(including `latchd`) get fixes. Beta builds don't.

## Reporting a vulnerability

**Please don't open a public issue for a security problem.**

- Preferred: use GitHub's private vulnerability reporting:
  [Report a vulnerability](https://github.com/moss-apps/Latch/security/advisories/new).
- Or email **fyketonel@gmail.com** with steps to reproduce.

You should hear back within a few days. Include the app version, device and
Android version, install source (Google Play, GitHub APK, or built from source),
and as much detail as you can without exposing real credentials or private
media.

## What counts

- Vault passwords, PINs, or keys leaking into logs, crash output, preferences,
  thumbnails, or the UI
- Weaknesses in vault encryption (AES-256-GCM/CTR, Argon2id key wrapping,
  per-file key derivation) or in how `flutter_secure_storage` is used
- Ways around the decoy vault, auto-kill, or screenshot protection that expose
  vault contents
- Unexpected network traffic or misleading encryption/transfer disclosures
- `latchd` problems: pairing token bypass, exposing the web UI beyond loopback,
  or weaknesses in the backup archive or manifest
- Android surface issues: exported components, `locker://` deep links,
  permissions

## What doesn't

- Bugs in third-party apps or SDKs (Flick, WebDAV/SMB servers, …)
- Compromised, rooted, or physically accessed devices
- Denial of service from large files or user-chosen input
- Social engineering

## What we try to guarantee

- Credentials and local key material use `flutter_secure_storage` (Android
  Keystore). Secrets never go in logs or ordinary preferences and error
  messages. Desktop backup intentionally exports a **wrapped** master-key
  bundle, not a plaintext one; restoring it needs the original credential.
  Decrypted exports are explicitly outside the vault's protection.
- File encryption follows each file's chosen policy. Desktop backup and WebDAV
  preserve payloads **as stored**, including hidden-only files that are
  plaintext. Their manifests are encrypted; that does not encrypt the payloads.
  Desktop pairing uses token-gated HTTP, not TLS. Tokens are access control, not
  transport confidentiality. Use a trusted LAN or USB, and prefer HTTPS for
  WebDAV.
- `latchd`'s web UI binds to loopback only (`127.0.0.1:7800`). Pairing is
  token-gated and only exists while a session is active.
- No analytics, external crash reporting, or project-operated cloud storage.
  Backup, sync, sharing, and exports that the user starts can copy data off the
  device.

Thanks for helping keep users safe.
