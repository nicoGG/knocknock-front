import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/data/selected_list_store.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/logic/notes_state.dart';

class NotesCubit extends Cubit<NotesState> {
  NotesCubit(this._repository, {SelectedListStore? selectedListStore})
    : _selectedListStore =
          selectedListStore ?? SharedPreferencesSelectedListStore(),
      super(const NotesState());

  final NotesRepository _repository;
  final SelectedListStore _selectedListStore;
  StreamSubscription<NotesRealtimeEvent>? _realtimeSubscription;

  Future<void> load() async {
    emit(
      state.copyWith(
        status: NotesStatus.loading,
        pinnedNotes: const [],
        isLoadingPinned: false,
      ),
    );
    _realtimeSubscription ??= _repository.realtimeEvents.listen(_onRealtime);
    try {
      final lists = await _repository.fetchLists();
      final rememberedListId = await _readRememberedListId();
      final selectedListId = _resolveSelectedListId(lists, rememberedListId);
      await _rememberSelectedList(selectedListId);
      await _repository.connect(selectedListId);
      final notes = await _repository.fetchNotes(selectedListId);
      emit(
        state.copyWith(
          status: NotesStatus.ready,
          lists: lists,
          selectedListId: selectedListId,
          notes: notes,
        ),
      );
    } catch (error) {
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
    emit(
      state.copyWith(
        status: NotesStatus.loading,
        selectedListId: listId,
        notes: const [],
      ),
    );
    await _rememberSelectedList(listId);
    await _repository.connect(listId);
    try {
      final notes = await _repository.fetchNotes(listId);
      if (state.selectedListId != listId) return;
      emit(state.copyWith(status: NotesStatus.ready, notes: notes));
    } catch (error) {
      if (state.selectedListId != listId) return;
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
        ),
      );
      await _rememberSelectedList(list.id);
      await _repository.connect(list.id);
      final notes = await _repository.fetchNotes(list.id);
      if (state.selectedListId != list.id) return;
      emit(state.copyWith(status: NotesStatus.ready, notes: notes));
    } catch (error) {
      emit(
        state.copyWith(isSavingList: false, message: _friendlyMessage(error)),
      );
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
          isSavingList: false,
          message: 'Lista eliminada.',
        ),
      );
      await _rememberSelectedList(nextList.id);
      await _repository.connect(nextList.id);
      final notes = await _repository.fetchNotes(nextList.id);
      if (state.selectedListId == nextList.id) {
        emit(state.copyWith(status: NotesStatus.ready, notes: notes));
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
          if (draft.assigneeUid != null || note.assigneeUid != null)
            'assigneeUid': draft.assigneeUid,
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

  Future<void> updateNoteColor(Note note, NoteColor color) =>
      _updateNoteFields(note, {'color': color.name});

  Future<void> updateNoteCategory(Note note, NoteCategory category) =>
      _updateNoteFields(note, {'category': category.name});

  Future<void> updateNoteReminder(Note note, DateTime? reminderAt) =>
      _updateNoteFields(note, {'reminderAt': reminderAt?.toIso8601String()});

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
      await _repository.deleteNote(note.id);
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

  void _onRealtime(NotesRealtimeEvent event) {
    switch (event) {
      case NoteChanged(:final note):
        if (note.boardId == state.selectedListId ||
            note.isPinned ||
            state.pinnedNotes.any((item) => item.id == note.id)) {
          _upsert(note);
        }
      case NoteRemoved(:final id, :final boardId):
        if (boardId == state.selectedListId ||
            state.pinnedNotes.any((note) => note.id == id)) {
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
      case ListAccessRemoved(:final listId):
        if (state.lists.any((list) => list.id == listId)) {
          unawaited(_refreshAfterAccessRemoved());
        }
      case RealtimeConnectionChanged(:final isConnected):
        emit(state.copyWith(isRealtimeConnected: isConnected));
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

    emit(
      state.copyWith(
        status: NotesStatus.ready,
        notes: notes,
        pinnedNotes: pinnedNotes,
      ),
    );
  }

  void _remove(String id) {
    emit(
      state.copyWith(
        notes: state.notes.where((note) => note.id != id).toList(),
        pinnedNotes: state.pinnedNotes.where((note) => note.id != id).toList(),
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
    if (error is DioException) {
      final status = error.response?.statusCode;
      final data = error.response?.data;
      final serverMessage = data is Map ? data['message'] : null;
      if (status == 401) {
        return 'Tu sesión venció. Inicia sesión nuevamente.';
      }
      if (status == 403) {
        return serverMessage is String
            ? serverMessage
            : 'No tienes permiso para modificar esta lista.';
      }
      if ((status == 409 || status == 503) && serverMessage is String) {
        return serverMessage;
      }
    }
    if (error is DioException && error.response?.statusCode == 400) {
      final data = error.response?.data;
      final serverMessage = data is Map ? data['message'] : null;
      return serverMessage is String
          ? serverMessage
          : 'Revisa los datos e inténtalo nuevamente.';
    }
    return 'No pudimos conectar con NockNock. Verifica que el backend esté encendido.';
  }

  @override
  Future<void> close() async {
    await _realtimeSubscription?.cancel();
    _repository.dispose();
    return super.close();
  }
}
