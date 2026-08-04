import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nocknock/app/nocknock_app.dart';
import 'package:nocknock/core/config/app_config.dart';
import 'package:nocknock/features/auth/data/firebase_auth_repository.dart';
import 'package:nocknock/features/notes/data/api_notes_repository.dart';
import 'package:nocknock/features/notes/data/auth_aware_notes_repository.dart';
import 'package:nocknock/features/notes/data/local_notes_repository.dart';
import 'package:nocknock/firebase_options.dart';
import 'package:nocknock/features/notifications/logic/notifications_controller.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await initializeDateFormatting('es');
  final authRepository = FirebaseAuthRepository();
  await authRepository.initialize();
  final notificationsController = NotificationsController(
    authRepository: authRepository,
    apiBaseUrl: AppConfig.apiBaseUrl,
  );
  authRepository.setBeforeSignOutHook(
    notificationsController.unregisterCurrentDevice,
  );
  runApp(
    NockNockApp(
      authRepository: authRepository,
      notificationsController: notificationsController,
      repository: AuthAwareNotesRepository(
        authRepository: authRepository,
        localRepository: LocalNotesRepository(),
        remoteRepository: ApiNotesRepository(
          apiBaseUrl: AppConfig.apiBaseUrl,
          socketBaseUrl: AppConfig.socketBaseUrl,
          accessTokenProvider: authRepository.getIdToken,
        ),
      ),
    ),
  );
  await notificationsController.initialize();
}
