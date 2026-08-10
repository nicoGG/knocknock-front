import 'package:flutter/material.dart';
import 'package:nocknock/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef ThemePreferencesLoader = Future<SharedPreferences> Function();

class AppThemeController extends ChangeNotifier {
  AppThemeController({ThemePreferencesLoader? preferencesLoader})
    : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _themeModeStorageKey = 'nocknock.theme_mode.v1';
  static const _colorThemeStorageKey = 'nocknock.color_theme.v1';

  final ThemePreferencesLoader _preferencesLoader;
  ThemeMode _themeMode = ThemeMode.system;
  AppColorTheme _colorTheme = AppColorTheme.sunset;

  ThemeMode get themeMode => _themeMode;
  AppColorTheme get colorTheme => _colorTheme;

  Future<void> load() async {
    try {
      final preferences = await _preferencesLoader();
      _themeMode = _themeModeFromStorage(
        preferences.getString(_themeModeStorageKey),
      );
      _colorTheme = _colorThemeFromStorage(
        preferences.getString(_colorThemeStorageKey),
      );
      notifyListeners();
    } catch (_) {
      // The system theme remains a safe fallback when storage is unavailable.
    }
  }

  Future<void> setThemeMode(ThemeMode value) async {
    if (_themeMode == value) return;
    _themeMode = value;
    notifyListeners();
    try {
      final preferences = await _preferencesLoader();
      await preferences.setString(_themeModeStorageKey, value.name);
    } catch (_) {
      // Keep the selected mode for this session even if it cannot be persisted.
    }
  }

  Future<void> setColorTheme(AppColorTheme value) async {
    if (_colorTheme == value) return;
    _colorTheme = value;
    notifyListeners();
    try {
      final preferences = await _preferencesLoader();
      await preferences.setString(_colorThemeStorageKey, value.name);
    } catch (_) {
      // Keep the selected palette for this session if persistence fails.
    }
  }

  ThemeMode _themeModeFromStorage(String? value) => switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  AppColorTheme _colorThemeFromStorage(String? value) =>
      AppColorTheme.values.where((theme) => theme.name == value).firstOrNull ??
      AppColorTheme.sunset;
}
