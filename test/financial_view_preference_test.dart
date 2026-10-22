import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nocknock/features/finance/financial_list_board.dart';
import 'package:nocknock/features/notes/presentation/board_view_mode_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'financial_improvements_test.dart' as f;

void main() {
  setUpAll(() => initializeDateFormatting('es'));
  testWidgets(
    'financial view is restored after reopening from persisted preferences',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      var controller = BoardViewModeController();
      await controller.load();
      Widget board() => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FinancialListBoard(
              list: f.list(),
              notes: [f.note(f.entry())],
              onEdit: (_) {},
              onAdd: () {},
              listView:
                  controller.viewModeFor('expenses') == BoardViewMode.list,
              onViewChanged: (value) => controller.setViewMode(
                'expenses',
                value ? BoardViewMode.list : BoardViewMode.grid,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(board());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Ver lista'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ver lista'));
      await tester.pumpAndSettle();
      expect(controller.viewModeFor('expenses'), BoardViewMode.list);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      controller = BoardViewModeController();
      await controller.load();
      await tester.pumpWidget(board());
      await tester.pumpAndSettle();
      final selector = tester.widget<SegmentedButton<bool>>(
        find.byType(SegmentedButton<bool>),
      );
      expect(selector.selected, {true});
      expect(controller.viewModeFor('another-list'), BoardViewMode.grid);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
