# Latch Refactor & Hardening Roadmap

Born from an architecture + security audit (2026-07). Phases are ordered
by dependency. Phases 0 and 1 are independent and shippable immediately.
Phase 2 unblocks Phase 4. Phase 3 is independent of Phase 2. Phase 5
(tests) weaves through all of them.

## Locked decisions

- **Lockout default (Phase 0.1):** `failedUnlockProtectionEnabled = true`
  for **new installs only**. Existing users' stored setting is preserved
  because `toJson` already writes the field explicitly; the `fromJson`
  fallback only applies to absent keys.
- **Service wiring (Phase 2):** **constructor injection**. Each split
  service takes its dependencies via the constructor and is
  Riverpod-provided. This makes Phase 4 (dropping singletons) nearly free.
  First step of Phase 2 is auditing every `.instance` call site.

## Execution order

```
Week 1:  Phase 0 (ship) + Phase 1 (ship), in parallel
         Phase 5 tests for these land first
Week 2-3: Phase 2 (vault_service split) + Phase 3 (screen split), parallel
Week 4:   Phase 4 (Riverpod) — cheap once services are split
```

---

## Phase 0 — Quick hardening (low risk)

| # | Change | Location | Status |
|---|---|---|---|
| 0.1 | Default `failedUnlockProtectionEnabled = true` (new installs only) | `services/vault_service.dart:3093`, `:3197` | **Done** |
| 0.3 | Fix stale doc comment "AES-256-CBC with PKCS7" → GCM/CTR | `services/encryption_service.dart:23-24` | **Done** |
| 0.2 | ~~`evictCachedKeys()` wired to lock/logout~~ | — | **Dropped** |
| 0.4 | ~~Dispose dialog `TextEditingController`s~~ | — | **Dropped** |

**Why 0.2 was dropped:** there is **no in-session lock flow**. The app
unlocks once at `UnlockScreen`, stays unlocked for the process, and
"auto-kill" = the OS kills the whole process on background (memory
reclaimed automatically). There is no "lock now" button, no
relock-on-background, no relock timer — so `evictCachedKeys()` would have
**no caller** (YAGNI). `resetKeys()` (`encryption_service.dart:1873`)
remains the nuclear wipe path. **Re-add `evictCachedKeys()` only when an
in-session lock/relock feature lands** (lock-now button, app-inactive
timer, or relock-on-background).

**Why 0.4 was dropped:** the flagged controllers are **local ephemeral**
variables inside dialog methods, not fields. When the dialog closes and
the method returns, they become unreachable and are GC'd cleanly —
`TextEditingController`'s listener is removed when its `TextField`
disposes. Not a real leak. The only field controller
(`unlock_screen._passwordController`) is already disposed correctly.

**0.1 correctness:** `_loadSettings()` (`vault_service.dart:417`) builds a
fresh `const VaultSettings()` when storage is empty (new installs →
constructor default `true`) and reads `VaultSettings.fromJson(...)` when
JSON exists (existing users' explicit `false` is preserved; the `?? true`
fallback only hits pre-feature installs whose blob lacks the key).

**Verify:** `flutter analyze`, unlock a few times (confirm lockout kicks
in at 5 attempts on a fresh install), decrypt roundtrip after lock→unlock.

---

## Phase 1 — Move heavy work off the main isolate ✅ DONE

### 1a. Legacy main-isolate streaming crypto — LEAVE (verified already isolated)
`encryption_service.dart:418, 492, 548, 725, 890, 1144, 1214`. Caller audit:
- **Full-file viewing** (`getVaultedFile` :1209) already routes modern
  **GCM/CTR files → `decryptFileInIsolate`** (crypto pool, off main). Only
  **legacy CBC files** (`format==0||3`) hit the main-isolate `decryptFile`.
  CBC is a diminishing legacy format; the fix is migration (re-encrypt →
  GCM), not isolate-ifying a dead format.
- **Notes/passwords** (`note_service`, `password_service`) — tiny text
  blobs; `compute()` spawn cost (~50ms+) exceeds the sub-ms crypto.
- **Thumbnails** (`vault_service:1326`) — small images, serialized by
  `_thumbGenLock`.

No change. The risk section below already called this out.

