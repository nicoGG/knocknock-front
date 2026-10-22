import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nocknock/features/finance/financial_charts.dart';
import 'package:nocknock/features/finance/financial_summary_page.dart';

import 'financial_improvements_test.dart' as f;

void main() {
  setUpAll(() => initializeDateFormatting('es'));
  test('grouping retains every unit and ignores zero values', () {
    final groups = {
      for (var i = 1; i <= 12; i++) 'Comercio $i': i * 100,
      'Vacío': 0,
    };
    final compact = compactExpenseGroups(groups);
    expect(compact, hasLength(7));
    expect(compact.values.fold<int>(0, (a, b) => a + b), 7800);
    expect(compact.containsKey('Vacío'), false);
  });
  testWidgets('chart can switch to bars and highlight a group', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FinancialExpenseChart(
              groups: {'Ana': 3000, 'Luis': 1000},
              currency: 'CLP',
              title: 'Distribución',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Gráfico de barras'), findsOneWidget);
    await tester.tap(find.byTooltip('Gráfico de barras'));
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();
    expect(find.text('75 %'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('all chart types work with a larger aggregated group', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FinancialExpenseChart(
              groups: {for (var i = 0; i < 20; i++) 'Persona $i': 100},
              currency: 'CLP',
              title: 'Distribución',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final tooltip in [
      'Gráfico de torta',
      'Gráfico de columnas',
      'Gráfico de barras',
      'Gráfico de dona',
    ]) {
      await tester.tap(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.ensureVisible(find.text('Otros'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Otros'));
    await tester.pumpAndSettle();
    expect(find.text('70 %'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'summary month selector changes totals without mixing currencies',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FinancialSummaryPage(
            list: f.list(),
            currency: 'CLP',
            month: null,
            onEdit: (_) {},
            notes: [
              f.note(
                f.entry(amount: 1000, date: DateTime(2026, 9, 1)),
                id: 'sep',
              ),
              f.note(
                f.entry(amount: 2000, date: DateTime(2026, 10, 1)),
                id: 'oct',
              ),
              f.note(
                f.entry(
                  amount: 90000,
                  currency: 'USD',
                  date: DateTime(2026, 10, 1),
                ),
                id: 'usd',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Todos los meses').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('septiembre 2026'));
      await tester.pumpAndSettle();
      expect(find.text('1 movimiento · 0 % pagado'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
