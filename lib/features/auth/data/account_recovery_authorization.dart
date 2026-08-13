const googleDriveAppDataScope = 'https://www.googleapis.com/auth/drive.appdata';

/// Supplies short-lived Google authorization headers without exposing or
/// persisting the token in the notes layer.
abstract interface class AccountRecoveryAuthorizationProvider {
  Future<Map<String, String>?> accountRecoveryAuthorizationHeaders();
}