### 1b. `compression_service` image resize — DONE
Swapped sync `BicubicResizer.resizeJpeg` → isolate-backed
`resizeJpegAsync` (the package ships the `Isolate.run` wrapper; FFI
`DynamicLibrary.open` works per-isolate, proven by the package's own
`getImageInfoAsync`). One-line change at `:62`. This is on the import hot
path (`vault_service:678`). Video path (ffmpeg subprocess) unchanged —
already off-thread.

### 1c. `office_converter_service` off main — DONE
`convertToPdf` now runs the ZIP-decode + XML-parse + Syncfusion PDF layout
in `Isolate.run`. Made the 7 heavy private methods `static` (no `this`
capture sent across). `rootBundle.load` (platform-channel, unavailable in
isolate) replaced by a main-isolate font pre-load (`_loadFontBytes`, cached)
passed into the worker as `Uint8List? fontBytes`. docx/odt/rtf only.

### 1d. `backup_service` ZIP building — LEAVE (disk-safety design)
The expensive part (decryption per file) already runs in the crypto isolate
pool. The remaining main-thread work is `ZipFileEncoder.addFile` deflate.
Moving it to an isolate requires staging *all* decrypted files on disk
simultaneously (doubles transient disk usage) or a complex incremental
delegate. The current streaming design (decrypt → stage → zip → delete per
file) **bounds disk usage** — a safety property for a vault that can hold
GB. Keeping it; re-evaluate if backup jank is reported on very large vaults.

**Verify:** `flutter analyze` = No issues. `flutter test` = 52/52 passed.
Profile-mode timeline validation deferred to a device session.

**Risk (realized):** `compute()`/`Isolate.run` has message-copy overhead —
net negative for tiny payloads. Confirmed why note/password encryption
stays on main.

---

## Phase 2 — Split `vault_service.dart` (was 3209L, 101 methods) ✅ DONE

Keystone refactor. Phase 4 depends on it. Result: `vault_service.dart`
3034L → 534L facade wrapping 8 split services + 1 state holder. All 72
tests pass, `flutter analyze` clean.

### Steps

| Step | Status | Detail |
|---|---|---|
| 2.1 Data classes → `models/` | **Done** | `VaultSettings` → `models/vault_settings.dart`; `FileToVault` + `FolderImportResult` → `models/file_to_vault.dart`. `vault_service.dart` trimmed 3209→3019 lines. 6 callers updated with model imports. `flutter analyze` clean, 52 tests pass. |
| 2.2 Behavioral test net | **Done** | 20 tests in `test/vault_service_test.dart`: settings (defaults, persist+reload, fromJson), albums (cross-mutation, delete, remove, favorites), folders (create, addFile, **deleteFolder clears folderId**), tags (add, remove), favorites (toggle, filter), search (by name, by tag), sort (name, date), stats (counts, storage), clearVault. Mocks secure storage + path provider via MethodChannel. `flutter analyze` clean, 72 tests pass. |
| 2.3 Bug fix | **Done** | `VaultedFile.removeFromFolder()` (`vaulted_file.dart:252`) was broken — `copyWith(folderId: null)` is a no-op because copyWith uses `??` (treats null as "not provided"). Fixed with JSON round-trip that correctly nulls folderId. **Genuine production bug**: files kept orphaned folderIds after folder deletion/removal. |
| 2.4 Extract `VaultStore` | **Done** | `services/vault_store.dart` (~340L). Owns `FlutterSecureStorage`, all `cached*` public fields, `vaultDirectory`/`decoyDirectory`, all `load*`/`save*` methods, `ensureVaultDirectory`/`ensureDecoyDirectory`, `streamCopyFile`, `deleteFileIfExists`, `getFileSizeIfExists`, `generateVaultFilename`, `getSubdirectory`, `read`/`write`/`delete` (secure storage passthrough), `reloadAll`, `wipe`. Static key constants exported: `vaultIndexKey`, `decoyIndexKey`, `albumsKey`, `tagsKey`, `settingsKey`, `foldersKey`, `reEncryptJournalKey`, `vaultFolderName`, `decoyFolderName`. Fields public (dropped `_` prefix). |
| 2.5 Extract domain services | **Done** | 8 new service files (see "New files" below). Each takes `VaultStore` + deps via constructor. `FileProgressInfo` kept public (used by `file_import_service`). `_deriveKeyForFile` → public `deriveKeyForFile` (called by `ThumbnailService`). `_StoredThumb` → public `StoredThumb`. `_updateTagUsage` → public `updateTagUsage` (called by `FileService` via late wire). File↔Thumbnail construction cycle broken with `late FileService fileService` field set by `VaultService._wire()` post-construction. Album↔File cycle broken with late-bound `removeFileFromAlbumFn` function ref on `FileService`. |
| 2.6 `VaultService` facade + verify | **Done** | `vault_service.dart` (534L) composes 8 services, forwards ~100 public methods. `_wire()` called from `initialize()` and `loadIndexesForTesting()`. `sortFiles` kept inline (pure, no deps). `clearVault` = `_store.wipe` + `clearThumbnailCache`. `refresh` = atomic reload into `cached*` fields. `flutter analyze lib/` = No issues found. `flutter test` = 72/72 passed. |

