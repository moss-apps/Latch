# Locker

<p align="center">
  <img src="assets/banner_locker.png" alt="Locker Banner" width="100%">
</p>

---

Locker is a secure, private media vault application built with Flutter for Android. It provides a safe space to hide and protect your sensitive photos, videos, and documents from prying eyes, with multiple layers of security including biometric authentication, optional AES-256 encryption, and an auto-kill feature that removes the app from the recent apps list when you leave.

## Key Features

### Core Functionality
- **Media Vault**: Securely hide images, videos, and documents from your device gallery
- **Gallery Import**: Import media directly from your device gallery with the option to delete originals
- **Camera Integration**: Capture photos and videos directly into the vault
- **Document Support**: Store and view PDFs, Office documents (Word, Excel, PowerPoint), and text files
- **Custom Media Picker**: Built-in media picker with album browsing and multi-select support
- **Custom Document Picker**: File browser for selecting documents from device storage
- **Media Scanner**: Automatic duplicate detection when importing files
- **Backup & Restore**: Create local backups of your vault and restore when needed
- **Compression Options**: Choose compression levels for media files to save storage space

### Organization
- **Albums**: Create custom albums to organize your hidden files
- **Tags**: Add color-coded tags to files for easy categorization and filtering
- **Favorites**: Mark files as favorites for quick access
- **Search**: Find files by name, tags, type, date, or other criteria
- **Sorting**: Multiple sorting options including date, name, size, and type

### Viewing
- **Image Viewer**: Full-screen image viewing with pinch-to-zoom and slideshow mode
- **Video Player**: Built-in video player with playback controls, speed adjustment, and loop options
- **Song Player**: Built-in audio playback with external app handoff support
- **Document Viewer**: Native PDF rendering and Office document conversion for viewing
- **File Export**: Export files to Downloads folder or open with external applications
- **Performance Overlay**: Real-time display of FPS and performance metrics

### Security Features
- **PIN Authentication**: 6-digit PIN lock with secure storage
- **Password Authentication**: Traditional password protection option
- **Biometric Authentication**: Fingerprint and face recognition support
- **Optional Encryption**: AES-256-CBC/CTR encryption for stored files (off by default for performance)
- **Auto-Kill**: Automatically removes app from recent apps when leaving
- **Decoy Mode**: Set up a fake vault with a separate PIN to show if forced to unlock
- **Secure Delete**: Overwrite files before deletion to prevent recovery
- **Change Security**: Update PIN or password at any time with verification

### Theme & Customization
- **Dynamic Accent Colors**: Choose from multiple accent colors (Blue, Purple, Pink, Red, Orange, Teal, Green, Gunmetal)
- **Custom Theme**: Personalize the app's look to match your style
- **Performance Mode**: Adjust frame rate and performance settings for optimal experience
- **Glassmorphism**: Modern unlock screen design with visual effects

## Moss Ecosystem

Locker is part of the **Moss ecosystem** by Ultra Electronica, a suite of interconnected apps that share infrastructure and capabilities.

### Apps in the Ecosystem
- **Locker**: Secure media vault for hiding photos, videos, and documents
- **Flick Player**: High-performance audiophile music player with UAC 2.0 support

### Cross-App Integration
Locker integrates with Flick Player through platform channels:
- **Playback Handoff**: Locker can hand off audio playback to Flick for advanced audio engine features (EQ, effects, UAC 2.0 DAC output)
- **Shared Infrastructure**: Last.fm scrobbling, adaptive theming, and library scanning are shared across Moss apps

### Using Locker with Flick
When you want to play an audio file stored in Locker using Flick's advanced audio capabilities:
1. Select the audio file in Locker
2. Choose to open with Flick Player
3. Flick handles playback with its high-performance engine
4. Last.fm scrobbling continues uninterrupted

## Technology Stack

### Frontend (Flutter)
| Package | Purpose |
|---------|---------|
| `flutter_riverpod` | State management |
| `flutter_secure_storage` | Secure storage for credentials and metadata |
| `pointycastle` | AES-256 encryption |
| `photo_manager` | Media gallery access and import |
| `pdfrx` | Native PDF rendering |
| `syncfusion_flutter_pdf` | Office document conversion (Word/Excel/PowerPoint) |
| `flutter_image_compress` | Image compression |
| `video_compress` | Video compression |
| `archive` | ZIP/RAR/7Z archive support |
| `permission_handler` | Runtime permission management |
| `local_auth` | Biometric authentication (fingerprint/face) |
| `camera` | Camera integration for photo/video capture |
| `just_audio` | Audio playback with external handoff support |
| `in_app_update` | Google Play In-App Updates |

### Backend (Kotlin/Android)
| Component | Purpose |
|-----------|---------|
| `MainActivity.kt` | Auto-kill feature, performance settings, content URI handling |
| `AutoKillService` | Removes app from recent apps when backgrounded |
| `PermissionHandler` | Android runtime permission management |

## Project Structure

