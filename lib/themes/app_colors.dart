import 'package:flutter/material.dart';

/// App Color Palette
/// Contains all color definitions used throughout the Latch app
/// Follows golden design rules with eye-friendly colors
class AppColors {
  AppColors._(); // Private constructor to prevent instantiation

  // ===== DARK MODE COLORS =====
  // Eye-friendly dark theme with reduced blue light and warm undertones

  /// Dark mode background - Soft charcoal with warm undertone (#1A1A1D)
  static const Color darkBackground = Color(0xFF1A1A1D);

  /// Dark mode secondary background (#242428)
  static const Color darkBackgroundSecondary = Color(0xFF242428);

  /// Dark mode surface for cards/containers (#2D2D32)
  static const Color darkSurface = Color(0xFF2D2D32);

  /// Dark mode elevated surface (#38383E)
  static const Color darkSurfaceElevated = Color(0xFF38383E);

  /// Dark mode text primary - Warm off-white (#E8E6E3)
  static const Color darkTextPrimary = Color(0xFFE8E6E3);

  /// Dark mode text secondary (#B8B6B3)
  static const Color darkTextSecondary = Color(0xFFB8B6B3);

  /// Dark mode text tertiary (#8A8886)
  static const Color darkTextTertiary = Color(0xFF8A8886);

  /// Dark mode text disabled (#5A5856)
  static const Color darkTextDisabled = Color(0xFF5A5856);

  /// Dark mode divider (#3D3D42)
  static const Color darkDivider = Color(0xFF3D3D42);

  /// Dark mode border (#4A4A50)
  static const Color darkBorder = Color(0xFF4A4A50);

  /// Dark mode accent - Soft blue (#5C9CE6)
  static const Color darkAccent = Color(0xFF5C9CE6);

  /// Dark mode accent light (#7AB3F0)
  static const Color darkAccentLight = Color(0xFF7AB3F0);

  // ===== GLASSMORPHIC COLORS =====

  /// Glass background (dark mode) - semi-transparent
  static const Color glassDarkBg = Color(0x1AFFFFFF); // 10% white

  /// Glass background (light mode) - semi-transparent
  static const Color glassLightBg = Color(0x0D000000); // 5% black

  /// Glass border (dark mode) - subtle white border
  static const Color glassDarkBorder = Color(0x33FFFFFF); // 20% white

  /// Glass border (light mode) - subtle dark border
  static const Color glassLightBorder = Color(0x1A000000); // 10% black

  /// Glass highlight (for shine effect)
  static const Color glassHighlight = Color(0x26FFFFFF); // 15% white

  // ===== LEGACY PRIMARY COLORS (for backward compatibility) =====

  /// Main background color - Dark Gray (#121212)
  static const Color primaryBackground = Color(0xFF121212);

  /// Main text color - Light Gray (#F5F5F5)
  static const Color primaryText = Color(0xFFF5F5F5);

  // ===== BACKGROUND VARIATIONS =====

  /// Darker variation of primary background
  static const Color backgroundDark = Color(0xFF0A0A0A);

  /// Slightly lighter variation of primary background
  static const Color backgroundLight = Color(0xFF1E1E1E);

  /// Surface color for cards, containers
  static const Color surface = Color(0xFF262626);

  /// Elevated surface color
  static const Color surfaceElevated = Color(0xFF2D2D2D);

  // ===== TEXT VARIATIONS =====

  /// Primary text color (same as primaryText for consistency)
  static const Color textPrimary = Color(0xFFF5F5F5);

  /// Secondary text color - slightly dimmed
  static const Color textSecondary = Color(0xFFE0E0E0);

  /// Tertiary text color - more dimmed
  static const Color textTertiary = Color(0xFFBDBDBD);

  /// Disabled text color
  static const Color textDisabled = Color(0xFF757575);

  /// Hint text color
  static const Color textHint = Color(0xFF9E9E9E);

  // ===== ACCENT COLORS =====

  /// Success color - Soft green
  static const Color success = Color(0xFF4CAF50);

  /// Success color for dark mode - Softer green
  static const Color darkSuccess = Color(0xFF66BB6A);

  /// Error color
  static const Color error = Color(0xFFE53935);

