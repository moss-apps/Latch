# Changelog

Notable changes to Latch.

## 0.15.0-beta.1

### Password Vault & Autofill
- **Password vault** — store, edit, and organize credentials inside the encrypted vault
- **Password editor** with generator for strong random passwords
- **Password list** with search, domain filtering, and multi-select
- **Android Autofill service** — fill credentials in other apps and browsers
- Autofill credential toggle with security warning dialog
- Autofill support on PIN and password unlock inputs
- **Clipboard auto-clear** after pasting passwords
- Password index included in vault backups

### Crypto Overhaul
- **AEAD key-wrapping** for vault master key (AES-256-GCM wrapping)
- **Argon2id** key derivation alongside PBKDF2
- `HeaderCodec` for encrypted file format detection
- Stateless **AES-256-GCM** and **AES-256-CTR** cipher primitives
- **Key wrapping and biometric unlock** for master keys
- Encryption key **re-wrapping** after password/PIN change
- Constant-time string comparison for cryptographic operations
- **PBKDF2 iterations increased to 600,000** (from 100,000)
- Default encryption algorithm set to **AES-256-GCM**

### Update System Rework
- **GitHub-based updates** via `url_launcher` (non-Play Store installs)
- Install source detection — Play Store vs sideload vs GitHub
- Pre-release version ordering with `pub_semver`

### Testing & Infrastructure
- **CI workflow** for versionF branch
- Unit tests: AES-256-GCM, CTR, crypto hygiene, password strength, PBKDF2 isolates, Argon2id KWK + key wrapping

### UI Polish
- Tooltips on song player, media viewer, and password editor buttons
- SnackBar margin/shape/elevation styling
- Search and sort actions moved to overflow menu
- GestureDetector replaced with IconButton (accessibility)
- `forceReload` parameter on vault cache loaders

### Security Hardening
- App backup disabled
- Network security config for cleartext traffic policy
- ProGuard minification on release builds; rules for Flutter, crypto, and autofill service

### Cleanup
- Firebase dependencies removed from Android Gradle config
- Deprecated compression services and widgets removed
- Redundant file-existence checks removed
- Unused UI components, imports, and platform stubs removed
- `cupertino_icons` and `encrypt` replaced with `device_info_plus`

---

## 0.14.4-beta.5

### Security
- **Constant-time credential comparison** (`secure_compare.dart`) in AuthService and DecoyService verify paths; legacy SHA-256 branch padded with dummy PBKDF2 work
- **Decoy PIN minimum 4 → 6 digits**
- **Password-strength enforcement** — `minPasswordLength = 8` + `validatePasswordStrength()` centralized in AuthService
- **Plaintext temp wiped** — re-encryption/rotation intermediates written to app-private temp and `secureDelete`d
- **iOS Keychain accessibility** set to `unlocked_this_device` (Android-only app, low-impact but correct)
- Raw `$e` removed from all crypto/UI exception strings; detail kept in `debugPrint`

### Architecture
- **Crypto module split** — `encryption_service.dart` split into pure, tested modules under `lib/crypto/`: `AesGcmCipher`, `AesCtrCipher`, `KeyDerivation`, `HeaderCodec`, `KeyWrap`. `EncryptionService` is now a behavior-preserving facade. +33 round-trip/auth tests.
- **Vault cache-NPE fix** — `refresh()` swaps caches atomically instead of nulling first, closing the crash vector where an in-flight mutation could NPE on a nulled cache. Full repository split deferred.

### UI & Cleanup
- **Password vault integration** — open/create password entries from the gallery screen
- **Search and sort** moved into the overflow menu
- **Centralized toasts** (`ToastUtils` via global `navigatorKey`); `fluttertoast` dropped
- **Centralized paths** (`PathUtils.getDownloadsDirectory()` + `androidSourceRoots`)
- **FileTypeColors** map added to `app_colors.dart`
- **Dead code purge** — deleted `OptimizedScrollView`, `OptimizedGridView`, `OptimizedThumbnail`, `PerformanceOverlayWidget`, `CompactPermissionWarning`, `showOperationProgressSheet`, `compression_options_dialog`, dead `locker_logo_512.png`, dead `_importFromDocuments`
- **Vestigial Firebase removed** — `google-services` plugin, `firebase-bom`, `google-services.json` (no Dart Firebase consumed)
- **`.metadata` cleanup** — removed ios/linux/macos/web/windows platform entries

