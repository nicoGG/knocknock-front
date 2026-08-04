import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/data/local_notes_repository.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'pins notes first and persists drag ordering within each section',
    () async {
      final repository = LocalNotesRepository();
      final first = await repository.createNote(
        'home',
        const NoteDraft(
          title: 'Primera',
          content: '',
          color: NoteColor.yellow,
          authorName: 'Invitado',
        ),
      );
      final second = await repository.createNote(
        'home',
        const NoteDraft(
          title: 'Segunda',
          content: '',
          color: NoteColor.blue,
          authorName: 'Invitado',
        ),
      );
      final third = await repository.createNote(
        'home',
        const NoteDraft(
          title: 'Tercera',
          content: '',
          color: NoteColor.green,
          authorName: 'Invitado',
        ),
      );
      final cubit = NotesCubit(repository);
      await cubit.load();

      await cubit.togglePin(first);
      expect(cubit.state.notes.first.id, first.id);
      expect(cubit.state.notes.first.isPinned, isTrue);

      await cubit.reorderVisibleNotes([first.id, second.id, third.id]);
      expect(cubit.state.notes.map((note) => note.id), [
        first.id,
        second.id,
        third.id,
      ]);
      expect((await repository.fetchNotes('home')).map((note) => note.id), [
        first.id,
        second.id,
        third.id,
      ]);

      await cubit.close();
    },
  );
}
