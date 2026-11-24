# Stable release checks

## Where things stand

**Not approved for stable release yet.** Build and automated checks are
necessary, but physical-device acceptance hasn't been recorded. This document
doesn't authorize installation, upgrade, publication, or destructive testing.

The November 2026 review left three gates:

| Gate | Status |
|---|---|
| Accurate security/privacy and restore disclosures | Fixed in this working tree; legal version 2 needs renewed consent |
| Current native code in the Android release artifact | Verified in the rebuilt local AAB below; fingerprinted builds reject stale payloads |
| Recorded hardware, upgrade, restore, and interruption acceptance | **Waiting on explicit target approval and execution** |

Finishing roadmap items doesn't replace these gates. Don't promote the beta or
publish a release just because a build succeeds.

## Safety preflight — read before touching hardware

- **No automatic installation on the owner's phone or PC.** The commands below
  don't use `adb install`, `flutter run`, installers, or app-data resets. Don't
  replace a desktop executable, register a service, or run a downloaded
  installer as part of verification.
- Use a **spare arm64 Android device with no personal Latch vault**. An emulator
  can supplement testing, but it can't replace physical-device acceptance. If
  there's no isolated physical target, stop and leave the gate pending.
- Get approval for the **exact target** before changing anything: device
  identifier/profile, package ID, source and candidate versions, artifact path
  and SHA-256, and action (fresh install or test upgrade). A connected USB
  device is not approval. An AAB isn't directly installable; record the hash and
  native verification for any APK you derive or deliver.
- Use generated/non-sensitive fixtures and dummy credentials only. A test
  upgrade starts from an older build seeded with fixtures on the isolated
  target — never from an experiment on the personal vault.
- On the PC, don't install or replace `latchd`. An approved run uses a local test
  binary, a fresh private `LATCHD_CONFIG_DIR`, and separate backup/export
  directories under a uniquely created disposable test root. Don't use the
  default config, an existing backup directory, a mounted personal drive, or
  current decrypted exports. Check the paths before starting.
- Verify a fixture backup independently before any reinstall/reset scenario. Keep
  its original credential and a separate fixture inventory/hash list. A personal
  backup is not disposable test material.
- Uninstall, clear-data, wipe, permanent delete, and destructive recovery tests
  need **separate explicit approval for the disposable target and paths**.
  Never change the phone clock, factory-reset a device, or recursively clean
  broad directories. Cleanup stays inside the exact test root you created.
- Localhost test servers use ephemeral ports, temporary data, and test tokens.
  LAN/USB pairing tests need separate approval for the receiver and network.
  Never expose the receiver publicly or point tests at a personal sync server.
- A backup doesn't give permission to risk personal data. If isolation, key
  continuity, or destination ownership is unclear, stop and ask.

## Build-only checks

Use the toolchain pinned in the README and the project's existing dependencies.
Don't silently install tools or applications on the owner's system. Resolve
missing prerequisites explicitly first.

```sh
flutter pub get --enforce-lockfile
make legal-sync
make packaging-test
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
make latchd-test
(cd pocketbase && go test ./...)
make android-release-aab
python3 scripts/pocketbase_artifact.py verify build/app/outputs/bundle/release/app-release.aab
```

`make pb` compiles to a temporary sibling and only replaces the generated,
gitignored native artifact after verification. It doesn't run the sidecar. The
verifier reads Go build metadata and a retained source fingerprint, and checks
Android/ABI/CGO, the pinned PocketBase/SQLite versions, Go's minimum version,
and native source/embedded migration/module-lock inputs. It also reads the
sidecar inside APK/AAB archives without installing or executing it.

Direct Gradle release builds reject a missing or stale sidecar. CI also checks
both Go modules, packaging regressions, and the native payload of an arm64 debug
APK, so it doesn't need the private release keystore. A debug artifact is not
signed release acceptance. After changes, rebuild and re-record evidence for the
final candidate; old hashes and sign-offs don't carry forward.

## Hardware acceptance — all pending

Record pass/fail, target/Android version, exact artifact, settings, expected vs.
actual behavior, and redacted evidence. Don't store tokens, keys, real filenames,
or credentials in the record.

| Check | What needs to pass | Procedure |
|---|---|---|
| Legal consent and disclosures | Prior-version acceptance prompts for version 2 on mobile/desktop; hiding/HTTP/as-stored warnings are visible | `legal/*`, desktop/mobile consent flows |
| PocketBase on Android | Real arm64 sidecar starts, health succeeds, all collections work, no unnoticed legacy fallback; lock/restart lifecycle works | [PocketBase checks](pb_testing.md) |
| Upgrade and migration | Prior-version fixture vault survives an in-place test upgrade with files, settings, metadata, and key continuity; no duplicate/lost entries | PocketBase checks + inventory comparison |
| Desktop backup/restore | Hash-check fixture backup; fresh setup restores with the original credential; wrong credential fails safely; existing restore replaces matching IDs and leaves unrelated entries alone | [Desktop backup](desktop_backup.md) |
| USB and QR pairing | Manual/QR paths and cancellation work; camera permission denial is recoverable; no unintended receiver or default-path use | Desktop backup + approved transport |
| Large operations | 1–2 GB WebDAV transfers and a representative large multi-file desktop snapshot finish responsively without memory failure; verify output bytes | [WebDAV checks](local_server_testing.md) |
| Interruptions and conflicts | Cancel, lock mid-transfer, force-stop/restart, and two-client conflict choices preserve source/committed data; unsafe servers are rejected | [Sync policy](local_server_sync.md), WebDAV checks |
| Local recovery | Recently Deleted deadlines, metadata/encryption restoration, restart replay, backup exclusion, decoy isolation, and approved test-only deletion cases work | [Device checks](phase5_testing.md) |
| Android integration | Camera/pickers/share intake, import failures/cancellation, and source-original preservation work; Autofill uses dummy logins | Device checks, [Autofill](unlock_autofill.md) |
| Viewing and accessibility | Media/document/song paging, export/unhide/editing, TalkBack, large text, and navigation work on the release artifact | Device checks |
| Key portability | A fresh fixture install plus desktop restore establishes the original master key before a WebDAV pull; ordinary fresh setup alone can't decrypt the old vault | WebDAV + desktop checks |

