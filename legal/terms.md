# Latch Terms and Conditions

**Version 2 — Last updated: 2026-11-12**

These Terms govern your use of Latch (mobile app) and latchd / Latch Web (desktop companion). By using the software you accept these Terms plus the EULA (`eula.md`) and Privacy Policy (`privacy.md`).

## 1. The service (such as it is)

Latch provides local software only. There is no hosted service, no account system, and no server operated by us. Everything runs on hardware you control: your phone and your desktop.

## 2. License

The software is MIT-licensed. You own your data at all times. We claim no rights over your vault contents.

## 3. Privacy

We collect nothing. No analytics, no telemetry, no crash reports sent externally, no ads, no tracking. Details are in the Privacy Policy (`privacy.md` / in-app Settings → Privacy Policy).

## 4. Security properties and limits

- Hiding is the default; file encryption is opt-in. Hidden-only files remain readable on disk. Encrypted files use AES-256 with per-file keys; the master key is wrapped using a credential-derived key (Argon2id/PBKDF2 and AES-GCM unwrap).
- Desktop backup and WebDAV transfer file payloads as stored, including plaintext hidden-only files. Manifests are encrypted. Desktop backup also exports a wrapped master-key bundle, not the plaintext key; restoring onto a fresh install requires the original credential. The companion uses your entered vault password in memory, not as a saved plaintext credential.
- Pairing uses a per-session 256-bit token and closes on completion, cancel, or 5-minute idle timeout. The web UI binds loopback (`127.0.0.1`) only; only the pairing receiver touches the LAN, and only while a session is active.
- Desktop pairing uses plain HTTP, not TLS, with an explicit warning. The token gates access, not network confidentiality; hidden-only file contents can be exposed. Use trusted LAN/USB and prefer HTTPS for WebDAV.
- No software is perfectly secure. A compromised OS, a stolen unlocked device, or a weak password can defeat any local vault. Use a strong password, keep your OS updated, and lock your devices.

## 5. Backups, restore, export

- Desktop backup contains an encrypted manifest, as-stored content-addressed payloads, and a wrapped key bundle. Verify the manifest and every referenced blob, and test restore with the original credential. New backups exclude Recently Deleted; folder/album definitions and saved smart collections are not included.
- Existing-vault restore keeps the current key, replaces matching file IDs and adds new entries; unrelated local entries remain. A backup from another key cannot be merged this way. Fresh-install restore installs the received wrapped key after credential verification. Missing blobs are reported as skipped, not restored.
- "Export decrypted" writes plaintext to `~/latchd-exports/<folder>` (desktop) or your chosen location (mobile ZIP export). That output is no longer protected by Latch.
- You are responsible for the confidentiality, integrity, and retention of backup media.
- Local deletion does not erase older backups or retained server blobs. Uninstalling or clearing app data removes the local vault and keys; do not use a live vault for reinstall/clear-data testing.

## 6. Updates

Mobile updates ship via the Play Store / GitHub releases; desktop updates ship as new latchd binaries. Updating is your choice, but running old versions may miss security fixes. Release notes may be fetched from GitHub (user-triggered update check only).

## 7. Prohibited conduct

Do not misuse the software: no unlawful content, no infringing others' rights, no attacking other installations, no misrepresenting the software's security properties to third parties.

## 8. Warranty and liability

As in the MIT license and EULA: provided "AS IS", no warranties, no liability for any damages including data loss, to the maximum extent permitted by law.

## 9. Termination and changes

You may stop using the software at any time by uninstalling. Material changes to these Terms require re-acceptance (version in `legal/version.txt`); continued use after acceptance constitutes agreement.
