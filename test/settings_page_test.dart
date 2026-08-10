import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/core/theme/app_theme.dart';
import 'package:nocknock/features/auth/data/auth_repository.dart';
import 'package:nocknock/features/auth/domain/app_user.dart';
import 'package:nocknock/features/settings/presentation/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows softly floating icons behind the settings overview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SettingsPage(
          authRepository: const _SettingsAuthRepository(),
          onOpenProfile: () {},
          onClearLocalData: () async => true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 480));

    const iconKeys = [
      'settings-floating-icon-note',
      'settings-floating-icon-checklist',
      'settings-floating-icon-lock',
      'settings-floating-icon-cloud',
      'settings-floating-icon-shield',
    ];
    for (final key in iconKeys) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }

    final floatingNote = find.byKey(
      const ValueKey('settings-floating-icon-note'),
    );
    final initialOffset = tester
        .widget<Transform>(floatingNote)
        .transform
        .getTranslation();

    await tester.pump(const Duration(milliseconds: 620));

    final movedOffset = tester
        .widget<Transform>(floatingNote)
        .transform
        .getTranslation();
    expect((movedOffset.x - initialOffset.x).abs(), greaterThan(0.1));
    expect((movedOffset.y - initialOffset.y).abs(), greaterThan(0.1));
    expect(tester.takeException(), isNull);
  });
}

class _SettingsAuthRepository implements AuthRepository {
  const _SettingsAuthRepository();

  @override
  AppUser get currentUser => const AppUser(
    id: 'settings-user',
    displayName: 'Nico',
    email: 'nico@example.com',
  );

  @override
  Stream<AppUser?> get authStateChanges => const Stream.empty();

  @override
  Future<void> deleteAccount() async {}

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => null;

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut() async {}
}