Desktop snapshot construction currently buffers all payloads in memory. Its
large-vault behavior needs its own device test; passing streaming WebDAV tests
doesn't prove the snapshot path is safe. Never test limits with irreplaceable
files.

## Evidence record — 2026-11-12

Scope: committed and pushed on `versionF` through `aa9b7b8`, based on the
release-safety work in `3fc89c7` (from
`19afbd517c8ede482bfc16f8effdf04abd0930fc`, plus the owner's QR scanner work).
PR #130 merged that work into `main`; PR #135 carries the receiver shutdown fix.
This still isn't a tagged stable release or hardware acceptance.

| Check | Result |
|---|---|
| Packaging regression tests | 13 pass, fake/temp artifacts only; the preserved old native binary is rejected without execution |
| Remote CI on pushed commit | `versionF` run `43184997129` passed both jobs; `main` run `43194966766` failed `TestReceiverPushRoundtrip` (keep-alive reuse), fixed by `aa9b7b8`; PR #135 run `43341442515` passed both jobs |
| Pairing receiver shutdown | Idle keep-alive connections drain on stop; 100 repeated receiver-package runs, the full `latchd` suite, and `go vet` pass |
| Mobile legal/consent tests | 7 pass, including stale version-1 acceptance and bundled privacy equality |
| Desktop web assets | TypeScript + Vite production build passes with existing dependencies |
| `latchd` Go tests | Pass, including canonical/embedded legal consistency and renewed version-2 consent |
| Full Flutter suite / analysis / formatting | 367 tests pass; no analysis issues; 243 Dart files formatted with zero changes |
| PocketBase Go bootstrap/persistence checks | Pass: build-info creates no data, token authorization/rotation, four migrations, REST writes, restart persistence, and fixture deletion; isolated temporary host database, not Android |
| Native and signed release bundle | `make android-release-aab` passes; packaged PocketBase 0.40.4 matches current native sources and dependencies; `jarsigner -verify` reports `jar verified` (warnings below) |
| Packaged disclosures | Canonical privacy/terms/EULA, bundled privacy asset, and changelog match current source files byte-for-byte |
| Static native page alignment | All 16 packaged 64-bit ELF libraries have LOAD alignment of at least 16 KiB; no runtime 16 KiB-device compatibility claim |
| Live WebDAV | Earlier audit: 4 pass against isolated loopback rclone; no physical-device key/transport sign-off |
| Phone/PC installs, personal vault or backup mutations | **None performed** |
| Hardware target/artifact approval and execution | **Not granted / not run** |

Final local artifact (build-only, not installed or published):

- Path: `build/app/outputs/bundle/release/app-release.aab`
- Size: `69,868,512` bytes
- SHA-256: `31810a6638fb0172ced59becc566f6b8b9b274f35f9b3782c289e9630090cc5c`
- Packaged native source fingerprint: `c9ea74ba952206c3876f83f1527396e10c85fced88851fb27422bc16705b6ff0`

Signature verification reports self-signed/untrusted-chain, missing timestamp,
POSIX-attribute, and JarFile/JarInputStream manifest-order warnings. That's not
proof of Play acceptance. Flutter also warns about a future built-in Kotlin
migration; the pinned toolchain builds fine today.

A knowledge-graph refresh was attempted with `graphify update .`. Its existing
semantic-node preservation guard refused the update, and the saved graph wasn't
force-overwritten or deleted. That's a tooling limitation, not a passing graph
refresh or an Android build failure.

GitHub reports 14 open Dependabot alerts for `latchd/web-src` development
tooling: Vite, its `fast-uri` dependency, and CLI transitive packages such as
`@hono/node-server`, `minimatch`, `systeminformation`, and `deepmerge`. The
shipped web UI is prebuilt static output; these packages don't run in the app or
the latchd binary. Treat them as build-environment maintenance, not runtime
stable gates, and keep the committed build reproducible when updating.

## Release call

Stable stays **NO-GO** until the hardware matrix has a recorded pass for the
final candidate and a maintainer explicitly approves release. Fix any
correctness or data-loss finding first. Then choose the stable version/build
metadata, reconcile beta/prerelease labels and support policy, verify the exact
signed/distributed artifacts, and approve publication separately. Make sure the
public/store-facing privacy and security disclosures match the final release
too — editing local copies doesn't publish them.

Deferred refactors, remote blob garbage collection, snapshot retention UI, and
the future Kotlin toolchain migration aren't automatically stable blockers. Keep
their limitations honest, but don't trade away recovery/security acceptance to
finish unrelated polish.
