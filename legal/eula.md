# Latch End-User License Agreement (EULA)

**Version 2 — Last updated: 2026-11-12**

This End-User License Agreement ("Agreement") is between you ("User") and the Latch project ("we", "Latch"). By installing, running, or using Latch (the mobile app) or latchd / Latch Web (the desktop companion), you agree to this Agreement. If you do not agree, do not install or use the software.

This is a plain-language summary of the terms in `terms.md` plus the license grant below. Where they differ, the MIT license and `terms.md` control.

## 1. License grant

Latch is licensed under the MIT License (see `LICENSE` / `LICENSE.txt`):

- You may use, copy, modify, merge, publish, distribute, and sell copies of the software, subject to keeping the copyright and permission notices.
- The software is provided "AS IS", without warranty of any kind.

## 2. What Latch is

- A device-first vault. Hiding is the default; file encryption is opt-in. Hidden-only files retain readable bytes. The master key is wrapped using a key derived from your credential.
- Desktop backup and WebDAV move file payloads **as stored**, including unencrypted files. Their manifests are encrypted. Desktop backup also transfers a wrapped key bundle; a fresh-install restore needs the original vault credential.
- There are no project-run accounts, hosted vaults, analytics, or tracking. You may explicitly transfer data to your own computer, server, or selected apps. See the Privacy Policy.

## 3. Your responsibilities

- **Remember your password/PIN.** There is no recovery. A lost credential means a lost vault — we cannot unlock it for you.
- **Keep your own backups.** You choose where backups live (phone, desktop folder, USB drive). You are responsible for securing that storage.
- **Pair on networks you trust.** Pairing opens a token-gated receiver over plain HTTP, not TLS. The token controls access but does not encrypt traffic; hidden-only files can cross the network as plaintext. Prefer trusted LAN/USB and HTTPS for WebDAV. Do not pair on hostile or public networks.
- **Export decrypted means plaintext.** The optional "export decrypted" action writes readable files to disk. Only use it where that disk is safe.
- **Keep your devices secure.** OS lock screen, disk encryption, and physical control of the backup drive are your job.
- **Understand restore.** Existing-vault restore keeps the local key, replaces matching file IDs, adds new entries, and leaves unrelated local entries intact. Fresh-install restore installs the wrapped key only after credential verification. New backups exclude Recently Deleted and do not include folder/album definitions or saved smart collections.

## 4. Acceptable use

- Do not use Latch to violate the law or the rights of others.
- Do not attempt to bypass the pairing token, authentication, or encryption controls of other people's installations.
- You are responsible for the content you choose to store.

## 5. No warranty, limited liability

To the maximum extent permitted by law: the software is provided "AS IS" without warranties of merchantability, fitness for a particular purpose, or non-infringement. In no event are the authors liable for any claim, damages, or loss (including data loss) arising from use or inability to use the software.

## 6. Termination

This Agreement terminates if you stop using the software or breach its terms. You may terminate at any time by uninstalling and deleting your copies. Sections 5 (warranty/liability) survives termination.

## 7. Changes

If this Agreement changes materially, the app and Latch Web will ask you to accept the new version before continuing. The current version number is in `legal/version.txt`.
