# Locker

Locker is a secure, private media vault application built with Flutter for Android. It provides a safe space to hide and protect your sensitive photos, videos, and documents from prying eyes, with multiple layers of security including biometric authentication, optional AES-256 encryption, and an auto-kill feature that removes the app from the recent apps list when you leave.

---

## Table of Contents

- [Features](#features)
- [Security](#security)
- [Requirements](#requirements)
- [Installation](#installation)
- [Building from Source](#building-from-source)
- [Usage](#usage)
- [File Support](#file-support)
- [Architecture](#architecture)
- [Permissions](#permissions)
- [Configuration](#configuration)
- [Contributing](#contributing)
- [License](#license)
- [Disclaimer](#disclaimer)
- [Contact](#contact)
- [Documentation](#documentation)

---

## Features

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

---

## Security

### Authentication Methods

Locker supports three authentication methods:

1. **PIN**: A 6-digit numeric PIN
2. **Password**: An alphanumeric password of any length
3. **Biometrics**: Fingerprint or face recognition (requires PIN or password as backup)

### Changing Authentication

You can change your PIN or password at any time:

1. Open Settings from the drawer
2. Select "Change Security"
3. Verify your current credentials
4. Set up your new PIN or password
5. Optionally enable or disable biometrics

### Encryption

When enabled, files are encrypted using AES-256 encryption:

- **Small files**: AES-256-CBC mode with in-memory processing
- **Large files**: AES-256-CTR mode with streaming encryption for memory efficiency

Encryption is disabled by default for performance reasons. Enable it in Settings for maximum security.

### Auto-Kill Feature

The auto-kill feature ensures the app is removed from the Android recent apps switcher when:

- The user presses the home button
- The user switches to another app
- The app goes into the background

This prevents others from seeing that the app was recently used.

### Decoy Mode

Decoy mode allows you to set up a fake vault with a different PIN. If someone forces you to unlock the app, enter the decoy PIN to show the fake vault instead of your real hidden files.

---

## Requirements

- **Android**: 6.0 (API level 23) or higher
- **Target SDK**: Android 14 (API level 34)
- **Minimum SDK**: Android 6.0 (API level 23)
- **Storage**: Sufficient space for your hidden files
- **Flutter**: 3.4.4 or higher

---

## Installation

### From Release APK

1. Download the latest APK from the Releases page
2. Enable "Install from unknown sources" in your device settings
3. Install the APK
4. Launch and set up your authentication method

### From Source

See [Building from Source](#building-from-source) below.

---

## Building from Source

### Prerequisites

- Flutter SDK 3.4.4 or higher
- Dart SDK (included with Flutter)
- Android SDK with API level 34
- Java Development Kit (JDK) 17

### Steps

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

4. Build for Android:

   ```bash
   # Debug build
   flutter build apk --debug

   # Release build
   flutter build apk --release
   ```

5. Install on device:

   ```bash
   flutter install
   ```

### Running in Development

```bash
flutter run
```

---

## Usage

### First Launch

1. Launch the app for the first time
2. Choose your preferred authentication method (PIN, Password, or Biometrics)
3. Set up your credentials
4. Optionally configure settings like encryption and decoy mode

### Hiding Files

1. Tap the "Import" button or use the floating action button
2. Select the source:
   - **Images**: Import images from your gallery
   - **Videos**: Import videos from your gallery
   - **All Media**: Import both images and videos
   - **Camera**: Capture a new photo or video
   - **Documents**: Import documents from your device
3. Select the files you want to hide
4. Confirm the import - originals will be deleted from your gallery by default

### Viewing Files

- Tap any file to open it in the built-in viewer
- Use gestures to zoom and pan images
- Swipe left/right to navigate between files
- Tap the screen to show/hide controls

### Organizing Files

- **Albums**: Access from the drawer menu, create albums to group related files
- **Tags**: Long-press a file and select "Add Tag" to categorize
- **Favorites**: Tap the heart icon to mark as favorite

### Unhiding Files

1. Select files in the vault
2. Tap the "Unhide" action
3. Files will be restored to your device gallery (DCIM/Restored folder)

---

## File Support

### Images

- JPEG, PNG, GIF, WebP, BMP, HEIC

### Videos

- MP4, MOV, AVI, MKV, WebM, 3GP

### Documents

- PDF (native viewing)
- Microsoft Word (DOC, DOCX) - converted to PDF for viewingS
- Text files (TXT, MD, JSON, XML, CSV, LOG)

### Other Files

- ZIP, RAR, 7Z archives
- APK files
- Audio files (MP3, WAV, FLAC, AAC, OGG)
- Any other file type (stored but not previewable)

---

## Architecture

### Technology Stack

- **Framework**: Flutter 3.4.4+
- **State Management**: Riverpod
- **Storage**: Flutter Secure Storage for credentials and metadata
- **Encryption**: PointyCastle (AES-256)
- **Native Integration**: Kotlin for Android-specific features
- **Compression**: flutter_image_compress, video_compress
- **Media Access**: photo_manager
- **PDF Rendering**: pdfrx
- **Office Documents**: syncfusion_flutter_pdf for Word/Excel/PowerPoint conversion

### Project Structure

```
lib/
  main.dart                 # Application entry point
  models/                   # Data models
    album.dart              # Album and tag models
    vaulted_file.dart       # Vaulted file model
    accent_color.dart      # Accent color model
  providers/                # Riverpod state providers
    vault_providers.dart    # Vault state management
    theme_provider.dart     # Theme management
    performance_provider.dart # Performance settings
  screens/                  # UI screens
    albums_screen.dart
    album_detail_screen.dart
    auth_method_selection_screen.dart
    backup_file_selection_screen.dart
    camera_screen.dart
    document_picker_screen.dart
    document_viewer_screen.dart
    favorites_screen.dart
    folder_picker_screen.dart
    gallery_vault_screen.dart
    home_screen.dart
    local_backup_screen.dart
    media_picker_screen.dart
    media_viewer_screen.dart
    performance_settings_screen.dart
    pin_setup_screen.dart
    password_setup_screen.dart
    biometric_setup_screen.dart
    change_security_screen.dart
    accent_color_picker_screen.dart
    song_player_screen.dart
    tags_screen.dart
    unlock_screen.dart
    vault_settings_screen.dart
  services/                 # Business logic services
    auth_service.dart       # Authentication handling
    auto_kill_service.dart  # Auto-kill feature
    backup_service.dart    # Backup and restore
    compression_service.dart # Media compression
    decoy_service.dart     # Decoy mode
    encryption_service.dart # File encryption
    file_import_service.dart # Import/export logic
    flick_integration_service.dart # Video playback integration
    improved_compression_service.dart # Enhanced compression
    improved_vault_operations.dart # Enhanced vault operations
    media_compress_service.dart # Video compression
    media_compression_service.dart # Media compression utilities
    media_scanner_service.dart # Media scanning
    office_converter_service.dart # Office document conversion
    permission_service.dart # Permission handling
    screenshot_protection_service.dart # Screenshot prevention
    vault_service.dart      # Core vault operations
  themes/                   # App theming
    app_colors.dart
    app_theme.dart
  utils/                    # Utility classes
    toast_utils.dart
    compression_helper.dart # Compression utilities
    encryption_diagnostics.dart # Encryption diagnostics
    frame_rate_optimizer.dart # Performance optimization
    performance_config.dart # Performance settings
    responsive_utils.dart  # Responsive layout utilities
    vault_file_checker.dart # File validation
  widgets/                  # Reusable widgets
    auth_method_card.dart
    compression_options_dialog.dart
    conversion_warning_dialog.dart
    office_conversion_confirm_dialog.dart
    operation_progress_sheet.dart
    optimized_image_widget.dart
    optimized_scroll_view.dart
    permission_warning_banner.dart
    performance_overlay_widget.dart
    pin_input_widget.dart
    vault_operation_progress_dialog.dart

android/
  app/src/main/kotlin/      # Native Kotlin code
    MainActivity.kt         # Auto-kill and performance
```

---

## Permissions

Locker requires the following Android permissions:

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

---

## Configuration

### Settings

Access settings from the drawer menu or security icon:

| Setting | Description | Default |
|---------|-------------|---------|
| Encryption | Enable AES-256 encryption for new files | Off |
| Secure Delete | Overwrite files before deletion | On |
| Default Sort | How files are sorted in the vault | Date Added (Newest) |
| Decoy Mode | Enable fake vault with separate PIN | Off |
| Accent Color | App accent color | Blue |
| Performance Mode | Frame rate and optimization settings | Auto |
| Backup | Create and restore local backups | Manual |

### Backup & Restore

1. Open Settings from the drawer
2. Select "Local Backup"
3. Choose "Create Backup" to export your vault data
4. Choose "Restore Backup" to import a previous backup
5. Follow the on-screen instructions

### Performance Settings

1. Open Settings from the drawer
2. Select "Performance Settings"
3. Adjust frame rate limit (60/90/120 FPS or Unlimited)
4. Enable or disable performance overlay
5. Configure memory optimization options

---

## Contributing

Contributions are welcome. To contribute:

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

### Code Style

- Follow the Dart style guide
- Run `flutter analyze` before submitting
- Ensure all existing tests pass

---

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

```
MIT License

Copyright (c) 2025 ultraelectronica

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
```

---

## Disclaimer

Locker is intended for personal privacy protection only. The developers are not responsible for any misuse of this application. Use responsibly and in accordance with applicable laws.

This application:

- Does not upload your files anywhere
- Does not collect any personal data
- Stores all data locally on your device
- Cannot recover files if you forget your PIN/password

---

## Contact

For questions, suggestions, or bug reports:

- Open an issue on GitHub
- Email: athrundiscinity@protonmail.com

---

## Acknowledgments

Built with the following open-source libraries:

- Flutter and Dart by Google
- Riverpod for state management
- PointyCastle for encryption
- photo_manager for media access
- pdfrx for PDF viewing
- flutter_image_compress for image optimization
- video_compress for video compression
- syncfusion_flutter_pdf for Office document conversion
- archive for ZIP/RAR/7Z support
- And many other excellent packages

---

## Documentation

Additional documentation available:

- [Architecture Diagram](docs/architecture_media.md) - Detailed system architecture design covering compression, encryption, and file operations
- [Flick Integration Guide](docs/flick_integration.md) - Contract and implementation notes for making Flick a first-class Locker playback companion

---

Made with care for your privacy.