  /// Error color for dark mode - Softer red
  static const Color darkError = Color(0xFFEF5350);

  /// Warning color
  static const Color warning = Color(0xFFFF9800);

  /// Warning color for dark mode
  static const Color darkWarning = Color(0xFFFFB74D);

  /// Info color
  static const Color info = Color(0xFF2196F3);

  /// Info color for dark mode
  static const Color darkInfo = Color(0xFF64B5F6);

  // ===== UTILITY COLORS =====

  /// Divider color
  static const Color divider = Color(0xFF424242);

  /// Border color
  static const Color border = Color(0xFF616161);

  /// Shadow color
  static const Color shadow = Color(0xFF000000);

  /// Overlay color (for modals, dialogs)
  static const Color overlay = Color(0x80000000);

  // ===== LIGHT THEME COLORS =====

  /// Light theme background
  static const Color lightBackground = Color(0xFFFFFFFF);

  /// Light theme secondary background
  static const Color lightBackgroundSecondary = Color(0xFFF8F9FA);

  /// Light theme surface
  static const Color lightSurface = Color(0xFFFFFFFF);

  /// Light theme text primary
  static const Color lightTextPrimary = Color(0xFF212121);

  /// Light theme text secondary
  static const Color lightTextSecondary = Color(0xFF424242);

  /// Light theme text tertiary
  static const Color lightTextTertiary = Color(0xFF757575);

  /// Light theme divider
  static const Color lightDivider = Color(0xFFE0E0E0);

  /// Light theme border
  static const Color lightBorder = Color(0xFFBDBDBD);

  /// Light theme accent color
  static const Color accent = Color(0xFF1976D2);

  /// Light theme accent light
  static const Color accentLight = Color(0xFF42A5F5);

  // ===== ADAPTIVE COLOR GETTERS =====
  // These return the appropriate color based on theme brightness

  /// Get background color based on brightness
  static Color background(Brightness brightness) {
    return brightness == Brightness.dark ? darkBackground : lightBackground;
  }

  /// Get secondary background color based on brightness
  static Color backgroundSecondary(Brightness brightness) {
    return brightness == Brightness.dark
        ? darkBackgroundSecondary
        : lightBackgroundSecondary;
  }

  /// Get surface color based on brightness
  static Color surfaceColor(Brightness brightness) {
    return brightness == Brightness.dark ? darkSurface : lightSurface;
  }

  /// Get primary text color based on brightness
  static Color textPrimaryColor(Brightness brightness) {
    return brightness == Brightness.dark ? darkTextPrimary : lightTextPrimary;
  }

  /// Get secondary text color based on brightness
  static Color textSecondaryColor(Brightness brightness) {
    return brightness == Brightness.dark
        ? darkTextSecondary
        : lightTextSecondary;
  }

  /// Get tertiary text color based on brightness
  static Color textTertiaryColor(Brightness brightness) {
    return brightness == Brightness.dark ? darkTextTertiary : lightTextTertiary;
  }

  /// Get divider color based on brightness
  static Color dividerColor(Brightness brightness) {
    return brightness == Brightness.dark ? darkDivider : lightDivider;
  }

  /// Get border color based on brightness
  static Color borderColor(Brightness brightness) {
    return brightness == Brightness.dark ? darkBorder : lightBorder;
  }

  /// Get accent color based on brightness
  static Color accentColor(Brightness brightness) {
    return brightness == Brightness.dark ? darkAccent : accent;
  }

  // ===== GRADIENTS =====

