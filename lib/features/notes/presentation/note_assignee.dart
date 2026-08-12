import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';

const _customAssigneePrefix = 'custom:';

String? noteAssigneeFilterKey(Note note) {
  final uid = note.assigneeUid?.trim();
  if (uid != null && uid.isNotEmpty) return uid;
  final name = note.customAssigneeName?.trim();
  if (name == null || name.isEmpty) return null;
  return '$_customAssigneePrefix${name.toLowerCase()}';
}

ListCollaborator? resolveNoteAssignee(
  Note note,
  Iterable<ListCollaborator> collaborators,
) {
  final uid = note.assigneeUid?.trim();
  if (uid != null && uid.isNotEmpty) {
    for (final person in collaborators) {
      if (person.uid == uid) return person;
    }
  }
  final customName = note.customAssigneeName?.trim();
  if (customName == null || customName.isEmpty) return null;
  return ListCollaborator(
    uid: '$_customAssigneePrefix${note.id}',
    email: '',
    displayName: customName,
    role: ListMemberRole.editor,
    joinedAt: note.createdAt,
  );
}

bool isCustomNoteAssignee(ListCollaborator person) =>
    person.uid.startsWith(_customAssigneePrefix);
