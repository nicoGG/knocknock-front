import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef ThemePreferencesLoader = Future<SharedPreferences> Function();

class AppThemeController extends ChangeNotifier {
  AppThemeController({ThemePreferencesLoader? preferencesLoader})
    : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _storageKey = 'nocknock.theme_mode.v1';

  final ThemePreferencesLoader _preferencesLoader;
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  Future<void> load() async {
    try {
      final preferences = await _preferencesLoader();
      _themeMode = _fromStorage(preferences.getString(_storageKey));
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
      await preferences.setString(_storageKey, value.name);
    } catch (_) {
      // Keep the selected mode for this session even if it cannot be persisted.
    }
  }

  ThemeMode _fromStorage(String? value) => switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}
