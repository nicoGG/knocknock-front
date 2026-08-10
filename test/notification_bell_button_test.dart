import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/core/theme/app_theme.dart';
import 'package:nocknock/features/notifications/presentation/widgets/notification_bell_button.dart';

void main() {
  testWidgets('stays calm and hides the badge without unread notifications', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(unreadCount: 0));

    expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
    expect(
      find.byKey(const ValueKey('notification-count-badge')),
      findsNothing,
    );
    expect(find.byTooltip('Notificaciones'), findsOneWidget);
  });

  testWidgets('rings the bell and pops in the unread count', (tester) async {
    await tester.pumpWidget(_testApp(unreadCount: 7));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);
    expect(
      find.byKey(const ValueKey('notification-count-badge')),
      findsOneWidget,
    );
    expect(find.text('7'), findsOneWidget);
    expect(find.byTooltip('7 notificaciones sin leer'), findsOneWidget);

    final ringingBell = tester.widget<Transform>(
      find.byKey(const ValueKey('notification-bell-rotation')),
    );
    expect(ringingBell.transform.entry(0, 1).abs(), greaterThan(0.001));

    await tester.pumpAndSettle();
    final settledBell = tester.widget<Transform>(
      find.byKey(const ValueKey('notification-bell-rotation')),
    );
    expect(settledBell.transform.entry(0, 1).abs(), lessThan(0.001));
  });

  testWidgets('animates a changed count and caps the visible label at 99+', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(unreadCount: 7));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_testApp(unreadCount: 108));
    await tester.pump();

    expect(find.text('99+'), findsOneWidget);
    expect(find.byTooltip('108 notificaciones sin leer'), findsOneWidget);

    final badge = tester.widget<Transform>(
      find.byKey(const ValueKey('notification-badge-scale')),
    );
    expect(badge.transform.entry(0, 0), lessThan(1));

    await tester.pumpAndSettle();
    final settledBadge = tester.widget<Transform>(
      find.byKey(const ValueKey('notification-badge-scale')),
    );
    expect(settledBadge.transform.entry(0, 0), closeTo(1, 0.001));
  });

  testWidgets('shows the active state without motion when animations are off', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(unreadCount: 3, disableAnimations: true));

    final bell = tester.widget<Transform>(
      find.byKey(const ValueKey('notification-bell-rotation')),
    );
    final badge = tester.widget<Transform>(
      find.byKey(const ValueKey('notification-badge-scale')),
    );
    expect(bell.transform.entry(0, 1).abs(), lessThan(0.001));
    expect(badge.transform.entry(0, 0), closeTo(1, 0.001));
    expect(find.byKey(const ValueKey('notification-bell-halo')), findsNothing);
  });
}

Widget _testApp({required int unreadCount, bool disableAnimations = false}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: Center(
          child: NotificationBellButton(
            unreadCount: unreadCount,
            onPressed: () {},
          ),
        ),
      ),
    ),
  );
}