### Key finding: deeper coupling than the roadmap assumed

The original plan assumed clean comment-banner seams. **Reality**: all
caches (`_cachedFiles` ×25 refs, `_cachedAlbums` ×28, `_cachedFolders`
×40, `_cachedTags` ×29, `_cachedSettings` ×22) are read **inline** across
every seam. Even `SettingsService` isn't independent — file ops read
`_cachedSettings?.encryptionEnabled / .compressionEnabled / .secureDelete`
inline (lines 552, 576, 676, 706, 716, 966, 1020, 1091, 2566, 2668). No
single service extracts cleanly without a shared state holder first.
This is why `VaultStore` (2.4) had to land before any domain service.

### Approach (locked, as executed)

Centralize state into a `VaultStore` (owns `_storage`, directories,
all `_cached*` maps, all `_load*`/`_save*` methods,
`_ensureVaultDirectory`). Domain services depend on `VaultStore` +
`EncryptionService` via constructor. `VaultService` becomes a thin
facade composing all services + forwarding method calls, preserving
`VaultService.instance` so the 11 direct callers + providers don't
break. Phase 4 (Riverpod) removes the facade. Pattern = strangler fig.

### New files this phase

```
lib/services/vault_store.dart          ~340L (state + persistence + dir methods)
lib/services/file_service.dart        ~1400L (file CRUD, import, export, re-encrypt, notes/password)
lib/services/thumbnail_service.dart    ~185L (encrypted thumbnails)
lib/services/album_service.dart        ~250L (album CRUD + cross-mutation)
lib/services/folder_service.dart       ~310L (folder CRUD + importDeviceFolder)
lib/services/tag_service.dart          ~170L (tag + favorites ops)
lib/services/search_service.dart        ~55L (read-only search)
lib/services/settings_service.dart      ~25L (settings load/save)
lib/services/stats_service.dart         ~25L (read-only stats)
```

### Files changed this phase

```
lib/models/vault_settings.dart         NEW (2.1)
lib/models/file_to_vault.dart          NEW (2.1)
lib/models/vaulted_file.dart           removeFromFolder() bug fix (2.3)
lib/services/vault_store.dart          NEW (2.4)
lib/services/settings_service.dart     NEW (2.4)
lib/services/stats_service.dart        NEW (2.4)
lib/services/search_service.dart       NEW (2.4)
lib/services/album_service.dart        NEW (2.5)
lib/services/folder_service.dart       NEW (2.5)
lib/services/tag_service.dart          NEW (2.5)
lib/services/file_service.dart         NEW (2.5)
lib/services/thumbnail_service.dart    NEW (2.5)
lib/services/vault_service.dart        3034→534L facade (2.6)
test/vault_service_test.dart           NEW (2.2, 20 tests)
lib/services/auth_service.dart         vault_settings import added (2.1)
lib/providers/vault_providers.dart     vault_settings import added (2.1)
lib/services/file_import_service.dart  file_to_vault import added (2.1)
lib/screens/encryption_settings_screen.dart  vault_settings import added (2.1)
lib/screens/vault_settings_screen.dart       vault_settings import added (2.1)
```

### Cycle-breaking notes

- **File↔Thumbnail**: `ThumbnailService` constructor takes no
  `FileService`; `VaultService._wire()` sets
  `_thumbnails.fileService = _files` after both exist. Neither reads
  the other during construction, only at runtime.
- **File↔Tag**: `FileService` calls
  `_tags.updateTagUsage(...)` during import via a late-bound function
  ref (`_files.updateTagUsage`) set by `_wire()`.
- **File↔Album**: `FileService.removeFile` calls
  `_albums.removeFileFromAlbum(fileId, albumId)` via a late-bound
  function ref (`_files.removeFileFromAlbumFn`) set by `_wire()`.
