import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/data/local_notes_repository.dart';
import 'package:nocknock/features/notes/data/selected_list_store.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('restores the last selected list after reopening the app', () async {
    final firstRepository = LocalNotesRepository();
    final selectedList = await firstRepository.createList('Viaje');
    final firstCubit = NotesCubit(firstRepository);

    await firstCubit.load();
    await firstCubit.selectList(selectedList.id);
    expect(firstCubit.state.selectedListId, selectedList.id);
    await firstCubit.close();

    final reopenedCubit = NotesCubit(LocalNotesRepository());
    await reopenedCubit.load();

    expect(reopenedCubit.state.selectedListId, selectedList.id);
    expect(reopenedCubit.state.selectedList?.name, 'Viaje');
    await reopenedCubit.close();
  });

  test('falls back safely when the remembered list no longer exists', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      SharedPreferencesSelectedListStore.storageKey,
      'deleted-list',
    );
    final cubit = NotesCubit(LocalNotesRepository());

    await cubit.load();

    expect(cubit.state.selectedListId, 'home');
    expect(
      preferences.getString(SharedPreferencesSelectedListStore.storageKey),
      'home',
    );
    await cubit.close();
  });
}
