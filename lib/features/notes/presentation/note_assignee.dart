import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';

const _customAssigneePrefix = 'custom:';

String? noteAssigneeFilterKey(Note note) =>
    noteAssigneeFilterKeys(note).firstOrNull;

List<String> noteAssigneeFilterKeys(Note note) => [
  ...note.assignedUserIds,
  for (final name in note.assignedCustomNames)
    '$_customAssigneePrefix${name.toLowerCase()}',
];

List<ListCollaborator> resolveNoteAssignees(
  Note note,
  Iterable<ListCollaborator> collaborators,
) => [
  for (final person in collaborators)
    if (note.assignedUserIds.contains(person.uid)) person,
  for (final name in note.assignedCustomNames)
    ListCollaborator(
      uid: '$_customAssigneePrefix${name.toLowerCase()}',
      email: '',
      displayName: name,
      role: ListMemberRole.editor,
      joinedAt: note.createdAt,
    ),
];

ListCollaborator? resolveNoteAssignee(
  Note note,
  Iterable<ListCollaborator> collaborators,
) {
  final people = resolveNoteAssignees(note, collaborators);
  if (people.isEmpty) return null;
  if (people.length == 1) return people.first;
  final first = people.first;
  return ListCollaborator(
    uid: first.uid,
    email: first.email,
    displayName: people
        .map(
          (person) => person.displayName.trim().isEmpty
              ? person.email
              : person.displayName,
        )
        .join(', '),
    photoUrl: first.photoUrl,
    role: first.role,
    joinedAt: first.joinedAt,
  );
}

bool isCustomNoteAssignee(ListCollaborator person) =>
    person.uid.startsWith(_customAssigneePrefix);
