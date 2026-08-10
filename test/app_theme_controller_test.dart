import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/core/theme/app_theme.dart';
import 'package:nocknock/core/theme/app_theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists the selected mode and color theme between sessions', () async {
    final controller = AppThemeController();
    await controller.load();
    expect(controller.themeMode, ThemeMode.system);
    expect(controller.colorTheme, AppColorTheme.sunset);

    await controller.setThemeMode(ThemeMode.dark);
    await controller.setColorTheme(AppColorTheme.graphite);
    expect(controller.themeMode, ThemeMode.dark);
    expect(controller.colorTheme, AppColorTheme.graphite);
    controller.dispose();

    final reopenedController = AppThemeController();
    await reopenedController.load();
    expect(reopenedController.themeMode, ThemeMode.dark);
    expect(reopenedController.colorTheme, AppColorTheme.graphite);
    reopenedController.dispose();
  });
}
