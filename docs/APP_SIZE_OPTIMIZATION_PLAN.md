# Locker App Size & Memory Optimization Plan

**Target:** Meet Google Play Feb-2027 technical quality requirements  
**Current Version:** 0.17.2-beta.3  
**Last Updated:** 2026-09-01

---

## Executive Summary

**Current State:**
- Universal APK: 71 MB (285 MB uncompressed)
- AAB: 121 MB (includes debug symbols)
- Per-device download (AAB, single ABI): ~35-42 MB
- DEX: 5.33 MB (under 10 MB threshold, exempt from 25% R8 requirement)
- Largest single file: `libpocketbase.so` at 33 MB (arm64-v8a)

**Top Optimization Opportunities:**
1. `assets/banner_locker.png`: 16 MB → <1 MB (WebP recompression)
2. `pdfium.wasm`: 4 MB (web-only artifact leaking to Android)
3. ABI splitting: 71 MB universal → ~35 MB per-ABI download
4. Syncfusion PDF: 2-3 MB (optional removal if external viewing acceptable)

**Expected Savings After Phase 1-2:** ~20-30 MB download size reduction, 16+ MB install size reduction.

---

## Policy Requirements (Google Play Feb-2027)

### 1. DEX Code Optimization
- **Threshold:** Apps >10 MB DEX code must show ≥25% shrinking/optimization/obfuscation
- **Locker Status:** 5.33 MB DEX – **EXEMPT** but should maintain R8 fullMode for headroom
- **Enforcement:** Feb 2027

### 2. Runtime Memory (Anonymous RSS + Swap)
- **Thresholds (P90, 4 GB devices):**
  - Foreground: ≤2 GB
  - User-perceived service: ≤1 GB
  - Background: ≤1 GB
- **Bitmap Memory (P90):**
  - User-perceived services: ≤200 MB
  - Background: ≤200 MB
  - Cached: ≤400 MB
- **Enforcement:** Feb 2027

### 3. Download Size Limits
- Base module: ≤500 MB
- Individual feature module: ≤500 MB
- Total compressed download: ≤34 GB
- **Locker Status:** Well within limits (~71 MB APK, ~35-42 MB per-ABI AAB)

---

## Phase 0: Instrumentation (1 day)

### Tasks
- [ ] Record Play Console → Android Vitals → Memory P90 by RAM tier
- [ ] Screenshot App Bundle Explorer DEX optimization %
- [ ] Run `flutter build appbundle --analyze-size --target-platform android-arm64`
- [ ] Run `bundletool get-size --apks` for per-device download simulation
- [ ] Capture `dumpsys meminfo com.mossapps.locker` during gallery view with 500+ photos
- [ ] Perfetto trace of vault unlock → gallery open → scroll

### Baseline Metrics to Record
```
# Command outputs to save
unzip -l build/app/outputs/bundle/release/latch*.aab | sort -nr > baseline_apk_contents.txt
flutter build appbundle --analyze-size > baseline_size_analysis.txt
```

---

## Phase 1: Quick Wins (<1 week, ~18-35 MB saved)

### 1a. Recompress `assets/banner_locker.png` (16 MB → <1 MB)

**Current:** 5299×3820 PNG, 16.2 MB raw, 15.46 MB decoded  
**Action:** Convert to WebP with quality 85

```bash
# Install webp
sudo apt install webp

# Convert banner (lossy, quality 85)
cwebp -q 85 assets/banner_locker.png -o assets/banner_locker.webp

# Or lossless if visual perfection needed
cwebp -lossless assets/banner_locker.png -o assets/banner_locker.webp

# Verify size
ls -lh assets/banner_locker.*
```

**Expected:** 16 MB → 0.3-0.8 MB (95% reduction)

**Code Changes:** Update `pubspec.yaml` assets section and any direct references.

### 1b. Recompress `assets/padlock.png` (1.33 MB → ~150 KB)

```bash
cwebp -q 85 assets/padlock.png -o assets/padlock.webp
```

### 1c. Exclude `pdfium.wasm` from Android build

**Issue:** 3.98 MB WebAssembly file for PDF rendering in browser leaking to Android APK  
**Location:** `assets/flutter_assets/packages/pdfrx/assets/pdfium.wasm`

**Fix:** Add asset filter in `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/
    - packages/pdfrx/assets/pdfium_client.js  # Keep JS
    # Exclude pdfium.wasm (web-only)
```

