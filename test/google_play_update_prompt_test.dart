import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/core/update/google_play_update_prompt.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('does not check Google Play updates in debug mode', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final gateway = _FakePlayUpdateGateway(
      check: const PlayUpdateCheck(
        updateAvailable: true,
        flexibleUpdateAllowed: true,
        downloaded: false,
      ),
    );
    addTearDown(gateway.dispose);

    await tester.pumpWidget(
      _app(preferences: preferences, gateway: gateway, enabled: null),
    );
    await tester.pump();

    expect(gateway.checkCalls, 0);
    expect(find.text('Hay una nueva versión'), findsNothing);
  });

  testWidgets('offers and starts a flexible Google Play update', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final gateway = _FakePlayUpdateGateway(
      check: const PlayUpdateCheck(
        updateAvailable: true,
        flexibleUpdateAllowed: true,
        downloaded: false,
        availableVersionCode: 503,
      ),
    );
    addTearDown(gateway.dispose);

    await tester.pumpWidget(_app(preferences: preferences, gateway: gateway));
    await tester.pump();

    expect(find.text('Hay una nueva versión'), findsOneWidget);
    expect(find.text('Actualizar ahora'), findsOneWidget);

    await tester.tap(find.byKey(const Key('google-play-update-now')));
    await tester.pump();

    expect(gateway.startCalls, 1);
    expect(
      find.text('La actualización se está descargando desde Google Play.'),
      findsOneWidget,
    );
  });

  testWidgets('snoozes the prompt for 24 hours', (tester) async {
    final preferences = await SharedPreferences.getInstance();
    final gateway = _FakePlayUpdateGateway(
      check: const PlayUpdateCheck(
        updateAvailable: true,
        flexibleUpdateAllowed: true,
        downloaded: false,
      ),
    );
    addTearDown(gateway.dispose);
    final now = DateTime(2026, 8, 5, 20);

    await tester.pumpWidget(
      _app(preferences: preferences, gateway: gateway, now: () => now),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('google-play-update-later')));
    await tester.pump();

    expect(
      preferences.getInt(googlePlayUpdateSnoozedAtKey),
      now.millisecondsSinceEpoch,
    );
  });

  testWidgets('does not check again during the snooze window', (tester) async {
    final now = DateTime(2026, 8, 5, 20);
    SharedPreferences.setMockInitialValues({
      googlePlayUpdateSnoozedAtKey: now
          .subtract(const Duration(hours: 2))
          .millisecondsSinceEpoch,
    });
    final preferences = await SharedPreferences.getInstance();
    final gateway = _FakePlayUpdateGateway(
      check: const PlayUpdateCheck(
        updateAvailable: true,
        flexibleUpdateAllowed: true,
        downloaded: false,
      ),
    );
    addTearDown(gateway.dispose);

    await tester.pumpWidget(
      _app(preferences: preferences, gateway: gateway, now: () => now),
    );
    await tester.pump();

    expect(gateway.checkCalls, 0);
    expect(find.text('Hay una nueva versión'), findsNothing);
  });

  testWidgets('asks to restart after the flexible update downloads', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final gateway = _FakePlayUpdateGateway(
      check: const PlayUpdateCheck(
        updateAvailable: false,
        flexibleUpdateAllowed: false,
        downloaded: false,
      ),
    );
    addTearDown(gateway.dispose);

    await tester.pumpWidget(_app(preferences: preferences, gateway: gateway));
    await tester.pump();
    gateway.emit(PlayUpdateInstallStatus.downloaded);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.text('La actualización está lista para instalar.'),
      findsOneWidget,
    );
    expect(gateway.completeCalls, 0);

    await tester.tap(find.byKey(const Key('google-play-update-restart')));
    await tester.pump();

    expect(gateway.completeCalls, 1);
  });

  testWidgets('opens Play Store when flexible updates are unavailable', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final gateway = _FakePlayUpdateGateway(
      check: const PlayUpdateCheck(
        updateAvailable: true,
        flexibleUpdateAllowed: false,
        downloaded: false,
      ),
    );
    addTearDown(gateway.dispose);

    await tester.pumpWidget(_app(preferences: preferences, gateway: gateway));
    await tester.pump();
    await tester.tap(find.byKey(const Key('google-play-update-now')));
    await tester.pump();

    expect(gateway.startCalls, 0);
    expect(gateway.openStoreCalls, 1);
  });
}

Widget _app({
  required SharedPreferences preferences,
  required PlayUpdateGateway gateway,
  DateTime Function()? now,
  bool? enabled = true,
}) {
  final navigatorKey = GlobalKey<NavigatorState>();
  return MaterialApp(
    navigatorKey: navigatorKey,
    home: const Scaffold(body: Text('Inicio')),
    builder: (context, child) => GooglePlayUpdatePrompt(
      preferences: preferences,
      navigatorKey: navigatorKey,
      gateway: gateway,
      enabled: enabled,
      now: now ?? DateTime.now,
      child: child ?? const SizedBox.shrink(),
    ),
  );
}

class _FakePlayUpdateGateway implements PlayUpdateGateway {
  _FakePlayUpdateGateway({required this.check});

  final PlayUpdateCheck check;
  final _statuses = StreamController<PlayUpdateInstallStatus>.broadcast();
  int checkCalls = 0;
  int startCalls = 0;
  int completeCalls = 0;
  int openStoreCalls = 0;

  @override
  Stream<PlayUpdateInstallStatus> get installStatuses => _statuses.stream;

  @override
  Future<PlayUpdateCheck> checkForUpdate() async {
    checkCalls += 1;
    return check;
  }

  @override
  Future<PlayUpdateStartResult> startFlexibleUpdate() async {
    startCalls += 1;
    return PlayUpdateStartResult.accepted;
  }

  @override
  Future<void> completeFlexibleUpdate() async {
    completeCalls += 1;
  }

  @override
  Future<void> openStoreListing() async {
    openStoreCalls += 1;
  }

  void emit(PlayUpdateInstallStatus status) => _statuses.add(status);

  Future<void> dispose() => _statuses.close();
}
