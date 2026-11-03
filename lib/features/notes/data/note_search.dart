import 'package:nocknock/features/finance/monthly_finance_series.dart';
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

class _SearchFields {
  _SearchFields(Note note) {
    final entry = note.financialEntry;
    text = normalizeNoteSearchText(
      [
        note.title,
        note.content,
        ...note.checklist.map((item) => item.text),
        if (entry != null) ...[
          entry.counterparty,
          entry.paidBy,
          ...entry.participants,
        ],
      ].whereType<String>().join(' '),
    );
    if (entry == null) return;
    final raw = entry.editableAmount;
    final parts = raw.split(',');
    final grouped = parts.first.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]}.',
    );
    final values = {
      raw,
      raw.replaceAll(',', '.'),
      [grouped, ...parts.skip(1)].join(','),
      if (raw.endsWith(',00')) parts.first,
      if (raw.endsWith(',00')) grouped,
      if (raw.endsWith('0') && parts.length == 2)
        raw.substring(0, raw.length - 1),
      if (raw.endsWith('0') && parts.length == 2)
        raw.substring(0, raw.length - 1).replaceAll(',', '.'),
    };
    final currency = entry.currency.toLowerCase();
    final symbol = currency == 'eur' ? '€' : r'$';
    for (final value in values) {
      amounts.addAll([
        value,
        '$currency$value',
        '$value$currency',
        '$symbol$value',
      ]);
    }
  }
  late final String text;
  final amounts = <String>{};
  bool matches(String normalized) =>
      normalized.isNotEmpty &&
      (text.contains(normalized) ||
          amounts.contains(normalized.replaceAll(' ', '')));
}

bool noteMatchesQuery(Note note, String query) =>
    MonthlyFinanceRule.decode(note.financialData) == null &&
    _SearchFields(note).matches(normalizeNoteSearchText(query));

/// Session-only plaintext index. It intentionally has no serialization API so
/// decrypted note text cannot leak into the account cache or offline queue.
class PrivateNoteSearchIndex {
  final _notesById = <String, Note>{};
  final _searchableTextById = <String, _SearchFields>{};

  void upsert(Note note) {
    if (MonthlyFinanceRule.decode(note.financialData) != null) {
      remove(note.id);
      return;
    }
    _notesById[note.id] = note;
    _searchableTextById[note.id] = _SearchFields(note);
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
      if (entry.value.matches(normalized)) {
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