### Platform & Tooling
- **CI workflow** (`github/workflows/ci.yml`) — pub get / analyze / test on push
- **ProGuard rules** for Flutter, crypto, and autofill service
- **AndroidManifest** — `allowBackup="false"` + `dataExtractionRules` + `networkSecurityConfig`
- **Release builds** — `minifyEnabled` / `shrinkResources` / `proguardFiles`
- `permission_service.dart` hardcoded SDK 33 → `device_info_plus`
- Dropped unused deps `encrypt`, `cupertino_icons`; `fluttertoast` removed

### Fixes
- `media_viewer_screen.dart` delete-from-viewer no longer mutates the caller's file list (operates on a local copy)
- `gallery_vault_screen.dart` `mounted` guards on 8 `setState`-after-await sites
- `note_editor_screen.dart` folder-picker tautology bug fixed
- `TextEditingController`s now disposed in dialogs/sheets (10 sites)
- Sub-48px tap targets replaced with `IconButton`
- `main.dart` update-check `StreamSubscription` stored + cancelled in `dispose()`

---

## 0.14.4-beta.4

### Notes System
- **Encrypted note management** — create, edit, and organize secure notes inside the vault
- **Note editor screen** with rich text editing
- **Note folders** with CRUD operations for hierarchical organization
- **Note list screen** with search, folder browsing, and multi-select
- **NoteCard widget** with selection support and formatted date display
- **Riverpod providers** for reactive note state management
- **Async PBKDF2 key derivation** using isolates for note encryption
- Notes integration in gallery vault and vault explorer navigation

### Audio Recording
- **Audio recorder screen** with real-time amplitude visualization
- Recording preview and save-to-vault functionality
- Integrated into the gallery vault screen

### UI & Design
- **Adaptive logo widget** — automatically switches between light and dark variants
- SVG logo replaced with `AdaptiveLogo` across all screens
- **Resizable sidebar** in vault explorer
- Checkmark icons on selected encryption algorithm chips
- Dynamic accent color for slider thumb and track
- Redesigned password setup and change security screens; gradients removed

### Architecture
- **Centralized `FileOpenService`** — all vault file opening routed through a single service
- Refactored file grid to use the new service

### Platform Cleanup
- Removed Windows, Linux, macOS, iOS, and web platform stubs — app is now explicitly Android-only

### Fixes
- Fixed import options sheet layout and scrolling
- Removed extra card margin in performance settings screen

---

## 0.14.3-beta.4

### Always Up-to-Date Content
- **"What's New"** highlights and **full changelog** fetch from GitHub on launch with ETag caching — release notes propagate without an APK update
- Bundled assets serve as instant offline fallback

### Video Player
- **Video load phases** with cancellation support and progress tracking

### Encryption Reliability
- **CTR decryption** writes to a temporary file and renames on success, preventing data loss on failure
- **Progress callback** added to `getVaultedFile` for better UX during decryption

### Per-File Encryption
- **Per-file encryption configuration** — each file can have its own encryption algorithm and KDF settings
- **Encryption settings prompt** on every import flow, letting users choose per-file options
- **Re-encrypt file picker screen** with selection UI and progress tracking, replacing the old dialog
- **`derivedKey` parameter** for per-file key derivation
- `encryptionAlgorithm` and `kdfIterations` fields added to `VaultedFile`
- Optional `fileFilter` parameter added to `reEncryptVault`

### Bug Fixes
- Fixed `Uint8List.view` shared buffer issue in encryption workers — prevents corrupted output when iterating across views

---

## 0.14.2-beta.3

### What's New & Changelog
- **"What's New" bottom sheet** — in-app version highlights shown on first launch after update
- **Changelog screen** accessible from vault settings
- **WhatsNewService** for delivering version-specific feature highlights

### Theming & Visual Consistency
- Hardcoded light theme colors replaced with **context-aware theme colors** across the app
- Document viewer colors migrated to theme context
- File overlay badges unified into a single container
- File names and **type-specific icons** shown in grid thumbnails for all file types
- **AnimatedSwitcher** for smooth view-mode transitions

### Encryption Reliability
- **Crash recovery** added to re-encryption journal — interrupted re-encryption operations resume safely
- Encrypt output written to a **temp file** and renamed on success, preventing corrupt vaulted files on failure
- Temp file cleanup on re-encryption success
- **Non-empty final block** handling in GCM decryption worker

### Settings
- **Permission warning** setting added to vault settings

---

## 0.14.1-beta.2

