# Stable release checks

## Decision

**Not approved for stable release yet.** Automated/build checks are necessary,
but physical-device acceptance has not been recorded. This document does not
authorize installation, upgrade, publication, or destructive testing.

The November 2026 review identified three gates:

| Gate | Status |
|---|---|
| Accurate security/privacy and restore disclosures | Corrected in this working tree; legal version 2 requires renewed consent |
| Current native code in the Android release artifact | Verified in the rebuilt local AAB below; fingerprinted builds reject stale payloads |
| Recorded hardware, upgrade, restore and interruption acceptance | **Pending explicit target approval and execution** |

Implementation completion in the roadmap is not a substitute for these gates.
Do not promote the current beta version or publish a release just because a
build succeeds.

## Safety preflight — mandatory before hardware testing

- **No automatic installation on the owner's phone or PC.** Build/test commands
  below do not use `adb install`, `flutter run`, installers, or app-data resets.
  Do not replace a desktop executable, register a service, or run a downloaded
  installer as part of verification.
- Prefer a **spare arm64 Android device with no personal Latch vault**. An
  emulator can supplement but not replace physical-device acceptance. If no
  isolated physical target is available, stop and leave the gate pending.
- Before any device mutation, obtain approval for the **exact target** (device
  identifier/profile), package ID, source and candidate versions, artifact path
  and SHA-256, and action (fresh install or test upgrade). Do not infer approval
  from a connected USB device. An AAB is not directly installable; record any
  derived/delivered APK's hash and native verification too.
- Use only generated/non-sensitive fixtures and dummy credentials. The test
  upgrade must start from an older build seeded with fixtures on the isolated
  target, never an upgrade experiment on the personal vault.
- On the PC, do not install/replace `latchd`. Any approved run must use a local
  test binary, a fresh private `LATCHD_CONFIG_DIR`, and separate explicit backup
  and export directories under a uniquely created disposable test root. Do not
  use the default config, an existing backup directory, mounted personal drive,
  or current decrypted exports. Check the chosen paths before starting.
- Verify a fixture backup independently before any reinstall/reset scenario.
  Keep its original credential and a separate fixture inventory/hash list.
  An existing personal backup is not disposable test material.
- Uninstall, clear-data, wipe, permanent delete, and destructive recovery tests
  require **separate explicit approval for the disposable target and paths**.
  Never change the phone clock, factory-reset a device, or recursively clean
  broad directories. Cleanup is limited to the exact test root that was created.
- Localhost test servers use ephemeral ports, temporary data and test tokens.
  LAN/USB pairing tests require separate approval for the receiver and network.
  Never expose the receiver publicly or point tests at a personal sync server.
- A backup alone does not grant permission to risk personal data. If isolation,
  key continuity, or destination ownership is uncertain, stop and ask.

## Build-only verification

Use the toolchain pinned in the README and existing project dependencies. Do not
silently install tools or applications on the owner's system. Resolve missing
prerequisites explicitly before proceeding.

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

`make pb` compiles to a temporary sibling and replaces only the generated
gitignored native artifact after verification. It does not run the sidecar.
The verifier reads Go build metadata and a retained source fingerprint; it
checks Android/ABI/CGO, the pinned PocketBase/SQLite versions, Go's minimum
version, and native source/embedded migration/module-lock inputs. It also reads
the sidecar inside APK/AAB archives without installing or executing it.

Direct Gradle release builds reject a missing/stale sidecar. CI additionally
checks both Go modules, packaging regressions and an arm64 debug APK's native
payload without needing the private release keystore. A debug artifact is not
signed release acceptance. After changes, rebuild and re-record evidence for
the final candidate; previous hashes/sign-offs do not carry forward.

## Required hardware acceptance — all pending

Record pass/fail, target/Android version, exact artifact, settings, expected vs.
actual behavior and redacted evidence. Do not store tokens, keys, real filenames
or credentials in the record.

