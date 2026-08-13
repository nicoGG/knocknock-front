import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/data/selected_list_store.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/logic/notes_error_message.dart';
import 'package:nocknock/features/notes/logic/notes_state.dart';

class NotesCubit extends Cubit<NotesState> {
  NotesCubit(this._repository, {SelectedListStore? selectedListStore})
    : _selectedListStore =
          selectedListStore ?? SharedPreferencesSelectedListStore(),
      super(const NotesState());

  final NotesRepository _repository;
  final SelectedListStore _selectedListStore;
  StreamSubscription<NotesRealtimeEvent>? _realtimeSubscription;
  int _loadGeneration = 0;
  static const _notesPageSize = 40;

  Future<void> load() async {
    unawaited(_refreshOfflineSyncSummary());
    final generation = ++_loadGeneration;
    emit(
      state.copyWith(
        status: NotesStatus.loading,
        lists: const [],
        selectedListId: 'home',
        notes: const [],
        pinnedNotes: const [],
        reminderNotes: const [],
        aggregateBoardAppearances: const AggregateBoardAppearances(),
        isLoadingPinned: false,
        isLoadingReminderNotes: false,
        isLoadingMoreNotes: false,
        hasMoreNotes: false,
        clearNextNotesCursor: true,
      ),
    );
    _realtimeSubscription ??= _repository.realtimeEvents.listen(_onRealtime);
    final rememberedListId = await _readRememberedListId();
    final cached = await _readCache();
    if (generation != _loadGeneration || isClosed) return;

    var didShowCache = false;
    if (cached != null && cached.lists.isNotEmpty) {
      final cachedListId = _resolveSelectedListId(
        cached.lists,
        rememberedListId,
      );
      final cachedNotes = cached.notesByBoard[cachedListId];
      if (cachedNotes != null) {
        didShowCache = true;
        emit(
          state.copyWith(
            status: NotesStatus.ready,
            lists: cached.lists,
            selectedListId: cachedListId,
            notes: _cachedInitialNotes(cachedNotes),
            aggregateBoardAppearances:
                cached.aggregateBoardAppearances ??
                state.aggregateBoardAppearances,
          ),
        );
      } else if (cached.aggregateBoardAppearances != null) {
        emit(
          state.copyWith(
            aggregateBoardAppearances: cached.aggregateBoardAppearances,
          ),
        );
      }
    }

    try {
      final lists = await _repository.fetchLists();
      if (generation != _loadGeneration || isClosed) return;
      final selectedListId = _resolveSelectedListId(lists, rememberedListId);
      unawaited(_rememberSelectedList(selectedListId));
      unawaited(_connectBestEffort(selectedListId));
      final notesFuture = _fetchNotesPage(selectedListId);
      final appearancesFuture = _fetchAggregateBoardAppearances();
      final notesPage = await notesFuture;
      final aggregateBoardAppearances = await appearancesFuture;
      if (generation != _loadGeneration || isClosed) return;
      emit(
        state.copyWith(
          status: NotesStatus.ready,
          lists: lists,
          selectedListId: selectedListId,
          notes: _sortedNotes(notesPage.items),
          nextNotesCursor: notesPage.nextCursor,
          clearNextNotesCursor: notesPage.nextCursor == null,
          hasMoreNotes: notesPage.hasMore,
          aggregateBoardAppearances:
              aggregateBoardAppearances ?? state.aggregateBoardAppearances,
        ),
      );
    } catch (error) {
      if (generation != _loadGeneration || isClosed) return;
      if (didShowCache) {
        emit(
          state.copyWith(
            status: NotesStatus.ready,
            message:
                'Mostrando las notas guardadas. No pudimos actualizar los cambios más recientes.',
          ),
        );
        return;
      }
      emit(
        state.copyWith(
          status: NotesStatus.failure,
          message: _friendlyMessage(error),
        ),
      );
    }
  }

