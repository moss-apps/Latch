# Latch End-User License Agreement (EULA)

**Version 1 — Last updated: 2026-09-16**

This End-User License Agreement ("Agreement") is between you ("User") and the Latch project ("we", "Latch"). By installing, running, or using Latch (the mobile app) or latchd / Latch Web (the desktop companion), you agree to this Agreement. If you do not agree, do not install or use the software.

This is a plain-language summary of the terms in `terms.md` plus the license grant below. Where they differ, the MIT license and `terms.md` control.

## 1. License grant

Latch is licensed under the MIT License (see `LICENSE` / `LICENSE.txt`):

- You may use, copy, modify, merge, publish, distribute, and sell copies of the software, subject to keeping the copyright and permission notices.
- The software is provided "AS IS", without warranty of any kind.

## 2. What Latch is

- A device-first encrypted vault. Your vault key is derived from your password/PIN on your own device and never leaves it in plaintext.
- The desktop companion (latchd) moves **ciphertext only** over the local network. Decryption happens locally after transfer, only after you enter your vault password.
- There are no accounts, no cloud, no analytics, no tracking. See the Privacy Policy.

## 3. Your responsibilities

- **Remember your password/PIN.** There is no recovery. A lost credential means a lost vault — we cannot unlock it for you.
- **Keep your own backups.** You choose where backups live (phone, desktop folder, USB drive). You are responsible for securing that storage.
- **Pair on networks you trust.** Pairing opens a token-gated receiver on your LAN over plain HTTP (the token admits only your phone; content stays encrypted). Do not pair on hostile or public networks.
- **Export decrypted means plaintext.** The optional "export decrypted" action writes readable files to disk. Only use it where that disk is safe.
- **Keep your devices secure.** OS lock screen, disk encryption, and physical control of the backup drive are your job.

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