  /// Primary background gradient
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF121212),
      Color(0xFF1E1E1E),
    ],
  );

  /// Dark mode background gradient
  static const LinearGradient darkBackgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF1A1A1D),
      Color(0xFF242428),
    ],
  );

  /// Card gradient
  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF262626),
      Color(0xFF1E1E1E),
    ],
  );

  // ===== MATERIAL COLOR SWATCHES =====

  /// Primary material color swatch based on the background color
  static const MaterialColor primarySwatch = MaterialColor(
    0xFF121212,
    <int, Color>{
      50: Color(0xFFE8E8E8),
      100: Color(0xFFC6C6C6),
      200: Color(0xFFA0A0A0),
      300: Color(0xFF7A7A7A),
      400: Color(0xFF5E5E5E),
      500: Color(0xFF424242),
      600: Color(0xFF3C3C3C),
      700: Color(0xFF333333),
      800: Color(0xFF2A2A2A),
      900: Color(0xFF121212),
    },
  );

  /// Text material color swatch based on the text color
  static const MaterialColor textSwatch = MaterialColor(
    0xFFF5F5F5,
    <int, Color>{
      50: Color(0xFFFFFFFF),
      100: Color(0xFFFAFAFA),
      200: Color(0xFFF5F5F5),
      300: Color(0xFFE0E0E0),
      400: Color(0xFFBDBDBD),
      500: Color(0xFF9E9E9E),
      600: Color(0xFF757575),
      700: Color(0xFF616161),
      800: Color(0xFF424242),
      900: Color(0xFF212121),
    },
  );

  // ===== COLOR SCHEMES =====

  /// Light color scheme
  static const ColorScheme lightColorScheme = ColorScheme.light(
    primary: Color(0xFF1976D2),
    primaryContainer: Color(0xFFBBDEFB),
    secondary: Color(0xFF424242),
    secondaryContainer: Color(0xFFE0E0E0),
    surface: Color(0xFFFFFFFF),
    error: Color(0xFFE53935),
    onPrimary: Color(0xFFFFFFFF),
    onSecondary: Color(0xFFFFFFFF),
    onSurface: Color(0xFF212121),
    onError: Color(0xFFFFFFFF),
  );

  /// Dark color scheme - Eye-friendly with warm undertones
  static const ColorScheme darkColorScheme = ColorScheme.dark(
    primary: Color(0xFF5C9CE6), // Soft blue accent
    primaryContainer: Color(0xFF2D4A6B),
    secondary: Color(0xFFE8E6E3), // Warm off-white
    secondaryContainer: Color(0xFF38383E),
    surface: Color(0xFF2D2D32),
    error: Color(0xFFEF5350), // Softer red
    onPrimary: Color(0xFF1A1A1D),
    onSecondary: Color(0xFF1A1A1D),
    onSurface: Color(0xFFE8E6E3),
    onError: Color(0xFF1A1A1D),
  );
}

/// Extension on BuildContext for easy access to adaptive theme colors
extension AppColorsExtension on BuildContext {
  /// Returns true if the current theme is dark mode
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  /// Primary text color (adapts to theme)
  Color get textPrimary =>
      isDarkMode ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

  /// Secondary text color (adapts to theme)
  Color get textSecondary =>
      isDarkMode ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

  /// Tertiary text color (adapts to theme)
  Color get textTertiary =>
      isDarkMode ? AppColors.darkTextTertiary : AppColors.lightTextTertiary;

  /// Background color (adapts to theme)
  Color get backgroundColor =>
      isDarkMode ? AppColors.darkBackground : AppColors.lightBackground;

  /// Secondary background color (adapts to theme)
  Color get backgroundSecondary => isDarkMode
      ? AppColors.darkBackgroundSecondary
      : AppColors.lightBackgroundSecondary;

  /// Surface color for cards (adapts to theme)
  Color get surfaceColor =>
      isDarkMode ? AppColors.darkSurface : AppColors.lightSurface;

  /// Border color (adapts to theme)
  Color get borderColor =>
      isDarkMode ? AppColors.darkBorder : AppColors.lightBorder;

  /// Divider color (adapts to theme)
  Color get dividerColor =>
      isDarkMode ? AppColors.darkDivider : AppColors.lightDivider;

  /// Accent color (uses theme's primary color which is set dynamically)
  Color get accentColor => Theme.of(this).colorScheme.primary;

  /// Accent color variant (uses theme's primary container)
  Color get accentColorVariant => Theme.of(this).colorScheme.primaryContainer;

  /// Glass background color (adapts to theme)
  Color get glassBg => isDarkMode ? AppColors.glassDarkBg : AppColors.glassLightBg;

  /// Glass border color (adapts to theme)
  Color get glassBorder => isDarkMode ? AppColors.glassDarkBorder : AppColors.glassLightBorder;

  /// Glass highlight color
  Color get glassHighlight => AppColors.glassHighlight;
}
