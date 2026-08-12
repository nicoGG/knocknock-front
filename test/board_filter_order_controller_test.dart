import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/presentation/board_filter_order_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists independent assignee and category orders', () async {
    final preferences = await SharedPreferences.getInstance();
    final controller = BoardFilterOrderController(
      preferencesLoader: () async => preferences,
    );
    addTearDown(controller.dispose);
    await controller.load();

    const assignees = ['ana', 'nico', 'pedro'];
    const categories = [
      NoteCategory.general,
      NoteCategory.shopping,
      NoteCategory.travel,
    ];
    await controller.moveAssignee(
      draggedId: 'pedro',
      targetId: 'ana',
      availableIds: assignees,
    );
    await controller.moveCategory(
      draggedCategory: NoteCategory.travel,
      targetCategory: NoteCategory.general,
      availableCategories: categories,
    );

    expect(controller.orderAssignees(assignees), ['pedro', 'ana', 'nico']);
    expect(controller.orderCategories(categories), [
      NoteCategory.travel,
      NoteCategory.general,
      NoteCategory.shopping,
    ]);

    final restored = BoardFilterOrderController(
      preferencesLoader: () async => preferences,
    );
    addTearDown(restored.dispose);
    await restored.load();

    expect(restored.orderAssignees(assignees), ['pedro', 'ana', 'nico']);
    expect(restored.orderCategories(categories), [
      NoteCategory.travel,
      NoteCategory.general,
      NoteCategory.shopping,
    ]);
  });

  test(
    'keeps unavailable values without disturbing visible filter order',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final controller = BoardFilterOrderController(
        preferencesLoader: () async => preferences,
      );
      addTearDown(controller.dispose);
      await controller.load();

      await controller.moveAssignee(
        draggedId: 'pedro',
        targetId: 'ana',
        availableIds: const ['ana', 'pedro'],
      );
      expect(controller.orderAssignees(const ['ana', 'nico', 'pedro']), [
        'pedro',
        'ana',
        'nico',
      ]);
    },
  );
}
