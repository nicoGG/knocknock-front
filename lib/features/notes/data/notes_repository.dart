import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';

sealed class NotesRealtimeEvent {
  const NotesRealtimeEvent();
}

class NoteChanged extends NotesRealtimeEvent {
  const NoteChanged(this.note);
  final Note note;
}

class NoteRemoved extends NotesRealtimeEvent {
  const NoteRemoved(this.id, this.boardId);
  final String id;
  final String boardId;
}

class NotesReordered extends NotesRealtimeEvent {
  const NotesReordered(this.boardId, this.notes);
  final String boardId;
  final List<Note> notes;
}

class ListAppearanceChanged extends NotesRealtimeEvent {
  const ListAppearanceChanged(this.listId, this.appearance);

  final String listId;
  final ListAppearance appearance;
}

class ListNameChanged extends NotesRealtimeEvent {
  const ListNameChanged(this.listId, this.name, this.updatedAt);

  final String listId;
  final String name;
  final DateTime updatedAt;
}

class AggregateBoardAppearanceChanged extends NotesRealtimeEvent {
  const AggregateBoardAppearanceChanged(this.scope, this.appearance);

  final AggregateBoardScope scope;
  final ListAppearance appearance;
}

class ListAccessRemoved extends NotesRealtimeEvent {
  const ListAccessRemoved(this.listId);

  final String listId;
}

class ListKeyShareRequested extends NotesRealtimeEvent {
  const ListKeyShareRequested(this.listId);

  final String listId;
}

class ListKeyEnvelopeUpdated extends NotesRealtimeEvent {
  const ListKeyEnvelopeUpdated(this.listId);

  final String listId;
}

class RealtimeConnectionChanged extends NotesRealtimeEvent {
  const RealtimeConnectionChanged(this.isConnected);
  final bool isConnected;
}

class RealtimeConnectionAttemptStarted extends NotesRealtimeEvent {
  const RealtimeConnectionAttemptStarted();
}

class OfflineSyncStateChanged extends NotesRealtimeEvent {
  const OfflineSyncStateChanged({
    required this.pendingCount,
    required this.conflictCount,
    required this.isSyncing,
  });

  final int pendingCount;
  final int conflictCount;
  final bool isSyncing;
}

class OfflineSyncOperationDiscarded extends NotesRealtimeEvent {
  const OfflineSyncOperationDiscarded(this.message);

  final String message;
}

class NotesSourceChanged extends NotesRealtimeEvent {
  const NotesSourceChanged();
}

class GuestDataSyncStarted extends NotesRealtimeEvent {
  const GuestDataSyncStarted();
}

class GuestDataSyncCompleted extends NotesRealtimeEvent {
  const GuestDataSyncCompleted({
    required this.listsImported,
    required this.notesImported,
  });

  final int listsImported;
  final int notesImported;
}

class GuestDataSyncFailed extends NotesRealtimeEvent {
  const GuestDataSyncFailed();
}

class NotesCacheSnapshot {
  const NotesCacheSnapshot({
    required this.lists,
    required this.notesByBoard,
    this.aggregateBoardAppearances,
    this.fullyLoadedBoardIds = const {},
  });

  final List<NoteList> lists;
  final Map<String, List<Note>> notesByBoard;
  final AggregateBoardAppearances? aggregateBoardAppearances;
  final Set<String> fullyLoadedBoardIds;
}

/// Optional capability for repositories that can serve account data from a
/// device cache before refreshing it from the network.
abstract interface class NotesCacheReader {
  Future<NotesCacheSnapshot?> readCache();
}

abstract interface class AggregateBoardAppearancesRepository {
  Future<AggregateBoardAppearances> fetchAggregateBoardAppearances();

  Future<AggregateBoardAppearances> updateAggregateBoardAppearance(
    AggregateBoardScope scope,
    ListAppearance appearance,
  );
}

class NotesPersistenceFailure implements Exception {
  const NotesPersistenceFailure();
}

enum NoteConflictResolution { keepLocal, keepRemote }

enum OfflineMutationKind { create, update, delete, reaction, reorder }

class NoteSyncConflict {
  const NoteSyncConflict({
    required this.mutationId,
    required this.kind,
    required this.localNote,
    required this.remoteNote,
  });

  final String mutationId;
  final OfflineMutationKind kind;
  final Note localNote;
  final Note remoteNote;
}

class OfflineSyncSummary {
  const OfflineSyncSummary({
    this.pendingCount = 0,
    this.conflictCount = 0,
    this.isSyncing = false,
  });

  final int pendingCount;
  final int conflictCount;
  final bool isSyncing;
}

abstract interface class OfflineSyncRepository {
  Future<OfflineSyncSummary> offlineSyncSummary();

  Future<void> syncPendingChanges();

