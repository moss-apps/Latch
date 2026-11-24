# Contributing to Latch

Thanks for wanting to help. Latch is a local-first media vault for Android with
opt-in encryption, plus a small Go desktop backup companion (`latchd`). The docs
in [`docs/`](./docs/README.md) are the source of truth: if a change affects
behavior, scope, or setup, update the relevant doc in the same pull request.

## Rules we don't bend

These aren't negotiable. Please don't send changes that break them.

- **No cloud.** No backend service, account system, sync service, telemetry, or
  analytics. Network traffic is limited to loopback/LAN `latchd` pairing and
  backup, sync the user explicitly configured (PocketBase/WebDAV/SMB), and Play
  Store updates.
- **Keep encryption choices intact.** Sync and desktop backup carry payloads as
  stored, including hidden files that are not encrypted. Never claim that hiding
  is encryption. Local ZIP export intentionally decrypts files; say so.
- **Protect secrets.** Use `flutter_secure_storage` (Android Keystore) for local
  credentials and key wraps. Never put them in logs, ordinary preferences, or
  crash output. Desktop backup intentionally exports a credential-wrapped key
  bundle, not a plaintext master key. Explicit decrypted exports are outside the
  vault's protection.
- **Respect saved security settings.** Auto-kill defaults on; file encryption and
  screenshot protection default off. Don't silently change a user's choices.
- **Android, `arm64-v8a`, for the embedded PocketBase sidecar.** Adding another
  ABI is a deliberate decision, not a drive-by change.

## What you need

- Flutter 3.47.2 (stable), the version pinned in CI
- Dart SDK `>=3.4.4` (comes with Flutter)
- JDK 17 and the Android SDK/NDK versions required by the pinned Flutter/Gradle
  setup; a device or emulator on API 26+
- Go 1.27+ for the PocketBase sidecar; Go 1.26+ for `latchd` (check each
  `go.mod`)
- Node, only if you're working on the `latchd/web-src` UI
- Python 3 and Make for the native artifact fingerprint/build check

## Setup

```sh
flutter pub get --enforce-lockfile
make pb          # build the arm64-v8a PocketBase sidecar into jniLibs
make latchd      # build the desktop companion (optional)
```

`make latchd-web` rebuilds the committed `latchd` web UI from `web-src/`. You
only need it when you're changing that UI.

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
both Go modules and the native payload in a freshly built arm64 debug APK. For a
signed release AAB, use `make android-release-aab` after dependency resolution
and local signing setup. It builds only and never installs. Release builds fail
closed when the sidecar is stale or missing.

Run `make legal-sync` after editing the canonical legal files; mobile and desktop
tests guard the bundled copies. Material changes require bumping
`legal/version.txt` and both consent constants. Hardware checks need the
approval and isolation steps in the
[stable release checklist](docs/stable_release_checklist.md).

## Pull requests

1. Branch from `versionF` (`feat/…`, `fix/…`, `docs/…`, `chore/…`). PRs target
   `versionF`; maintainers merge `versionF` into `main` for releases.
2. Keep commits focused. Use the imperative mood and a short subject, matching
   the existing history.
3. Fill in the PR template. CI has to be green before review.
4. Add a `CHANGELOG.md` entry under `Unreleased`. Don't rewrite released entries.
5. Never commit secrets, keys, tokens, or machine-local files (`key.properties`,
   keystores, `graphify-out/`; see `.gitignore`).

## Where things live

| Area | Contents |
|---|---|
| `lib/crypto/` | Pure-Dart ciphers, key derivation, and wrapping |
| `lib/services/` | Auth, encryption, file/vault ops, sync, backup, media |
| `lib/providers/` | Riverpod reactive state |
| `lib/screens/`, `lib/widgets/` | Feature UI |
| `android/app/src/main/kotlin/` | Auto-kill, permissions, native bridges |
| `latchd/` | Go desktop companion (web UI, pairing, backup) |
| `pocketbase/` | Embedded PocketBase sidecar wrapper |

## Bugs, features, and questions

Use the issue templates. For security problems, **don't open a public issue**;
follow [SECURITY.md](./SECURITY.md). Questions and ideas go to
[Discussions](https://github.com/moss-apps/Latch/discussions).

## Code of conduct

Participation is governed by [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md).

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](./LICENSE).
