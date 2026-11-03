import 'package:nocknock/features/assistant/assistant_excerpt.dart';
import 'package:nocknock/features/finance/financial_entry.dart';
import 'package:nocknock/features/finance/list_configuration.dart';
import 'package:nocknock/features/finance/financial_reports.dart';
import 'package:nocknock/features/notes/data/list_protection_controller.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/logic/notes_state.dart';
import 'package:nocknock/features/notes/presentation/today_page.dart';

/// Local screen description. Only the excerpt attached to the draft can be sent with the message.
class AssistantView {
  const AssistantView(
    this.key,
    this.title,
    this.suggestion,
    this.question, {
    this._excerpt = '',
    this.detail = '',
    this.listType,
  });
  final String key, title, suggestion, question, _excerpt, detail;
  final NoteListType? listType;
  String get excerpt => _excerpt.length <= 8000
      ? _excerpt
      : String.fromCharCodes(_excerpt.runes.take(8000));

  String get greeting => switch (key.split('/').first) {
    'today' => '¿Armamos tu plan para hoy? Puedo ayudarte a decidir qué atender primero.',
    'budget' =>
      '¿Revisamos cuánto llevas gastado y cuánto queda para este período?',
    'list' when key.contains('/note/') =>
      '¿Quieres convertir esta nota en pasos concretos?',
    'list' when listType != null && listType != NoteListType.normal =>
      'Estamos en «$title». ¿Revisamos los montos, lo que sigue pendiente o los próximos vencimientos?',
    'list' =>
      'Estamos en «$title». Puedo resumir lo que ves o preparar una nota contigo.',
    _ => '¿Qué quieres hacer en $title?',
  };

  factory AssistantView.list(NoteList list, NotesState state, {String? month}) {
    final notes = state.notes.where(
      (n) => n.boardId == list.id && n.deletedAt == null,
    );
    final excerpt = assistantExcerpt(list, state);
    final pending = notes.where((n) => !n.isCompleted).length;
    final detail = list.isFinancial
        ? '${notes.length} registros en la vista · ${month ?? "Todos los meses"}'
        : '$pending pendientes de ${notes.length} notas en la vista';
    final totals = <String, int>{};
    if (list.isFinancial) {
      for (final n in notes) {
        final e = n.financialEntry;
        if (e != null &&
            !e.isBudget &&
            !e.isSettlement &&
            e.status != 'rejected') {
          totals.update(
            e.currency,
            (v) => v + e.amountInMonth(month),
            ifAbsent: () => e.amountInMonth(month),
          );
        }
      }
    }
    final now = DateTime.now();
    final overdue = notes
        .where(
          (note) => !note.isCompleted && note.reminderAt?.isBefore(now) == true,
        )
        .length;
    final amounts = totals.entries
        .map((e) => FinancialEntry.formatAmount(e.value, e.key))
        .join(' · ');
    return AssistantView(
      'list/${list.id}/${month ?? ''}',
      list.name,
      list.isFinancial
          ? 'Analizar movimientos'
          : overdue > 0
          ? 'Revisar pendientes vencidos'
          : 'Priorizar pendientes',
      list.isFinancial
          ? 'Analiza los movimientos del extracto por moneda y señala vencimientos o saldos pendientes.'
          : 'Ordena mis pendientes por prioridad y propone el siguiente paso.',
      detail: detail,
      listType: list.configuration.type,
      excerpt: excerpt.isEmpty
          ? ''
          : 'Lista: ${list.name}. $detail.\n${amounts.isEmpty ? '' : 'Monto de los registros de esta vista en el período, por moneda: $amounts. Los importes del detalle corresponden a los registros completos.\n'}$excerpt',
    );
  }

