import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nocknock/features/auth/data/auth_repository.dart';
import 'package:nocknock/features/auth/domain/app_user.dart';
import 'package:nocknock/features/notifications/logic/notifications_controller.dart';
import 'package:nocknock/features/notifications/presentation/notifications_page.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es');
  });

  testWidgets(
    'selects multiple notifications and deletes them through the API',
    (tester) async {
      final requests = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:4000/api'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            if (options.method == 'GET' && options.path == '/notifications') {
              handler.resolve(
                Response<List<dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: [
                    _notificationJson('notification-1', 'Primera notificación'),
                    _notificationJson('notification-2', 'Segunda notificación'),
                  ],
                ),
              );
              return;
            }
            if (options.method == 'DELETE' &&
                options.path == '/notifications/batch') {
              handler.resolve(
                Response<void>(requestOptions: options, statusCode: 200),
              );
              return;
            }
            handler.reject(
              DioException(
                requestOptions: options,
                message:
                    'Unexpected request: ${options.method} ${options.path}',
              ),
            );
          },
        ),
      );
      final controller = NotificationsController(
        authRepository: const _SignedInAuthRepository(),
        apiBaseUrl: 'http://localhost:4000/api',
        dio: dio,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(home: NotificationsPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('start-notifications-selection-button')),
      );
      await tester.pump();
      expect(find.text('Seleccionar'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('notification-notification-1')),
      );
      await tester.pump();
      expect(find.text('1 seleccionada'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('notification-notification-2')),
      );
      await tester.pump();
      expect(find.text('2 seleccionadas'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('delete-selected-notifications-button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('¿Eliminar 2 notificaciones?'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('confirm-delete-notifications-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Todo al día'), findsOneWidget);
      expect(find.text('2 notificaciones eliminadas.'), findsOneWidget);
      final deleteRequest = requests.singleWhere(
        (request) =>
            request.method == 'DELETE' &&
            request.path == '/notifications/batch',
      );
      final payload = Map<String, dynamic>.from(deleteRequest.data as Map);
      expect(
        payload['ids'],
        unorderedEquals(['notification-1', 'notification-2']),
      );
      expect(deleteRequest.headers['Authorization'], 'Bearer test-token');
    },
  );
}

Map<String, dynamic> _notificationJson(String id, String title) => {
  'id': id,
  'type': 'reminder',
  'title': title,
  'body': 'Abre NockNock para verla.',
  'data': <String, String>{},
  'readAt': null,
  'createdAt': '2026-08-10T15:00:00.000Z',
};

class _SignedInAuthRepository implements AuthRepository {
  const _SignedInAuthRepository();

  @override
  AppUser get currentUser => const AppUser(
    id: 'user-1',
    displayName: 'Nico',
    email: 'nico@example.com',
  );

  @override
  Stream<AppUser?> get authStateChanges => const Stream.empty();

  @override
  Future<void> deleteAccount() async {}

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => 'test-token';

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut() async {}
}
