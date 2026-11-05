import 'package:nocknock/features/personal_expenses/expense_dashboard.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/personal_expenses/personal_expenses_page.dart';

Map<String, dynamic> sampleStatement() => {
  'issuer': 'CMR Banco Falabella',
  'contractLast4': '1234',
  'cards': [
    {'role': 'T', 'last4': '4321'},
  ],
  'billingDate': '2026-10-24',
  'periodStart': '2026-09-25',
  'periodEnd': '2026-10-24',
  'dueDate': '2026-11-10',
  'totalBilled': 30000,
  'minimumPayment': 5000,
  'totals': {
    'purchases': 30000,
    'refunds': 0,
    'charges': 0,
    'payments': -10000,
    'billed': 30000,
    'difference': 0,
  },
  'warnings': [
    'Hay movimientos sin tarjeta indicada en el PDF; se conservaron sin asignar.',
  ],
  'movements': [
    {
      'id': '1',
      'date': '2026-10-01',
      'description': 'Compra supermercado',
      'location': 'Santiago',
      'section': 'COMPRAS NACIONALES',
      'cardLast4': '4321',
      'kind': 'purchase',
      'operationAmount': 90000,
      'totalAmount': 90000,
      'billedAmount': 30000,
      'installment': 1,
      'installments': 3,
      'firstCharge': 'nov-2026',
    },
    {
      'id': '2',
      'date': '2026-10-02',
      'description': 'Compra futura',
      'location': 'S/I',
      'section': 'COMPRAS NACIONALES',
      'cardLast4': null,
      'kind': 'purchase',
      'operationAmount': 60000,
      'totalAmount': 60000,
      'billedAmount': 0,
      'installment': 0,
      'installments': 3,
      'firstCharge': 'dic-2026',
    },
  ],
};

void main() {
  testWidgets(
    'monthly dashboard switches history and explains missing months',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var imports = 0;
      final statements = [
        sampleStatement(),
        {...sampleStatement(), 'billingDate': '2026-11-24'},
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                ExpenseDashboard(
                  statements: statements,
                  onOpen: (_) {},
                  onDelete: (_) {},
                  onImport: () => imports++,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Gasto neto facturado del mes'), findsOneWidget);
      expect(find.textContaining('Sin cambios'), findsOneWidget);
      await tester.tap(find.text('Historial'));
      await tester.pumpAndSettle();
      expect(find.text('Tu historial de 2026'), findsOneWidget);
      expect(find.text('Sin estado importado'), findsWidgets);
      await tester.tap(find.text('Subir otro mes'));
      expect(imports, 1);
      await tester.tap(find.text('Guía de gastos'));
      await tester.pumpAndSettle();
      expect(find.text('1. Completa tu historial'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'preview fits a phone and filters transactions by card and merchant',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final loader = FontLoader('Lato')
        ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'));
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            fontFamily: 'Lato',
            colorSchemeSeed: const Color(0xff66795a),
          ),
          home: RepaintBoundary(
            key: key,
            child: PersonalStatementPage(
              statement: sampleStatement(),
              preview: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Revisar importación'), findsOneWidget);
      expect(find.text('Confirmar e importar movimientos'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (Platform.environment['EXPENSES_SCREENSHOT'] case final path?) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(path).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.scrollUntilVisible(
        find.text('Sin asignar'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('Sin asignar')),
        alignment: 0.3,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sin asignar'));
      await tester.pumpAndSettle();
      expect(find.text('1 movimientos'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Compra futura'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Compra supermercado'), findsNothing);
      await Scrollable.ensureVisible(
        tester.element(find.text('Compra futura')),
        alignment: 0.3,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compra futura'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('Pendiente de facturar'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Pendiente de facturar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
