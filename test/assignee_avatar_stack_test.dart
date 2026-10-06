import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/presentation/note_assignee.dart';
import 'package:nocknock/features/notes/presentation/widgets/post_it_card.dart';

void main() {
  final date = DateTime(2026);
  final note = Note(
    id: 'stack-note',
    boardId: 'home',
    title: 'Tarea',
    content: '',
    color: NoteColor.green,
    category: NoteCategory.work,
    authorName: 'Nico',
    assigneeUids: ['nico', 'ana'],
    customAssigneeNames: ['Camila'],
    isCompleted: false,
    positionX: 0,
    positionY: 0,
    createdAt: date,
    updatedAt: date,
  );
  final collaborators = [
    ListCollaborator(
      uid: 'nico',
      email: '',
      displayName: 'Nico',
      photoUrl: 'https://example.com/nico.jpg',
      role: ListMemberRole.owner,
      joinedAt: date,
    ),
    ListCollaborator(
      uid: 'ana',
      email: '',
      displayName: 'Ana',
      photoUrl: 'https://example.com/ana.jpg',
      role: ListMemberRole.editor,
      joinedAt: date,
    ),
  ];
  for (final layout in PostItCardLayout.values) {
    testWidgets('overlaps each assigned avatar in ${layout.name} cards', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: PostItCard(
                  note: note,
                  layout: layout,
                  enableHero: false,
                  assignee: resolveNoteAssignee(note, collaborators),
                  assignees: resolveNoteAssignees(note, collaborators),
                  onToggle: () {},
                  onPin: () {},
                  onOpen: () {},
                  onChecklistToggle: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final group = find.byKey(const ValueKey('assignee-stack-stack-note'));
      expect(group, findsOneWidget);
      final avatars = find.descendant(
        of: group,
        matching: find.byType(CircleAvatar),
      );
      expect(avatars, findsNWidgets(3));
      final widgets = tester.widgetList<CircleAvatar>(avatars).toList();
      final firstImage = widgets[0].foregroundImage! as ResizeImage;
      final secondImage = widgets[1].foregroundImage! as ResizeImage;
      expect(
        (firstImage.imageProvider as NetworkImage).url,
        collaborators[0].photoUrl,
      );
      expect(
        (secondImage.imageProvider as NetworkImage).url,
        collaborators[1].photoUrl,
      );
      expect(widgets[2].foregroundImage, isNull);
      expect(
        find.descendant(of: group, matching: find.text('C')),
        findsOneWidget,
      );
      final first = tester.getRect(avatars.at(0));
      final second = tester.getRect(avatars.at(1));
      expect(second.left, greaterThan(first.left));
      expect(second.left, lessThan(first.right));
      expect(find.byTooltip('Responsables: Nico, Ana, Camila'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
