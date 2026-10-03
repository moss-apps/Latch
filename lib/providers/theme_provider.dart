import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/accent_color.dart';

/// Theme mode preference key for SharedPreferences
const String _themeModeKey = 'theme_mode';

/// Accent color preference key for SharedPreferences
const String _accentColorKey = 'accent_color';

/// Theme mode notifier for managing app theme state
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _loadThemeMode();
    return ThemeMode.light; // Default to light mode
  }

  /// Load theme mode from SharedPreferences
  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    // Default to ThemeMode.light (index 1) if not set
    final themeModeIndex = prefs.getInt(_themeModeKey) ?? ThemeMode.light.index;
    state =
        ThemeMode.values[themeModeIndex.clamp(0, ThemeMode.values.length - 1)];
  }

  /// Save theme mode to SharedPreferences
  Future<void> _saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, mode.index);
  }

  /// Toggle between light and dark mode
  Future<void> toggleTheme() async {
    state = state == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    await _saveThemeMode(state);
  }

  /// Set specific theme mode
  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await _saveThemeMode(mode);
  }

  /// Check if currently in dark mode
  bool get isDarkMode => state == ThemeMode.dark;
}

/// Accent color notifier for managing app accent color
class AccentColorNotifier extends Notifier<AccentColorOption> {
  @override
  AccentColorOption build() {
    _loadAccentColor();
    return AccentColors.blue; // Default to blue
  }

  /// Load accent color from SharedPreferences
  Future<void> _loadAccentColor() async {
    final prefs = await SharedPreferences.getInstance();
    final colorId = prefs.getString(_accentColorKey) ?? 'blue';
    state = AccentColors.getById(colorId) ?? AccentColors.blue;
  }

  /// Save accent color to SharedPreferences
  Future<void> _saveAccentColor(AccentColorOption color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accentColorKey, color.id);
  }

  /// Set accent color
  Future<void> setAccentColor(AccentColorOption color) async {
    state = color;
    await _saveAccentColor(color);
  }
}

/// Provider for theme mode state
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(() {
  return ThemeModeNotifier();
});

/// Provider for accent color state
final accentColorProvider =
    NotifierProvider<AccentColorNotifier, AccentColorOption>(() {
  return AccentColorNotifier();
});

/// Helper provider to check if dark mode is active
final isDarkModeProvider = Provider<bool>((ref) {
  final themeMode = ref.watch(themeModeProvider);
  return themeMode == ThemeMode.dark;
});

/// Helper provider to get current accent color based on theme
final currentAccentColorProvider = Provider<Color>((ref) {
  final accentColor = ref.watch(accentColorProvider);
  final isDarkMode = ref.watch(isDarkModeProvider);
  return accentColor.getColor(isDarkMode ? Brightness.dark : Brightness.light);
});

/// Helper provider to get current accent color variant based on theme
final currentAccentColorVariantProvider = Provider<Color>((ref) {
  final accentColor = ref.watch(accentColorProvider);
  final isDarkMode = ref.watch(isDarkModeProvider);
  return accentColor
      .getVariantColor(isDarkMode ? Brightness.dark : Brightness.light);
});
