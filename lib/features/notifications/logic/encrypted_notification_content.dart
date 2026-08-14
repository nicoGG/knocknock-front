import 'dart:convert';
import 'dart:ui';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nocknock/features/notes/data/e2ee_crypto.dart';
import 'package:nocknock/core/theme/app_theme.dart';
import 'package:nocknock/core/theme/app_theme_controller.dart';
import 'package:nocknock/features/notifications/logic/reminder_notification_action.dart';
import 'package:shared_preferences/shared_preferences.dart';

const nockNockNotificationPreviewsEnabledKey =
    'nocknock.notification_previews_enabled.v1';

const nockNockNotificationChannel = AndroidNotificationChannel(
  'nocknock_notifications',
  'Notificaciones de NockNock',
  description: 'Cambios en listas compartidas y recordatorios.',
  importance: Importance.high,
);

final nockNockNotificationInitializationSettings = InitializationSettings(
  android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
  iOS: DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
    notificationCategories: [
      DarwinNotificationCategory(
        recurringReminderNotificationCategoryId,
        actions: [
          DarwinNotificationAction.plain(
            completeRecurringReminderActionId,
            'Listo por hoy',
            options: const {DarwinNotificationActionOption.foreground},
          ),
        ],
      ),
    ],
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
    final assignedByName = _nonEmpty(data['assignedByName']);
    final fallback = ResolvedNotificationContent(
      title: _nonEmpty(data['displayTitle']) ?? 'NockNock',
      body: assignedByName == null
          ? _nonEmpty(data['displayBody']) ?? 'Abre NockNock para ver la nota.'
          : '$assignedByName te asignó una tarea.',
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
        body: assignedByName == null
            ? preview.trim()
            : '$assignedByName te asignó “${preview.trim()}”.',
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
  final previewsEnabled = await _notificationPreviewsEnabled();
  final content = await resolveRemoteNotificationContent(
    data: message.data,
    userId: userId,
    previewsEnabled: previewsEnabled,
    resolver: resolver,
  );
  final visualTheme = await resolveNotificationVisualTheme();
  await localNotifications.show(
    id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
    title: content.title,
    body: content.body,
    notificationDetails: buildRemoteNotificationDetails(
      data: message.data,
      content: content,
      visualTheme: visualTheme,
    ),
    payload: jsonEncode(message.data),
  );
}

class NotificationVisualTheme {
  const NotificationVisualTheme({required this.surface, required this.accent});

  final Color surface;
  final Color accent;
}

Future<NotificationVisualTheme> resolveNotificationVisualTheme() async {
  var colorTheme = AppColorTheme.sunset;
  var storedThemeMode = 'system';
  try {
    final preferences = await SharedPreferences.getInstance();
    storedThemeMode =
        preferences.getString(AppThemeController.themeModeStorageKey) ??
        'system';
    final storedColorTheme = preferences.getString(
      AppThemeController.colorThemeStorageKey,
    );
    colorTheme =
        AppColorTheme.values
            .where((theme) => theme.name == storedColorTheme)
            .firstOrNull ??
        AppColorTheme.sunset;
  } on Object {
    // The default theme remains a safe fallback in a background isolate.
  }
  final systemIsDark =
      PlatformDispatcher.instance.platformBrightness == Brightness.dark;
  final isDark = switch (storedThemeMode) {
    'dark' => true,
    'light' => false,
    _ => systemIsDark,
  };
  return NotificationVisualTheme(
    surface: isDark ? AppTheme.darkCanvas : AppTheme.canvas,
    accent: colorTheme.seedColor,
  );
}

NotificationDetails buildRemoteNotificationDetails({
  required Map<String, dynamic> data,
  required ResolvedNotificationContent content,
  required NotificationVisualTheme visualTheme,
}) {
  final isRecurring =
      data['recurringReminder']?.toString() == 'true' &&
      data['occurrenceAt']?.toString().trim().isNotEmpty == true &&
      data['noteId']?.toString().trim().isNotEmpty == true;
  if (!isRecurring) {
    return const NotificationDetails(
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
    );
  }
  return NotificationDetails(
    android: AndroidNotificationDetails(
      'nocknock_notifications',
      'Notificaciones de NockNock',
      channelDescription: 'Cambios en listas compartidas y recordatorios.',
      icon: 'ic_stat_recurring_reminder',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.private,
      ticker: 'Recordatorio recurrente',
      subText: 'NockNock · Recurrente',
      color: visualTheme.surface,
      colorized: true,
      styleInformation: BigTextStyleInformation(
        content.body,
        contentTitle: content.title,
        summaryText: 'NockNock · Recurrente',
      ),
      actions: [
        AndroidNotificationAction(
          completeRecurringReminderActionId,
          'LISTO POR HOY',
          titleColor: visualTheme.accent,
          cancelNotification: false,
          semanticAction: SemanticAction.markAsRead,
        ),
      ],
    ),
    iOS: const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      categoryIdentifier: recurringReminderNotificationCategoryId,
    ),
  );
}

Future<ResolvedNotificationContent> resolveRemoteNotificationContent({
  required Map<String, dynamic> data,
  required String? userId,
  required bool previewsEnabled,
  EncryptedNotificationContentResolver? resolver,
}) {
  if (!previewsEnabled) {
    return Future.value(
      const ResolvedNotificationContent(
        title: 'NockNock',
        body: 'Tienes una nueva notificación.',
      ),
    );
  }
  return (resolver ?? EncryptedNotificationContentResolver()).resolve(
    data,
    userId: userId,
  );
}

Future<bool> _notificationPreviewsEnabled() async {
  try {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(nockNockNotificationPreviewsEnabledKey) ?? true;
  } catch (_) {
    return true;
  }
}
