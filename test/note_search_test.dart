import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/data/note_search.dart';
import 'package:nocknock/features/notes/domain/note.dart';

void main() {
  test(
    'finds accents and checklist text without exposing an external index',
    () {
      final date = DateTime.utc(2026, 8, 12);
      final note = Note(
        id: 'note-1',
        boardId: 'list-1',
        title: 'Reunión del miércoles',
        content: 'Preparar la presentación',
        color: NoteColor.blue,
        authorName: 'Nico',
        isCompleted: false,
        positionX: 0,
        positionY: 0,
        checklist: const [
          NoteChecklistItem(id: 'task-1', text: 'Confirmar asistentes'),
        ],
        createdAt: date,
        updatedAt: date,
      );

      expect(noteMatchesQuery(note, 'reunion'), isTrue);
      expect(noteMatchesQuery(note, 'PRESENTACIÓN'), isTrue);
      expect(noteMatchesQuery(note, 'asistentes'), isTrue);
      expect(noteMatchesQuery(note, 'presupuesto'), isFalse);
    },
  );
}
