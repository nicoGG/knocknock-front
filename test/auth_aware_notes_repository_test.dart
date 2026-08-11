import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/auth/data/auth_repository.dart';
import 'package:nocknock/features/auth/domain/app_user.dart';
import 'package:nocknock/features/notes/data/auth_aware_notes_repository.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';

void main() {
  test('routes guests locally and signed-in users remotely', () async {
    final authRepository = _ControllableAuthRepository();
    final localRepository = _TrackingNotesRepository('local');
    final remoteRepository = _TrackingNotesRepository('remote');
    final repository = AuthAwareNotesRepository(
      authRepository: authRepository,
      localRepository: localRepository,
      remoteRepository: remoteRepository,
    );

    expect((await repository.fetchLists()).single.name, 'local');

    final sourceChange = expectLater(
      repository.realtimeEvents,
      emitsInOrder([
        isA<RealtimeConnectionChanged>(),
        isA<NotesSourceChanged>(),
      ]),
    );
    authRepository.setUser(
      const AppUser(
        id: 'google-user',
        displayName: 'Nico',
        email: 'nico@example.com',
      ),
    );
    await sourceChange;

    expect((await repository.fetchLists()).single.name, 'remote');

    await repository.clearLocalData();
    expect(localRepository.clearLocalDataCalls, 1);
    expect(remoteRepository.clearLocalDataCalls, 0);

    repository.dispose();
    await authRepository.close();
  });

  test('syncs guest data before switching to the remote repository', () async {
    final authRepository = _ControllableAuthRepository();
    final localRepository = _TrackingNotesRepository(
      'local',
      snapshot: _guestSnapshot(),
    );
    final remoteRepository = _TrackingNotesRepository('remote');
    final repository = AuthAwareNotesRepository(
      authRepository: authRepository,
      localRepository: localRepository,
      remoteRepository: remoteRepository,
    );

    final events = expectLater(
      repository.realtimeEvents,
      emitsInOrder([
        isA<GuestDataSyncStarted>(),
        isA<GuestDataSyncCompleted>(),
        isA<RealtimeConnectionChanged>(),
        isA<NotesSourceChanged>(),
      ]),
    );
    authRepository.setUser(
      const AppUser(
        id: 'google-user',
        displayName: 'Nico',
        email: 'nico@example.com',
      ),
    );
    await events;

    expect(remoteRepository.syncedSnapshot, same(localRepository.snapshot));
    expect(localRepository.clearLocalDataCalls, 1);
    expect((await repository.fetchLists()).single.name, 'remote');

    repository.dispose();
    await authRepository.close();
  });

  test('keeps local data when the backend sync fails', () async {
    final authRepository = _ControllableAuthRepository();
    final localRepository = _TrackingNotesRepository(
      'local',
      snapshot: _guestSnapshot(),
    );
    final remoteRepository = _TrackingNotesRepository(
      'remote',
      syncError: const NotesPersistenceFailure(),
    );
    final repository = AuthAwareNotesRepository(
      authRepository: authRepository,
      localRepository: localRepository,
      remoteRepository: remoteRepository,
    );

    final events = expectLater(
      repository.realtimeEvents,
      emitsInOrder([
        isA<GuestDataSyncStarted>(),
        isA<GuestDataSyncFailed>(),
        isA<RealtimeConnectionChanged>(),
        isA<NotesSourceChanged>(),
      ]),
    );
    authRepository.setUser(
      const AppUser(
        id: 'google-user',
        displayName: 'Nico',
        email: 'nico@example.com',
      ),
    );
    await events;

    expect(localRepository.clearLocalDataCalls, 0);
    expect((await repository.fetchLists()).single.name, 'remote');

    repository.dispose();
    await authRepository.close();
  });

  test(
    'moves guest aggregate board backgrounds into the signed-in account',
    () async {
      final authRepository = _ControllableAuthRepository();
      final localRepository = _TrackingNotesRepository(
        'local',
        initialAggregateBoardAppearances: const AggregateBoardAppearances(
          pinned: ListAppearance(
            backgroundPreset: ListBackgroundPreset.aurora,
            backgroundBlur: 4,
          ),
        ),
      );
      final remoteRepository = _TrackingNotesRepository('remote');
      final repository = AuthAwareNotesRepository(
        authRepository: authRepository,
        localRepository: localRepository,
        remoteRepository: remoteRepository,
      );

      final events = expectLater(
        repository.realtimeEvents,
        emitsInOrder([
          isA<GuestDataSyncStarted>(),
          isA<GuestDataSyncCompleted>(),
          isA<RealtimeConnectionChanged>(),
          isA<NotesSourceChanged>(),
        ]),
      );
      authRepository.setUser(
        const AppUser(
          id: 'google-user',
          displayName: 'Nico',
          email: 'nico@example.com',
        ),
      );
      await events;

      expect(
        remoteRepository.aggregateBoardAppearances.pinned,
        localRepository.initialAggregateBoardAppearances.pinned,
      );
      expect(localRepository.clearLocalDataCalls, 1);

      repository.dispose();
      await authRepository.close();
    },
  );
}

