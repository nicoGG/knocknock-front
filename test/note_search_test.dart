import 'financial_improvements_test.dart' as fixtures;

import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/data/note_search.dart';
import 'package:nocknock/features/notes/domain/note.dart';

void main() {
  test(
    'guest and private search match financial fields and exact monetary units',
    () {
      final note = fixtures.note(
        fixtures.entry(
          amount: 15000,
          payer: 'José',
          people: ['José', 'Álvaro'],
        ),
      );
      final index = PrivateNoteSearchIndex()..upsert(note);
      for (final query in [
        'maria',
        'Jose',
        'alvaro',
        '15.000',
        r'$15.000',
        'CLP 15000',
      ]) {
        expect(noteMatchesQuery(note, query), isTrue, reason: query);
        expect(index.search(query), [note], reason: query);
      }
      expect(index.search('150'), isEmpty);
      final usd = fixtures.note(fixtures.entry(amount: 1050, currency: 'USD'));
      index.upsert(usd);
      expect(index.search('15.000'), isEmpty);
      for (final q in ['10,50', 'USD 10.50', '10,5']) {
        expect(index.search(q), [usd]);
      }
      expect(index.search('1050'), isEmpty);
      expect(index.search('EUR 10,50'), isEmpty);
      index.removeBoard(usd.boardId);
      expect(index.search('maria'), isEmpty);
    },
  );

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
