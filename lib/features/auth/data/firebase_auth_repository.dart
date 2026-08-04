import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:nocknock/features/auth/data/auth_repository.dart';
import 'package:nocknock/features/auth/domain/app_user.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _isInitialized = false;
  Future<void> Function()? _beforeSignOut;

  void setBeforeSignOutHook(Future<void> Function()? hook) {
    _beforeSignOut = hook;
  }

  Future<void> initialize() async {
    if (kIsWeb || _isInitialized) return;
    await _googleSignIn.initialize();
    _isInitialized = true;
  }

  @override
  AppUser? get currentUser => _mapUser(_firebaseAuth.currentUser);

  @override
  Stream<AppUser?> get authStateChanges =>
      _firebaseAuth.authStateChanges().map(_mapUser);

  @override
  Future<void> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        await _firebaseAuth.signInWithPopup(GoogleAuthProvider());
        return;
      }

      await initialize();
      if (!_googleSignIn.supportsAuthenticate()) {
        throw const AuthFailure(
          'Google no está disponible en este dispositivo.',
        );
      }
      final googleUser = await _googleSignIn.authenticate();
      final authentication = googleUser.authentication;
      final idToken = authentication.idToken;
      if (idToken == null) {
        throw const AuthFailure(
          'Google no pudo confirmar tu identidad. Inténtalo otra vez.',
        );
      }
      await _firebaseAuth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthFailure('Inicio de sesión cancelado.');
      }
      throw const AuthFailure(
        'No pudimos iniciar sesión con Google. Inténtalo nuevamente.',
      );
    } on FirebaseAuthException {
      throw const AuthFailure(
        'No pudimos iniciar sesión con Google. Revisa la configuración de Firebase.',
      );
    }
  }

  @override
  Future<void> signOut() async {
    await _beforeSignOut?.call();
    await _firebaseAuth.signOut();
    if (!kIsWeb && _isInitialized) await _googleSignIn.signOut();
  }

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return null;
    return user.getIdToken(forceRefresh);
  }

  AppUser? _mapUser(User? user) {
    if (user == null) return null;
    return AppUser(
      id: user.uid,
      displayName: user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : 'Usuario de NockNock',
      email: user.email ?? '',
      photoUrl: user.photoURL,
    );
  }
}
