import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/presentation/board_view_mode_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists view, status filter and completed section per list', () async {
    final controller = BoardViewModeController();
    await controller.load();
    expect(controller.viewModeFor('home'), BoardViewMode.grid);
    expect(controller.filterFor('home'), NoteFilter.all);
    expect(controller.completedSectionExpandedFor('home'), isTrue);
    expect(controller.viewModeFor('work'), BoardViewMode.grid);
    expect(controller.filterFor('work'), NoteFilter.all);

    await controller.setViewMode('home', BoardViewMode.list);
    await controller.setFilter('home', NoteFilter.pending);
    await controller.setFilter('work', NoteFilter.completed);
    await controller.setCompletedSectionExpanded('home', false);
    expect(controller.viewModeFor('home'), BoardViewMode.list);
    expect(controller.filterFor('home'), NoteFilter.pending);
    expect(controller.completedSectionExpandedFor('home'), isFalse);
    expect(controller.viewModeFor('work'), BoardViewMode.grid);
    expect(controller.filterFor('work'), NoteFilter.completed);
    controller.dispose();

    final reopenedController = BoardViewModeController();
    await reopenedController.load();
    expect(reopenedController.viewModeFor('home'), BoardViewMode.list);
    expect(reopenedController.filterFor('home'), NoteFilter.pending);
    expect(reopenedController.completedSectionExpandedFor('home'), isFalse);
    expect(reopenedController.viewModeFor('work'), BoardViewMode.grid);
    expect(reopenedController.filterFor('work'), NoteFilter.completed);
    reopenedController.dispose();
  });

  test('migrates the removed large view to the compact list', () async {
    SharedPreferences.setMockInitialValues({
      'nocknock.board_view_mode.v1': 'largeList',
    });

    final controller = BoardViewModeController();
    await controller.load();

    expect(controller.viewModeFor('home'), BoardViewMode.list);
    expect(controller.filterFor('home'), NoteFilter.all);
    expect(controller.viewModeFor('another-list'), BoardViewMode.list);
    controller.dispose();
  });

  test('forgets preferences that belonged to a deleted list', () async {
    final controller = BoardViewModeController();
    await controller.load();
    await controller.setViewMode('deleted-list', BoardViewMode.list);
    await controller.setFilter('deleted-list', NoteFilter.completed);

    await controller.forgetList('deleted-list');

    expect(controller.viewModeFor('deleted-list'), BoardViewMode.grid);
    expect(controller.filterFor('deleted-list'), NoteFilter.all);
    controller.dispose();
  });
}
