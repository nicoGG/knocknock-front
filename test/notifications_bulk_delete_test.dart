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

  testWidgets('completes a reminder and keeps it in history after reload', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var record = _notificationJson('reminder-1', 'Mi recordatorio');
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost:4000/api'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path == '/notifications/reminder-1/complete') {
            record = {
              ...record,
              'completedAt': '2026-11-05T12:00:00Z',
              'readAt': '2026-11-05T12:00:00Z',
            };
            handler.resolve(
              Response(requestOptions: options, data: record, statusCode: 200),
            );
          } else if (options.path == '/notifications/completed-reminders') {
            handler.resolve(
              Response<List<dynamic>>(
                requestOptions: options,
                data: [record],
                statusCode: 200,
              ),
            );
          } else {
            handler.resolve(
              Response<List<dynamic>>(
                requestOptions: options,
                data: record['completedAt'] == null ? [record] : [],
                statusCode: 200,
              ),
            );
          }
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
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: NotificationsPage(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('complete-reminder-reminder-1')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notification-reminder-1')), findsNothing);
    await tester.tap(find.text('Completados'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('notification-reminder-1')),
      findsOneWidget,
    );
    expect(find.textContaining('Completado el'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('complete-reminder-reminder-1')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selects multiple notifications and deletes them through the API',
    (tester) async {
      tester.view.physicalSize = const Size(393, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
                    _notificationJson('notification-3', 'Tercera notificación'),
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
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) =>
                  NotificationsPage(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('notifications-animated-background')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('notifications-overview-card')),
        findsOneWidget,
      );
      expect(find.text('3 notificaciones pendientes'), findsOneWidget);
      final appBarBackground = find.byKey(
        const ValueKey('notifications-appbar-background'),
      );
      expect(
        find.byKey(const ValueKey('notifications-appbar-bottom-fade')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('notifications-content-fade')),
        findsOneWidget,
      );
      final initialAppBarDecoration =
          tester.widget<DecoratedBox>(appBarBackground).decoration
              as BoxDecoration;

      await tester.drag(
        find.byKey(const ValueKey('notifications-list')),
        const Offset(0, -80),
      );
      await tester.pump();

      final scrolledAppBarDecoration =
          tester.widget<DecoratedBox>(appBarBackground).decoration
              as BoxDecoration;
      expect(
        scrolledAppBarDecoration.color!.a,
        greaterThan(initialAppBarDecoration.color!.a),
      );
      await tester.drag(
        find.byKey(const ValueKey('notifications-list')),
        const Offset(0, 100),
      );
      await tester.pumpAndSettle();

      final swipeTarget = find.byKey(
        const ValueKey('notification-notification-3'),
      );
      final notificationsScrollable = find.descendant(
        of: find.byKey(const ValueKey('notifications-list')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        swipeTarget,
        100,
        scrollable: notificationsScrollable,
      );
      await tester.drag(notificationsScrollable, const Offset(0, -200));
      await tester.pumpAndSettle();
      final swipe = await tester.startGesture(tester.getCenter(swipeTarget));
      await swipe.moveBy(const Offset(-20, 0));
      await tester.pump();
      await swipe.moveBy(const Offset(-90, 0));
      await tester.pump();
      expect(find.text('Eliminar'), findsOneWidget);
      await swipe.moveBy(const Offset(-190, 0));
      await tester.pump();
      expect(find.text('Suelta para eliminar'), findsOneWidget);
      await swipe.up();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('swipe-delete-notification-dialog')),
        findsOneWidget,
      );
      expect(find.text('¿Eliminar esta notificación?'), findsOneWidget);
      expect(swipeTarget, findsOneWidget);
      expect(
        requests.where(
          (request) =>
              request.method == 'DELETE' &&
              request.path == '/notifications/batch',
        ),
        isEmpty,
      );

      await tester.tap(
        find.byKey(const ValueKey('cancel-swipe-delete-notification-button')),
      );
      await tester.pumpAndSettle();
      expect(swipeTarget, findsOneWidget);

      await tester.drag(swipeTarget, const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('swipe-delete-notification-dialog')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('confirm-swipe-delete-notification-button')),
      );
      await tester.pumpAndSettle();

      expect(swipeTarget, findsNothing);
      expect(find.text('Notificación eliminada.'), findsOneWidget);
      expect(find.text('2 notificaciones pendientes'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('notification-notification-1')),
        -100,
        scrollable: notificationsScrollable,
      );

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
      final deleteRequests = requests
          .where(
            (request) =>
                request.method == 'DELETE' &&
                request.path == '/notifications/batch',
          )
          .toList(growable: false);
      expect(deleteRequests, hasLength(2));
      expect(
        Map<String, dynamic>.from(deleteRequests.first.data as Map)['ids'],
        ['notification-3'],
      );
      final deleteRequest = deleteRequests.last;
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
