import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_preview_dialog.dart';

void main() {
  testWidgets('quick editor tools stay inside the card on narrow screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showCreateNoteDialog(
                  context: context,
                  defaultAuthorName: 'Nico',
                  showAuthorField: false,
                  assignees: const [],
                ),
                child: const Text('Crear nota'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Crear nota'));
    await tester.pumpAndSettle();

    final toolsRect = tester.getRect(
      find.byKey(const ValueKey('quick-editor-tools')),
    );
    final firstActionRect = tester.getRect(
      find.byKey(const ValueKey('quick-editor-styles-action')),
    );
    final attachmentRect = tester.getRect(
      find.byKey(const ValueKey('quick-editor-attachment-action')),
    );

    expect(firstActionRect.left, greaterThanOrEqualTo(toolsRect.left));
    expect(attachmentRect.right, lessThanOrEqualTo(toolsRect.right));
    expect(tester.takeException(), isNull);
  });
}
