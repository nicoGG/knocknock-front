import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:nocknock/core/config/app_config.dart';
import 'package:nocknock/core/telemetry/app_telemetry.dart';
import 'package:nocknock/core/telemetry/telemetry_dio.dart';
import 'package:nocknock/features/auth/data/account_recovery_authorization.dart';
import 'package:nocknock/features/auth/data/auth_repository.dart';
import 'package:nocknock/features/auth/domain/app_user.dart';

class FirebaseAuthRepository
    implements AuthRepository, AccountRecoveryAuthorizationProvider {
  FirebaseAuthRepository({
    FirebaseAuth? firebaseAuth,
    Dio? dio,
    AppTelemetry? telemetry,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _telemetry = telemetry,
       _dio =
           dio ??
           createTelemetryDio(
             BaseOptions(baseUrl: AppConfig.apiBaseUrl),
             telemetry: telemetry,
           );

  final FirebaseAuth _firebaseAuth;
  final Dio _dio;
  final AppTelemetry? _telemetry;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  GoogleSignInAccount? _googleAccount;
  String? _googleDriveAccessToken;
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
        final provider = GoogleAuthProvider()
          ..addScope(googleDriveAppDataScope);
        final credential = await _firebaseAuth.signInWithPopup(provider);
        _googleDriveAccessToken = credential.credential?.accessToken;
        if (_googleDriveAccessToken?.isNotEmpty != true) {
          await _firebaseAuth.signOut();
          throw const AuthFailure(
            'Google no autorizó la recuperación de tus notas.',
          );
        }
        await _telemetry?.logLogin('google');
        return;
      }

      await initialize();
      if (!_googleSignIn.supportsAuthenticate()) {
        throw const AuthFailure(
          'Google no está disponible en este dispositivo.',
        );
      }
      final googleUser = await _googleSignIn.authenticate(
        scopeHint: const [googleDriveAppDataScope],
      );
      await googleUser.authorizationClient.authorizeScopes(const [
        googleDriveAppDataScope,
      ]);
      _googleAccount = googleUser;
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
      await _telemetry?.logLogin('google');
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
  Future<Map<String, String>?> accountRecoveryAuthorizationHeaders() async {
    if (kIsWeb) {
      final accessToken = _googleDriveAccessToken;
      return accessToken?.isNotEmpty == true
          ? {'Authorization': 'Bearer $accessToken'}
          : null;
    }
    await initialize();
    final client =
        _googleAccount?.authorizationClient ??
        _googleSignIn.authorizationClient;
    return client.authorizationHeaders(const [googleDriveAppDataScope]);
  }

  @override
  Future<void> signOut() async {
    await _beforeSignOut?.call();
    await _telemetry?.logEvent('logout');
    await _firebaseAuth.signOut();
    if (!kIsWeb && _isInitialized) await _googleSignIn.signOut();
    _googleAccount = null;
    _googleDriveAccessToken = null;
  }

  @override
  Future<void> deleteAccount() async {
    final token = await getIdToken(forceRefresh: true);
    if (token == null) {
      throw const AuthFailure(
        'Inicia sesión nuevamente para eliminar tu cuenta.',
      );
    }
    try {
      await _beforeSignOut?.call();
      await _dio.delete<void>(
        '/account',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      await _firebaseAuth.signOut();
      if (!kIsWeb && _isInitialized) await _googleSignIn.signOut();
      _googleAccount = null;
      _googleDriveAccessToken = null;
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        throw const AuthFailure(
          'Tu sesión venció. Inicia sesión nuevamente para eliminar tu cuenta.',
        );
      }
      throw const AuthFailure(
        'No pudimos eliminar tu cuenta. Inténtalo nuevamente.',
      );
    }
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
