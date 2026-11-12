# Privacy Policy

**Version 2 — Last updated: 2026-11-12**

Latch is on-device-first. The project operates no account service or hosted
vault and collects no telemetry. Your files stay local unless you choose an
export, share, desktop backup/restore, or server sync. Those actions can copy
file contents and metadata to destinations you control or select.

## Data we do not collect

- No personal information (name, email, phone number, etc.)
- No usage analytics or telemetry
- No crash reports or diagnostics sent externally
- No advertising identifiers or tracking data
- No location data
- No device identifiers
- No contacts, messages, or call logs
- No browsing history or app usage data

## Camera and microphone access

Camera access is used to scan pairing QR codes or capture media you choose to
import. Microphone access is used for audio/video recording you request.
Captured files follow your encryption choices and may later be transferred
through the explicit actions described below.

## Media & files

Hiding is the default; **file encryption is opt-in**, globally or per file.
Hidden-only files retain readable bytes on disk. Files you choose to encrypt
use AES-256. Hiding, a locked interface, and an encrypted manifest do not make
an unencrypted file's contents encrypted.

## Storage permission

Used to read files you choose to import and to write, restore, export, or
remove files through the app. Source deletion and permanent deletion require
your chosen settings/actions; flash-storage erasure cannot be guaranteed.

## Biometric authentication

Biometric data is handled entirely by the OS. Latch only receives a
success/failure signal and never stores or accesses your biometric data.

## Third-party services

Latch integrates with no analytics, advertising, or tracking services.
User-directed connections can include:

- Desktop backup/restore over LAN or USB, and a WebDAV server you configure
- App-store or GitHub update/release checks and links
- External apps you choose for sharing, export, playback, or credential filling
- Ko-fi donation link (optional, opened in your browser)

These destinations may receive the content or connection information needed
for your action and are subject to their own policies. We do not operate them.

## Backups, sync, and keys

- Desktop backups and WebDAV sync encrypt the manifest but transfer file
  payloads **as stored**. Hidden-only files remain unencrypted at the destination.
- Desktop pairing uses token-gated **HTTP, not TLS**. The token does not encrypt
  network traffic. Use trusted LAN/USB, especially for hidden-only files. Prefer
  HTTPS for WebDAV; HTTP is unsuitable for untrusted networks.
- Desktop backup exports the master key only as a credential-wrapped key bundle;
  a fresh-install restore needs the original credential. WebDAV does not upload
  that key bundle. Decryption temporarily uses keys in app/companion memory.
- ZIP backup and decrypted export write readable copies to your chosen location.
  Protect those copies and any hidden-only backup files yourself.
- New backups exclude Recently Deleted. Permanent local deletion does not erase
  earlier backups or retained remote blobs. Uninstalling/clearing app data removes
  the local vault and key material; keep an independently verified backup.

## Children's privacy

Latch does not knowingly collect any information from anyone, including
children under 13. No data is collected, so none can be gathered from
minors.

## Changes to this policy

Updates are reflected in the app. Review periodically.

## Contact

Questions about this policy: reach out through the project repository.
