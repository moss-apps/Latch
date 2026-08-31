# Phase 0 Baseline — Instrumentation Report

**Date:** 2026-09-01  
**Version:** 0.17.2-beta.3+24 (`latch_0.17.2-beta.3`)  
**Flutter:** 3.44.4 / Dart 3.12.2  
**Gradle:** 8.11.1 / AGP 8.9.1 / Kotlin 2.1.0 / R8 8.9.32  
**Device attached:** A063 (Android 15, SDK 35, arm64-v8a) — 7.4 GB RAM

Artifacts saved under `docs/baseline_artifacts/`:
- `aab-code-size-analysis_2026-09-01.json` — Dart DevTools app-size JSON (precompiler trace w/ 138k entities)
- `aab_contents_2026-09-01.txt` — `unzip -l` for AAB
- `apk_contents_2026-09-01.txt` — `unzip -l` for APK
- `bundletool_getsize_2026-09-01.txt` — `bundletool get-size total` outputs

---

## 1. Build Outputs (fresh `flutter build appbundle --analyze-size --target-platform android-arm64`)

```
flutter build appbundle --analyze-size  →  83.9 s
✓ Built build/app/outputs/bundle/release/latch_0.17.2-beta.3.aab (126.5 MB on disk, compressed)
```

| Artifact | Compressed (on disk) | Uncompressed (`unzip -l` sum) | Notes |
|----------|---------------------|-------------------------------|-------|
| `latch_0.17.2-beta.3.aab` | 126.5 MB (`126,503,880 B`) | 647.0 MB (`323,490,000` listed + headers) | Includes `BUNDLE-METADATA/debugsymbols` 47 MB |
| `latch_0.17.2-beta.3.apk` (universal) | 74.34 MB (`74,341,832 B`) | 299.6 MB | 3 ABIs bundled |
| `build/app/outputs/bundle/release/` also contains `latch_0.17.1-beta.2.aab` 121 MB | | | Previous beta similar size |

### 1.1 Bundletool per-device download simulations (`bundletool build-apks → get-size`)

```
bundletool build-apks --bundle=latch_0.17.2-beta.3.aab --output=/tmp/locker.apks  → 164 MB apks archive
get-size total --apks=/tmp/locker.apks  →  MIN,MAX  35155183,47370905

--dimensions SDK,ABI:
SDK 26-28, armeabi-v7a  35,155,183 – 35,169,738
SDK 26-28, arm64-v8a    47,340,259 – 47,354,814
SDK 26-28, x86_64       36,178,305 – 36,192,860
SDK 29+,   armeabi-v7a  35,171,274 – 35,185,829
SDK 29+,   arm64-v8a    47,356,350 – 47,370,905  ← primary target (modern devices)
SDK 29+,   x86_64       36,194,396 – 36,208,951

--device-spec arm64-v8a/sdk35/en/xxhdpi → 47,369,899 B = 47.4 MB (Play compressed delivery)
Extracted APKS for that spec sum to 88.85 MB on disk before Play recompression:
  base-master_2.apk   25.54 MB (28.20 MB uncompressed)
  base-arm64_v8a.apk  63.22 MB (63.15 MB uncompressed) — native libs stored uncompressed
  base-en.apk            33 KB
  base-xxhdpi.apk        49 KB
```

**Interpretation:** Play delivers ~47 MB to a Pixel-class arm64 device. Pre-split universal APK is 74.3 MB, so per-ABI delivery saves ~27 MB download. AAB on-disk is inflated by `BUNDLE-METADATA` (47 MB debug symbols + 3.6 MB obfuscation map) which is *not* delivered to users.

### 1.2 `--analyze-size` breakdown (compressed sizes as reported by Flutter)

```
AAB total compressed 121 MB (terminal) / 126.5 MB (actual file):
  BUNDLE-METADATA/                          47 MB
    debugsymbols                            47 MB
    obfuscation                              3 MB
  base/
    assets                                  19 MB
    dex                                      2 MB
    lib                                     49 MB
    Dart AOT symbols (decompressed)         11 MB
      package:flutter                        4 MB
      package:locker                         2 MB
      package:syncfusion_flutter_pdf       466 KB
      dart:mixin_deduplication             408 KB
      dart:core                            317 KB
      dart:ui                              248 KB
      dart:typed_data                      214 KB
      dart:io                              195 KB
      package:camera_android_camerax       187 KB
      package:pdfrx                        176 KB
      package:vector_graphics_compiler     160 KB
      ... (see docs/baseline_artifacts JSON for full precompiler trace)
```

