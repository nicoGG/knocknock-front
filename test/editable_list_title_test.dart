import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/presentation/widgets/editable_list_title.dart';

void main() {
  testWidgets('edits in place, rejects blank names and retries failed saves', (
    tester,
  ) async {
    var title = 'Guaguas 👶';
    var succeed = false;
    final savedNames = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => EditableListTitle(
              title: title,
              onSave: (name) async {
                savedNames.add(name);
                if (succeed) setState(() => title = name);
                return succeed;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text(title));
    await tester.pump();
    final field = find.byKey(const ValueKey('inline-list-name-field'));
    expect(field, findsOneWidget);
    await tester.enterText(field, '   ');
    await tester.tap(find.byTooltip('Guardar'));
    await tester.pump();
    expect(savedNames, isEmpty);
    expect(find.text('Escribe un nombre para la lista'), findsOneWidget);
    await tester.enterText(field, 'Familia');
    await tester.tap(find.byTooltip('Guardar'));
    await tester.pumpAndSettle();
    expect(field, findsOneWidget);
    succeed = true;
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    expect(find.text('Familia'), findsOneWidget);
    expect(savedNames, ['Familia', 'Familia']);
    await tester.tap(find.text('Familia'));
    await tester.pump();
    await tester.enterText(field, 'Otro nombre');
    await tester.tap(find.byTooltip('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Familia'), findsOneWidget);
    expect(savedNames, hasLength(2));
  });

  testWidgets('read-only titles do not open the editor', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EditableListTitle(title: 'Compartida', onSave: null),
        ),
      ),
    );
    await tester.tap(find.text('Compartida'));
    await tester.pump();
    expect(find.byType(TextFormField), findsNothing);
  });
}
