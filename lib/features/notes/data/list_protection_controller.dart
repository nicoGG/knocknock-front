import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ListProtectionResult { success, canceled, unavailable, failed }

abstract interface class ListBiometricAuthenticator {
  Future<ListProtectionResult> authenticate({required String reason});
}

class DeviceListBiometricAuthenticator implements ListBiometricAuthenticator {
  DeviceListBiometricAuthenticator({LocalAuthentication? localAuthentication})
    : _localAuthentication = localAuthentication ?? LocalAuthentication();

  final LocalAuthentication _localAuthentication;

  @override
  Future<ListProtectionResult> authenticate({required String reason}) async {
    try {
      final canCheckBiometrics = await _localAuthentication.canCheckBiometrics;
      if (!canCheckBiometrics) return ListProtectionResult.unavailable;

      final enrolled = await _localAuthentication.getAvailableBiometrics();
      if (enrolled.isEmpty) return ListProtectionResult.unavailable;

      final authenticated = await _localAuthentication.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      return authenticated
          ? ListProtectionResult.success
          : ListProtectionResult.canceled;
    } on LocalAuthException catch (error) {
      return switch (error.code) {
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noCredentialsSet =>
          ListProtectionResult.unavailable,
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.userRequestedFallback =>
          ListProtectionResult.canceled,
        _ => ListProtectionResult.failed,
      };
    } catch (_) {
      return ListProtectionResult.failed;
    }
  }
}

class ListProtectionController extends ChangeNotifier {
  ListProtectionController({
    SharedPreferences? preferences,
    ListBiometricAuthenticator? authenticator,
  }) : _preferences = preferences,
       _authenticator = authenticator ?? DeviceListBiometricAuthenticator(),
       _protectedListIds =
           preferences
               ?.getStringList(_protectedListIdsKey)
               ?.where((id) => id.trim().isNotEmpty)
               .toSet() ??
           <String>{};

  static const _protectedListIdsKey = 'protected_note_list_ids_v1';

  final SharedPreferences? _preferences;
  final ListBiometricAuthenticator _authenticator;
  Set<String> _protectedListIds;
  final Set<String> _unlockedListIds = {};

  String? _activeListId;
  String? _activeListName;
  bool _isAuthenticating = false;
  bool _privacyShieldRequired = false;
  ListProtectionResult? _lastResult;

  bool get isAuthenticating => _isAuthenticating;
  bool get privacyShieldRequired => _privacyShieldRequired;
  bool get isActiveListLocked =>
      _activeListId != null && !canAccess(_activeListId!);
  String? get activeListName => _activeListName;
  ListProtectionResult? get lastResult => _lastResult;

  bool isProtected(String listId) => _protectedListIds.contains(listId);

  bool canAccess(String listId) =>
      !isProtected(listId) || _unlockedListIds.contains(listId);

  void setActiveList(String? listId, {String? name}) {
    if (_activeListId == listId && _activeListName == name) return;
    _activeListId = listId;
    _activeListName = name;
    if (listId == null) _privacyShieldRequired = false;
    _lastResult = null;
    notifyListeners();
  }

  Future<ListProtectionResult> unlock(String listId, {String? listName}) async {
    if (canAccess(listId)) return ListProtectionResult.success;
    return _authenticate(
      reason: listName == null || listName.trim().isEmpty
          ? 'Autentícate para abrir esta lista protegida.'
          : 'Autentícate para abrir la lista ${listName.trim()}.',
      onSuccess: () {
        _unlockedListIds.add(listId);
        _privacyShieldRequired = false;
      },
    );
  }

  Future<ListProtectionResult> unlockActiveList() async {
    final listId = _activeListId;
    if (listId == null) return ListProtectionResult.success;
    return unlock(listId, listName: _activeListName);
  }

  Future<ListProtectionResult> setProtection(
    String listId, {
    required bool enabled,
    String? listName,
  }) async {
    if (_preferences == null) return ListProtectionResult.unavailable;
    if (isProtected(listId) == enabled) return ListProtectionResult.success;

    final action = enabled ? 'proteger' : 'quitar la protección de';
    final result = await _authenticate(
      reason: listName == null || listName.trim().isEmpty
          ? 'Autentícate para $action esta lista.'
          : 'Autentícate para $action la lista ${listName.trim()}.',
      onSuccess: () {},
    );
    if (result != ListProtectionResult.success) return result;

    final updated = Set<String>.of(_protectedListIds);
    if (enabled) {
      updated.add(listId);
    } else {
      updated.remove(listId);
    }
    final sortedIds = updated.toList()..sort();
    final didPersist = await _preferences.setStringList(
      _protectedListIdsKey,
      sortedIds,
    );
    if (!didPersist) {
      _lastResult = ListProtectionResult.failed;
      notifyListeners();
      return ListProtectionResult.failed;
    }

    _protectedListIds = updated;
    if (enabled) {
      _unlockedListIds.add(listId);
      _privacyShieldRequired = false;
    } else {
      _unlockedListIds.remove(listId);
    }
    _lastResult = ListProtectionResult.success;
    notifyListeners();
    return ListProtectionResult.success;
  }

  void lock(String listId) {
    if (!_unlockedListIds.remove(listId)) return;
    _lastResult = null;
    notifyListeners();
  }

  void lockAll({bool protectEntireApp = false}) {
    final shouldRequirePrivacyShield =
        protectEntireApp &&
        _activeListId != null &&
        isProtected(_activeListId!);
    if (_unlockedListIds.isEmpty &&
        _lastResult == null &&
        _privacyShieldRequired == shouldRequirePrivacyShield) {
      return;
    }
    _unlockedListIds.clear();
    _privacyShieldRequired = shouldRequirePrivacyShield;
    _lastResult = null;
    notifyListeners();
  }

  Future<void> forgetList(String listId) async {
    final wasProtected = _protectedListIds.remove(listId);
    final wasUnlocked = _unlockedListIds.remove(listId);
    if (_activeListId == listId) {
      _activeListId = null;
      _activeListName = null;
      _privacyShieldRequired = false;
    }
    if (wasProtected && _preferences != null) {
      final sortedIds = _protectedListIds.toList()..sort();
      await _preferences.setStringList(_protectedListIdsKey, sortedIds);
    }
    if (wasProtected || wasUnlocked) notifyListeners();
  }

  Future<ListProtectionResult> _authenticate({
    required String reason,
    required VoidCallback onSuccess,
  }) async {
    if (_isAuthenticating) return ListProtectionResult.canceled;
    _isAuthenticating = true;
    _lastResult = null;
    notifyListeners();

    final result = await _authenticator.authenticate(reason: reason);
    if (result == ListProtectionResult.success) onSuccess();
    _isAuthenticating = false;
    _lastResult = result;
    notifyListeners();
    return result;
  }
}