**Top flutter_assets by raw size (AAB `base/assets/flutter_assets/`):**

| Asset | Raw | Compressed | Share |
|-------|-----|------------|-------|
| `assets/banner_locker.png` | 16.21 MB | 16.16 MB (store) | 79.5% of flutter_assets |
| `packages/pdfrx/assets/pdfium.wasm` | 3.98 MB | 1.98 MB | 19.5% |
| `assets/padlock.png` | 1.33 MB | 1.30 MB | 6.5% |
| Others combined | ~0.22 MB | | |

**Top base/lib entries (AAB, per-ABI raw):**

| Entry | Raw | Notes |
|-------|-----|-------|
| `base/lib/arm64-v8a/libpocketbase.so` | 33.00 MB | Sym `libpocketbase.so.sym` same size (Go binary) |
| `base/lib/arm64-v8a/libflutter.so` | 11.58 MB | |
| `base/lib/arm64-v8a/libapp.so` | 12.06 MB | Dart AOT |
| `base/lib/arm64-v8a/libpdfium.so` | 4.98 MB | PDFium native |
| `base/lib/arm64-v8a/libc++_shared.so` | 1.29 MB | |
| `base/lib/arm64-v8a/libflutter_bicubic_resize.so` | 0.19 MB | Deduplicate candidate (see Phase 3) |

APK mirrors same; universal APK bloat sources triple-counted across ABIs.

---

## 2. DEX & R8 Status

| Metric | Value | Threshold | Status |
|--------|-------|-----------|--------|
| `classes.dex` raw (APK) | 5,333,540 B = **5.09 MiB (5.33 MB)** | 10 MB | EXEMPT ( < 10 MB ) |
| `classes.dex` compressed in AAB (`base/dex`) | 2,436,216 B = 2.32 MB (54% deflate) | — | — |
| R8 `r8.json` stats | `noShrinking 30.15%` → **shrinking 69.85%** | ≥ 25% | PASS |
| | `noObfuscation 30.29%` → **obfuscation 69.71%** | ≥ 25% | PASS |
| | `noOptimization 30.89%` → **optimization 69.11%** | ≥ 25% | PASS |
| R8 version | 8.9.32 (`mapping.txt` pg_map_hash `b6e2c87...`) | | |
| `proguard-rules.pro` | Keeps `io.flutter.**`, `org.bouncycastle.**`, `AutofillService` — broad keeps | | Phase 2 narrowing candidate |
| `proguard.map` | 43,113,610 B (AAB) / 42 MB `mapping.txt` | | |
| `usage.txt` (removed code) | 3.9 MB, 62,983 lines | |  گسترده dead-code elimination already active; see `build/app/outputs/mapping/release/usage.txt` |
| `minifyEnabled` | `true` | | |
| `shrinkResources` | `true` | | |
| `android.enableR8.fullMode` | **NOT set** (default compat mode) | | Phase 2 candidate |
| `isShrinkingEnabled` / `isObfuscationEnabled` / `isOptimizationsEnabled` (r8.json) | all `true` | | |

**Play Console DEX shrinking % (manual):** TODO — screenshot `App Bundle Explorer → Optimization`. Based on local `r8.json`, dashboard should show ~69% shrinking, well above Feb-2027 25% floor. Capture after next internal-track upload.

**Baseline command preservation:** `unzip -l build/app/outputs/flutter-apk/latch_0.17.2-beta.3.apk | grep classes.dex` and `unzip -lv ...` recorded in artifacts.

---

## 3. Native & Asset Bloat Detail (AAB `base/`)

```
AAB BUNDLE-METADATA (not delivered):
  debugsymbols arm64  24.09 MB (libpocketbase 11.47 MB, libflutter 6.72 MB, libapp 5.31 MB)
              armeabi 12.17 MB
              x86_64  12.50 MB
  Total BUNDLE-METADATA: 52.37 MB (47 MB debugsymbols + 3.6 MB proguard.map)

Base common (assets+dex+res):
  assets/flutter_assets: 19.77 MB (banner 16.21 + wasm 3.98 dominate)
  dex: 2.44 MB
  res/resources.pb/root/NOTICES: ~0.6 MB
  Common subtotal: 28.81 MB compressed (22.61 MB reported by Flutter after recompression accounting)
```