| Check | Required result | Detailed procedure |
|---|---|---|
| Legal consent and disclosures | Prior version acceptance prompts for version 2 on mobile/desktop; hiding/HTTP/as-stored warnings are visible | `legal/*`, desktop/mobile consent flows |
| PocketBase on Android | Real arm64 sidecar starts, health succeeds, all collections work, no unnoticed legacy fallback; lock/restart lifecycle works | [PocketBase checks](pb_testing.md) |
| Upgrade and migration | Prior-version fixture vault survives an in-place test upgrade with files, settings, metadata and key continuity; no duplicate/lost entries | PocketBase checks + inventory comparison |
| Desktop backup/restore | Hash-check fixture backup; fresh setup restores with original credential; wrong credential fails safely; existing restore replaces matching IDs and preserves unrelated entries | [Desktop backup](desktop_backup.md) |
| USB and QR pairing | Manual/QR paths and cancellation work; camera permission denial is recoverable; no unintended receiver/default-path use | Desktop backup + approved transport |
| Large operations | 1–2 GB file WebDAV transfers and a representative large multi-file desktop snapshot complete responsively without memory failure; verify output bytes | [WebDAV checks](local_server_testing.md) |
| Interruptions and conflicts | Cancel, lock mid-transfer, force-stop/restart and two-client conflict choices preserve source/committed data; unsafe servers are rejected | [Sync policy](local_server_sync.md), WebDAV checks |
| Local recovery | Recently Deleted deadlines, metadata/encryption restoration, restart replay, backup exclusion, decoy isolation and approved test-only deletion cases work | [Phase 5 checks](phase5_testing.md) |
| Android integration | Camera/pickers/share intake, import failures/cancellation and source-original preservation work; Autofill uses dummy logins | Phase 5 checks, [Autofill](unlock_autofill.md) |
| Viewing and accessibility | Media/document/song paging, export/unhide/editing, TalkBack, large text and navigation work on the release artifact | Phase 5 checks |
| Key portability | A fresh fixture installation plus desktop restore establishes the original master key before WebDAV pull; ordinary fresh setup alone cannot decrypt the old vault | WebDAV + desktop checks |

Desktop snapshot construction currently buffers all payloads in memory. Its
large-vault behavior needs its own device test; passing streaming WebDAV tests
does not establish desktop snapshot memory safety. Never test limits with
irreplaceable files.

## Evidence record — 2026-11-12

Scope: local working tree based on `19afbd517c8ede482bfc16f8effdf04abd0930fc`,
including the owner's uncommitted QR scanner work and these release-safety
changes. This is not a clean tagged release or a new remote CI result.

| Check | Result |
|---|---|
| Packaging regression tests | 13 pass; fake/temp artifacts only; the preserved old native binary is also rejected without execution |
| Mobile legal/consent tests | 7 pass, including stale version-1 acceptance and bundled privacy equality |
| Desktop web assets | TypeScript + Vite production build passes using existing dependencies |
| `latchd` Go tests | Pass, including canonical/embedded legal consistency and renewed version-2 consent |
| Full Flutter suite / analysis / formatting | 367 tests pass; no analysis issues; 243 Dart files formatted with zero changes |
| PocketBase Go bootstrap/persistence checks | Pass: build-info creates no data, token authorization/rotation, four migrations, REST writes, restart persistence and fixture deletion; isolated temporary host database, not Android |
| Native and signed release bundle | `make android-release-aab` passes; packaged PocketBase 0.40.4 matches current native sources and dependencies; `jarsigner -verify` reports `jar verified` (warnings below) |
| Packaged disclosures | Canonical privacy/terms/EULA, bundled privacy asset and changelog match the current source files byte-for-byte |
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
POSIX-attribute and JarFile/JarInputStream manifest-order warnings. It is not
proof of Play acceptance. Flutter also warns about a future built-in Kotlin
migration; the pinned toolchain builds successfully today.

Knowledge-graph refresh was attempted with `graphify update .`. Its existing
semantic-node preservation guard refused the update; the saved graph was not
force-overwritten or deleted. This is a tooling limitation, not a passing graph
refresh or an Android build failure.

## Release authorization

Stable remains **NO-GO** until the hardware matrix has a recorded passing result
for the final candidate and a maintainer explicitly approves release. Resolve
any correctness/data-loss finding first. Then choose stable version/build
metadata, reconcile beta/prerelease labels and support policy, verify the exact
signed/distributed artifacts, and approve publication separately.
Confirm that public/store-facing privacy and security disclosures match the
final release too; editing local copies does not publish them.

Deferred refactors, remote blob garbage collection, snapshot retention UI and
future Kotlin toolchain migration are not automatically stable blockers. Keep
their limitations honest; do not trade away recovery/security acceptance to
complete unrelated polish.
