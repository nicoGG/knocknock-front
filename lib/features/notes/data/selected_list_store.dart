import 'package:shared_preferences/shared_preferences.dart';

abstract interface class SelectedListStore {
  Future<String?> read();

  Future<void> write(String listId);
}

class SharedPreferencesSelectedListStore implements SelectedListStore {
  SharedPreferencesSelectedListStore({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const storageKey = 'nocknock.selected_list_id.v1';

  final Future<SharedPreferences> Function() _preferencesLoader;

  @override
  Future<String?> read() async {
    final value = (await _preferencesLoader()).getString(storageKey)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<void> write(String listId) async {
    await (await _preferencesLoader()).setString(storageKey, listId);
  }
}