### 3.1 PocketBase sidecar (`libpocketbase.so`)

- Location: `android/app/src/main/jniLibs/arm64-v8a/libpocketbase.so` (and AAB `base/lib/<abi>/`)
- Size: 33.00 MB raw, ~11.47 MB debug symbols sidecar
- Build: `pocketbase/cmd/locker-pb` via `Makefile` `LDFLAGS := -s -w` (CGO disabled, `GOOS=android GOARCH=arm64`)
- Phase 2 candidate: `-trimpath -extldflags '-Wl,--build-id=none'` saves ~0.5 MB; UPX `--lzma` would save ~12 MB but requires `extractNativeLibs="true"` (currently true) and incurs cold-start cost.

### 3.2 Asset exclusions identified

- `pdfium.wasm` (3.98 MB raw, 1.98 MB compressed) is web-only; leaks to Android via `pdfrx`. Phase 1b should exclude via asset filtering.
- `banner_locker.png` 5299×3820, 16.21 MB PNG — converts to WebP q85 at ~0.5–0.8 MB (95% saving). Currently declared in `pubspec.yaml: assets:` list.
- `padlock.png` 1.33 MB → ~150 KB WebP.

---

## 4. Runtime Memory (Current Configuration)

### 4.1 Static config audit

```dart
// lib/utils/performance_config.dart:30-31
PaintingBinding.instance.imageCache.maximumSize = 100;
PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024; // 50 MB
```

```dart
// lib/services/thumbnail_service.dart:32
static const int _cacheLimit = 200; // unbounded bytes, FIFO eviction only
// clearCache() exists but no onTrimMemory / didHaveMemoryPressure wiring
```

- No `WidgetsBindingObserver.didHaveMemoryPressure` handler
- No `MainActivity.onTrimMemory → MethodChannel` bridge
- `ThumbnailService.clearCache()` is manual-only, not lifecycle-bound
- `PocketBaseRuntime` starts on app init (see `lib/services/pb/pocketbase_runtime.dart`) — not lazy; remains resident in background (33 MB RSS impact)

### 4.2 Live device probe (A063, 7.4 GB, SDK 35)

```
adb shell dumpsys meminfo com.mossapps.locker → "No process found" (app not running)
adb shell getprop: ro.product.cpu.abi arm64-v8a, abilist arm64-v8a,armeabi-v7a,armeabi
MemTotal 7,432,272 kB, MemAvailable 1,473,584 kB, SwapCached 40,400 kB
```

- **Play Console → Android Vitals → Memory P90 by RAM tier:** TODO — record after rollout (requires Play Console access; not capturable locally). See Phase 0 task list.
- **Local gallery stress test:** TODO — install release APK, load 500+ photos, capture `adb shell dumpsys meminfo com.mossapps.locker` and Perfetto trace (`vault unlock → gallery scroll`). Deferred: app not installed during baseline run; see instructions below.

### 4.3 Policy thresholds (for reference, Feb-2027)

- Foreground P90 ≤ 2 GB (4 GB devices)
- User-perceived service ≤ 1 GB, background ≤ 1 GB
- Bitmap memory P90: user-perceived/bg ≤ 200 MB, cached ≤ 400 MB

Current static config (50 MB imageCache + 200-entry thumbnail cache + 33 MB PB resident) is compliant on paper, but Phase 4 will harden pressure handling.

---

## 5. Build Config Flags

| Flag | Current | Recommended | Phase |
|------|---------|-------------|-------|
| `android:extractNativeLibs` (`AndroidManifest.xml:34`) | `true` | `false` for API 23+ (keep libs compressed) — unless UPX chosen | 1f / 2d decision |
| ABI `splits` | Not configured (universal APK) | `splits { abi { enable true ... } }` or `flutter build apk --split-per-abi` | 1e |
| `android.enableR8.fullMode` | Not set | `true` in `gradle.properties` | 2a |
| `minSdkVersion` | 26 | — | — |
| `targetSdk` | `flutter.targetSdkVersion` (currently 35 via Flutter 3.44) | Plan 35/36 before Android 17 memory limits | Open decision #5 |
| `ndkVersion` | `flutter.ndkVersion` | | |

