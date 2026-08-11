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
  });

  final List<NoteList> lists;
  final Map<String, List<Note>> notesByBoard;
  final AggregateBoardAppearances? aggregateBoardAppearances;
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

  Future<void> deleteNote(String id);

  void dispose();
}
