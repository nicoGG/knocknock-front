import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/auth/data/auth_repository.dart';
import 'package:nocknock/features/auth/domain/app_user.dart';
import 'package:nocknock/features/subscriptions/plus_page.dart';

class _Auth implements AuthRepository {
  _Auth([this.currentUser]);
  @override
  final AppUser? currentUser;
  @override
  Stream<AppUser?> get authStateChanges => const Stream.empty();
  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => null;
  @override
  Future<void> deleteAccount() async {}
  @override
  Future<void> signInWithGoogle() async {}
  @override
  Future<void> signOut() async {}
}

void main() {
  testWidgets(
    'Plus preview explains shared ownership and never offers an unconfigured purchase',
    (tester) async {
      await tester.pumpWidget(MaterialApp(home: PlusPage(auth: _Auth())));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('NockNock Plus'), findsOneWidget);
      expect(
        find.textContaining('Los invitados participan gratis'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.textContaining(r'$34.990 CLP / año'),
        180,
      );
      expect(find.textContaining(r'$34.990 CLP / año'), findsOneWidget);
      expect(find.text('AHORRA 27%'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('Próximamente.'),
        200,
      );
      expect(find.textContaining('no se realizan cobros'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets('Plus fits a narrow screen with large text (dark: $dark)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: PlusPage(auth: _Auth()),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.scrollUntilVisible(
        find.textContaining(r'$3.990 CLP / mes'),
        180,
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.textContaining('no se realizan cobros'),
        180,
      );
      expect(find.byType(FilledButton), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'verification failure stays recoverable and does not imply a free plan',
    (tester) async {
      const user = AppUser(
        id: 'owner',
        displayName: 'Owner',
        email: 'owner@example.com',
      );
      await tester.pumpWidget(MaterialApp(home: PlusPage(auth: _Auth(user))));
      await tester.pump(const Duration(seconds: 2));
      await tester.scrollUntilVisible(
        find.textContaining('No pudimos completar'),
        200,
      );
      expect(find.textContaining('No pudimos completar'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Actualizar estado'), 100);
      expect(find.text('Actualizar estado'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
