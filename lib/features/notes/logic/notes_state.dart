import 'package:equatable/equatable.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';

enum NotesStatus { initial, loading, ready, failure }

class NotesState extends Equatable {
  const NotesState({
    this.status = NotesStatus.initial,
    this.notes = const [],
    this.lists = const [],
    this.selectedListId = 'home',
    this.isRealtimeConnected = false,
    this.isSaving = false,
    this.isSavingList = false,
    this.isInviting = false,
    this.isSavingAppearance = false,
    this.message,
  });

  final NotesStatus status;
  final List<Note> notes;
  final List<NoteList> lists;
  final String selectedListId;
  final bool isRealtimeConnected;
  final bool isSaving;
  final bool isSavingList;
  final bool isInviting;
  final bool isSavingAppearance;
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
    List<NoteList>? lists,
    String? selectedListId,
    bool? isRealtimeConnected,
    bool? isSaving,
    bool? isSavingList,
    bool? isInviting,
    bool? isSavingAppearance,
    String? message,
  }) => NotesState(
    status: status ?? this.status,
    notes: notes ?? this.notes,
    lists: lists ?? this.lists,
    selectedListId: selectedListId ?? this.selectedListId,
    isRealtimeConnected: isRealtimeConnected ?? this.isRealtimeConnected,
    isSaving: isSaving ?? this.isSaving,
    isSavingList: isSavingList ?? this.isSavingList,
    isInviting: isInviting ?? this.isInviting,
    isSavingAppearance: isSavingAppearance ?? this.isSavingAppearance,
    message: message,
  );

  @override
  List<Object?> get props => [
    status,
    notes,
    lists,
    selectedListId,
    isRealtimeConnected,
    isSaving,
    isSavingList,
    isInviting,
    isSavingAppearance,
    message,
  ];
}
