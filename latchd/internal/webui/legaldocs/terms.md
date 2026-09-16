# Latch Terms and Conditions

**Version 1 — Last updated: 2026-09-16**

These Terms govern your use of Latch (mobile app) and latchd / Latch Web (desktop companion). By using the software you accept these Terms plus the EULA (`eula.md`) and Privacy Policy (`privacy.md`).

## 1. The service (such as it is)

Latch provides local software only. There is no hosted service, no account system, and no server operated by us. Everything runs on hardware you control: your phone and your desktop.

## 2. License

The software is MIT-licensed. You own your data at all times. We claim no rights over your vault contents.

## 3. Privacy

We collect nothing. No analytics, no telemetry, no crash reports sent externally, no ads, no tracking. Details are in the Privacy Policy (`privacy.md` / in-app Settings → Privacy Policy).

## 4. Security properties and limits

- Vault contents are AES-256 encrypted with keys derived from your credential (Argon2id/PBKDF2 + AES-GCM unwrap, per-file keys).
- The desktop transfer moves ciphertext only; the vault password is never sent to the phone or written to disk by latchd (memory only).
- Pairing uses a per-session 256-bit token and closes on completion, cancel, or 5-minute idle timeout. The web UI binds loopback (`127.0.0.1`) only; only the pairing receiver touches the LAN, and only while a session is active.
- Plain HTTP on the LAN is used with an explicit warning (same stance as WebDAV sync). The token gates the session; encryption gates the content.
- No software is perfectly secure. A compromised OS, a stolen unlocked device, or a weak password can defeat any local vault. Use a strong password, keep your OS updated, and lock your devices.

## 5. Backups, restore, export

- Backup is a full encrypted snapshot (manifest + content-addressed blobs + key bundle). A backup is complete only if the manifest decrypts and every referenced blob verifies.
- Restoring over an existing vault replaces it wholesale — confirm explicitly in the UI.
- "Export decrypted" writes plaintext to `~/latchd-exports/<folder>` (desktop) or your chosen location (mobile ZIP export). That output is no longer protected by Latch.
- You are responsible for the confidentiality, integrity, and retention of backup media.

## 6. Updates

Mobile updates ship via the Play Store / GitHub releases; desktop updates ship as new latchd binaries. Updating is your choice, but running old versions may miss security fixes. Release notes may be fetched from GitHub (user-triggered update check only).

## 7. Prohibited conduct

Do not misuse the software: no unlawful content, no infringing others' rights, no attacking other installations, no misrepresenting the software's security properties to third parties.

## 8. Warranty and liability

As in the MIT license and EULA: provided "AS IS", no warranties, no liability for any damages including data loss, to the maximum extent permitted by law.

## 9. Termination and changes

You may stop using the software at any time by uninstalling. Material changes to these Terms require re-acceptance (version in `legal/version.txt`); continued use after acceptance constitutes agreement.