  Future<void> selectList(String listId) async {
    if (listId == state.selectedListId) return;
    final generation = ++_loadGeneration;
    emit(
      state.copyWith(
        status: NotesStatus.loading,
        selectedListId: listId,
        notes: const [],
        isLoadingMoreNotes: false,
        hasMoreNotes: false,
        clearNextNotesCursor: true,
      ),
    );
    unawaited(_rememberSelectedList(listId));
    unawaited(_connectBestEffort(listId));

    var didShowCache = false;
    final cached = await _readCache();
    if (generation != _loadGeneration || isClosed) return;
    final cachedNotes = cached?.notesByBoard[listId];
    if (cachedNotes != null) {
      didShowCache = true;
      emit(
        state.copyWith(
          status: NotesStatus.ready,
          notes: _cachedInitialNotes(cachedNotes),
        ),
      );
    }

    try {
      final notesPage = await _fetchNotesPage(listId);
      if (generation != _loadGeneration ||
          state.selectedListId != listId ||
          isClosed) {
        return;
      }
      emit(
        state.copyWith(
          status: NotesStatus.ready,
          notes: _sortedNotes(notesPage.items),
          nextNotesCursor: notesPage.nextCursor,
          clearNextNotesCursor: notesPage.nextCursor == null,
          hasMoreNotes: notesPage.hasMore,
        ),
      );
    } catch (error) {
      if (generation != _loadGeneration ||
          state.selectedListId != listId ||
          isClosed) {
        return;
      }
      if (didShowCache) {
        emit(
          state.copyWith(
            status: NotesStatus.ready,
            message:
                'Mostrando las notas guardadas. No pudimos actualizar los cambios más recientes.',
          ),
        );
        return;
      }
      emit(
        state.copyWith(
          status: NotesStatus.failure,
          message: _friendlyMessage(error),
        ),
      );
    }
  }

  Future<void> loadPinnedNotes() async {
    if (state.isLoadingPinned) return;
    emit(state.copyWith(isLoadingPinned: true));
    try {
      final pinnedNotes = await _repository.fetchPinnedNotes()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      emit(state.copyWith(pinnedNotes: pinnedNotes, isLoadingPinned: false));
    } catch (error) {
      emit(
        state.copyWith(
          isLoadingPinned: false,
          message: _friendlyMessage(error),
        ),
      );
    }
  }

  Future<void> loadMoreNotes() async {
    final repository = _repository;
    final cursor = state.nextNotesCursor;
    if (repository is! PaginatedNotesRepository ||
        state.status != NotesStatus.ready ||
        state.isLoadingMoreNotes ||
        !state.hasMoreNotes ||
        cursor == null) {
      return;
    }
    final listId = state.selectedListId;
    final generation = _loadGeneration;
    emit(state.copyWith(isLoadingMoreNotes: true));
    try {
      final page = await (repository as PaginatedNotesRepository)
          .fetchNotesPage(listId, cursor: cursor, limit: _notesPageSize);
      if (generation != _loadGeneration ||
          state.selectedListId != listId ||
          isClosed) {
        return;
      }
      final merged = {
        for (final note in state.notes) note.id: note,
        for (final note in page.items) note.id: note,
      };
      emit(
        state.copyWith(
          notes: _sortedNotes(merged.values),
          isLoadingMoreNotes: false,
          hasMoreNotes: page.hasMore,
          nextNotesCursor: page.nextCursor,
          clearNextNotesCursor: page.nextCursor == null,
        ),
      );
    } catch (error) {
      if (generation == _loadGeneration &&
          state.selectedListId == listId &&
          !isClosed) {
        emit(
          state.copyWith(
            isLoadingMoreNotes: false,
            message: _friendlyMessage(error),
          ),
        );
      }
    }
  }

  Future<void> loadReminderNotes() async {
    if (state.isLoadingReminderNotes) return;
    emit(state.copyWith(isLoadingReminderNotes: true));
    try {
      final reminderNotes = await _repository.fetchReminderNotes()
        ..sort(_compareReminderNotes);
      emit(
        state.copyWith(
          reminderNotes: reminderNotes,
          isLoadingReminderNotes: false,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          isLoadingReminderNotes: false,
          message: _friendlyMessage(error),
        ),
      );
    }
  }

