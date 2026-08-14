import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ListShortcutsController extends ChangeNotifier {
  static const _favoritesKey = 'nocknock.favorite_lists.v1';
  static const _recentsKey = 'nocknock.recent_lists.v1';
  final Set<String> _favorites = {};
  final List<String> _recents = [];

  Set<String> get favorites => Set.unmodifiable(_favorites);
  List<String> get recents => List.unmodifiable(_recents);

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    _favorites.addAll(_read(preferences.getString(_favoritesKey)));
    _recents.addAll(_read(preferences.getString(_recentsKey)));
    notifyListeners();
  }

  Future<void> recordOpened(String listId) async {
    _recents
      ..remove(listId)
      ..insert(0, listId);
    if (_recents.length > 4) _recents.removeRange(4, _recents.length);
    await _persist();
    notifyListeners();
  }

  Future<bool> toggleFavorite(String listId) async {
    if (!_favorites.contains(listId) && _favorites.length >= 3) return false;
    if (!_favorites.add(listId)) _favorites.remove(listId);
    await _persist();
    notifyListeners();
    return true;
  }

  List<String> _read(String? encoded) {
    try {
      return List<String>.from(jsonDecode(encoded ?? '[]'));
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persist() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_favoritesKey, jsonEncode(_favorites.toList()));
    await preferences.setString(_recentsKey, jsonEncode(_recents));
  }
}
