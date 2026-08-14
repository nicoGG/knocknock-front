import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nocknock/core/config/app_config.dart';
import 'package:nocknock/firebase_options.dart';

const completeRecurringReminderActionId =
    'nocknock.complete_recurring_reminder_occurrence';
const recurringReminderNotificationCategoryId = 'nocknock.recurring_reminder';

@pragma('vm:entry-point')
Future<void> nockNockNotificationResponseBackground(
  NotificationResponse response,
) async {
  await handleRecurringReminderNotificationAction(response);
}

Future<bool> handleRecurringReminderNotificationAction(
  NotificationResponse response, {
  Future<String?> Function()? accessTokenProvider,
  Dio? dio,
  FlutterLocalNotificationsPlugin? localNotifications,
}) async {
  if (response.actionId != completeRecurringReminderActionId) return false;
  final data = _decodePayload(response.payload);
  if (data == null) return false;

  final completed = await completeRecurringReminderOccurrence(
    data,
    accessTokenProvider: accessTokenProvider,
    dio: dio,
  );
  if (!completed) return false;

  final notificationId = response.id;
  if (notificationId != null) {
    try {
      await (localNotifications ?? FlutterLocalNotificationsPlugin()).cancel(
        id: notificationId,
      );
    } on Object {
      // The occurrence is already complete; dismissal is only visual cleanup.
    }
  }
  return true;
}

Future<bool> completeRecurringReminderOccurrence(
  Map<String, dynamic> data, {
  Future<String?> Function()? accessTokenProvider,
  Dio? dio,
}) async {
  final noteId = _nonEmpty(data['noteId']);
  final occurrenceAt = _nonEmpty(data['occurrenceAt']);
  if (data['recurringReminder']?.toString() != 'true' ||
      noteId == null ||
      occurrenceAt == null) {
    return false;
  }

  try {
    final token = await (accessTokenProvider ?? _firebaseIdToken)();
    if (token == null || token.isEmpty) return false;
    final client =
        dio ??
        Dio(
          BaseOptions(
            baseUrl: AppConfig.apiBaseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
          ),
        );
    final options = Options(headers: {'Authorization': 'Bearer $token'});
    await client.patch<void>(
      '/notes/${Uri.encodeComponent(noteId)}/reminder-occurrences/complete',
      data: {'occurrenceAt': occurrenceAt},
      options: options,
    );

    final notificationId = _nonEmpty(data['notificationId']);
    if (notificationId != null) {
      try {
        await client.patch<void>(
          '/notifications/${Uri.encodeComponent(notificationId)}/read',
          options: options,
        );
      } on Object {
        // Completing the occurrence is authoritative; read state is secondary.
      }
    }
    return true;
  } on Object catch (error) {
    debugPrint('No se pudo completar el recordatorio recurrente: $error');
    return false;
  }
}

Future<String?> _firebaseIdToken() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  return FirebaseAuth.instance.currentUser?.getIdToken();
}

Map<String, dynamic>? _decodePayload(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  try {
    final decoded = jsonDecode(payload);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } on Object {
    return null;
  }
}

String? _nonEmpty(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