  Future<void> createList(String name) async {
    emit(state.copyWith(isSavingList: true));
    try {
      final list = await _repository.createList(name);
      final lists = [...state.lists, list];
      emit(
        state.copyWith(
          status: NotesStatus.loading,
          lists: lists,
          selectedListId: list.id,
          notes: const [],
          isSavingList: false,
          isLoadingMoreNotes: false,
          hasMoreNotes: false,
          clearNextNotesCursor: true,
        ),
      );
      await _rememberSelectedList(list.id);
      await _repository.connect(list.id);
      final notesPage = await _fetchNotesPage(list.id);
      if (state.selectedListId != list.id) return;
      emit(
        state.copyWith(
          status: NotesStatus.ready,
          notes: notesPage.items,
          nextNotesCursor: notesPage.nextCursor,
          clearNextNotesCursor: notesPage.nextCursor == null,
          hasMoreNotes: notesPage.hasMore,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(isSavingList: false, message: _friendlyMessage(error)),
      );
    }
  }

  Future<bool> reorderLists(List<String> orderedIds) async {
    final previous = List<NoteList>.of(state.lists);
    final existingIds = previous.map((list) => list.id).toSet();
    if (orderedIds.length != previous.length ||
        orderedIds.toSet().length != orderedIds.length ||
        !existingIds.containsAll(orderedIds)) {
      return false;
    }
    if (_sameOrder(previous.map((list) => list.id), orderedIds)) return true;

    final listsById = {for (final list in previous) list.id: list};
    final optimistic = orderedIds.map((id) => listsById[id]!).toList();
    emit(state.copyWith(lists: optimistic, isSavingList: true));
    try {
      final saved = await _repository.reorderLists(orderedIds);
      if (saved.length != orderedIds.length ||
          !_sameOrder(saved.map((list) => list.id), orderedIds)) {
        throw const NotesPersistenceFailure();
      }
      emit(
        state.copyWith(
          lists: saved,
          isSavingList: false,
          message: 'Orden de listas actualizado.',
        ),
      );
      return true;
    } catch (error) {
      emit(
        state.copyWith(
          lists: previous,
          isSavingList: false,
          message: _friendlyMessage(error),
        ),
      );
      return false;
    }
  }

  Future<bool> updateSelectedList(String name) async {
    final selected = state.selectedList;
    final normalizedName = name.trim();
    if (selected == null || normalizedName.isEmpty) return false;
    if (selected.name == normalizedName) return true;
    emit(state.copyWith(isSavingList: true));
    try {
      final updated = await _repository.updateList(selected.id, normalizedName);
      emit(
        state.copyWith(
          lists: _replaceList(updated),
          isSavingList: false,
          message: 'Nombre de la lista actualizado.',
        ),
      );
      return true;
    } catch (error) {
      emit(
        state.copyWith(isSavingList: false, message: _friendlyMessage(error)),
      );
      return false;
    }
  }

  Future<bool> deleteSelectedList() async {
    final selected = state.selectedList;
    if (selected == null) return false;
    emit(state.copyWith(isSavingList: true));
    try {
      await _repository.deleteList(selected.id);
      var remaining = state.lists
          .where((list) => list.id != selected.id)
          .toList();
      if (remaining.isEmpty) {
        final replacement = await _repository.createList('Mis notas');
        remaining = [replacement];
      }
      final nextList = remaining.first;
      emit(
        state.copyWith(
          status: NotesStatus.loading,
          lists: remaining,
          selectedListId: nextList.id,
          notes: const [],
          pinnedNotes: state.pinnedNotes
              .where((note) => note.boardId != selected.id)
              .toList(),
          reminderNotes: state.reminderNotes
              .where((note) => note.boardId != selected.id)
              .toList(),
          isSavingList: false,
          isLoadingMoreNotes: false,
          hasMoreNotes: false,
          clearNextNotesCursor: true,
          message: 'Lista eliminada.',
        ),
      );
      await _rememberSelectedList(nextList.id);
      await _repository.connect(nextList.id);
      final notesPage = await _fetchNotesPage(nextList.id);
      if (state.selectedListId == nextList.id) {
        emit(
          state.copyWith(
            status: NotesStatus.ready,
            notes: notesPage.items,
            nextNotesCursor: notesPage.nextCursor,
            clearNextNotesCursor: notesPage.nextCursor == null,
            hasMoreNotes: notesPage.hasMore,
          ),
        );
      }
      return true;
    } catch (error) {
      emit(
        state.copyWith(isSavingList: false, message: _friendlyMessage(error)),
      );
      return false;
    }
  }

  Future<bool> inviteCollaborator(String email) async {
    emit(state.copyWith(isInviting: true));
    try {
      final updated = await _repository.inviteCollaborator(
        state.selectedListId,
        email.trim(),
      );
      final lists = state.lists
          .map((list) => list.id == updated.id ? updated : list)
          .toList();
      emit(
        state.copyWith(
          lists: lists,
          isInviting: false,
          message: 'Invitación enviada a ${email.trim().toLowerCase()}.',
        ),
      );
      return true;
    } catch (error) {
      emit(state.copyWith(isInviting: false, message: _friendlyMessage(error)));
      return false;
    }
  }

  Future<bool> removeCollaborator(String collaboratorUid) async {
    final collaborator = state.selectedList?.collaborators
        .where((person) => person.uid == collaboratorUid)
        .firstOrNull;
    if (collaborator == null || collaborator.role == ListMemberRole.owner) {
      return false;
    }

    emit(state.copyWith(isRemovingCollaborator: true));
    try {
      final updated = await _repository.removeCollaborator(
        state.selectedListId,
        collaboratorUid,
      );
      emit(
        state.copyWith(
          lists: _replaceList(updated),
          isRemovingCollaborator: false,
          message: '${collaborator.displayName} ya no tiene acceso.',
        ),
      );
      return true;
    } catch (error) {
      emit(
        state.copyWith(
          isRemovingCollaborator: false,
          message: _friendlyMessage(error),
        ),
      );
      return false;
    }
  }

  Future<bool> updateListAppearance(ListAppearance appearance) async {
    final previous = state.selectedList;
    if (previous == null || previous.appearance == appearance) return true;

    final optimistic = previous.copyWith(appearance: appearance);
    emit(
      state.copyWith(lists: _replaceList(optimistic), isSavingAppearance: true),
    );
    try {
      final updated = await _repository.updateListAppearance(
        previous.id,
        appearance,
      );
      emit(
        state.copyWith(
          lists: _replaceList(updated),
          isSavingAppearance: false,
          message: 'Fondo de la lista actualizado.',
        ),
      );
      return true;
    } catch (error) {
      emit(
        state.copyWith(
          lists: _replaceList(previous),
          isSavingAppearance: false,
          message: _friendlyMessage(error),
        ),
      );
      return false;
    }
  }

  Future<bool> updateAggregateBoardAppearance(
    AggregateBoardScope scope,
    ListAppearance appearance,
  ) async {
    final repository = _repository;
    if (repository is! AggregateBoardAppearancesRepository) return false;
    final previous = state.aggregateBoardAppearances;
    if (previous.forScope(scope) == appearance) return true;

    emit(
      state.copyWith(
        aggregateBoardAppearances: previous.copyWithScope(scope, appearance),
        isSavingAppearance: true,
      ),
    );
    try {
      final updated = await (repository as AggregateBoardAppearancesRepository)
          .updateAggregateBoardAppearance(scope, appearance);
      emit(
        state.copyWith(
          aggregateBoardAppearances: updated,
          isSavingAppearance: false,
          message: 'Fondo sincronizado con tu cuenta.',
        ),
      );
      return true;
    } catch (error) {
      emit(
        state.copyWith(
          aggregateBoardAppearances: previous,
          isSavingAppearance: false,
          message: _friendlyMessage(error),
        ),
      );
      return false;
    }
  }

  List<NoteList> _replaceList(NoteList updated) => state.lists
      .map((list) => list.id == updated.id ? updated : list)
      .toList();

  String _resolveSelectedListId(
    List<NoteList> lists,
    String? rememberedListId,
  ) {
    bool exists(String? id) => id != null && lists.any((list) => list.id == id);

    if (exists(rememberedListId)) return rememberedListId!;
    if (exists(state.selectedListId)) return state.selectedListId;
    return lists.firstOrNull?.id ?? 'home';
  }

  Future<String?> _readRememberedListId() async {
    try {
      return await _selectedListStore.read();
    } catch (_) {
      return null;
    }
  }

  Future<void> _rememberSelectedList(String listId) async {
    try {
      await _selectedListStore.write(listId);
    } catch (_) {
      // The selected list still works when local preference storage is
      // temporarily unavailable.
    }
  }

  Future<NotesCacheSnapshot?> _readCache() async {
    final repository = _repository;
    if (repository is! NotesCacheReader) return null;
    try {
      return await (repository as NotesCacheReader).readCache();
    } on Object {
      return null;
    }
  }

  Future<NotesPage> _fetchNotesPage(String boardId) async {
    final repository = _repository;
    if (repository is PaginatedNotesRepository) {
      return (repository as PaginatedNotesRepository).fetchNotesPage(
        boardId,
        limit: _notesPageSize,
      );
    }
    return NotesPage(
      items: await repository.fetchNotes(boardId),
      nextCursor: null,
    );
  }

  List<Note> _cachedInitialNotes(List<Note> notes) {
    final sorted = _sortedNotes(notes);
    if (_repository is! PaginatedNotesRepository) return sorted;
    return sorted.take(_notesPageSize).toList();
  }

  Future<AggregateBoardAppearances?> _fetchAggregateBoardAppearances() async {
    final repository = _repository;
    if (repository is! AggregateBoardAppearancesRepository) return null;
    try {
      return await (repository as AggregateBoardAppearancesRepository)
          .fetchAggregateBoardAppearances();
    } on Object {
      return null;
    }
  }

  Future<void> _connectBestEffort(String listId) async {
    try {
      await _repository.connect(listId);
    } on Object {
      // REST data and the device cache remain usable while realtime reconnects.
    }
  }

  List<Note> _sortedNotes(Iterable<Note> notes) =>
      List<Note>.of(notes)..sort(compareNotes);

  Future<void> createNote(NoteDraft draft) async {
    emit(state.copyWith(isSaving: true));
    try {
      _upsert(await _repository.createNote(state.selectedListId, draft));
    } catch (error) {
      emit(state.copyWith(message: _friendlyMessage(error)));
    } finally {
      emit(state.copyWith(isSaving: false));
    }
  }

  Future<void> editNote(Note note, NoteDraft draft) async {
    emit(state.copyWith(isSaving: true));
    try {
      _upsert(
        await _repository.updateNote(note.id, {
          'title': draft.title,
          'content': draft.content,
          'contentDelta': draft.contentDelta,
          'color': draft.color.name,
          'category': draft.category.name,
          'checklist': draft.checklist.map((item) => item.toJson()).toList(),
          'authorName': draft.authorName,
          if (draft.assigneeUid != note.assigneeUid ||
              draft.customAssigneeName != note.customAssigneeName) ...{
            'assigneeUid': draft.assigneeUid,
            'customAssigneeName': draft.customAssigneeName,
          },
          if (!listEquals(draft.photoAttachments, note.photoAttachments))
            'attachments': draft.photoAttachments
                .map((entry) => entry.toJson())
                .toList(),
          'reminderAt': draft.reminderAt?.toIso8601String(),
        }),
      );
    } catch (error) {
      emit(state.copyWith(message: _friendlyMessage(error)));
    } finally {
      emit(state.copyWith(isSaving: false));
    }
  }

  Future<void> updateNoteContent(
    Note note,
    String content, [
    String? contentDelta,
  ]) => _updateNoteFields(note, {
    'content': content,
    'contentDelta': ?contentDelta,
  });

  Future<void> updateNoteTitle(Note note, String title) =>
      _updateNoteFields(note, {'title': title});

  Future<void> updateNoteColor(Note note, NoteColor color) =>
      _updateNoteFields(note, {'color': color.name});

  Future<void> updateNoteCategory(Note note, NoteCategory category) =>
      _updateNoteFields(note, {'category': category.name});

  Future<void> updateNoteReminder(Note note, DateTime? reminderAt) =>
      _updateNoteFields(note, {'reminderAt': reminderAt?.toIso8601String()});

  Future<void> updateNoteAssignee(
    Note note, {
    String? assigneeUid,
    String? customAssigneeName,
  }) => _updateNoteFields(note, {
    'assigneeUid': assigneeUid,
    'customAssigneeName': customAssigneeName,
  });

  Future<NoteAttachment> loadAttachment(Note note, String attachmentId) async {
    final repository = _repository;
    if (repository is! NoteAttachmentsRepository ||
        !note.photoAttachments.any((entry) => entry.id == attachmentId)) {
      throw const NotesPersistenceFailure();
    }
    return (repository as NoteAttachmentsRepository).fetchAttachment(
      note.id,
      attachmentId,
    );
  }

  Future<void> toggleReaction(
    Note note,
    String emoji,
    String? currentUserId,
  ) async {
    if (!supportedNoteReactionEmojis.contains(emoji)) return;
    final userUid = currentUserId ?? localNoteReactionUserId;
    final reactions = [...note.reactions];
    final reactionIndex = reactions.indexWhere(
      (reaction) => reaction.emoji == emoji,
    );
    final userUids = reactionIndex == -1
        ? <String>{}
        : reactions[reactionIndex].userUids.toSet();
    final active = !userUids.contains(userUid);
    if (active) {
      userUids.add(userUid);
    } else {
      userUids.remove(userUid);
    }
    if (userUids.isEmpty) {
      if (reactionIndex != -1) reactions.removeAt(reactionIndex);
    } else {
      final reaction = NoteReaction(
        emoji: emoji,
        userUids: userUids.toList()..sort(),
      );
      if (reactionIndex == -1) {
        reactions.add(reaction);
      } else {
        reactions[reactionIndex] = reaction;
      }
    }
    reactions.sort(
      (a, b) => supportedNoteReactionEmojis
          .indexOf(a.emoji)
          .compareTo(supportedNoteReactionEmojis.indexOf(b.emoji)),
    );

    emit(state.copyWith(isSaving: true));
    _upsert(note.copyWith(reactions: reactions));
    try {
      _upsert(await _repository.setNoteReaction(note.id, emoji, active));
    } catch (error) {
      _upsert(note);
      emit(state.copyWith(message: _friendlyMessage(error)));
    } finally {
      emit(state.copyWith(isSaving: false));
    }
  }

  Future<void> toggleChecklistItem(Note note, NoteChecklistItem item) {
    final checklist = note.checklist
        .map(
          (current) => current.id == item.id
              ? current.copyWith(isCompleted: !current.isCompleted)
              : current,
        )
        .toList();
    return updateChecklist(note, checklist);
  }

  Future<void> updateChecklist(
    Note note,
    List<NoteChecklistItem> checklist,
  ) async {
    final normalized = normalizeNoteChecklist(checklist);
    final optimistic = note.copyWith(checklist: normalized);
    _upsert(optimistic);
    try {
      _upsert(
        await _repository.updateNote(note.id, {
          'checklist': normalized.map((item) => item.toJson()).toList(),
        }),
      );
    } catch (error) {
      _upsert(note);
      emit(state.copyWith(message: _friendlyMessage(error)));
    }
  }

  Future<void> _updateNoteFields(
    Note note,
    Map<String, dynamic> changes,
  ) async {
    emit(state.copyWith(isSaving: true));
    try {
      _upsert(await _repository.updateNote(note.id, changes));
    } catch (error) {
      emit(state.copyWith(message: _friendlyMessage(error)));
    } finally {
      emit(state.copyWith(isSaving: false));
    }
  }

  Future<void> toggleNote(Note note) async {
    final optimistic = note.copyWith(isCompleted: !note.isCompleted);
    _upsert(optimistic);
    try {
      _upsert(
        await _repository.updateNote(note.id, {
          'isCompleted': optimistic.isCompleted,
        }),
      );
    } catch (error) {
      _upsert(note);
      emit(state.copyWith(message: _friendlyMessage(error)));
    }
  }

  Future<void> togglePin(Note note) async {
    final targetPinned = !note.isPinned;
    final knownBoardNotes = state.selectedListId == note.boardId
        ? state.notes
        : state.pinnedNotes.where((item) => item.boardId == note.boardId);
    final targetOrders = knownBoardNotes
        .where((item) => item.id != note.id && item.isPinned == targetPinned)
        .map((item) => item.sortOrder);
    final targetOrder = !targetPinned && state.selectedListId != note.boardId
        ? note.sortOrder
        : targetOrders.isEmpty
        ? 0
        : targetOrders.reduce((a, b) => a < b ? a : b) - 1;
    final optimistic = note.copyWith(
      isPinned: targetPinned,
      sortOrder: targetOrder,
    );
    _upsert(optimistic);
    try {
      _upsert(
        await _repository.updateNote(note.id, {
          'isPinned': targetPinned,
          'sortOrder': targetOrder,
        }),
      );
    } catch (error) {
      _upsert(note);
      emit(state.copyWith(message: _friendlyMessage(error)));
    }
  }

  Future<void> reorderVisibleNotes(List<String> orderedVisibleIds) async {
    if (orderedVisibleIds.length < 2 ||
        orderedVisibleIds.toSet().length != orderedVisibleIds.length) {
      return;
    }

    final previous = [...state.notes]..sort(compareNotes);
    final notesById = {for (final note in previous) note.id: note};
    if (orderedVisibleIds.any((id) => !notesById.containsKey(id))) return;

    final visibleIds = orderedVisibleIds.toSet();
    final reordered = [...previous];
    var visibleIndex = 0;
    for (var index = 0; index < reordered.length; index++) {
      if (visibleIds.contains(reordered[index].id)) {
        reordered[index] = notesById[orderedVisibleIds[visibleIndex++]]!;
      }
    }

    var foundUnpinned = false;
    for (final note in reordered) {
      if (!note.isPinned) {
        foundUnpinned = true;
      } else if (foundUnpinned) {
        emit(
          state.copyWith(
            message:
                'Para moverla a esa sección, primero ancla o desancla la nota.',
          ),
        );
        return;
      }
    }

    final optimistic = [
      for (var index = 0; index < reordered.length; index++)
        reordered[index].copyWith(sortOrder: index),
    ];
    emit(state.copyWith(status: NotesStatus.ready, notes: optimistic));

    try {
      final saved = await _repository.reorderNotes(
        state.selectedListId,
        optimistic.map((note) => note.id).toList(),
      );
      final sorted = [...saved]..sort(compareNotes);
      emit(state.copyWith(status: NotesStatus.ready, notes: sorted));
    } catch (error) {
      emit(
        state.copyWith(
          status: NotesStatus.ready,
          notes: previous,
          message: _friendlyMessage(error),
        ),
      );
    }
  }

  Future<void> deleteNote(Note note) async {
    _remove(note.id);
    try {
      await _repository.deleteNote(note.id, expectedRevision: note.revision);
    } catch (error) {
      _upsert(note);
      emit(state.copyWith(message: _friendlyMessage(error)));
    }
  }

  Future<bool> clearLocalData() async {
    final repository = _repository;
    if (repository is! LocalNotesDataCleaner) return false;

    emit(state.copyWith(isSaving: true));
    try {
      final cleaner = repository as LocalNotesDataCleaner;
      await cleaner.clearLocalData();
      if (cleaner.isLocalDataActive) await load();
      return true;
    } catch (_) {
      return false;
    } finally {
      emit(state.copyWith(isSaving: false));
    }
  }

  Future<List<NoteSearchResult>> searchNotes(String query) async {
    final repository = _repository;
    if (repository is! NotesSearchRepository || query.trim().isEmpty) {
      return const [];
    }
    return (repository as NotesSearchRepository).searchNotes(query.trim());
  }

  Future<List<NoteSyncConflict>> fetchSyncConflicts() async {
    final repository = _repository;
    if (repository is! OfflineSyncRepository) return const [];
    return (repository as OfflineSyncRepository).fetchNoteSyncConflicts();
  }

  Future<void> resolveSyncConflict(
    String mutationId,
    NoteConflictResolution resolution,
  ) async {
    final repository = _repository;
    if (repository is! OfflineSyncRepository) return;
    await (repository as OfflineSyncRepository).resolveNoteSyncConflict(
      mutationId,
      resolution,
    );
    await _refreshOfflineSyncSummary();
  }

  Future<void> retryOfflineSync() async {
    final repository = _repository;
    if (repository is! OfflineSyncRepository) return;
    try {
      await (repository as OfflineSyncRepository).syncPendingChanges();
      await _refreshOfflineSyncSummary();
    } on Object {
      if (!isClosed) {
        emit(
          state.copyWith(
            message:
                'No pudimos sincronizar todavía. Tus cambios siguen guardados en este dispositivo.',
          ),
        );
      }
    }
  }

  Future<void> _refreshOfflineSyncSummary() async {
    final repository = _repository;
    if (repository is! OfflineSyncRepository) return;
    try {
      final summary = await (repository as OfflineSyncRepository)
          .offlineSyncSummary();
      if (isClosed) return;
      emit(
        state.copyWith(
          pendingSyncCount: summary.pendingCount,
          syncConflictCount: summary.conflictCount,
          isSyncingOfflineChanges: summary.isSyncing,
        ),
      );
    } on Object {
      // Loading the board remains usable even if the local sync index fails.
    }
  }

  void _onRealtime(NotesRealtimeEvent event) {
    switch (event) {
      case NoteChanged(:final note):
        if (note.boardId == state.selectedListId ||
            note.isPinned ||
            note.reminderAt != null ||
            state.pinnedNotes.any((item) => item.id == note.id) ||
            state.reminderNotes.any((item) => item.id == note.id)) {
          _upsert(note);
        }
      case NoteRemoved(:final id, :final boardId):
        if (boardId == state.selectedListId ||
            state.pinnedNotes.any((note) => note.id == id) ||
            state.reminderNotes.any((note) => note.id == id)) {
          _remove(id);
        }
      case NotesReordered(:final boardId, :final notes):
        if (boardId == state.selectedListId) {
          final sorted = [...notes]..sort(compareNotes);
          emit(state.copyWith(status: NotesStatus.ready, notes: sorted));
        }
      case ListAppearanceChanged(:final listId, :final appearance):
        final index = state.lists.indexWhere((list) => list.id == listId);
        if (index != -1) {
          emit(
            state.copyWith(
              lists: _replaceList(
                state.lists[index].copyWith(appearance: appearance),
              ),
            ),
          );
        }
      case ListNameChanged(:final listId, :final name, :final updatedAt):
        final index = state.lists.indexWhere((list) => list.id == listId);
        if (index != -1) {
          emit(
            state.copyWith(
              lists: _replaceList(
                state.lists[index].copyWith(name: name, updatedAt: updatedAt),
              ),
            ),
          );
        }
      case AggregateBoardAppearanceChanged(:final scope, :final appearance):
        emit(
          state.copyWith(
            aggregateBoardAppearances: state.aggregateBoardAppearances
                .copyWithScope(scope, appearance),
          ),
        );
      case ListAccessRemoved(:final listId):
        if (state.lists.any((list) => list.id == listId)) {
          unawaited(_refreshAfterAccessRemoved());
        }
      case ListKeyShareRequested():
        break;
      case ListKeyEnvelopeUpdated():
        unawaited(load());
      case RealtimeConnectionChanged(:final isConnected):
        emit(
          state.copyWith(
            isRealtimeConnected: isConnected,
            isRealtimeConnecting: false,
          ),
        );
      case RealtimeConnectionAttemptStarted():
        emit(
          state.copyWith(
            isRealtimeConnected: false,
            isRealtimeConnecting: true,
          ),
        );
      case NotesSourceChanged():
        unawaited(load());
      case GuestDataSyncStarted():
        emit(
          state.copyWith(message: 'Estamos guardando tus notas en tu cuenta…'),
        );
      case GuestDataSyncCompleted(:final listsImported, :final notesImported):
        final total = listsImported + notesImported;
        emit(
          state.copyWith(
            message: total == 1
                ? 'Tu contenido local ya está guardado en tu cuenta.'
                : total > 1
                ? 'Tus $total elementos locales ya están guardados en tu cuenta.'
                : 'Tus datos locales ya están guardados en tu cuenta.',
          ),
        );
      case GuestDataSyncFailed():
        emit(
          state.copyWith(
            message:
                'No pudimos sincronizar tus notas locales. Siguen seguras en este dispositivo y volveremos a intentarlo.',
          ),
        );
      case OfflineSyncStateChanged(
        :final pendingCount,
        :final conflictCount,
        :final isSyncing,
      ):
        emit(
          state.copyWith(
            pendingSyncCount: pendingCount,
            syncConflictCount: conflictCount,
            isSyncingOfflineChanges: isSyncing,
          ),
        );
      case OfflineSyncOperationDiscarded(:final message):
        emit(state.copyWith(message: message));
    }
  }

  Future<void> _refreshAfterAccessRemoved() async {
    await load();
    if (!isClosed && state.status == NotesStatus.ready) {
      emit(
        state.copyWith(
          message: 'Ya no tienes acceso a una de las listas compartidas.',
        ),
      );
    }
  }

  void _upsert(Note note) {
    final notes = [...state.notes];
    if (note.boardId == state.selectedListId) {
      final index = notes.indexWhere((item) => item.id == note.id);
      if (index == -1) {
        notes.insert(0, note);
      } else {
        notes[index] = note;
      }
      notes.sort(compareNotes);
    }

    final pinnedNotes = [...state.pinnedNotes];
    final pinnedIndex = pinnedNotes.indexWhere((item) => item.id == note.id);
    if (note.isPinned) {
      if (pinnedIndex == -1) {
        pinnedNotes.insert(0, note);
      } else {
        pinnedNotes[pinnedIndex] = note;
      }
    } else if (pinnedIndex != -1) {
      pinnedNotes.removeAt(pinnedIndex);
    }
    pinnedNotes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final reminderNotes = [...state.reminderNotes];
    final reminderIndex = reminderNotes.indexWhere(
      (item) => item.id == note.id,
    );
    if (note.reminderAt != null) {
      if (reminderIndex == -1) {
        reminderNotes.add(note);
      } else {
        reminderNotes[reminderIndex] = note;
      }
    } else if (reminderIndex != -1) {
      reminderNotes.removeAt(reminderIndex);
    }
    reminderNotes.sort(_compareReminderNotes);

    emit(
      state.copyWith(
        status: NotesStatus.ready,
        notes: notes,
        pinnedNotes: pinnedNotes,
        reminderNotes: reminderNotes,
      ),
    );
  }

  void _remove(String id) {
    emit(
      state.copyWith(
        notes: state.notes.where((note) => note.id != id).toList(),
        pinnedNotes: state.pinnedNotes.where((note) => note.id != id).toList(),
        reminderNotes: state.reminderNotes
            .where((note) => note.id != id)
            .toList(),
      ),
    );
  }

  String _friendlyMessage(Object error) {
    if (error is NotesPersistenceFailure) {
      return 'No pudimos guardar los cambios en este dispositivo.';
    }
    if (error is CollaborationRequiresSignInFailure) {
      return 'Inicia sesión con Google para invitar colaboradores.';
    }
    return notesErrorMessage(error);
  }

  @override
  Future<void> close() async {
    await _realtimeSubscription?.cancel();
    _repository.dispose();
    return super.close();
  }
}

int _compareReminderNotes(Note a, Note b) {
  final byReminder = a.reminderAt!.compareTo(b.reminderAt!);
  return byReminder != 0 ? byReminder : b.updatedAt.compareTo(a.updatedAt);
}

bool _sameOrder(Iterable<String> current, List<String> expected) {
  var index = 0;
  for (final id in current) {
    if (index >= expected.length || id != expected[index]) return false;
    index++;
  }
  return index == expected.length;
}
