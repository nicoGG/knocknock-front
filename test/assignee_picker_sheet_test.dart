import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/presentation/widgets/assignee_picker_sheet.dart';

void main() {
  final people = List.generate(
    4,
    (index) => ListCollaborator(
      uid: 'person-$index',
      email: 'person$index@example.com',
      displayName: 'Persona $index',
      role: ListMemberRole.editor,
      joinedAt: DateTime(2026),
    ),
  );

  Future<void> openPicker(
    WidgetTester tester, {
    List<String> uids = const [],
    List<String> names = const [],
    ValueChanged<AssigneeSelection?>? onResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final result = await showModalBottomSheet<AssigneeSelection>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .75,
                  ),
                  builder: (_) => AssigneePickerSheet(
                    selectedUids: uids,
                    customNames: names,
                    assignees: people,
                  ),
                );
                onResult?.call(result);
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> addName(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(const ValueKey('preview-assignee-custom')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('custom-assignee-name-field')),
      name,
    );
    await tester.tap(find.byKey(const ValueKey('save-custom-assignee-button')));
    await tester.pumpAndSettle();
  }

  testWidgets('combines an invited person with two custom names', (
    tester,
  ) async {
    AssigneeSelection? saved;
    await openPicker(
      tester,
      uids: ['person-0'],
      onResult: (value) => saved = value,
    );
    await addName(tester, 'Camila');
    await addName(tester, 'Pedro');
    expect(find.text('3 personas seleccionadas'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('assignee-limit-warning')),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.byKey(const ValueKey('save-assignees-button')));
    await tester.pumpAndSettle();
    expect(saved?.uids, ['person-0']);
    expect(saved?.customNames, ['Camila', 'Pedro']);
  });

  testWidgets('caps the total at three and allows removing a selection', (
    tester,
  ) async {
    AssigneeSelection? saved;
    await openPicker(
      tester,
      uids: ['person-0', 'person-1'],
      names: ['Camila'],
      onResult: (value) => saved = value,
    );
    final third = find.byKey(const ValueKey('preview-assignee-person-2'));
    await tester.scrollUntilVisible(
      third,
      60,
      scrollable: find.byType(Scrollable).last,
    );
    await Scrollable.ensureVisible(tester.element(third), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(third);
    await tester.pumpAndSettle();
    expect(find.text('3 personas seleccionadas'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('assignee-limit-warning')),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    final custom = find.byKey(const ValueKey('preview-assignee-custom'));
    await tester.scrollUntilVisible(
      custom,
      -60,
      scrollable: find.byType(Scrollable).last,
    );
    await Scrollable.ensureVisible(tester.element(custom), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(custom);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('custom-assignee-name-field')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('custom-assignee-Camila')));
    await tester.pumpAndSettle();
    expect(find.text('2 personas seleccionadas'), findsOneWidget);
    expect(find.byKey(const ValueKey('assignee-limit-warning')), findsNothing);
    await tester.scrollUntilVisible(
      third,
      60,
      scrollable: find.byType(Scrollable).last,
    );
    await Scrollable.ensureVisible(tester.element(third), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(third);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-assignees-button')));
    await tester.pumpAndSettle();
    expect(saved?.uids, ['person-0', 'person-1', 'person-2']);
    expect(saved?.customNames, isEmpty);
  });

  testWidgets('supports three custom people and ignores duplicate names', (
    tester,
  ) async {
    AssigneeSelection? saved;
    await openPicker(tester, onResult: (value) => saved = value);
    await addName(tester, 'Camila');
    await addName(tester, 'camila');
    expect(find.text('1 persona seleccionada'), findsOneWidget);
    await addName(tester, 'Pedro');
    await addName(tester, 'Sofía');
    await tester.tap(find.byKey(const ValueKey('save-assignees-button')));
    await tester.pumpAndSettle();
    expect(saved?.uids, isEmpty);
    expect(saved?.customNames, ['Camila', 'Pedro', 'Sofía']);
  });
}
