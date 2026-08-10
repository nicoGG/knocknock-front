import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nocknock/features/notes/data/e2ee_crypto.dart';

const nockNockNotificationChannel = AndroidNotificationChannel(
  'nocknock_notifications',
  'Notificaciones de NockNock',
  description: 'Cambios en listas compartidas y recordatorios.',
  importance: Importance.high,
);

const nockNockNotificationInitializationSettings = InitializationSettings(
  android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  iOS: DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  ),
);

class ResolvedNotificationContent {
  const ResolvedNotificationContent({required this.title, required this.body});

  final String title;
  final String body;
}

/// Resolves notification previews only on an authenticated device that owns
/// the list key. The encrypted preview remains opaque to the API and FCM.
class EncryptedNotificationContentResolver {
  EncryptedNotificationContentResolver({
    E2eeKeyStore? keyStore,
    E2eeCipher? cipher,
  }) : _keyStore = keyStore ?? E2eeKeyStore(),
       _cipher = cipher ?? E2eeCipher();

  final E2eeKeyStore _keyStore;
  final E2eeCipher _cipher;

  Future<ResolvedNotificationContent> resolve(
    Map<String, dynamic> data, {
    required String? userId,
  }) async {
    final fallback = ResolvedNotificationContent(
      title: _nonEmpty(data['displayTitle']) ?? 'NockNock',
      body: _nonEmpty(data['displayBody']) ?? 'Abre NockNock para ver la nota.',
    );
    final boardId = _nonEmpty(data['boardId']);
    final encryptedPreview = _nonEmpty(data['encryptedPreview']);
    final field = switch (_nonEmpty(data['previewField'])) {
      'noteTitle' => e2eeNoteTitleField,
      'listName' => e2eeListNameField,
      _ => null,
    };
    if (userId == null ||
        userId.isEmpty ||
        boardId == null ||
        encryptedPreview == null ||
        field == null ||
        !E2eeCipher.isCiphertext(encryptedPreview)) {
      return fallback;
    }

    try {
      final key = await _keyStore.readListKey(userId, boardId);
      if (key == null) return fallback;
      final preview = await _cipher.decryptString(
        encryptedPreview,
        key,
        field: field,
      );
      if (preview.trim().isEmpty) return fallback;
      return ResolvedNotificationContent(
        title: fallback.title,
        body: preview.trim(),
      );
    } on Object {
      return fallback;
    }
  }

  String? _nonEmpty(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

Future<void> showEncryptedRemoteNotification({
  required FlutterLocalNotificationsPlugin localNotifications,
  required RemoteMessage message,
  required String? userId,
  EncryptedNotificationContentResolver? resolver,
}) async {
  final content = await (resolver ?? EncryptedNotificationContentResolver())
      .resolve(message.data, userId: userId);
  await localNotifications.show(
    id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
    title: content.title,
    body: content.body,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'nocknock_notifications',
        'Notificaciones de NockNock',
        channelDescription: 'Cambios en listas compartidas y recordatorios.',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
    payload: jsonEncode(message.data),
  );
}
