import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/presentation/board_view_mode_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists the selected board view between app sessions', () async {
    final controller = BoardViewModeController();
    await controller.load();
    expect(controller.viewMode, BoardViewMode.grid);

    await controller.setViewMode(BoardViewMode.largeList);
    expect(controller.viewMode, BoardViewMode.largeList);
    controller.dispose();

    final reopenedController = BoardViewModeController();
    await reopenedController.load();
    expect(reopenedController.viewMode, BoardViewMode.largeList);
    reopenedController.dispose();
  });
}