Or create `.flutter-plugins-dependencies` exclusion.

**Expected:** 4 MB uncompressed, ~1.5 MB compressed saved.

### 1d. Font subsetting

**Current:** 4 Product Sans variants × ~50 KB = 206 KB  
**Action:** Subset to Latin glyphs only, or drop unused italic variants

```bash
# Install fonttools
pip install fonttools

# Subset to Latin (example)
pyftsubset fonts/productsans_regular.ttf --unicodes="0000-00FF"
```

**Check usage:**
```bash
grep -r "productsans_italic" lib/  # If 0 results, drop italic variants
```

### 1e. Enable ABI splits for APK builds

**Add to `android/app/build.gradle`:**
```gradle
android {
    // ... existing config
    
    splits {
        abi {
            enable true
            reset()
            include 'arm64-v8a', 'armeabi-v7a', 'x86_64'
            universalApk false  // Set true if you want universal + split APKs
        }
    }
}
```

**Build:**
```bash
flutter build apk --split-per-abi
# Output: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk (~30-36 MB)
```

**Expected:** 71 MB universal → ~30-36 MB per-ABI APK.

### 1f. Verify `extractNativeLibs` setting

**Current:** `android:extractNativeLibs="true"` in `AndroidManifest.xml:36`

**Recommendation:** Change to `false` for Android 6+ (API 23+) to keep libs compressed in APK.

```xml
<application
    android:extractNativeLibs="false"
    ... >
```

**Trade-off:** Slightly faster install on modern devices, marginally slower first native lib load.

---

## Phase 2: Build Config Hardening (2-3 days, +3-8 MB)

### 2a. Enable R8 fullMode

**Add to `android/gradle.properties`:**
```properties
android.enableR8.fullMode=true
```

**Verify:**
```bash
./gradlew app:assembleRelease --info | grep R8
# Should show: "R8 is running in full mode"
```

**Expected:** 30-45% code shrinkage, keeps DEX under 10 MB threshold.

### 2b. Narrow ProGuard keep rules

**Current `android/app/proguard-rules.pro`:**
```proguard
-keep class io.flutter.** { *; }
-keep class org.bouncycastle.** { *; }
-keep class com.mossapps.locker.AutofillService { *; }
```

**Action:** Change to `keepclassmembers` for Flutter, audit BouncyCastle usage:
```proguard
# More targeted Flutter keeps
-keepclassmembers class io.flutter.plugin.common.** { *; }
-keepclassmembers class io.flutter.embedding.** { *; }

# Keep only used PointyCastle classes (audit lib/crypto/)
-keep class org.bouncycastle.jce.provider.** { *; }
```

**Check usage report:**
```bash
cat build/app/outputs/mapping/release/usage.txt | head -100
# 3.9 MB of unused code identified
```

### 2c. Go binary optimization

**Current `Makefile:10`:**
```makefile
LDFLAGS := -s -w
```

**Enhanced:**
```makefile
LDFLAGS := -s -w -extldflags '-Wl,--build-id=none' -trimpath
```

**Build with:**
```bash
cd pocketbase
GOOS=android GOARCH=arm64 CGO_ENABLED=0 \
  go build -ldflags="$(LDFLAGS)" -trimpath -o ../android/app/src/main/jniLibs/arm64-v8a/libpocketbase.so ./cmd/locker-pb
```

**Expected:** 0.5-1 MB reduction (already stripped, limited gains).

### 2d. Consider UPX compression (optional, trade-off)

```bash
# Install UPX
sudo apt install upx

# Compress (LZMA for max ratio)
upx --lzma android/app/src/main/jniLibs/arm64-v8a/libpocketbase.so

# Verify
ls -lh android/app/src/main/jniLibs/arm64-v8a/libpocketbase.so
# Expected: 33 MB → ~20 MB
```

**Trade-offs:**
- Pros: ~12 MB saved
- Cons: Slightly slower cold start, potential antivirus false positives
- Requires: `android:extractNativeLibs="true"` for UPX to work

---

## Phase 3: Dependency Slimming (1-3 weeks, +8-30 MB)

### 3a. Syncfusion PDF → External viewing (largest saving)

**Current:** `syncfusion_flutter_pdf: ^33.1.46` in `lib/services/office_converter_service.dart`

**Usage:** On-device DOCX/ODT/RTF → PDF conversion

**Option A: Remove entirely (recommended)**
- Delete `office_converter_service.dart`
- Return `requiresExternalApp: true` for all Office types
- Users open via system viewer (Google Docs, Microsoft Office app)

