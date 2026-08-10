import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nocknock/app/nocknock_app.dart';
import 'package:nocknock/core/config/app_config.dart';
import 'package:nocknock/core/telemetry/app_telemetry.dart';
import 'package:nocknock/features/auth/data/firebase_auth_repository.dart';
import 'package:nocknock/features/notes/data/api_notes_repository.dart';
import 'package:nocknock/features/notes/data/auth_aware_notes_repository.dart';
import 'package:nocknock/features/notes/data/cached_notes_repository.dart';
import 'package:nocknock/features/notes/data/e2ee_notes_repository.dart';
import 'package:nocknock/features/notes/data/local_notes_repository.dart';
import 'package:nocknock/firebase_options.dart';
import 'package:nocknock/features/notifications/logic/notifications_controller.dart';
import 'package:nocknock/features/notifications/logic/encrypted_notification_content.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final localNotifications = FlutterLocalNotificationsPlugin();
  await localNotifications.initialize(
    settings: nockNockNotificationInitializationSettings,
  );
  await localNotifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(nockNockNotificationChannel);
  await showEncryptedRemoteNotification(
    localNotifications: localNotifications,
    message: message,
    userId: FirebaseAuth.instance.currentUser?.uid,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final telemetry = AppTelemetry.instance;
  await telemetry.initialize();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await initializeDateFormatting('es');
  final preferences = await SharedPreferences.getInstance();
  final authRepository = FirebaseAuthRepository(telemetry: telemetry);
  await authRepository.initialize();
  await telemetry.bindUserChanges(
    authRepository.authStateChanges.map((user) => user?.id),
    initialUserId: authRepository.currentUser?.id,
  );
  final notificationsController = NotificationsController(
    authRepository: authRepository,
    apiBaseUrl: AppConfig.apiBaseUrl,
    telemetry: telemetry,
  );
  authRepository.setBeforeSignOutHook(
    notificationsController.unregisterCurrentDevice,
  );
  runApp(
    NockNockApp(
      authRepository: authRepository,
      navigatorObservers: telemetry.collectionEnabled
          ? [telemetry.navigatorObserver]
          : const [],
      preferences: preferences,
      notificationsController: notificationsController,
      repository: AuthAwareNotesRepository(
        authRepository: authRepository,
        localRepository: LocalNotesRepository(),
        remoteRepository: E2eeNotesRepository(
          userIdProvider: () => authRepository.currentUser?.id,
          repository: CachedNotesRepository(
            preferences: preferences,
            userIdProvider: () => authRepository.currentUser?.id,
            repository: ApiNotesRepository(
              apiBaseUrl: AppConfig.apiBaseUrl,
              socketBaseUrl: AppConfig.socketBaseUrl,
              accessTokenProvider: authRepository.getIdToken,
              telemetry: telemetry,
            ),
          ),
        ),
      ),
    ),
  );
  await notificationsController.initialize();
}
