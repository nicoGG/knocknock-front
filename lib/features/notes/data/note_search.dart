import 'package:nocknock/features/notes/domain/note.dart';

String normalizeNoteSearchText(String value) {
  const accents = 'áéíóúüñàèìòùäëïöü';
  const plain = 'aeiouunaeiouaeiou';
  var normalized = value.toLowerCase().trim();
  for (var index = 0; index < accents.length; index++) {
    normalized = normalized.replaceAll(accents[index], plain[index]);
  }
  return normalized.replaceAll(RegExp(r'\s+'), ' ');
}

bool noteMatchesQuery(Note note, String query) {
  final normalized = normalizeNoteSearchText(query);
  if (normalized.isEmpty) return false;
  final searchable = normalizeNoteSearchText(
    [
      note.title,
      note.content,
      ...note.checklist.map((item) => item.text),
    ].join(' '),
  );
  return searchable.contains(normalized);
}

/// Session-only plaintext index. It intentionally has no serialization API so
/// decrypted note text cannot leak into the account cache or offline queue.
class PrivateNoteSearchIndex {
  final _notesById = <String, Note>{};
  final _searchableTextById = <String, String>{};

  void upsert(Note note) {
    _notesById[note.id] = note;
    _searchableTextById[note.id] = normalizeNoteSearchText(
      [
        note.title,
        note.content,
        ...note.checklist.map((item) => item.text),
      ].join(' '),
    );
  }

  void remove(String noteId) {
    _notesById.remove(noteId);
    _searchableTextById.remove(noteId);
  }

  void removeBoard(String boardId) {
    final ids = _notesById.values
        .where((note) => note.boardId == boardId)
        .map((note) => note.id)
        .toList();
    for (final id in ids) {
      remove(id);
    }
  }

  List<Note> search(String query) {
    final normalized = normalizeNoteSearchText(query);
    if (normalized.isEmpty) return const [];
    final results = <Note>[];
    for (final entry in _searchableTextById.entries) {
      if (entry.value.contains(normalized)) {
        final note = _notesById[entry.key];
        if (note != null) results.add(note);
      }
    }
    results.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return results;
  }

  void clear() {
    _notesById.clear();
    _searchableTextById.clear();
  }
}
