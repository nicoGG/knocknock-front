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

class ListAccessRemoved extends NotesRealtimeEvent {
  const ListAccessRemoved(this.listId);

  final String listId;
}

class RealtimeConnectionChanged extends NotesRealtimeEvent {
  const RealtimeConnectionChanged(this.isConnected);
  final bool isConnected;
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

class NotesPersistenceFailure implements Exception {
  const NotesPersistenceFailure();
}

class CollaborationRequiresSignInFailure implements Exception {
  const CollaborationRequiresSignInFailure();
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

  Future<void> deleteList(String listId);

  Future<NoteList> inviteCollaborator(String listId, String email);

  Future<NoteList> removeCollaborator(String listId, String collaboratorUid);

  Future<NoteList> updateListAppearance(
    String listId,
    ListAppearance appearance,
  );

  Future<List<Note>> fetchNotes(String boardId);

  Future<List<Note>> fetchPinnedNotes();

  Future<Note> createNote(String boardId, NoteDraft draft);

  Future<Note> updateNote(String id, Map<String, dynamic> changes);

  Future<List<Note>> reorderNotes(String boardId, List<String> orderedIds);

  Future<void> deleteNote(String id);

  void dispose();
}
