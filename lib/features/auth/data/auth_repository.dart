import 'package:nocknock/features/auth/domain/app_user.dart';

class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;
}

abstract interface class AuthRepository {
  AppUser? get currentUser;

  Stream<AppUser?> get authStateChanges;

  Future<void> signInWithGoogle();

  Future<String?> getIdToken({bool forceRefresh = false});

  Future<void> signOut();
}
