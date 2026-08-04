import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notifications/domain/app_notification.dart';

void main() {
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
}