  factory AssistantView.today(
    List<NoteSearchResult> snapshot,
    NotesState state,
    ListProtectionController protection,
    String uid,
  ) {
    final allowed = {
      for (final list in state.lists)
        if (!list.isEncryptionKeyPending && !protection.isProtected(list.id))
          list.id: list,
    };
    final visible = snapshot.where(
      (r) =>
          allowed.containsKey(r.note.boardId) &&
          r.note.boardId == r.list.id &&
          !r.list.isEncryptionKeyPending,
    );
    final groups = groupTodayNotes(visible, now: DateTime.now(), userId: uid);
    final sourceIds = visible.map((r) => r.note.boardId).toSet().toList()
      ..sort();
    final counts = groups.entries
        .map((g) => '${g.key}: ${g.value.length}')
        .join(' · ');
    final entries = [
      for (final g in groups.entries)
        for (final r in g.value) (section: g.key, result: r),
    ];
    final lines = [
      counts,
      'Detalle de ${entries.take(12).length} de ${entries.length} notas:',
      for (final item in entries.take(12))
        '• ${item.section} · ${String.fromCharCodes(allowed[item.result.list.id]!.name.runes.take(50))}: ${String.fromCharCodes(item.result.note.title.runes.take(100))}${item.result.note.reminderAt == null ? '' : ' · recordatorio ${item.result.note.reminderAt!.toLocal().toIso8601String().substring(0, 16)}'}',
    ];
    final overdue = groups['Atrasadas']!.length;
    return AssistantView(
      'today/${sourceIds.join("/")}',
      'Hoy',
      overdue > 0 ? 'Ordenar mis atrasadas' : 'Preparar mi día',
      'Prepara un plan para hoy a partir del extracto. Distingue lo vencido de lo que viene y sugiere por dónde empezar.',
      detail: 'Para hoy: ${groups["Para hoy"]!.length} · Atrasadas: $overdue',
      excerpt: lines.join('\n'),
    );
  }

  factory AssistantView.selection(
    String title,
    List<NoteSearchResult> snapshot,
    NotesState state,
    ListProtectionController protection,
  ) {
    final allowed = {
      for (final l in state.lists)
        if (!l.isEncryptionKeyPending && !protection.isProtected(l.id)) l.id: l,
    };
    final rows = snapshot.where(
      (r) =>
          r.note.deletedAt == null &&
          r.note.boardId == r.list.id &&
          allowed.containsKey(r.list.id) &&
          !r.list.isEncryptionKeyPending,
    );
    final ids = rows.map((r) => r.list.id).toSet().toList()..sort();
    return AssistantView(
      'selection/$title/${ids.join("/")}',
      title,
      'Organizar esta vista',
      'Analiza estas notas y propón por dónde empezar.',
      detail: '${rows.length} notas en la vista',
      excerpt: [
        '$title · ${rows.length} notas. Primeras 12:',
        for (final r in rows.take(12))
          '• ${allowed[r.list.id]!.name}: ${String.fromCharCodes(r.note.title.runes.take(100))} · ${r.note.isCompleted ? "completada" : "pendiente"}',
      ].join('\n'),
    );
  }

  factory AssistantView.budget(
    NoteList list,
    NotesState state,
    BudgetSelection selected,
  ) {
    final notes = state.notes.where(
      (n) => n.boardId == list.id && n.deletedAt == null,
    );
    final budgets = notes.where((n) {
      final b = n.financialEntry;
      return b != null &&
          b.isBudget &&
          b.period == selected.period &&
          b.currency == selected.currency;
    }).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final limit = budgets.firstOrNull?.financialEntry?.amountMinor;
    final spent = budgetSpentFor(
      notes,
      currency: selected.currency,
      period: selected.period,
    );
    String amount(int n) => FinancialEntry.formatAmount(n, selected.currency);
    final period = selected.period == 'all' ? 'Toda la lista' : selected.period;
    final detail = '$period · ${selected.currency}';
    final excerpt = [
      'Presupuesto de ${list.name} · $detail.',
      'Gasto registrado: ${amount(spent)}.',
      if (limit == null)
        'Sin límite guardado.'
      else ...[
        'Límite guardado: ${amount(limit)}.',
        if (spent > limit)
          'Exceso: ${amount(spent - limit)}.'
        else
          'Disponible: ${amount(limit - spent)}.',
      ],
      if (selected.proposedLimit != null && selected.proposedLimit != limit)
        'Límite propuesto sin guardar: ${amount(selected.proposedLimit!)}.',
      if (state.hasMoreNotes) 'Totales parciales de los movimientos cargados.',
    ].join('\n');
    return AssistantView(
      'budget/${list.id}/$detail',
      'Presupuesto · ${list.name}',
      limit != null && spent > limit
          ? 'Entender el exceso'
          : 'Revisar presupuesto',
      'Explica el gasto y el saldo de este presupuesto para el período y moneda indicados. Si hay un límite propuesto, compara ambos escenarios. Sugiere un paso concreto.',
      detail: detail,
      excerpt: excerpt,
    );
  }
}

typedef BudgetSelection = ({
  String currency,
  String period,
  int? proposedLimit,
});