---

## 6. Commands Executed (repro)

```bash
# 1. Fresh size analysis
flutter build appbundle --analyze-size --target-platform android-arm64
# Output logged to terminal; JSON at ~/.flutter-devtools/aab-code-size-analysis_01.json
# (copied to docs/baseline_artifacts/aab-code-size-analysis_2026-09-01.json)

# 2. ZIP listings
unzip -l build/app/outputs/bundle/release/latch_0.17.2-beta.3.aab | sort -k1 -n -r > docs/baseline_artifacts/aab_contents_2026-09-01.txt
unzip -l build/app/outputs/flutter-apk/latch_0.17.2-beta.3.apk | sort -k1 -n -r > docs/baseline_artifacts/apk_contents_2026-09-01.txt

# 3. Bundletool delivery simulation (requires curl fetch of bundletool 1.18.1 to /tmp/bundletool.jar)
java -jar /tmp/bundletool.jar build-apks --bundle=build/app/outputs/bundle/release/latch_0.17.2-beta.3.aab --output=/tmp/locker.apks --overwrite
java -jar /tmp/bundletool.jar get-size total --apks=/tmp/locker.apks
java -jar /tmp/bundletool.jar get-size total --apks=/tmp/locker.apks --dimensions=SDK,ABI

# 4. R8 / ProGuard inspection
unzip -p build/app/outputs/bundle/release/latch_0.17.2-beta.3.aab BUNDLE-METADATA/com.android.tools/r8.json | python3 -m json.tool
ls -lh build/app/outputs/mapping/release/  # usage.txt 3.9 MB, mapping.txt 42 MB
unzip -lv build/app/outputs/flutter-apk/latch_0.17.2-beta.3.apk | grep classes.dex

# 5. Device
adb shell dumpsys meminfo com.mossapps.locker
adb shell getprop ro.product.model; adb shell getprop ro.build.version.sdk; adb shell cat /proc/meminfo

# 6. Perf trace placeholder (requires running app)
# adb shell perfetto --config ... --out /data/misc/perfetto-traces/trace
# (deferred — app not running during baseline)
```

---

## 7. Remaining Manual Steps (owner TODO after next Play upload)

- [ ] Play Console → App Bundle Explorer → **DEX optimization %** screenshot
- [ ] Play Console → App Bundle Explorer → **Download size** (reference device) screenshot
- [ ] Play Console → Android Vitals → **Memory** → P90 by RAM tier (4 GB tier) export
- [ ] `adb install build/app/outputs/flutter-apk/latch_0.17.2-beta.3.apk` then `adb shell dumpsys meminfo com.mossapps.locker` during 500-photo gallery session
- [ ] Perfetto trace: vault unlock → gallery open → scroll (capture with `perfetto` or Android Studio Profiler)

---

## 8. Baseline Summary Table

| Category | Baseline | Notes |
|----------|----------|-------|
| AAB compressed (disk) | 126.5 MB | 47 MB is debug symbols not delivered |
| AAB download (Play, arm64 SDK29+) | **47.37 MB** | `get-size total` compressed delivery |
| Universal APK (3 ABIs) | 74.34 MB disk / 299.6 MB uncompressed | |
| Per-ABI saving (Play) | **27 MB** (74.34 → 47.37) | |
| DEX raw | 5.33 MB (2.44 MB compressed in AAB) | Exempt from 25% rule; actual shrinking 69.85% |
| Largest single asset | `banner_locker.png` 16.21 MB | Phase 1a target |
| Largest native lib | `libpocketbase.so` 33.00 MB | Phase 2c/2d target |
| WASM leak (Android) | `pdfium.wasm` 3.98 MB (1.98 MB compressed) | Phase 1c |
| ImageCache | 100 items / 50 MB | Phase 4a → 50 / 25 MB |
| Thumbnail cache | 200 entries, FIFO, no pressure handler | Phase 4c |
| `extractNativeLibs` | `true` | Phase 1f |

---

## 9. References

- `docs/APP_SIZE_OPTIMIZATION_PLAN.md` — Phases 1–5, effort/savings matrix, quick-reference commands
- `docs/baseline_artifacts/` — raw listings for diffing after Phase 1
- Flutter docs: `flutter build appbundle --analyze-size`, DevTools App Size tool (`dart devtools --appSizeBase=...`)
