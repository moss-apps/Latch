# Contributing to Latch

Thanks for your interest. Latch is a local-first, encrypted media vault for
Android, with a small Go desktop companion (`latchd`) for encrypted backups.
The docs in [`docs/`](./docs) are the source of truth — if a change alters
behavior, scope, or setup, update the relevant doc in the same pull request.

## Invariants

These are non-negotiable; changes that violate them will not be merged:

- **No cloud.** No backend service, account, sync, telemetry, or analytics.
  Network traffic is limited to loopback `latchd` pairing/backup, sync the user
  explicitly configured (PocketBase/WebDAV/SMB), and Play Store updates.
- **Media leaves the device encrypted.** Vault backups and sync carry
  ciphertext only.
- **Secrets never leave secure storage.** PINs, passwords, and keys go through
  `flutter_secure_storage` (Android Keystore) only — never into logs, prefs,
  plaintext files, or crash output.
- **Security defaults stay on.** Auto-kill and screenshot protection must not
  be silently weakened.
- **Android, `arm64-v8a`** for the embedded PocketBase sidecar. Adding ABIs is
  a deliberate decision, not a drive-by change.

## Prerequisites

- Flutter 3.47.2 (stable) — the version pinned in CI
- Dart SDK `>=3.4.4` (ships with Flutter)
- Android SDK API 36, JDK 17; a device or emulator running API 26+
- Go 1.25.x for `latchd` and the PocketBase sidecar
- Node (only for `latchd/web-src` UI work)

## Setup

```sh
flutter pub get
make pb          # build the arm64-v8a PocketBase sidecar into jniLibs
make latchd      # build the desktop companion (optional)
```

`make latchd-web` rebuilds the committed `latchd` web UI from `web-src/` and is
only needed when touching that UI.

## Checks

Run these before opening a pull request (CI runs the same set):

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
make latchd-test        # if latchd or pocketbase changed
```

If you touch `pocketbase/`, also verify the sidecar still builds with `make pb`.

## Pull requests

1. Branch from `versionF` (`feat/…`, `fix/…`, `docs/…`, `chore/…`). Pull
   requests target `versionF`; maintainers merge `versionF` into `main` for
   releases.
2. Keep commits focused; imperative mood, concise subject (match the existing
   history style).
3. Fill in the PR template. CI must be green before review.
4. Update `CHANGELOG.md` under the current version heading.
5. Never commit secrets, keys, tokens, or machine-local files (`key.properties`,
   keystores, `graphify-out/` — see `.gitignore`).

## Architecture

| Area | Contents |
|---|---|
| `lib/crypto/` | Pure-Dart ciphers, key derivation and wrapping |
| `lib/services/` | Auth, encryption, file/vault ops, sync, backup, media |
| `lib/providers/` | Riverpod reactive state |
| `lib/screens/`, `lib/widgets/` | Feature UI |
| `android/app/src/main/kotlin/` | Auto-kill, permissions, native bridges |
| `latchd/` | Go desktop companion (web UI, pairing, backup) |
| `pocketbase/` | Embedded PocketBase sidecar wrapper |

## Reporting bugs and requesting features

Use the issue templates. For security issues, do **not** open a public issue —
follow [SECURITY.md](./SECURITY.md). Questions and ideas go to
[Discussions](https://github.com/moss-apps/Latch/discussions).

## Code of conduct

Participation is governed by [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md).

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](./LICENSE).
