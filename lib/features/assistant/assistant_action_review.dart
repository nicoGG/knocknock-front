import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:nocknock/core/widgets/liquid_alert_dialog.dart';
import 'package:nocknock/features/assistant/assistant_actions.dart';
import 'package:nocknock/features/assistant/assistant_client.dart';
import 'package:nocknock/features/finance/financial_entry_editor.dart';
import 'package:nocknock/features/finance/list_configuration.dart';
import 'package:nocknock/features/notes/data/list_protection_controller.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_rich_text.dart'
    show noteContentMaxLength;
import 'package:uuid/uuid.dart';

class AssistantActionReview {
  const AssistantActionReview({
    required this.cubit,
    required this.protection,
    required this.current,
    required this.listId,
    required this.noteId,
    required this.author,
  });
  final NotesCubit cubit;
  final ListProtectionController protection;
  final bool Function() current;
  final String? listId, noteId;
  final String author;

  bool _allowed(NoteList list) =>
      current() &&
      list.canEdit &&
      !list.isEncryptionKeyPending &&
      !protection.isProtected(list.id);
  NoteList? _list(String id) =>
      cubit.state.lists.where((l) => l.id == id && _allowed(l)).firstOrNull;

  NoteList? matchingExpenseList(AssistantExpense expense, [String? name]) {
    final wanted = (name ?? expense.suggestedList).trim().toLowerCase();
    return cubit.state.lists
        .where(
          (l) =>
              _allowed(l) &&
              l.configuration.type == NoteListType.expenses &&
              l.configuration.currency == expense.currency &&
              l.name.trim().toLowerCase() == wanted,
        )
        .firstOrNull;
  }

