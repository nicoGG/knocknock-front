import 'dart:async';

import 'package:nocknock/features/auth/data/auth_repository.dart';
import 'package:nocknock/features/auth/domain/app_user.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';

/// Uses device storage for guests and the connected repository after sign-in.
class AuthAwareNotesRepository
    implements
        NotesRepository,
        LocalNotesDataCleaner,
        NotesCacheReader,
        AggregateBoardAppearancesRepository,
        OfflineSyncRepository,
        NotesSearchRepository,
        PaginatedNotesRepository {
  AuthAwareNotesRepository({
    required AuthRepository authRepository,
    required this.localRepository,
    required this.remoteRepository,
  }) : _authRepository = authRepository,
       _isSignedIn = false,
       _requestedUserId = authRepository.currentUser?.id {
    _authTransition = _applyAuthState(
      authRepository.currentUser,
      notifySourceChange: false,
    );
    _authSubscription = _authRepository.authStateChanges.listen(_onAuthChanged);
    _localSubscription = localRepository.realtimeEvents.listen((event) {
      if (!_isSignedIn) _events.add(event);
    });
    _remoteSubscription = remoteRepository.realtimeEvents.listen((event) {
      if (_isSignedIn) _events.add(event);
    });
  }

  final AuthRepository _authRepository;
  final NotesRepository localRepository;
  final NotesRepository remoteRepository;
  final _events = StreamController<NotesRealtimeEvent>.broadcast();

  late final StreamSubscription<AppUser?> _authSubscription;
  late final StreamSubscription<NotesRealtimeEvent> _localSubscription;
  late final StreamSubscription<NotesRealtimeEvent> _remoteSubscription;
  late Future<void> _authTransition;
  bool _isSignedIn;
  String? _requestedUserId;

  NotesRepository get _activeRepository =>
      _isSignedIn ? remoteRepository : localRepository;

  @override
  Stream<NotesRealtimeEvent> get realtimeEvents => _events.stream;

  @override
  Future<void> connect(String boardId) =>
      _whenReady((repository) => repository.connect(boardId));

  @override
  void disconnect() {
    localRepository.disconnect();
    remoteRepository.disconnect();
  }

  @override
  Future<List<NoteList>> fetchLists() =>
      _whenReady((repository) => repository.fetchLists());

  @override
  Future<NoteList> createList(String name) =>
      _whenReady((repository) => repository.createList(name));

  @override
  Future<NoteList> updateList(String listId, String name) =>
      _whenReady((repository) => repository.updateList(listId, name));

  @override
  Future<List<NoteList>> reorderLists(List<String> orderedIds) =>
      _whenReady((repository) => repository.reorderLists(orderedIds));

  @override
  Future<void> deleteList(String listId) =>
      _whenReady((repository) => repository.deleteList(listId));

  @override
  Future<NoteList> inviteCollaborator(String listId, String email) async {
    await _authTransition;
    if (!_isSignedIn) throw const CollaborationRequiresSignInFailure();
    return remoteRepository.inviteCollaborator(listId, email);
  }

  @override
  Future<NoteList> removeCollaborator(
    String listId,
    String collaboratorUid,
  ) async {
    await _authTransition;
    if (!_isSignedIn) throw const CollaborationRequiresSignInFailure();
    return remoteRepository.removeCollaborator(listId, collaboratorUid);
  }

  @override
  Future<NoteList> updateListAppearance(
    String listId,
    ListAppearance appearance,
  ) => _whenReady(
    (repository) => repository.updateListAppearance(listId, appearance),
  );

  @override
  Future<AggregateBoardAppearances> fetchAggregateBoardAppearances() =>
      _whenReady((repository) {
        if (repository is! AggregateBoardAppearancesRepository) {
          throw const NotesPersistenceFailure();
        }
        return (repository as AggregateBoardAppearancesRepository)
            .fetchAggregateBoardAppearances();
      });

  @override
  Future<AggregateBoardAppearances> updateAggregateBoardAppearance(
    AggregateBoardScope scope,
    ListAppearance appearance,
  ) => _whenReady((repository) {
    if (repository is! AggregateBoardAppearancesRepository) {
      throw const NotesPersistenceFailure();
    }
    return (repository as AggregateBoardAppearancesRepository)
        .updateAggregateBoardAppearance(scope, appearance);
  });

  @override
  Future<List<Note>> fetchNotes(String boardId) =>
      _whenReady((repository) => repository.fetchNotes(boardId));

  @override
  Future<NotesPage> fetchNotesPage(
    String boardId, {
    String? cursor,
    int limit = 40,
  }) => _whenReady((repository) async {
    if (repository is PaginatedNotesRepository) {
      return (repository as PaginatedNotesRepository).fetchNotesPage(
        boardId,
        cursor: cursor,
        limit: limit,
      );
    }
    if (cursor != null) return const NotesPage(items: [], nextCursor: null);
    return NotesPage(
      items: await repository.fetchNotes(boardId),
      nextCursor: null,
    );
  });

  @override
  Future<List<Note>> fetchPinnedNotes() =>
      _whenReady((repository) => repository.fetchPinnedNotes());

  @override
  Future<List<Note>> fetchReminderNotes() =>
      _whenReady((repository) => repository.fetchReminderNotes());

  @override
  Future<List<NoteSearchResult>> searchNotes(String query) =>
      _whenReady((repository) {
        if (repository is! NotesSearchRepository) return Future.value(const []);
        return (repository as NotesSearchRepository).searchNotes(query);
      });

  @override
  Future<OfflineSyncSummary> offlineSyncSummary() => _whenReady((repository) {
    if (repository is! OfflineSyncRepository) {
      return Future.value(const OfflineSyncSummary());
    }
    return (repository as OfflineSyncRepository).offlineSyncSummary();
  });

  @override
  Future<void> syncPendingChanges() => _whenReady((repository) {
    if (repository is! OfflineSyncRepository) return Future.value();
    return (repository as OfflineSyncRepository).syncPendingChanges();
  });

  @override
  Future<List<NoteSyncConflict>> fetchNoteSyncConflicts() =>
      _whenReady((repository) {
        if (repository is! OfflineSyncRepository) return Future.value(const []);
        return (repository as OfflineSyncRepository).fetchNoteSyncConflicts();
      });

  @override
  Future<void> resolveNoteSyncConflict(
    String mutationId,
    NoteConflictResolution resolution,
  ) => _whenReady((repository) {
    if (repository is! OfflineSyncRepository) return Future.value();
    return (repository as OfflineSyncRepository).resolveNoteSyncConflict(
      mutationId,
      resolution,
    );
  });

  @override
  Future<NotesCacheSnapshot?> readCache() async {
    await _authTransition;
    if (!_isSignedIn || remoteRepository is! NotesCacheReader) return null;
    return (remoteRepository as NotesCacheReader).readCache();
  }

  @override
  Future<Note> createNote(String boardId, NoteDraft draft) =>
      _whenReady((repository) => repository.createNote(boardId, draft));

  @override
  Future<Note> updateNote(String id, Map<String, dynamic> changes) =>
      _whenReady((repository) => repository.updateNote(id, changes));

  @override
  Future<Note> setNoteReaction(String id, String emoji, bool active) =>
      _whenReady((repository) => repository.setNoteReaction(id, emoji, active));

  @override
  Future<List<Note>> reorderNotes(String boardId, List<String> orderedIds) =>
      _whenReady((repository) => repository.reorderNotes(boardId, orderedIds));

  @override
  Future<void> deleteNote(
    String id, {
    int? expectedRevision,
    String? clientMutationId,
  }) => _whenReady(
    (repository) => repository.deleteNote(
      id,
      expectedRevision: expectedRevision,
      clientMutationId: clientMutationId,
    ),
  );

  @override
  bool get isLocalDataActive => !_isSignedIn;

  @override
  Future<void> clearLocalData() {
    final repository = localRepository;
    if (repository is! LocalNotesDataCleaner) {
      throw const NotesPersistenceFailure();
    }
    return (repository as LocalNotesDataCleaner).clearLocalData();
  }

  void _onAuthChanged(AppUser? user) {
    if (user?.id == _requestedUserId) return;
    _requestedUserId = user?.id;
    _authTransition = _authTransition.then(
      (_) => _applyAuthState(user, notifySourceChange: true),
    );
  }

  Future<void> _applyAuthState(
    AppUser? user, {
    required bool notifySourceChange,
  }) async {
    if (user != null && !_isSignedIn) await _syncGuestData();
    remoteRepository.disconnect();
    _isSignedIn = user != null;
    if (notifySourceChange) {
      _events
        ..add(const RealtimeConnectionChanged(false))
        ..add(const NotesSourceChanged());
    }
  }

  Future<void> _syncGuestData() async {
    final local = localRepository;
    final remote = remoteRepository;
    if (local is! LocalNotesDataReader || local is! LocalNotesDataCleaner) {
      return;
    }
    final snapshot = await (local as LocalNotesDataReader).readLocalData();
    final localAppearances = local is AggregateBoardAppearancesRepository
        ? await (local as AggregateBoardAppearancesRepository)
              .fetchAggregateBoardAppearances()
        : const AggregateBoardAppearances();
    final hasAppearanceData =
        localAppearances != const AggregateBoardAppearances();
    if (!snapshot.hasData && !hasAppearanceData) return;

    _events.add(const GuestDataSyncStarted());
    try {
      final result = snapshot.hasData
          ? remote is GuestDataSyncTarget
                ? await (remote as GuestDataSyncTarget).syncGuestData(snapshot)
                : throw const NotesPersistenceFailure()
          : const GuestDataSyncResult(listsImported: 0, notesImported: 0);
      if (hasAppearanceData && remote is AggregateBoardAppearancesRepository) {
        final target = remote as AggregateBoardAppearancesRepository;
        for (final scope in AggregateBoardScope.values) {
          final appearance = localAppearances.forScope(scope);
          if (appearance != const ListAppearance()) {
            await target.updateAggregateBoardAppearance(scope, appearance);
          }
        }
      }
      await (local as LocalNotesDataCleaner).clearLocalData();
      _events.add(
        GuestDataSyncCompleted(
          listsImported: result.listsImported,
          notesImported: result.notesImported,
        ),
      );
    } on Object {
      _events.add(const GuestDataSyncFailed());
    }
  }

  Future<T> _whenReady<T>(
    Future<T> Function(NotesRepository repository) action,
  ) async {
    await _authTransition;
    return action(_activeRepository);
  }

  @override
  void dispose() {
    unawaited(_authSubscription.cancel());
    unawaited(_localSubscription.cancel());
    unawaited(_remoteSubscription.cancel());
    localRepository.dispose();
    remoteRepository.dispose();
    unawaited(_events.close());
  }
}
