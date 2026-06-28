# Latch

<p align="center">
  <img src="assets/banner_locker.png" alt="Latch Banner" width="100%">
</p>

<p align="center">
  <a href="https://play.google.com/store/apps/details?id=com.mossapps.locker">
    <img src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png" alt="Get it on Google Play" height="80">
  </a>
</p>

---

Latch is a private media vault for Android, written in Flutter. It hides
photos, videos, and documents behind PIN/password/biometric auth, encrypts
them with AES-256, and removes itself from the recents list when you leave
(auto-kill).

> Renamed from Locker to Latch. The repo directory is still `Locker`, but
> the app and all user-facing references are **Latch**.
> On Google Play: [Download Latch](https://play.google.com/store/apps/details?id=com.mossapps.locker).

## Features

**Vault**
- Import from gallery, camera, or files; optionally delete the originals
- Duplicate detection on import
- Per-file encryption settings and compression
- Local backup and restore

**Organization**
- Nested folders with drag-and-drop, breadcrumbs, and a tree view
- Albums, color-coded tags, favorites
- Grid/list explorer with filters, multi-select, sorting (date, name, size, type)
- Search across name, tags, type, and date

**Viewing**
- Image viewer (pinch-zoom, slideshow)
- Video player (speed, loop)
- Song player with Flick handoff
- PDF and Office document viewer
- Export to Downloads or external apps

**Security**
- PIN or password unlock, with biometrics
- AES-256-GCM (default) or AES-256-CTR, with re-encryption of existing files
- Argon2id master-key wrapping; per-file PBKDF2
- Auto-kill, screenshot protection, secure delete
- Decoy vault behind a separate PIN

**Theme**
- Accent colors, custom theming, glassmorphism unlock screen

## Moss Ecosystem

Latch is part of the Moss ecosystem. **Flick** is the companion music
player (UAC 2.0 DAC support). Latch can hand audio playback to Flick and
return via `locker://return`. Details in the
[Flick Integration Guide](docs/flick_integration.md).

## Technology Stack

**Flutter**

| Package | Purpose |
|---------|---------|
| `flutter_riverpod` | State management |
| `flutter_secure_storage` | Credentials and metadata |
| `pointycastle` | AES-256 encryption |
| `photo_manager` | Gallery access and import |
| `pdfrx` | Native PDF rendering |
| `syncfusion_flutter_pdf` | Office document conversion |
| `flutter_image_compress` | Image compression |
| `video_compress` | Video compression |
| `archive` | ZIP/RAR/7Z support |
| `permission_handler` | Runtime permissions |
| `local_auth` | Biometric authentication |
| `camera` | Photo/video capture |
| `just_audio` | Audio playback |
| `in_app_update` | Play Store updates |

**Kotlin / Android**

| Component | Purpose |
|-----------|---------|
| `MainActivity.kt` | Auto-kill, performance settings, content URI handling |
| `AutoKillService` | Removes app from recents when backgrounded |
| `PermissionHandler` | Runtime permission management |

## Getting Started

**Prerequisites:** Flutter 3.4.4+, Android SDK API 36, JDK 17, Android 8.0 (API 26)+ device.

```bash
flutter pub get
flutter run                                  # debug
flutter run -d <device-id>                   # specific device
flutter build apk --release --obfuscate --split-debug-info=./build/symbols
flutter pub run flutter_launcher_icons       # regenerate icons (optional)
```

## Permissions

| Permission | Purpose |
|------------|---------|
| READ_EXTERNAL_STORAGE / WRITE_EXTERNAL_STORAGE | File access (Android ≤12) |
| READ_MEDIA_IMAGES / READ_MEDIA_VIDEO | Media access (Android 13+) |
| MANAGE_EXTERNAL_STORAGE | Full file access for hide/unhide (Android 11+) |
| CAMERA | Capture photos and videos |
| RECORD_AUDIO | Audio with video |
| USE_BIOMETRIC | Biometric authentication |

## Architecture

Service-based, split into four layers: **Services** (auth, encryption,
file ops, media), **Providers** (Riverpod reactive state), **Screens**
(feature UI), and a **Kotlin backend** (auto-kill, permissions, camera).
All sensitive data (PINs, passwords, keys) goes through
`flutter_secure_storage` into Android's Keystore. See
[Media Encryption & Compression](docs/architecture_media.md).

## Documentation

- [Media Encryption & Compression](docs/architecture_media.md): compression, encryption, file ops
- [Unlock Autofill](docs/unlock_autofill.md): unlock credential autofill and its security model
- [Flick Integration Guide](docs/flick_integration.md): Flick playback handoff contract

## Contributing

Fork → feature branch → `flutter analyze` + pass tests → pull request.
Follow the Dart style guide.

## License

MIT, see [LICENSE](LICENSE). Free, no ads, no paid features.

## Contributors

- [@ultraelectronica](https://github.com/ultraelectronica) (creator)
