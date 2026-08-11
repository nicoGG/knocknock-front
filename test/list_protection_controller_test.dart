import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/data/list_protection_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('persists protection and locks access between sessions', () async {
    final preferences = await SharedPreferences.getInstance();
    final authenticator = _FakeBiometricAuthenticator();
    final controller = ListProtectionController(
      preferences: preferences,
      authenticator: authenticator,
    );

    final enabled = await controller.setProtection(
      'private-list',
      enabled: true,
      listName: 'Privadas',
    );

    expect(enabled, ListProtectionResult.success);
    expect(controller.isProtected('private-list'), isTrue);
    expect(controller.canAccess('private-list'), isTrue);
    expect(authenticator.authenticationCount, 1);

    controller.lockAll();
    expect(controller.canAccess('private-list'), isFalse);

    final restored = ListProtectionController(
      preferences: preferences,
      authenticator: authenticator,
    );
    expect(restored.isProtected('private-list'), isTrue);
    expect(restored.canAccess('private-list'), isFalse);

    final unlocked = await restored.unlock(
      'private-list',
      listName: 'Privadas',
    );
    expect(unlocked, ListProtectionResult.success);
    expect(restored.canAccess('private-list'), isTrue);
    expect(authenticator.authenticationCount, 2);
  });

  test('does not change protection when biometric auth is canceled', () async {
    final preferences = await SharedPreferences.getInstance();
    final authenticator = _FakeBiometricAuthenticator(
      results: [ListProtectionResult.canceled],
    );
    final controller = ListProtectionController(
      preferences: preferences,
      authenticator: authenticator,
    );

    final result = await controller.setProtection(
      'private-list',
      enabled: true,
    );

    expect(result, ListProtectionResult.canceled);
    expect(controller.isProtected('private-list'), isFalse);
    expect(preferences.getStringList('protected_note_list_ids_v1'), isNull);
  });
}

class _FakeBiometricAuthenticator implements ListBiometricAuthenticator {
  _FakeBiometricAuthenticator({
    List<ListProtectionResult> results = const [ListProtectionResult.success],
  }) : _results = List.of(results);

  final List<ListProtectionResult> _results;
  int authenticationCount = 0;

  @override
  Future<ListProtectionResult> authenticate({required String reason}) async {
    authenticationCount += 1;
    if (_results.isEmpty) return ListProtectionResult.success;
    return _results.removeAt(0);
  }
}