  Future<List<NoteSyncConflict>> fetchNoteSyncConflicts();

  Future<void> resolveNoteSyncConflict(
    String mutationId,
    NoteConflictResolution resolution,
  );
}

class NoteSearchResult {
  const NoteSearchResult({required this.note, required this.list});

  final Note note;
  final NoteList list;
}

abstract interface class NotesSearchRepository {
  Future<List<NoteSearchResult>> searchNotes(String query);
}

class NotesPage {
  const NotesPage({required this.items, required this.nextCursor});

  final List<Note> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// Optional capability that lets large boards load progressively while older
/// repository implementations keep using [NotesRepository.fetchNotes].
abstract interface class PaginatedNotesRepository {
  Future<NotesPage> fetchNotesPage(
    String boardId, {
    String? cursor,
    int limit = 40,
  });
}

/// Optional capability for repositories that can lazily load encrypted file
/// bytes without adding them to every board response.
abstract interface class NoteAttachmentsRepository {
  Future<NoteAttachment> fetchAttachment(String noteId, String attachmentId);
}

class CollaborationRequiresSignInFailure implements Exception {
  const CollaborationRequiresSignInFailure();
}

class EncryptionKeyUnavailableFailure implements Exception {
  const EncryptionKeyUnavailableFailure();
}

class EncryptionRecipient {
  const EncryptionRecipient({
    required this.userUid,
    required this.deviceId,
    required this.publicKey,
    required this.hasEnvelope,
  });

  factory EncryptionRecipient.fromJson(Map<String, dynamic> json) =>
      EncryptionRecipient(
        userUid: json['userUid'] as String,
        deviceId: json['deviceId'] as String,
        publicKey: json['publicKey'] as String,
        hasEnvelope: json['hasEnvelope'] as bool? ?? false,
      );

  final String userUid;
  final String deviceId;
  final String publicKey;
  final bool hasEnvelope;
}

abstract interface class E2eeNotesTransport {
  Future<void> registerEncryptionDevice({
    required String deviceId,
    required String publicKey,
  });

  Future<NoteList> createEncryptedList({
    required String encryptedName,
    required ListKeyEnvelope keyEnvelope,
  });

  Future<NoteList> enableListEncryption({
    required String listId,
    required String encryptedName,
    required String? encryptedCustomBackgroundImage,
    required ListKeyEnvelope keyEnvelope,
  });

  Future<List<EncryptionRecipient>> fetchEncryptionRecipients(String listId);

  Future<void> storeListKeyEnvelope({
    required String listId,
    required String recipientUid,
    required String deviceId,
    required String envelope,
  });
}

/// Optional capability for repositories that own guest data on this device.
abstract interface class LocalNotesDataCleaner {
  bool get isLocalDataActive;

  Future<void> clearLocalData();
}

class LocalNotesSnapshot {
  const LocalNotesSnapshot({required this.lists, required this.notes});

  final List<NoteList> lists;
  final List<Note> notes;

  bool get hasData =>
      notes.isNotEmpty ||
      lists.any(
        (list) =>
            list.id != 'home' || list.appearance != const ListAppearance(),
      );
}

class GuestDataSyncResult {
  const GuestDataSyncResult({
    required this.listsImported,
    required this.notesImported,
  });

  final int listsImported;
  final int notesImported;
}

abstract interface class LocalNotesDataReader {
  Future<LocalNotesSnapshot> readLocalData();
}

abstract interface class GuestDataSyncTarget {
  Future<GuestDataSyncResult> syncGuestData(LocalNotesSnapshot snapshot);
}

abstract interface class NotesRepository {
  Stream<NotesRealtimeEvent> get realtimeEvents;

  Future<void> connect(String boardId);

  void disconnect();

  Future<List<NoteList>> fetchLists();

  Future<NoteList> createList(String name);

  Future<NoteList> updateList(String listId, String name);

  Future<List<NoteList>> reorderLists(List<String> orderedIds);

  Future<void> deleteList(String listId);

  Future<NoteList> inviteCollaborator(String listId, String email);

  Future<NoteList> removeCollaborator(String listId, String collaboratorUid);

  Future<NoteList> updateListAppearance(
    String listId,
    ListAppearance appearance,
  );

  Future<List<Note>> fetchNotes(String boardId);

  Future<List<Note>> fetchPinnedNotes();

  Future<List<Note>> fetchReminderNotes();

  Future<Note> createNote(String boardId, NoteDraft draft);

  Future<Note> updateNote(String id, Map<String, dynamic> changes);

  Future<Note> setNoteReaction(String id, String emoji, bool active);

  Future<List<Note>> reorderNotes(String boardId, List<String> orderedIds);

  Future<void> deleteNote(
    String id, {
    int? expectedRevision,
    String? clientMutationId,
  });

  void dispose();
}
