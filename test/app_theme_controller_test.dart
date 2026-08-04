import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/core/theme/app_theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists the selected theme mode between app sessions', () async {
    final controller = AppThemeController();
    await controller.load();
    expect(controller.themeMode, ThemeMode.system);

    await controller.setThemeMode(ThemeMode.dark);
    expect(controller.themeMode, ThemeMode.dark);
    controller.dispose();

    final reopenedController = AppThemeController();
    await reopenedController.load();
    expect(reopenedController.themeMode, ThemeMode.dark);
    reopenedController.dispose();
  });
}
