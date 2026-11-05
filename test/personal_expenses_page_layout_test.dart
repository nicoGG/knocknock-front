import 'personal_expenses_test.dart' show sampleStatement;

import 'package:nocknock/features/personal_expenses/expense_dashboard.dart';
import 'package:nocknock/features/personal_expenses/expense_style.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/core/theme/app_theme.dart';
import 'package:nocknock/features/personal_expenses/personal_expenses_client.dart';
import 'package:nocknock/features/personal_expenses/personal_expenses_page.dart';

class _EmptyClient extends PersonalExpensesClient {
  _EmptyClient() : super(tokenProvider: () async => null);
  @override
  Future<List<Map<String, dynamic>>> list() async => [];
}

void main() {
  for (final dark in [true, false]) {
    testWidgets(
      'history and statement remain usable with large text: dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final font = FontLoader('Avenir')
          ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'));
        await font.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
        final boundaryKey = GlobalKey();
        var opened = false;
        var deleted = false;
        final statement = sampleStatement();
        Future<void> capture(String name) async {
          if (Platform.environment['EXPENSE_SECTION_SCREENSHOT']
              case final path?) {
            await tester.runAsync(() async {
              final boundary =
                  boundaryKey.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: 2);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File('$path-$name-${dark ? 'dark' : 'light'}.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        }

        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: RepaintBoundary(
              key: boundaryKey,
              child: Scaffold(
                appBar: AppBar(title: const Text('Gastos personales')),
                body: ExpenseBackground(
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      ExpenseDashboard(
                        statements: [statement],
                        onOpen: (_) => opened = true,
                        onDelete: (_) => deleted = true,
                        onImport: () {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Historial'));
        await tester.pumpAndSettle();
        await capture('history');
        await tester.ensureVisible(
          find.byKey(const ValueKey('history-2026-10')),
        );
        await tester.tap(find.text('Octubre 2026').last);
        await tester.pumpAndSettle();
        final issuer = find.textContaining('CMR Banco Falabella');
        await tester.ensureVisible(issuer);
        await tester.tap(issuer);
        expect(opened, isTrue);
        await tester.tap(find.byTooltip('Eliminar estado'));
        expect(deleted, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: RepaintBoundary(
              key: boundaryKey,
              child: PersonalStatementPage(statement: statement),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await capture('statement');
        tester.view.physicalSize = const Size(320, 640);
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Compra supermercado'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(
          tester.element(find.text('Compra supermercado')),
          alignment: .25,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Compra supermercado'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Monto operación:'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final dark in [true, false]) {
    testWidgets('import welcome fits phone and enlarged text: dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final font = FontLoader('Avenir')
        ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'));
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: RepaintBoundary(
            key: boundaryKey,
            child: PersonalExpensesPage(client: _EmptyClient()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Subir estado PDF').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (Platform.environment['EXPENSE_WELCOME_SCREENSHOT'] case final path?) {
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$path-${dark ? 'dark' : 'light'}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Tu información, privada'),
        200,
      );
      await tester.tap(find.text('Tu información, privada'));
      await tester.pumpAndSettle();
      expect(find.textContaining('30 páginas'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
