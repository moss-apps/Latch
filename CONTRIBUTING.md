# Contributing to Latch

Thanks for your interest. Latch is a local-first media vault with opt-in
encryption for Android and a small Go desktop backup companion (`latchd`).
The docs in [`docs/`](./docs) are the source of truth — if a change alters
behavior, scope, or setup, update the relevant doc in the same pull request.

## Invariants

These are non-negotiable; changes that violate them will not be merged:

- **No cloud.** No backend service, account, sync, telemetry, or analytics.
  Network traffic is limited to loopback/LAN `latchd` pairing/backup, sync the user
  explicitly configured (PocketBase/WebDAV/SMB), and Play Store updates.
- **Preserve encryption choices.** Sync and desktop backup carry payloads as
  stored, including hidden, unencrypted files. Never claim hiding is encryption.
  Local ZIP export deliberately decrypts files; disclose that boundary.
- **Protect secrets.** Use `flutter_secure_storage` (Android Keystore) for local
  credentials/key wraps, never logs, ordinary prefs, or crash output. Desktop
  backup deliberately exports a credential-wrapped key bundle, not a plaintext
  master key. Explicit decrypted exports are outside vault protection.
- **Preserve security settings.** Auto-kill defaults on; file encryption and
  screenshot protection default off. Do not silently change saved choices.
- **Android, `arm64-v8a`** for the embedded PocketBase sidecar. Adding ABIs is
  a deliberate decision, not a drive-by change.

## Prerequisites

- Flutter 3.47.2 (stable) — the version pinned in CI
- Dart SDK `>=3.4.4` (ships with Flutter)
- JDK 17 and Android SDK/NDK versions required by the pinned Flutter/Gradle
  configuration; a device or emulator running API 26+
- Go 1.27+ for the PocketBase sidecar; Go 1.26+ for `latchd` (see each `go.mod`)
- Node (only for `latchd/web-src` UI work)
- Python 3 and Make for the native artifact fingerprint/build gate

## Setup

```sh
flutter pub get
make pb          # build the arm64-v8a PocketBase sidecar into jniLibs
make latchd      # build the desktop companion (optional)
```

`make latchd-web` rebuilds the committed `latchd` web UI from `web-src/` and is
only needed when touching that UI.

## Checks

Run these before opening a pull request:

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
make packaging-test
make latchd-test        # desktop Go module
(cd pocketbase && go test ./...)
```

If you touch `pocketbase/`, also run `make pb` and `make pb-verify`. CI checks
both Go modules and a freshly built arm64 debug APK's actual native payload.
For a signed release AAB, use `make android-release-aab` after dependency
resolution and local signing setup. This builds only; it never installs.
Direct release builds fail closed on a stale/missing sidecar.

Run `make legal-sync` after canonical legal edits; mobile/desktop tests guard
the bundled copies. Material changes require updating `legal/version.txt` and
both consent constants. Hardware checks require the explicit approval and
isolation preflight in [stable release checks](docs/stable_release_checklist.md).

## Pull requests

1. Branch from `versionF` (`feat/…`, `fix/…`, `docs/…`, `chore/…`). Pull
   requests target `versionF`; maintainers merge `versionF` into `main` for
   releases.
2. Keep commits focused; imperative mood, concise subject (match the existing
   history style).
3. Fill in the PR template. CI must be green before review.
4. Update `CHANGELOG.md` under `Unreleased`; do not rewrite released entries.
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