```
locker/
├── lib/                          # Flutter/Dart source
│   ├── main.dart                 # Application entry point
│   ├── models/                   # Data models
│   │   ├── album.dart            # Album and tag models
│   │   └── vaulted_file.dart    # Vaulted file model
│   ├── providers/                # Riverpod state providers
│   │   ├── vault_providers.dart  # Vault state management
│   │   ├── theme_provider.dart   # Theme management
│   │   └── performance_provider.dart # Performance settings
│   ├── screens/                  # UI screens
│   │   ├── unlock_screen.dart    # Authentication unlock screen
│   │   ├── home_screen.dart      # Main vault home screen
│   │   ├── gallery_vault_screen.dart # Gallery import screen
│   │   ├── media_viewer_screen.dart # Image/video viewer
│   │   ├── document_viewer_screen.dart # PDF/Office document viewer
│   │   ├── song_player_screen.dart # Audio player screen
│   │   └── settings/             # Settings screens
│   │       ├── vault_settings_screen.dart # Vault configuration
│   │       └── performance_settings_screen.dart # Performance tweaks
│   ├── services/                 # Business logic services
│   │   ├── auth_service.dart     # Authentication handling
│   │   ├── encryption_service.dart # AES-256 encryption/decryption
│   │   ├── vault_service.dart    # Core vault operations
│   │   ├── backup_service.dart   # Backup and restore
│   │   └── flick_integration_service.dart # Flick Player handoff
│   ├── themes/                   # App theming
│   │   ├── app_colors.dart       # Accent color definitions
│   │   └── app_theme.dart        # Theme configuration
│   └── widgets/                  # Reusable widgets
│       ├── pin_input_widget.dart # PIN entry widget
│       └── performance_overlay_widget.dart # FPS overlay
├── android/                      # Android platform code
│   └── app/src/main/kotlin/com/ultraelectronica/locker/
│       └── MainActivity.kt       # Auto-kill and performance
├── assets/                       # Static assets
│   ├── banner_locker.png         # App banner
│   └── ...
├── docs/                         # Architecture documentation
│   ├── architecture_media.md     # Media compression/encryption design
│   └── flick_integration.md      # Flick Player integration guide
└── pubspec.yaml                  # Flutter dependencies
```

## Getting Started

### Prerequisites
- Flutter SDK 3.4.4 or higher
- Dart SDK (included with Flutter)
- Android SDK with API level 34
- Java Development Kit (JDK) 17
- Android device with Android 6.0 (API 23) or higher

### Installation
#### From Release APK
1. Download the latest APK from the [Releases page](https://github.com/heimin22/Locker/releases)
2. Enable "Install from unknown sources" in your device settings
3. Install the APK
4. Launch and set up your authentication method

### Running
```bash
# Run in debug mode
flutter run

# Run on a specific device
flutter run -d <device-id>
```

### Building
```bash
# Debug build
flutter build apk --debug

# Release build
flutter build apk --release
```

#### Building from Source
1. Clone the repository:
   ```bash
   git clone https://github.com/heimin22/Locker.git
   cd Locker
   ```
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Generate launcher icons (optional):
   ```bash
   flutter pub run flutter_launcher_icons
   ```
4. Build using the commands above

## Platform-Specific Notes

### Android
Locker is designed exclusively for Android, using Flutter for UI and Kotlin for native features:
- **Auto-Kill**: Uses Android's activity lifecycle to remove the app from recent tasks when backgrounded
- **Biometrics**: Leverages Android's BiometricPrompt API for fingerprint/face authentication
- **Media Access**: Uses `photo_manager` to access device gallery media (requires storage permissions)
- **Camera**: Integrates with Android's Camera API for photo/video capture

#### Permissions
| Permission | Purpose |
|------------|---------|
| READ_EXTERNAL_STORAGE | Access files on device (Android 12 and below) |
| WRITE_EXTERNAL_STORAGE | Write files to device (Android 12 and below) |
| READ_MEDIA_IMAGES | Access images (Android 13+) |
| READ_MEDIA_VIDEO | Access videos (Android 13+) |
| MANAGE_EXTERNAL_STORAGE | Full file access for hiding/unhiding (Android 11+) |
| CAMERA | Capture photos and videos |
| RECORD_AUDIO | Record audio with video |
| USE_BIOMETRIC | Biometric authentication |

## Architecture
Locker follows a service-based architecture with clear separation of concerns:
- **Services Layer**: Business logic for authentication, encryption, file operations, and media handling
- **Providers Layer**: Riverpod providers for reactive state management across UI components
- **Screens**: Feature-specific UI screens for authentication, vault management, settings, and media viewing
- **Native Backend**: Kotlin code for Android-specific features like auto-kill, permissions, and camera access

All sensitive data (PIN, passwords, encryption keys) is stored via `flutter_secure_storage` in Android's Keystore system.

## Documentation
Additional documentation available:
- [Architecture Diagram](docs/architecture_media.md) - Detailed system architecture design covering compression, encryption, and file operations
- [Flick Integration Guide](docs/flick_integration.md) - Contract and implementation notes for making Flick a first-class Locker playback companion

## License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

Locker is purely open-source and free. There are no premium features, ads, or paid components.

## Contributors
- [@heimin22](https://github.com/heimin22) (Project creator)

## Contributing
Contributions are welcome. Please ensure all changes pass linting and testing before submitting pull requests.

### Code Style
- Follow the Dart style guide
- Run `flutter analyze` before submitting
- Ensure all existing tests pass

### Steps
1. Fork the repository
2. Create a feature branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. Make your changes and commit:
   ```bash
   git commit -m "Add your feature description"
   ```
4. Push to your fork:
   ```bash
   git push origin feature/your-feature-name
   ```
5. Open a Pull Request