### Encryption & Crypto Hardening
- **AES-256-GCM v2** authenticated encryption format with crypto isolate pool support
- **Isolate-based crypto worker pool** for AES encryption/decryption, offloading heavy crypto from the UI thread
- **PBKDF2 hashing** moved entirely to Dart isolates — no more direct Pointy Castle dependency on the main thread
- **Dynamic KDF iterations** for password and PIN hashing, stored per-credential with rotation on config changes
- **Decoy credential migration**: KDF iteration counts stored per credential, rotate when vault settings change
- **Re-encryption warning dialog**: detailed risk explanations shown before the confirmation dialog
- **`needsMigration`** field added to `VaultedFile` for tracking files needing re-encryption

### Media Selection & UX
- New **hold-to-action** gesture: long-press triggers an action sheet instead of immediate selection
- **Media multi-select action bottom sheet** with batch operations
- Refactored selection mode with improved multi-select actions

### In-App Updates
- **In-app update service** with update state providers (Riverpod)
- **Update dialog** with in-app update support
- Vault settings auto-scan for update info on init
- `connectivity_plus` dependency for network availability checks

### Reliability & Error Handling
- Error handling for vault entry parsing and empty index saves
- Parallel file export refactored with improved progress tracking
- Type cast fix for `fileSize` and `viewCount`
- Removed unused loading state from unlock logic
- Removed redundant vault operation and diagnostic utilities

### Housekeeping
- README updated with closed beta sign-up info
- Removed outdated example files

---

## 0.14.0-beta.1

### Rebranding
- App renamed from **Locker** to **Latch**
- Package identifier changed from `com.ultraelectronica.locker` to `com.mossapps.locker`
- Updated app label, assets, and all internal references
- New launcher icons and logo assets

### Encryption Hardening
- Added **AES-256-GCM** encryption mode (authenticated encryption with integrity verification)
- Re-encryption support: migrate existing vault files between AES-256-CTR and AES-256-GCM
- **PBKDF2** key derivation for password/PIN hashing with configurable iteration count
- Migration of decoy credentials to PBKDF2 with salted hashing
- New **Encryption Settings** screen for algorithm selection and re-encryption management
- `EncryptionAlgorithm` enum with display names and descriptions

### Folder & Explorer Management
- **VaultFolder** model for hierarchical folder organization
- **Vault Explorer** screen with full folder management UI
- **Folder Detail** screen with file management features
- **Folders** screen with grid layout and folder import support
- **Breadcrumb** navigation widget for folder paths
- **Folder Tree** widget with expandable navigation
- **Explorer Toolbar** widget with view mode and sort controls
- **Explorer File Grid** widget with filter and selection support
- **Explorer state providers** (Riverpod) for reactive folder state
- File Explorer drawer item in gallery vault screen
- Folder import functionality in file import service

### Flick Audio Integration
- **Flick Player** integration for external audio playback handoff
- Flick integration service with deterministic package-targeted handoff
- `locker://return` contract for explicit "Back to Latch" return
- Song player with internal playback and Flick handoff support
- Audio handling in favorites, gallery, and tags screens
- Song directory support in vault and decoy modes
- Updated `onNewIntent` for new activity launches from Flick

### Performance Settings
- New **Performance Settings** screen with custom theming and layout
- Frame rate optimization and control
- Real-time performance overlay widget
- Performance state management with Riverpod

### Security Improvements
- **Auto-Kill** enhancements: improved background task removal
- **Screenshot Protection** service
- Backup credential fallback for biometric authentication
- Decoy mode password migration to PBKDF2 with salted hashing
- Temp file cleanup on player/viewer dispose

### UI / UX
- **Select All / Deselect All** buttons in album, favorites, and tags selection modes
- **Sliding selection** in gallery vault and media picker screens
- Original file names displayed instead of extensions throughout the app
- Media scanner integration with duplicate detection
- Privacy Policy screen with markdown rendering

### Build & Infrastructure
- **Release signing** configured (upload keystore)
- Android `minSdkVersion` bumped to **26**
- `in_app_update` and `package_info_plus` for Play Store update support
- Google Services plugin for Firebase
- Privacy policy markdown file added to assets
- Google services JSON added to `.gitignore`

### Documentation
- README updated with feature details and Flick ecosystem info
- `docs/architecture_media.md` — system architecture design
- `docs/flick_integration.md` — Flick Player integration guide

---

> **GitHub Releases Deprecated**
>
> Latch is distributed exclusively via **Google Play Closed Beta**. Join: `moss_apps@proton.me`. Old release APKs/tags kept for historical reference.
