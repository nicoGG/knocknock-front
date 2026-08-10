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
    this.message,
  });

  final NotesStatus status;
  final List<Note> notes;
  final List<Note> pinnedNotes;
  final List<Note> reminderNotes;
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
    String? message,
  }) => NotesState(
    status: status ?? this.status,
    notes: notes ?? this.notes,
    pinnedNotes: pinnedNotes ?? this.pinnedNotes,
    reminderNotes: reminderNotes ?? this.reminderNotes,
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
    message: message,
  );

  @override
  List<Object?> get props => [
    status,
    notes,
    pinnedNotes,
    reminderNotes,
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
    message,
  ];
}
