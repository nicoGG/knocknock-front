import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/core/telemetry/telemetry_dio.dart';

void main() {
  test('sanitizes resource identifiers from telemetry routes', () {
    expect(
      sanitizeTelemetryRoute(
        '/api/lists/board-123/collaborators/firebase-user-456',
      ),
      '/api/lists/:id/collaborators/:id',
    );
    expect(
      sanitizeTelemetryRoute('/api/notifications/notification-123/read'),
      '/api/notifications/:id/read',
    );
    expect(sanitizeTelemetryRoute('/api/notes/pinned'), '/api/notes/pinned');
  });
}