- `_wire()` is guarded by `bool _wired`, called once from
  `initialize()` (end) and `loadIndexesForTesting()` (start).

**Risk (realized):** ~200 cache-field references rewritten; test net
caught behavioral regressions that `flutter analyze` couldn't (cache
consistency, missing forwarding, state init bugs). Album/folder/tag
logic covered by 20 tests. All 72 tests pass post-split.

---

## Phase 3 — Split `gallery_vault_screen.dart` (4557L) (~3-4 days, independent of Phase 2)

### 3a. Collapse the 10 `_importXxx` methods → one parameterized importer
`_importImagesFromGallery`, `_importVideosFromGallery`,
`_importMediaFromGallery`, `_importDocuments`, `_importSongs`,
`_importAnyFiles`, `_importFolderFromDevice`, … → one
`_import({required VaultCategory category, required ImportSource source})`.
Biggest single win in the file.

### 3b. Extract sheets to `widgets/`
Each `_showXxxSheet` builds a sheet inline. Move to widget files:
- `_showMultiSelectActionSheet` (`:1134`)
- `_showFileOptionsSheet` (`:1458`)
- `_showAddToAlbumSheet` (`:2413`)
- `_showAddTagsSheet` (`:2519`, 476L)
- `_showCustomizeBarSheet` (`:555`)
- `_showSortOptions` (`:2340`)
- `_showDecoyModeSheet` (`:3004`)
- `_showSetDecoyPinDialog` (`:3132`, **902 lines** — promote to its own screen/dialog)
- `media_hold_action_sheet.dart` already exists at 345L — delegate to it

### 3c. Extract drawer
`_buildDrawer` (`:1965`) + header/section/item helpers →
`widgets/app_drawer.dart`. Self-contained.

### 3d. Extract customize bar
`_buildBottomBar`, `_buildImportBarItem`, `_buildCategoryItem` →
`widgets/customize_bar.dart`.

**Target after 3a–3d:** screen is ~800–1200 lines (grid + state + delegation).

**Verify:** manual walkthrough of every import source, sheet, drawer,
multi-select, decoy setup. Widget smoke test that mounts the screen.

**Risk:** screen holds lots of `ConsumerState` state (selection, sliding
selection, current tab). Extracted widgets take callbacks + read
providers directly; keep state in parent, pass callbacks.

---

## Phase 4 — Riverpod modernization (~2-3 days, depends on Phase 2)

**Problem:** 12 hand-rolled `instance` singletons wrapped in providers
that just re-expose them. Pay singleton cost (global state, untestable)
+ provider cost (indirection) with neither's benefit.

**Approach:**
1. Each split service (from Phase 2) becomes Riverpod-provided with
   constructor deps:
   ```dart
   final fileServiceProvider = Provider((ref) =>
     FileService(ref.read(encryptionServiceProvider)));
   ```
2. Delete `instance = X._()` from all 12 services.
3. Migrate `flutter_riverpod/legacy.dart` → modern `Notifier` API.
   Replace `StateProvider<int>` for sort/filter with `Notifier<int>`
   where state has business meaning; keep `StateProvider` for trivial
   ephemeral UI flags only.
4. Remove the legacy import from all provider files.

**Verify:** `flutter analyze` clean (no legacy import warnings). Each
provider testable with an injected fake.

**Risk:** services currently relying on `VaultService.instance` from
non-widget code (isolates, MethodChannel handlers, `main.dart`) need the
provider container or a top-level `ProviderContainer`. Audit before
migrating.

---

## Phase 5 — Test suite (ongoing, weaves through all phases)

Current: 8 test files, crypto-only. No tests for services, providers, or
screens.

**Priority order:**
1. **Phase 0/1 tests first** — lock/evict roundtrip, compression-in-isolate
   parity, office-convert output equality. Lock in behavior *before*
   refactoring.
2. **Phase 2 tests** — one test per split service, primary method
   (create/get/delete roundtrip). Regression net during the split.
3. **Phase 3 tests** — widget smoke test for the screen + one test per
   extracted sheet/dialog.
4. **Phase 4 tests** — provider tests with overridden fakes.

**Test discipline:** no per-method suites, no fixtures unless needed. One
test per public method's happy path + one failure path for anything
security-touching. Don't build a test framework.
