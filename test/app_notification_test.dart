import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notifications/domain/app_notification.dart';

void main() {
  test(
    'preserves completion when resolving encrypted content and marking read',
    () {
      final notification = AppNotification.fromJson({
        'id': 'completed',
        'type': 'reminder',
        'data': <String, String>{},
        'createdAt': '2026-11-04T12:00:00Z',
        'completedAt': '2026-11-05T12:00:00Z',
      });
      final resolved = notification
          .copyWith(title: 'Decrypted')
          .markRead(DateTime.now());
      expect(resolved.isCompleted, isTrue);
      expect(resolved.completedAt, DateTime.utc(2026, 11, 5, 12));
    },
  );

  test('maps backend notification types and deep-link data', () {
    final notification = AppNotification.fromJson({
      'id': 'notification-1',
      'type': 'collaborator_joined',
      'title': 'Alguien se unió',
      'body': 'Ana se unió a Casa.',
      'data': {'boardId': 'shared'},
      'readAt': null,
      'createdAt': '2026-08-04T15:00:00.000Z',
    });

    expect(notification.type, AppNotificationType.collaboratorJoined);
    expect(notification.data['boardId'], 'shared');
    expect(notification.isRead, isFalse);
  });

  test('maps task assignment notifications explicitly', () {
    final notification = AppNotification.fromJson({
      'id': 'notification-2',
      'type': 'task_assigned',
      'title': 'Te asignaron una tarea',
      'body': 'Comprar pan',
      'data': {'boardId': 'shared', 'noteId': 'note-1'},
      'readAt': null,
      'createdAt': '2026-08-10T15:00:00.000Z',
    });

    expect(notification.type, AppNotificationType.taskAssigned);
  });
}