**Option B: Replace with lightweight `pdf` package**
```yaml
dependencies:
  pdf: ^3.11.0  # ~400 KB, pure Dart, text-only PDF generation
```

**Expected savings:** 2-3 MB compressed, 5 MB uncompressed.

### 3b. Deduplicate image processing

**Current dependencies:**
- `flutter_image_compress: ^2.4.0` (native, 32 KB/ABI)
- `flutter_bicubic_resize: ^1.4.0` (native, 188 KB arm64)
- `image: ^4.8.0` (pure Dart, ~1 MB)

**Action:** Keep `flutter_image_compress` (most capable), remove `flutter_bicubic_resize`.

**Update `pubspec.yaml`:**
```yaml
dependencies:
  # flutter_bicubic_resize: ^1.4.0  # Remove
  flutter_image_compress: ^2.4.0
  image: ^4.8.0  # Keep for pure-Dart fallback
```

**Update imports in `lib/services/thumbnail_service.dart`:**
```dart
// Remove: import 'package:flutter_bicubic_resize/flutter_bicubic_resize.dart';
// Use FlutterImageCompress for all resizing
```

**Expected:** 0.6 MB + 2 native libs removed.

### 3c. Audit unused dependencies

```bash
# Check which packages are actually imported
grep -r "import.*package:" lib/ | cut -d: -f3 | sort | uniq -c | sort -nr

# Cross-reference with pubspec.yaml
cat pubspec.yaml | grep "  [a-z]"
```

**Potential removals:**
- `archive: ^4.0.7` – only used in `office_converter_service.dart` (remove with 3a)
- `xml: ^6.6.1` – only used in `office_converter_service.dart` (remove with 3a)
- `pdfrx: ^2.2.16` – keep if PDF viewing needed, else use `open_filex`

---

## Phase 4: Runtime Memory Compliance (parallel to size work)

### 4a. Reduce ImageCache size

**Current `lib/utils/performance_config.dart:30-31`:**
```dart
PaintingBinding.instance.imageCache.maximumSize = 100;
PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024; // 50 MB
```

**Recommended:**
```dart
PaintingBinding.instance.imageCache.maximumSize = 50;  // 100 → 50
PaintingBinding.instance.imageCache.maximumSizeBytes = 25 * 1024 * 1024; // 50 MB → 25 MB
```

### 4b. Add memory pressure handlers

**Add to `lib/main.dart`:**
```dart
class AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didHaveMemoryPressure() {
    PaintingBinding.instance.imageCache.clear();
    // Clear thumbnail cache
    ThumbnailService(/* deps */)._cache.clear();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Release heavy resources
      PaintingBinding.instance.imageCache.clearEvictable();
    }
  }
}
```

**Register in `main()`:**
```dart
WidgetsBinding.instance.addObserver(AppLifecycleObserver());
```

### 4c. Thumbnail cache eviction

**Current `lib/services/thumbnail_service.dart:36`:**
```dart
static const int _cacheLimit = 200;
```

**Add eviction on lifecycle:**
```dart
void clearCache() {
  _cache.clear();
  _inFlight.clear();
}
```

Call from `AppLifecycleObserver.didChangeAppLifecycleState(AppLifecycleState.paused)`.

### 4d. Forward `onTrimMemory` from Android to Dart

**Add to `MainActivity.kt`:**
```kotlin
override fun onTrimMemory(level: Int) {
    super.onTrimMemory(level)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        .invokeMethod('onTrimMemory', level)
}
```

**Handle in Dart:**
```dart
methodChannel.setMethodCallHandler((call) async {
  if (call.method == 'onTrimMemory') {
    final level = call.arguments as int;
    if (level >= TrimMemory.MODERATE_MEMORY) {
      PaintingBinding.instance.imageCache.clear();
    }
  }
});
```

### 4e. Lazy-load PocketBase sidecar

**Current:** `lib/services/pb/pocketbase_runtime.dart` starts PB on app init.

**Recommended:** Start only on first vault write, stop on app pause.

```dart
class PocketBaseRuntime {
  static bool _isRunning = false;
  
  static Future<void> ensureRunning() async {
    if (_isRunning) return;
    // Start PB process
    _isRunning = true;
  }
  
  static Future<void> stop() async {
    if (!_isRunning) return;
    // Kill PB process
    _isRunning = false;
  }
}
```

