# Changelog

All notable changes to Latch are documented in this file.

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
