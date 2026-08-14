import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notifications/logic/encrypted_notification_content.dart';
import 'package:nocknock/features/notifications/logic/reminder_notification_action.dart';

void main() {
  const recurringData = {
    'recurringReminder': 'true',
    'noteId': 'note-1',
    'occurrenceAt': '2026-08-14T12:00:00.000Z',
    'notificationId': 'notification-1',
  };

  test('builds a themed recurring notification with a per-day action', () {
    final details = buildRemoteNotificationDetails(
      data: recurringData,
      content: const ResolvedNotificationContent(
        title: 'Recordatorio recurrente',
        body: 'Inyección Wegovy',
      ),
      visualTheme: const NotificationVisualTheme(
        surface: Color(0xFF171714),
        accent: Color(0xFF2F8A62),
      ),
    );

    final android = details.android!;
    expect(android.icon, 'ic_stat_recurring_reminder');
    expect(android.colorized, isTrue);
    expect(android.color, const Color(0xFF171714));
    expect(android.subText, 'NockNock · Recurrente');
    expect(android.actions, hasLength(1));
    expect(android.actions!.single.id, completeRecurringReminderActionId);
    expect(android.actions!.single.title, 'LISTO POR HOY');
    expect(android.actions!.single.cancelNotification, isFalse);
    expect(android.actions!.single.semanticAction, SemanticAction.markAsRead);
    expect(
      details.iOS!.categoryIdentifier,
      recurringReminderNotificationCategoryId,
    );
  });

  test('keeps ordinary notifications free of recurrence actions', () {
    final details = buildRemoteNotificationDetails(
      data: const {'type': 'reminder', 'noteId': 'note-1'},
      content: const ResolvedNotificationContent(
        title: 'Recordatorio de NockNock',
        body: 'Comprar pan',
      ),
      visualTheme: const NotificationVisualTheme(
        surface: Color(0xFFF7F3EA),
        accent: Color(0xFFEC5B3F),
      ),
    );

    expect(details.android!.actions, isNull);
    expect(details.android!.icon, isNull);
    expect(details.android!.colorized, isFalse);
    expect(details.android!.color, isNull);
  });

  test('completes the occurrence and marks its notification as read', () async {
    final requests = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.resolve(
            Response<void>(requestOptions: options, statusCode: 200),
          );
        },
      ),
    );

    final completed = await completeRecurringReminderOccurrence(
      recurringData,
      accessTokenProvider: () async => 'firebase-token',
      dio: dio,
    );

    expect(completed, isTrue);
    expect(requests, hasLength(2));
    expect(requests.first.path, '/notes/note-1/reminder-occurrences/complete');
    expect(requests.first.data, {'occurrenceAt': '2026-08-14T12:00:00.000Z'});
    expect(requests.first.headers['Authorization'], 'Bearer firebase-token');
    expect(requests.last.path, '/notifications/notification-1/read');
  });

  test('rejects payloads that are not an identified recurrence', () async {
    expect(
      await completeRecurringReminderOccurrence(const {
        'noteId': 'note-1',
      }, accessTokenProvider: () async => 'firebase-token'),
      isFalse,
    );
  });
}