**Expected:** Save 33 MB RSS when app is backgrounded.

---

## Phase 5: Validation & Rollout

### 5a. CI Gates

Add to CI pipeline:
```yaml
# .github/workflows/size-check.yml
- name: Check APK size
  run: |
    APK_SIZE=$(stat -c%s build/app/outputs/flutter-apk/app-arm64-v8a-release.apk)
    MAX_SIZE=$((70 * 1024 * 1024))  # 70 MB
    if [ $APK_SIZE -gt $MAX_SIZE ]; then
      echo "APK size $APK_SIZE exceeds limit $MAX_SIZE"
      exit 1
    fi

- name: Check DEX size
  run: |
    DEX_SIZE=$(unzip -l build/app/outputs/flutter-apk/app-arm64-v8a-release.apk | grep classes.dex | awk '{print $1}')
    MAX_DEX=$((10 * 1024 * 1024))  # 10 MB
    if [ $DEX_SIZE -gt $MAX_DEX ]; then
      echo "DEX size $DEX_SIZE exceeds limit $MAX_DEX"
      exit 1
    fi
```

### 5b. Play Console Verification

After upload to internal track:
1. **App Bundle Explorer** → Downloads → "Download size" (reference device)
2. **App Bundle Explorer** → Optimization → DEX shrinking %
3. **Android Vitals** → Memory → P90 by RAM tier
4. **Store Listing** → "Uninstalls on devices with <2 GB free" metric

### 5c. Phased Rollout

| Version | Changes | Rollout |
|---------|---------|---------|
| 0.17.3 | Phase 1 (assets, wasm, ABI splits) | 10% → 50% → 100% |
| 0.17.4 | Phase 2 (R8 fullMode, ProGuard) | 10% → 50% → 100% |
| 0.17.5 | Phase 3 (dependency removal) | Feature flag, A/B test |
| 0.18.0 | Phase 4 (memory compliance) | All users |

---

## Effort / Savings Matrix

| Phase | Effort | Risk | Download Saving | Install Saving |
|-------|--------|------|-----------------|----------------|
| 1a: Banner WebP | 0.5d | Low | 10-12 MB | 16 MB |
| 1b: WASM exclude | 0.5d | Low | 1.5 MB | 4 MB |
| 1e: ABI splits | 0.2d | None | 30 MB (perceived) | - |
| 2a: R8 fullMode | 1d | Medium | 1-3 MB | 1-3 MB |
| 2c: Go flags | 0.5d | Low | 0.5 MB | 0.5 MB |
| 3a: Remove Syncfusion | 3-5d | Product decision | 2-3 MB | 5 MB |
| 3c: Dedup image libs | 2d | Low | 0.6 MB | 0.6 MB |
| **Total Phase 1-2** | **~2-3 days** | **Low-Medium** | **~15-20 MB** | **~20-25 MB** |

---

## Open Decisions

1. **Banner compression quality:** Lossless WebP (slightly larger) vs quality 85 (max saving, visually identical)?
2. **Syncfusion removal:** Accept external app for Office docs, or keep on-device conversion?
3. **UPX for Go binary:** Accept 12 MB saving with trade-offs, or keep uncompressed?
4. **ABI support:** Confirm `arm64-v8a` only (drop `armeabi-v7a` for <3% of users)?
5. **Target SDK:** Plan upgrade to SDK 35/36 before Android 17 memory limits?

---

## Quick Reference Commands

```bash
# Build and analyze size
flutter build appbundle --analyze-size --target-platform android-arm64

# Extract and list APK contents
unzip -l build/app/outputs/flutter-apk/app-arm64-v8a-release.apk | sort -nr

# Check DEX size
unzip -l build/app/outputs/flutter-apk/app-arm64-v8a-release.apk | grep classes.dex

# Simulate per-device download
bundletool get-size --apks app.aab --device-config device_config.pb

# Check ProGuard usage
cat build/app/outputs/mapping/release/usage.txt | head -100

# Memory profiling
adb shell dumpsys meminfo com.mossapps.locker
```

---

## References

- [Google Play Technical Quality Requirements](https://support.google.com/googleplay/android-developer/answer/17492799)
- [App Size Optimization Guide](https://support.google.com/googleplay/android-developer/answer/9859372)
- [R8 Configuration](https://developer.android.com/studio/build/shrink-code)
- [Flutter Build Size Analysis](https://docs.flutter.dev/testing/build-performance#analyzing-your-apps-size)