  Future<NoteList?> createSuggestedList(
    BuildContext page,
    AssistantExpense expense,
  ) async {
    if (!current()) return null;
    var name = expense.suggestedList;
    final confirmed = await showDialog<String>(
      context: page,
      builder: (c) => LiquidAlertDialog(
        title: const Text('Crear lista de gastos'),
        content: TextFormField(
          initialValue: name,
          maxLength: 50,
          decoration: const InputDecoration(labelText: 'Nombre de la lista'),
          onChanged: (value) => name = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (name.trim().isNotEmpty) Navigator.pop(c, name.trim());
            },
            child: const Text('Crear lista'),
          ),
        ],
      ),
    );
    if (confirmed == null || !page.mounted || !current()) return null;
    return matchingExpenseList(expense, confirmed) ??
        await cubit.createExpenseListForCapture(confirmed, expense.currency);
  }

  Future<bool> expense(
    BuildContext page,
    AssistantExpense expense,
    NoteAttachment? photo,
  ) async {
    if (!current()) return false;
    final choices = cubit.state.lists
        .where(
          (l) => _allowed(l) && l.configuration.type == NoteListType.expenses,
        )
        .toList();
    final matching = matchingExpenseList(expense);
    int rank(NoteList list) => list.id == matching?.id
        ? 0
        : list.id == listId
        ? 1
        : 2;
    choices.sort(
      (a, b) => rank(a) == rank(b)
          ? a.name.compareTo(b.name)
          : rank(a).compareTo(rank(b)),
    );
    final choice = await showDialog<String>(
      context: page,
      builder: (c) => SimpleDialog(
        title: const Text('¿Dónde guardar el gasto?'),
        children: [
          for (final list in choices)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, list.id),
              child: Text('${list.name} · ${list.configuration.currency}'),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, ''),
            child: Text('Crear lista «${expense.suggestedList}»…'),
          ),
        ],
      ),
    );
    if (choice == null || !page.mounted || !current()) return false;
    String id = choice;
    if (choice.isEmpty) {
      final created = await createSuggestedList(page, expense);
      if (created == null) return false;
      id = created.id;
    }
    final list = _list(id);
    if (!page.mounted ||
        list == null ||
        list.configuration.type != NoteListType.expenses) {
      return false;
    }
    final saved = await showFinancialEntryEditor(
      context: page,
      list: list,
      author: author,
      initialEntry: expense.entry,
      initialTitle: expense.title,
      initialDetail: expense.detail,
      initialReceipt: photo,
      onSave: (draft) async {
        if (_list(id)?.configuration.type != NoteListType.expenses) {
          throw const AssistantFailure(
            'Ya no puedes guardar gastos en esta lista.',
          );
        }
        await cubit.createCapturedNote(
          id,
          draft.withSyncContext(
            clientNoteId: expense.noteId,
            clientMutationId: expense.mutationId,
          ),
        );
      },
    );
    return saved == true;
  }

  Future<bool> edit(BuildContext page, AssistantEdit edit) async {
    if (!current()) return false;
    bool eligible(String id) {
      final list = _list(id);
      return list != null &&
          !list.isFinancial &&
          (listId == null || id == listId);
    }

    final rows = await cubit.fetchVisibleListNotes(canShowList: eligible);
    if (!page.mounted || !current()) return false;
    final query = edit.targetTitle.trim().toLowerCase();
    final permitted = rows.where((r) => eligible(r.list.id));
    final exact = permitted.where(
      (r) => r.note.title.trim().toLowerCase() == query,
    );
    final matches =
        (noteId != null
                ? permitted.where((r) => r.note.id == noteId)
                : exact.isNotEmpty
                ? exact
                : permitted.where(
                    (r) => r.note.title.toLowerCase().contains(query),
                  ))
            .toList();
    if (matches.isEmpty) {
      throw const AssistantFailure(
        'No encontré esa nota entre las que puedes editar. Abre la nota o indica su título.',
      );
    }
    final selected = matches.length == 1
        ? matches.first.note
        : await showDialog<Note>(
            context: page,
            builder: (c) => SimpleDialog(
              title: const Text('Elige la nota que quieres editar'),
              children: [
                for (final row in matches)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(c, row.note),
                    child: Text('${row.note.title} · ${row.list.name}'),
                  ),
              ],
            ),
          );
    if (selected == null || !page.mounted || !eligible(selected.boardId)) {
      return false;
    }
    final changes = _changes(selected, edit);
    if (changes.isEmpty) {
      throw const AssistantFailure('La nota ya contiene esos cambios.');
    }
    final approved = await showDialog<bool>(
      context: page,
      builder: (c) => LiquidAlertDialog(
        title: Text('Editar «${selected.title}»'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_list(selected.boardId)?.name ?? ''),
              if (edit.replace != null && selected.content.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('Descripción actual: ${selected.content}'),
                ),
              for (final line in edit.descriptions)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(line),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Guardar cambios'),
          ),
        ],
      ),
    );
    if (approved != true || !page.mounted || !eligible(selected.boardId)) {
      return false;
    }
    final latest = (await cubit.fetchVisibleListNotes(
      canShowList: (id) => eligible(id) && id == selected.boardId,
    )).where((r) => r.note.id == selected.id).firstOrNull?.note;
    if (!page.mounted || !eligible(selected.boardId)) return false;
    if (latest == null || latest != selected) {
      throw const AssistantFailure(
        'La nota cambió. Revisa la propuesta otra vez antes de guardar.',
      );
    }
    await cubit.saveReviewedNoteChanges(selected, changes, edit.mutationId);
    return true;
  }

  Map<String, dynamic> _changes(Note note, AssistantEdit edit) {
    final patch = <String, dynamic>{};
    if (edit.title != null && edit.title != note.title) {
      patch['title'] = edit.title;
    }
    if (edit.replace != null || edit.append != null) {
      final body =
          edit.replace ??
          [if (note.content.isNotEmpty) note.content, edit.append!].join('\n');
      if (body.length > noteContentMaxLength) {
        throw const AssistantFailure(
          'El texto supera el límite de la nota. Pide una versión más breve.',
        );
      }
      if (body != note.content) {
        final raw = note.contentDelta;
        Object? delta;
        if (raw != null && raw.isNotEmpty) {
          try {
            delta = jsonDecode(raw);
          } on FormatException {
            delta = false;
          }
          if (delta is! List) {
            throw const AssistantFailure(
              'Esta nota tiene un dibujo o contenido especial. Puedes cambiar el título o las subtareas sin alterarlo.',
            );
          }
        }
        patch['content'] = body;
        patch['contentDelta'] = edit.append != null && delta is List
            ? jsonEncode([
                ...delta,
                {'insert': '${edit.append}\n'},
              ])
            : null;
      }
    }
    if (edit.addTasks.isNotEmpty || edit.completeTasks.isNotEmpty) {
      final tasks = [...note.checklist];
      String norm(String v) => v.trim().toLowerCase();
      for (final text in edit.addTasks) {
        if (!tasks.any((t) => norm(t.text) == norm(text))) {
          tasks.add(NoteChecklistItem(id: const Uuid().v4(), text: text));
        }
      }
      if (tasks.length > 100) {
        throw const AssistantFailure('La nota admite hasta 100 subtareas.');
      }
      for (final text in edit.completeTasks) {
        final matches = tasks.indexed
            .where((t) => norm(t.$2.text) == norm(text))
            .toList();
        if (matches.length != 1) {
          throw AssistantFailure(
            'No pude identificar de forma única la subtarea «$text».',
          );
        }
        final (i, item) = matches.single;
        tasks[i] = item.copyWith(isCompleted: true);
      }
      if (tasks.length != note.checklist.length ||
          tasks.indexed.any((t) => t.$2 != note.checklist[t.$1])) {
        patch['checklist'] = tasks.map((t) => t.toJson()).toList();
      }
    }
    if (edit.completed != null && edit.completed != note.isCompleted) {
      if (note.isRecurring) {
        throw const AssistantFailure(
          'Completa los recordatorios recurrentes desde la vista de la nota.',
        );
      }
      patch['isCompleted'] = edit.completed;
      patch['completedAt'] = edit.completed!
          ? DateTime.now().toUtc().toIso8601String()
          : null;
    }
    return patch;
  }
}
