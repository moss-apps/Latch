# Testing the Embedded PocketBase Store

How to exercise the PB sidecar (docs/embedded_pocketbase.md) at each level:
automated tests → host sidecar → real device. Do them in that order; each
level catches a different class of breakage.

## 0. Prerequisites

- Go (any recent version; the wrapper is pure-Go, no NDK)
- Flutter SDK
- For device tests: an **arm64** Android phone/emulator with USB debugging
- Package id: `com.mossapps.locker` (needed for `adb shell run-as`)

## 1. Automated tests (seconds, no device)

```sh
flutter test test/pb_runtime_test.dart   # stdout handshake parsing
flutter test test/pb_store_test.dart     # codec + DAO round-trip + reconcile
flutter test test/pb_wire_test.dart      # P4 e2e: seed → PB rows → runSync
```

Or the whole suite: `flutter test`. These run against an in-process fake of
the sidecar's REST surface — they catch Dart-side regressions only.

## 2. Host sidecar (minutes, no device)

Build and run the linux binary with a scratch data dir. `--auth-token`
pinning is supported, which the app never uses but makes curling easy:

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

From another terminal (substitute the port):

```sh
PORT=...   # from the handshake
TOK=devtoken

# token gate: must be 401 without the header, 200 with it
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:$PORT/api/health
curl -s -H "X-Locker-Token: $TOK" http://127.0.0.1:$PORT/api/health

# collections were auto-created by the embedded JS migrations
curl -s -H "X-Locker-Token: $TOK" \
  'http://127.0.0.1:$PORT/api/collections/vault_files/records' \
  | python3 -m json.tool

# round-trip one record; cipher_meta is an opaque json object (this is what
# ciphertext-at-rest looks like from the outside)
curl -s -H "X-Locker-Token: $TOK" \
  -H 'Content-Type: application/json' \
  -d '{"id":"abc123def456abc","blob_ref":"/vault/ab/cd/x.enc","cipher_meta":{"v":1},"modified_at":1000,"deleted":false}' \
  http://127.0.0.1:$PORT/api/collections/vault_files/records
```

Inspect the SQLite file directly if you want proof nothing plaintext is
stored (note: PB app-encrypted columns are opaque blobs, but non-secret
columns like `blob_ref` ARE plaintext by design):

```sh
sqlite3 /tmp/opencode/locker-pb/data.db 'select id, blob_ref from vault_files;'
```

Kill with Ctrl-C when done; delete `/tmp/opencode/locker-pb` to reset.

## 3. On-device (the real gate)

This is the check the plan still flags as outstanding: the sidecar has
never run on real hardware.

### 3a. Build + install

```sh
make pb                      # cross-compile → jniLibs/arm64-v8a/libpocketbase.so (~32 MB)
flutter run --release        # or --profile; debug works too
```

`make pb` must run before the build — the `.so` is a bundled artifact
(gitignored). If it's missing, `PocketBaseRuntime.start()` throws
"PocketBase binary missing" and the app silently stays on the legacy store.

### 3b. Drive the app

1. Unlock the **real** vault (not the decoy PIN — decoy never starts PB).
2. The unlock screen now, in order: starts the sidecar, runs the one-time
   legacy→PB migration, attaches PB as the preferred store, refreshes.

### 3c. Verify

Logcat is the primary signal:

```sh
flutter logs                 # or: adb logcat -s flutter
```

Look for:

- `[PB] sidecar up: pid=… port=…` — spawn + handshake + health all passed.
- No `[PB] … falling back to legacy` lines — those mean a PB call failed
  after startup and the store degraded (works, but not the thing under test).

Then exercise the app normally and confirm no regressions: add a file,
create/rename an album, tag something, run a sync, clear the vault. Every
one of those now writes through PB when it's active.

Optional — inspect the DB on a debug build (debuggable APKs allow run-as):

```sh
adb shell run-as com.mossapps.locker ls files/pocketbase/
# data.db  data.db-wal  migrations/  sidecar.pid
adb shell run-as com.mossapps.locker sh -c \
  'cat files/pocketbase/sidecar.pid'
```

The port/token are ephemeral and held only in app memory, so you can't curl
the device sidecar from outside — app behavior + logcat is the intended
observability for now.

### 3d. Reset PB state on device

- Full reset (drops PB rows AND vault files): Settings → clear vault. This
  also wipes the PB rows (`PocketBaseStore.wipe`).
- Migration rerun only: delete the secure-storage flag — easiest via clear
  vault, or `adb shell pm clear com.mossapps.locker` (nukes everything,
  including the vault credentials — effectively a fresh install).

## 4. Interpreting failures

| Symptom | Meaning |
|---|---|
| "PocketBase binary missing at …" in logs | APK built without `make pb` first |
| `no READY handshake within 15s` | sidecar spawned but never served — likely exec blocked (check `android:extractNativeLibs="true"` still set) |
| `[PB] activation failed, staying on legacy store` | sidecar up but a later step (migration, first load) failed — the app is still fully usable via the fallback |
| Rows missing after unlock | check the `pb_legacy_index_migrated` flag path: if the flag is set but the DB was wiped, PB starts empty and only *new* writes land there |

If the sidecar is fundamentally broken on device, the fallback keeps the
app working; the decision then is the P5 `sqflite` pivot per the plan.

## 5. What is intentionally NOT testable via PB directly

- Decoy vault: never touches PB (decoy code paths stay on the legacy store).
- Settings: always FlutterSecureStorage, never PB.
- Media bytes: never PB — only `blob_ref` paths.
