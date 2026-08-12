import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:nocknock/features/notes/data/offline_mutation_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('persists the web fallback queue and isolates it by account', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final firstStore = SharedPreferencesOfflineMutationStore(preferences);
    final createdAt = DateTime.utc(2026, 8, 12, 12);
    await firstStore.put(
      StoredOfflineMutation(
        id: 'mutation-1',
        userId: 'user-1',
        entityId: 'note-1',
        boardId: 'list-1',
        kind: StoredMutationKind.update,
        payload: '{"title":"ciphertext"}',
        baseRevision: 4,
        createdAt: createdAt,
      ),
    );
    await firstStore.close();

    final restoredStore = SharedPreferencesOfflineMutationStore(preferences);
    final restored = await restoredStore.listForUser('user-1');

    expect(restored, hasLength(1));
    expect(restored.single.id, 'mutation-1');
    expect(restored.single.baseRevision, 4);
    expect(await restoredStore.listForUser('user-2'), isEmpty);
    await restoredStore.remove('mutation-1');
    expect(await restoredStore.listForUser('user-1'), isEmpty);
    await restoredStore.close();
  });

  test('falls back when the native SQLite plugin is unavailable', () async {
    final fallback = InMemoryOfflineMutationStore();
    final store = ResilientOfflineMutationStore(
      primary: _MissingPluginOfflineMutationStore(),
      fallback: fallback,
    );
    final mutation = StoredOfflineMutation(
      id: 'mutation-fallback',
      userId: 'user-1',
      entityId: 'note-1',
      boardId: 'list-1',
      kind: StoredMutationKind.create,
      payload: '{"title":"ciphertext"}',
      baseRevision: 0,
      createdAt: DateTime.utc(2026, 8, 12, 13),
    );

    await store.put(mutation);

    expect(await store.listForUser('user-1'), [mutation]);
    await store.remove(mutation.id);
    expect(await store.listForUser('user-1'), isEmpty);
    await store.close();
  });

  test('migrates fallback rows when SQLite becomes available', () async {
    final primary = InMemoryOfflineMutationStore();
    final fallback = InMemoryOfflineMutationStore();
    final mutation = StoredOfflineMutation(
      id: 'mutation-to-migrate',
      userId: 'user-1',
      entityId: 'note-1',
      boardId: 'list-1',
      kind: StoredMutationKind.update,
      payload: '{"title":"ciphertext"}',
      baseRevision: 3,
      createdAt: DateTime.utc(2026, 8, 12, 14),
    );
    await fallback.put(mutation);
    final store = ResilientOfflineMutationStore(
      primary: primary,
      fallback: fallback,
    );

    expect(await store.listForUser('user-1'), [mutation]);
    expect(await primary.listForUser('user-1'), [mutation]);
    expect(await fallback.listForUser('user-1'), isEmpty);
    await store.close();
  });
}

class _MissingPluginOfflineMutationStore implements OfflineMutationStore {
  Never _missing() => throw MissingPluginException(
    'No implementation found for method getDatabasesPath',
  );

  @override
  Future<List<StoredOfflineMutation>> listForUser(String userId) async =>
      _missing();

  @override
  Future<void> put(StoredOfflineMutation mutation) async => _missing();

  @override
  Future<void> remove(String mutationId) async => _missing();

  @override
  Future<void> close() async {}
}