LocalNotesSnapshot _guestSnapshot() {
  final createdAt = DateTime(2026, 8, 4, 12);
  return LocalNotesSnapshot(
    lists: [
      NoteList(
        id: 'home',
        name: 'Mis notas',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    ],
    notes: [
      Note(
        id: 'local-note-1',
        boardId: 'home',
        title: 'Comprar pan',
        content: '',
        color: NoteColor.yellow,
        authorName: 'Nico',
        isCompleted: false,
        positionX: 0,
        positionY: 0,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    ],
  );
}

class _ControllableAuthRepository implements AuthRepository {
  final _controller = StreamController<AppUser?>.broadcast(sync: true);
  AppUser? _currentUser;

  @override
  Stream<AppUser?> get authStateChanges => _controller.stream;

  @override
  AppUser? get currentUser => _currentUser;

  void setUser(AppUser? user) {
    _currentUser = user;
    _controller.add(user);
  }

  Future<void> close() => _controller.close();

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => null;

  @override
  Future<void> deleteAccount() async => setUser(null);

  @override
  Future<void> signOut() async => setUser(null);
}

class _TrackingNotesRepository
    implements
        NotesRepository,
        LocalNotesDataCleaner,
        LocalNotesDataReader,
        GuestDataSyncTarget,
        AggregateBoardAppearancesRepository {
  _TrackingNotesRepository(
    this.name, {
    LocalNotesSnapshot? snapshot,
    this.syncError,
    this.initialAggregateBoardAppearances = const AggregateBoardAppearances(),
  }) : snapshot = snapshot ?? const LocalNotesSnapshot(lists: [], notes: []),
       aggregateBoardAppearances = initialAggregateBoardAppearances;

  final String name;
  final LocalNotesSnapshot snapshot;
  final Object? syncError;
  int clearLocalDataCalls = 0;
  LocalNotesSnapshot? syncedSnapshot;
  final AggregateBoardAppearances initialAggregateBoardAppearances;
  AggregateBoardAppearances aggregateBoardAppearances;

  @override
  bool get isLocalDataActive => true;

  @override
  Stream<NotesRealtimeEvent> get realtimeEvents => const Stream.empty();

  @override
  Future<void> connect(String boardId) async {}

  @override
  void disconnect() {}

  @override
  Future<List<NoteList>> fetchLists() async {
    final now = DateTime(2026);
    return [NoteList(id: name, name: name, createdAt: now, updatedAt: now)];
  }

  @override
  Future<NoteList> createList(String name) => throw UnimplementedError();

  @override
  Future<NoteList> updateList(String listId, String name) =>
      throw UnimplementedError();

  @override
  Future<List<NoteList>> reorderLists(List<String> orderedIds) =>
      throw UnimplementedError();

  @override
  Future<void> deleteList(String listId) => throw UnimplementedError();

  @override
  Future<NoteList> inviteCollaborator(String listId, String email) =>
      throw UnimplementedError();

  @override
  Future<NoteList> removeCollaborator(String listId, String collaboratorUid) =>
      throw UnimplementedError();

  @override
  Future<NoteList> updateListAppearance(
    String listId,
    ListAppearance appearance,
  ) => throw UnimplementedError();

  @override
  Future<AggregateBoardAppearances> fetchAggregateBoardAppearances() async =>
      aggregateBoardAppearances;

  @override
  Future<AggregateBoardAppearances> updateAggregateBoardAppearance(
    AggregateBoardScope scope,
    ListAppearance appearance,
  ) async {
    aggregateBoardAppearances = aggregateBoardAppearances.copyWithScope(
      scope,
      appearance,
    );
    return aggregateBoardAppearances;
  }

  @override
  Future<List<Note>> fetchNotes(String boardId) => throw UnimplementedError();

  @override
  Future<List<Note>> fetchPinnedNotes() => throw UnimplementedError();

  @override
  Future<List<Note>> fetchReminderNotes() => throw UnimplementedError();

  @override
  Future<Note> createNote(String boardId, NoteDraft draft) =>
      throw UnimplementedError();

  @override
  Future<Note> updateNote(String id, Map<String, dynamic> changes) =>
      throw UnimplementedError();

  @override
  Future<Note> setNoteReaction(String id, String emoji, bool active) =>
      throw UnimplementedError();

  @override
  Future<List<Note>> reorderNotes(String boardId, List<String> orderedIds) =>
      throw UnimplementedError();

  @override
  Future<void> deleteNote(String id) => throw UnimplementedError();

  @override
  Future<void> clearLocalData() async {
    clearLocalDataCalls++;
    aggregateBoardAppearances = const AggregateBoardAppearances();
  }

  @override
  Future<LocalNotesSnapshot> readLocalData() async => snapshot;

  @override
  Future<GuestDataSyncResult> syncGuestData(LocalNotesSnapshot snapshot) async {
    syncedSnapshot = snapshot;
    if (syncError case final error?) throw error;
    return GuestDataSyncResult(
      listsImported: snapshot.lists.where((list) => list.id != 'home').length,
      notesImported: snapshot.notes.length,
    );
  }

  @override
  void dispose() {}
}
