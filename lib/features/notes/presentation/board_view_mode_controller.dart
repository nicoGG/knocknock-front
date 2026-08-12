import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BoardViewMode { grid, list }

enum NoteFilter { all, pending, completed }

typedef BoardViewPreferencesLoader = Future<SharedPreferences> Function();

class BoardViewModeController extends ChangeNotifier {
  BoardViewModeController({BoardViewPreferencesLoader? preferencesLoader})
    : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _storageKey = 'nocknock.board_preferences_by_list.v1';
  static const _legacyViewModeStorageKey = 'nocknock.board_view_mode.v1';

  final BoardViewPreferencesLoader _preferencesLoader;
  final Map<String, _BoardListPreferences> _preferencesByList = {};
  BoardViewMode _legacyViewMode = BoardViewMode.grid;
  Future<void> _writeQueue = Future.value();

  BoardViewMode viewModeFor(String listId) =>
      _preferencesByList[listId]?.viewMode ?? _legacyViewMode;

  NoteFilter filterFor(String listId) =>
      _preferencesByList[listId]?.filter ?? NoteFilter.all;

  Future<void> load() async {
    try {
      final preferences = await _preferencesLoader();
      final locallyChangedPreferences = Map.of(_preferencesByList);
      _preferencesByList
        ..clear()
        ..addAll(_decode(preferences.getString(_storageKey)))
        ..addAll(locallyChangedPreferences);
      _legacyViewMode = _viewModeFromStorage(
        preferences.getString(_legacyViewModeStorageKey),
      );
      notifyListeners();
    } catch (_) {
      // Keep the in-memory selections when storage is unavailable.
    }
  }

  Future<void> setViewMode(String listId, BoardViewMode value) {
    final current = _preferencesFor(listId);
    if (current.viewMode == value) return Future.value();
    _preferencesByList[listId] = current.copyWith(viewMode: value);
    notifyListeners();
    return _schedulePersist();
  }

  Future<void> setFilter(String listId, NoteFilter value) {
    final current = _preferencesFor(listId);
    if (current.filter == value) return Future.value();
    _preferencesByList[listId] = current.copyWith(filter: value);
    notifyListeners();
    return _schedulePersist();
  }

  Future<void> forgetList(String listId) {
    if (_preferencesByList.remove(listId) == null) return Future.value();
    notifyListeners();
    return _schedulePersist();
  }

  _BoardListPreferences _preferencesFor(String listId) =>
      _preferencesByList[listId] ??
      _BoardListPreferences(viewMode: _legacyViewMode, filter: NoteFilter.all);

  Future<void> _schedulePersist() {
    _writeQueue = _writeQueue.then((_) async {
      try {
        final preferences = await _preferencesLoader();
        await preferences.setString(_storageKey, jsonEncode(_toJson()));
      } catch (_) {
        // Keep the selected preferences for this session if persistence fails.
      }
    });
    return _writeQueue;
  }

  Map<String, Object> _toJson() => _preferencesByList.map(
    (listId, preferences) => MapEntry(listId, preferences.toJson()),
  );

  Map<String, _BoardListPreferences> _decode(String? value) {
    if (value == null || value.isEmpty) return {};
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) return {};
    return {
      for (final MapEntry(:key, :value) in decoded.entries)
        if (value is Map<String, dynamic>)
          key: _BoardListPreferences.fromJson(value),
    };
  }

  BoardViewMode _viewModeFromStorage(String? value) => switch (value) {
    'list' => BoardViewMode.list,
    'largeList' => BoardViewMode.list,
    _ => BoardViewMode.grid,
  };
}

class _BoardListPreferences {
  const _BoardListPreferences({required this.viewMode, required this.filter});

  factory _BoardListPreferences.fromJson(Map<String, dynamic> json) =>
      _BoardListPreferences(
        viewMode: switch (json['viewMode']) {
          'list' || 'largeList' => BoardViewMode.list,
          _ => BoardViewMode.grid,
        },
        filter: switch (json['filter']) {
          'pending' => NoteFilter.pending,
          'completed' => NoteFilter.completed,
          _ => NoteFilter.all,
        },
      );

  final BoardViewMode viewMode;
  final NoteFilter filter;

  _BoardListPreferences copyWith({
    BoardViewMode? viewMode,
    NoteFilter? filter,
  }) => _BoardListPreferences(
    viewMode: viewMode ?? this.viewMode,
    filter: filter ?? this.filter,
  );

  Map<String, String> toJson() => {
    'viewMode': viewMode.name,
    'filter': filter.name,
  };
}
