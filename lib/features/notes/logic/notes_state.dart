import 'package:equatable/equatable.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';

enum NotesStatus { initial, loading, ready, failure }

class NotesState extends Equatable {
  const NotesState({
    this.status = NotesStatus.initial,
    this.notes = const [],
    this.pinnedNotes = const [],
    this.reminderNotes = const [],
    this.aggregateBoardAppearances = const AggregateBoardAppearances(),
    this.lists = const [],
    this.selectedListId = 'home',
    this.isRealtimeConnected = false,
    this.isRealtimeConnecting = false,
    this.isSaving = false,
    this.isSavingList = false,
    this.isInviting = false,
    this.isRemovingCollaborator = false,
    this.isSavingAppearance = false,
    this.isLoadingPinned = false,
    this.isLoadingReminderNotes = false,
    this.isLoadingMoreNotes = false,
    this.hasMoreNotes = false,
    this.nextNotesCursor,
    this.pendingSyncCount = 0,
    this.syncConflictCount = 0,
    this.isSyncingOfflineChanges = false,
    this.message,
  });

  final NotesStatus status;
  final List<Note> notes;
  final List<Note> pinnedNotes;
  final List<Note> reminderNotes;
  final AggregateBoardAppearances aggregateBoardAppearances;
  final List<NoteList> lists;
  final String selectedListId;
  final bool isRealtimeConnected;
  final bool isRealtimeConnecting;
  final bool isSaving;
  final bool isSavingList;
  final bool isInviting;
  final bool isRemovingCollaborator;
  final bool isSavingAppearance;
  final bool isLoadingPinned;
  final bool isLoadingReminderNotes;
  final bool isLoadingMoreNotes;
  final bool hasMoreNotes;
  final String? nextNotesCursor;
  final int pendingSyncCount;
  final int syncConflictCount;
  final bool isSyncingOfflineChanges;
  final String? message;

  NoteList? get selectedList {
    for (final list in lists) {
      if (list.id == selectedListId) return list;
    }
    return null;
  }

  NotesState copyWith({
    NotesStatus? status,
    List<Note>? notes,
    List<Note>? pinnedNotes,
    List<Note>? reminderNotes,
    AggregateBoardAppearances? aggregateBoardAppearances,
    List<NoteList>? lists,
    String? selectedListId,
    bool? isRealtimeConnected,
    bool? isRealtimeConnecting,
    bool? isSaving,
    bool? isSavingList,
    bool? isInviting,
    bool? isRemovingCollaborator,
    bool? isSavingAppearance,
    bool? isLoadingPinned,
    bool? isLoadingReminderNotes,
    bool? isLoadingMoreNotes,
    bool? hasMoreNotes,
    String? nextNotesCursor,
    bool clearNextNotesCursor = false,
    int? pendingSyncCount,
    int? syncConflictCount,
    bool? isSyncingOfflineChanges,
    String? message,
  }) => NotesState(
    status: status ?? this.status,
    notes: notes ?? this.notes,
    pinnedNotes: pinnedNotes ?? this.pinnedNotes,
    reminderNotes: reminderNotes ?? this.reminderNotes,
    aggregateBoardAppearances:
        aggregateBoardAppearances ?? this.aggregateBoardAppearances,
    lists: lists ?? this.lists,
    selectedListId: selectedListId ?? this.selectedListId,
    isRealtimeConnected: isRealtimeConnected ?? this.isRealtimeConnected,
    isRealtimeConnecting: isRealtimeConnecting ?? this.isRealtimeConnecting,
    isSaving: isSaving ?? this.isSaving,
    isSavingList: isSavingList ?? this.isSavingList,
    isInviting: isInviting ?? this.isInviting,
    isRemovingCollaborator:
        isRemovingCollaborator ?? this.isRemovingCollaborator,
    isSavingAppearance: isSavingAppearance ?? this.isSavingAppearance,
    isLoadingPinned: isLoadingPinned ?? this.isLoadingPinned,
    isLoadingReminderNotes:
        isLoadingReminderNotes ?? this.isLoadingReminderNotes,
    isLoadingMoreNotes: isLoadingMoreNotes ?? this.isLoadingMoreNotes,
    hasMoreNotes: hasMoreNotes ?? this.hasMoreNotes,
    nextNotesCursor: clearNextNotesCursor
        ? null
        : nextNotesCursor ?? this.nextNotesCursor,
    pendingSyncCount: pendingSyncCount ?? this.pendingSyncCount,
    syncConflictCount: syncConflictCount ?? this.syncConflictCount,
    isSyncingOfflineChanges:
        isSyncingOfflineChanges ?? this.isSyncingOfflineChanges,
    message: message,
  );

  @override
  List<Object?> get props => [
    status,
    notes,
    pinnedNotes,
    reminderNotes,
    aggregateBoardAppearances,
    lists,
    selectedListId,
    isRealtimeConnected,
    isRealtimeConnecting,
    isSaving,
    isSavingList,
    isInviting,
    isRemovingCollaborator,
    isSavingAppearance,
    isLoadingPinned,
    isLoadingReminderNotes,
    isLoadingMoreNotes,
    hasMoreNotes,
    nextNotesCursor,
    pendingSyncCount,
    syncConflictCount,
    isSyncingOfflineChanges,
    message,
  ];
}
