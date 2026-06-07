# Changelog

All notable changes to Latch are documented in this file.

## 0.14.3-beta.4

### Always Up-to-Date Content
- **"What's New"** highlights and **full changelog** now fetch from the GitHub repo on launch with ETag caching — new release notes propagate without an APK update
- Bundled assets serve as instant fallback when offline

### Video Player Improvements
- **Video load phases** with cancellation support and progress tracking

### Encryption Reliability
- **CTR decryption** now writes to a temporary file and renames on success, preventing data loss on failure
- **Progress callback** added to `getVaultedFile` for better UX during decryption

### Per-File Encryption
- **Per-file encryption configuration** — each file can now have its own encryption algorithm and KDF settings
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
- **AnimatedSwitcher** for smooth view mode transitions

### Encryption Reliability
- **Crash recovery** added to re-encryption journal — interrupted re-encryption operations can now resume safely
- Encrypt output now written to a **temp file** and renamed on success, preventing corrupt vaulted files on failure
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
- **Dynamic KDF iterations** for password and PIN hashing, stored per-credential with automatic rotation on config changes
- **Decoy credential migration**: KDF iteration counts stored per credential, rotate when vault settings change
- **Re-encryption warning dialog**: detailed risk explanations shown before the confirmation dialog
- **`needsMigration`** field added to `VaultedFile` for tracking files that need re-encryption

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
> GitHub Releases for Latch are no longer maintained. The app is distributed exclusively through **Google Play Store** as a Closed Beta Test.
> 
> To join the Closed Beta, email: `moss_apps@proton.me`
>
> Old release APKs and tags are kept for historical reference only.
