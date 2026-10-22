import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nocknock/core/theme/app_theme.dart';
import 'package:nocknock/features/finance/financial_list_board.dart';

import 'financial_improvements_test.dart' as f;

void main() {
  testWidgets('financial overview fits a narrow display in both themes', (
    tester,
  ) async {
    await initializeDateFormatting('es');
    if (Platform.environment['FINANCE_VISUAL_QA'] == '1') {
      await (FontLoader(
        'Avenir',
      )..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))).load();
      await (FontLoader(
        'Roboto',
      )..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final dark in [false, true]) {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              appBar: AppBar(title: const Text('Gastos del hogar')),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: FinancialListBoard(
                  list: f.list(),
                  notes: [
                    f.note(
                      f.entry(amount: 50000, kind: 'budget'),
                      id: 'budget',
                    ),
                    f.note(
                      f.entry(
                        amount: 15000,
                        status: 'paid',
                        people: ['Ana', 'María'],
                        payer: 'Ana',
                      ),
                      id: 'gasto',
                    ),
                    f.note(
                      f.entry(amount: 12000, payments: [f.payment(5000)]),
                      id: 'cuenta',
                    ),
                  ],
                  onEdit: (_) {},
                  onAdd: () {},
                  onSave: (_, _) async {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (Platform.environment['FINANCE_VISUAL_QA'] == '1') {
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/tmp/nocknock-finance-actions-${dark ? 'dark' : 'light'}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.ensureVisible(
        find.byKey(const ValueKey('financial-entry-cuenta')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (Platform.environment['FINANCE_VISUAL_QA'] == '1') {
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('/tmp/nocknock-finance-${dark ? 'dark' : 'light'}.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
  });
}
