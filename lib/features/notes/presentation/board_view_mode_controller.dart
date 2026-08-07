import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BoardViewMode { grid, list }

typedef BoardViewPreferencesLoader = Future<SharedPreferences> Function();

class BoardViewModeController extends ChangeNotifier {
  BoardViewModeController({BoardViewPreferencesLoader? preferencesLoader})
    : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _storageKey = 'nocknock.board_view_mode.v1';

  final BoardViewPreferencesLoader _preferencesLoader;
  BoardViewMode _viewMode = BoardViewMode.grid;

  BoardViewMode get viewMode => _viewMode;

  Future<void> load() async {
    try {
      final preferences = await _preferencesLoader();
      _viewMode = _fromStorage(preferences.getString(_storageKey));
      notifyListeners();
    } catch (_) {
      // Keep the grid as a safe fallback when storage is unavailable.
    }
  }

  Future<void> setViewMode(BoardViewMode value) async {
    if (_viewMode == value) return;
    _viewMode = value;
    notifyListeners();
    try {
      final preferences = await _preferencesLoader();
      await preferences.setString(_storageKey, value.name);
    } catch (_) {
      // Keep the selected view for this session if it cannot be persisted.
    }
  }

  BoardViewMode _fromStorage(String? value) => switch (value) {
    'list' => BoardViewMode.list,
    'largeList' => BoardViewMode.list,
    _ => BoardViewMode.grid,
  };
}
