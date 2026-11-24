# Testing the embedded PocketBase store

This is how to exercise the PocketBase (PB) sidecar described in
[embedded_pocketbase.md](embedded_pocketbase.md), one level at a time:
automated tests → host sidecar → real device. Do them in that order. Each level
catches a different kind of breakage.

## 0. What you need

- Go 1.27+ (check `pocketbase/go.mod`; pure Go, no NDK), Python 3, and Make
- Flutter SDK
- For device tests: an **arm64** Android phone or emulator with USB debugging
- Package ID `com.mossapps.locker` (needed for `adb shell run-as`)

## 1. Automated tests (seconds, no device)

```sh
flutter test test/pb_runtime_test.dart   # stdout handshake parsing
flutter test test/pb_store_test.dart     # codec + DAO round-trip + reconcile
flutter test test/pb_wire_test.dart      # e2e: seed → PB rows → runSync
```

Or run everything: `flutter test`. These use an in-process fake of the sidecar's
REST surface, so they only catch Dart-side regressions.

## 2. Host sidecar (minutes, no device)

Build the Linux binary and run it with a scratch data directory. `--auth-token`
pinning is supported; the app never uses it, but it makes curling easy:

```sh
make pb-linux
mkdir -p /tmp/opencode/locker-pb
./locker-pb --dir=/tmp/opencode/locker-pb --http=127.0.0.1:0 --auth-token=devtoken
```

On stdout you'll see the handshake the Dart runtime parses:

```
LOCKER_PB_PORT=<n>
LOCKER_PB_TOKEN=devtoken
LOCKER_PB_READY=1
```

From another terminal, substitute the port:

```sh
PORT=...   # from the handshake
TOK=devtoken

# token gate: 401 without the header, 200 with it
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:$PORT/api/health
curl -s -H "X-Locker-Token: $TOK" http://127.0.0.1:$PORT/api/health

# collections were auto-created by the embedded JS migrations
curl -s -H "X-Locker-Token: $TOK" \
  'http://127.0.0.1:$PORT/api/collections/vault_files/records' \
  | python3 -m json.tool

# round-trip one record; cipher_meta is an opaque JSON object (this is what
# ciphertext at rest looks like from the outside)
curl -s -H "X-Locker-Token: $TOK" \
  -H 'Content-Type: application/json' \
  -d '{"id":"abc123def456abc","blob_ref":"/vault/ab/cd/x.enc","cipher_meta":{"v":1},"modified_at":1000,"deleted":false}' \
  http://127.0.0.1:$PORT/api/collections/vault_files/records
```

If you want proof that nothing plaintext is stored, look at the SQLite file
directly. Note that PB's app-encrypted columns are opaque blobs, but non-secret
columns like `blob_ref` are plaintext on purpose:

```sh
sqlite3 /tmp/opencode/locker-pb/data.db 'select id, blob_ref from vault_files;'
```

Kill it with Ctrl+C when you're done, and delete `/tmp/opencode/locker-pb` to
reset.

## 3. On-device (the only real check)

Nobody has signed off a physical device yet. Host checks can't prove Android
execution, migration, or upgrade safety. Follow the approval and isolation steps
in the [stable release checklist](stable_release_checklist.md). Don't install,
clear data, or uninstall on a live-vault device for this test.

### 3a. Build only; installation needs separate approval

```sh
flutter pub get --enforce-lockfile
make android-release-aab     # rebuild, fingerprint, and verify packaged native code
```

That produces an AAB, not an installation. `make pb` builds the gitignored
sidecar atomically with a source fingerprint. Release builds fail if it's missing
or stale; `make pb-verify` checks it without running it. To check a derived APK:
`python3 scripts/pocketbase_artifact.py verify <apk-path>`. Debug builds can still
fall back to legacy when the sidecar is missing, so a debug success alone isn't
release evidence. Get approval for an isolated target and the exact artifact hash
before doing the steps below.

### 3b. Drive the app

1. Unlock the **main test vault** on the approved isolated target. Don't use the
   decoy PIN; the decoy never starts PB. Never use personal vault contents.
2. On unlock, the app starts the sidecar, runs the one-time legacy→PB migration,
   attaches PB as the preferred store, and refreshes.

### 3c. Verify

Logcat is the main signal:

```sh
flutter logs                 # or: adb logcat -s flutter
```

Look for:

- `[PB] sidecar up: pid=… port=…`: spawn, handshake, and health all passed.
- No `[PB] … falling back to legacy` lines. Those mean a PB call failed after
  startup and the store degraded. The app still works, but that's not what you're
  testing.

Then use disposable fixtures: add a file, create/rename an album, tag something,
and sync to an isolated test server. Any clear/reset test needs separate explicit
approval on that disposable target. Never clear a live vault.

Optional, on a debug build (debuggable APKs allow `run-as`):

```sh
adb shell run-as com.mossapps.locker ls files/pocketbase/
# data.db  data.db-wal  migrations/  sidecar.pid
adb shell run-as com.mossapps.locker sh -c \
  'cat files/pocketbase/sidecar.pid'
```

The port and token are ephemeral and live in app memory, so you can't curl the
device sidecar from outside. App behavior plus logcat is the intended
observability for now.

### 3d. Reset PB state on device

- Full reset (drops PB rows **and** vault files): Settings → clear vault. This
  also wipes the PB rows (`PocketBaseStore.wipe`).
- Migration rerun only: delete the secure-storage flag. The easy way is clear
  vault, or `adb shell pm clear com.mossapps.locker` (which nukes everything,
  including vault credentials, and is effectively a fresh install).

## 4. When it fails

| Symptom | Meaning |
|---|---|
| "PocketBase binary missing at …" in logs | The APK was built without `make pb` first. |
| `no READY handshake within 15s` | The sidecar spawned but never served. Likely exec was blocked; confirm `jniLibs.useLegacyPackaging = true` in `android/app/build.gradle` so the `.so` gets extracted. |
| `[PB] activation failed, staying on legacy store` | The sidecar came up, but a later step (migration or first load) failed. The app is still usable through the fallback. |
| Rows missing after unlock | Check the `pb_legacy_index_migrated` flag. If it's set but the DB was wiped, PB starts empty and only new writes land there. |

If the sidecar is fundamentally broken on device, the fallback keeps the app
working. The decision then is the deferred `sqflite` pivot described in the plan.

## 5. What you can't test through PB

- Decoy vault: never touches PB; decoy code stays on the legacy store.
- Settings: always FlutterSecureStorage, never PB.
- Media bytes: never PB, only `blob_ref` paths.
