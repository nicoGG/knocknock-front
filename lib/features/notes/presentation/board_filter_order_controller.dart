import 'package:flutter/foundation.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef BoardFilterOrderPreferencesLoader =
    Future<SharedPreferences> Function();

class BoardFilterOrderController extends ChangeNotifier {
  BoardFilterOrderController({
    BoardFilterOrderPreferencesLoader? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _assigneeOrderStorageKey =
      'nocknock.board_filter_order.assignees.v1';
  static const _categoryOrderStorageKey =
      'nocknock.board_filter_order.categories.v1';

  final BoardFilterOrderPreferencesLoader _preferencesLoader;
  List<String> _assigneeOrder = const [];
  List<NoteCategory> _categoryOrder = const [];

  Future<void> load() async {
    try {
      final preferences = await _preferencesLoader();
      _assigneeOrder = _uniqueNonEmpty(
        preferences.getStringList(_assigneeOrderStorageKey) ?? const [],
      );
      final categoriesByName = {
        for (final category in NoteCategory.values) category.name: category,
      };
      _categoryOrder = _uniqueNonEmpty(
        preferences.getStringList(_categoryOrderStorageKey) ?? const [],
      ).map(categoriesByName.newValue).nonNulls.toList(growable: false);
      notifyListeners();
    } catch (_) {
      // Keep the default order if local preferences are unavailable.
    }
  }

  List<String> orderAssignees(Iterable<String> availableIds) =>
      _orderAvailable(availableIds, _assigneeOrder);

  List<NoteCategory> orderCategories(
    Iterable<NoteCategory> availableCategories,
  ) => _orderAvailable(availableCategories, _categoryOrder);

  Future<void> moveAssignee({
    required String draggedId,
    required String targetId,
    required Iterable<String> availableIds,
  }) async {
    final reordered = _moveToTarget(
      orderAssignees(availableIds),
      draggedId,
      targetId,
    );
    if (reordered == null) return;
    _assigneeOrder = _mergeVisibleOrder(_assigneeOrder, reordered);
    notifyListeners();
    await _persistAssigneeOrder();
  }

  Future<void> moveCategory({
    required NoteCategory draggedCategory,
    required NoteCategory targetCategory,
    required Iterable<NoteCategory> availableCategories,
  }) async {
    final reordered = _moveToTarget(
      orderCategories(availableCategories),
      draggedCategory,
      targetCategory,
    );
    if (reordered == null) return;
    _categoryOrder = _mergeVisibleOrder(_categoryOrder, reordered);
    notifyListeners();
    await _persistCategoryOrder();
  }

  Future<void> _persistAssigneeOrder() async {
    try {
      final preferences = await _preferencesLoader();
      await preferences.setStringList(_assigneeOrderStorageKey, _assigneeOrder);
    } catch (_) {
      // Keep the chosen order for this session if it cannot be persisted.
    }
  }

  Future<void> _persistCategoryOrder() async {
    try {
      final preferences = await _preferencesLoader();
      await preferences.setStringList(
        _categoryOrderStorageKey,
        _categoryOrder.map((category) => category.name).toList(),
      );
    } catch (_) {
      // Keep the chosen order for this session if it cannot be persisted.
    }
  }
}

extension on Map<String, NoteCategory> {
  NoteCategory? newValue(String key) => this[key];
}

List<String> _uniqueNonEmpty(Iterable<String> values) {
  final seen = <String>{};
  return [
    for (final value in values)
      if (value.trim().isNotEmpty && seen.add(value.trim())) value.trim(),
  ];
}

List<T> _orderAvailable<T>(
  Iterable<T> availableValues,
  Iterable<T> preferredOrder,
) {
  final available = availableValues.toList(growable: false);
  final remaining = available.toSet();
  return [
    for (final value in preferredOrder)
      if (remaining.remove(value)) value,
    for (final value in available)
      if (remaining.remove(value)) value,
  ];
}

List<T>? _moveToTarget<T>(List<T> values, T dragged, T target) {
  final draggedIndex = values.indexOf(dragged);
  final targetIndex = values.indexOf(target);
  if (draggedIndex < 0 || targetIndex < 0 || draggedIndex == targetIndex) {
    return null;
  }
  final reordered = List<T>.of(values)..removeAt(draggedIndex);
  reordered.insert(targetIndex.clamp(0, reordered.length), dragged);
  return reordered;
}

List<T> _mergeVisibleOrder<T>(
  Iterable<T> previousOrder,
  Iterable<T> visibleOrder,
) {
  final visible = visibleOrder.toList(growable: false);
  final visibleSet = visible.toSet();
  return [
    ...visible,
    for (final value in previousOrder)
      if (!visibleSet.contains(value)) value,
  ];
}
