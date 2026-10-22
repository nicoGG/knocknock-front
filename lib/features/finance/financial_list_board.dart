import 'package:nocknock/features/finance/financial_reports.dart';
import 'package:nocknock/features/finance/financial_budget_dialog.dart';
import 'package:nocknock/features/finance/financial_export.dart';
import 'package:nocknock/features/finance/financial_style.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nocknock/features/finance/financial_entry.dart';
import 'package:nocknock/features/finance/list_configuration.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';

/// Totals always use the complete list, independently of the visible status filter.
Map<String, Map<String, int>> financialTotals(Iterable<Note> notes) {
  final totals = <String, Map<String, int>>{};
  for (final note in notes) {
    final entry = note.financialEntry;
    if (note.deletedAt != null ||
        entry == null ||
        entry.isBudget ||
        entry.isSettlement) {
      continue;
    }
    final group = totals.putIfAbsent(
      entry.currency,
      () => {'total': 0, 'pending': 0, 'paid': 0, 'accepted': 0, 'rejected': 0},
    );
    group['total'] = group['total']! + entry.amountMinor;
    if (['accepted', 'rejected'].contains(entry.status)) {
      group[entry.status] = group[entry.status]! + entry.amountMinor;
    } else {
      group['paid'] = group['paid']! + entry.paidMinor;
      group['pending'] = group['pending']! + entry.balanceMinor;
    }
  }
  return totals;
}

class FinancialListBoard extends StatefulWidget {
  const FinancialListBoard({
    required this.list,
    required this.notes,
    required this.onEdit,
    required this.onAdd,
    this.onSave,
    this.loadAttachment,
    super.key,
  });
  final NoteList list;
  final List<Note> notes;
  final ValueChanged<Note> onEdit;
  final VoidCallback onAdd;
  final Future<void> Function(NoteDraft, Note?)? onSave;
  final Future<NoteAttachment> Function(Note, String)? loadAttachment;
  @override
  State<FinancialListBoard> createState() => _FinancialListBoardState();
}

class _FinancialListBoardState extends State<FinancialListBoard> {
  String? _status;
  String? _month;
  bool _overdue = false;
  bool _exporting = false;
  Future<void> _settle(SharedTransfer transfer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Registrar transferencia'),
        content: Text(
          '¿Confirmas que ${transfer.from} pagó ${FinancialEntry.formatAmount(transfer.amountMinor, transfer.currency)} a ${transfer.to}? Se conservará el registro y se actualizarán los saldos compartidos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Registrar pago'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.onSave!(
        NoteDraft(
          title: 'Transferencia de ${transfer.from} a ${transfer.to}'.characters
              .take(80)
              .toString(),
          content: 'Liquidación de gastos compartidos.',
          color: NoteColor.green,
          category: NoteCategory.finance,
          authorName: transfer.from.characters.take(50).toString(),
          financialData: FinancialEntry(
            kind: 'settlement',
            amountMinor: transfer.amountMinor,
            currency: transfer.currency,
            counterparty: transfer.to,
            paidBy: transfer.from,
            date: DateTime.now(),
            status: 'paid',
          ).encoded,
        ),
        null,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo registrar la transferencia. Reintenta.'),
          ),
        );
      }
    }
  }

  Future<void> _export(String format) async {
    setState(() => _exporting = true);
    try {
      await saveFinancialExport(
        list: widget.list,
        notes: widget.notes,
        format: format,
        month: _month,
        loadAttachment: widget.loadAttachment,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo exportar. Comprueba la conexión para descargar todos los comprobantes.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _query = '';
  int _visibleCount = 40;
  @override
  Widget build(BuildContext context) {
    final config = widget.list.configuration;
    final allRecords = financialRecords(widget.notes);
    final records = financialRecords(widget.notes, month: _month);
    final totals = financialTotals(records);
    final months = {
      financialMonth(DateTime.now()),
      ?_month,
      ...allRecords
          .where((n) => n.financialEntry != null)
          .map((n) => financialMonth(n.financialEntry!.date)),
    }.toList()..sort((a, b) => b.compareTo(a));
    final budgetNotes =
        widget.notes
            .where(
              (n) =>
                  n.deletedAt == null &&
                  n.financialEntry?.isBudget == true &&
                  n.financialEntry!.period == (_month ?? 'all'),
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final budgets = <String, Note>{};
    for (final note in budgetNotes) {
      budgets.putIfAbsent(note.financialEntry!.currency, () => note);
    }
    final transfers = sharedTransfers(widget.notes);
    final quotes = records
        .where(
          (n) =>
              n.financialEntry != null &&
              n.financialEntry!.status != 'rejected',
        )
        .toList();
    final overdueCount = records
        .where(
          (n) =>
              n.financialEntry?.isOverdue(
                DateTime.now(),
                receivable: config.type == NoteListType.receivables,
              ) ==
              true,
        )
        .length;
    final notes = records
        .where(
          (note) =>
              (_status == null || note.financialEntry?.status == _status) &&
              (!_overdue ||
                  note.financialEntry?.isOverdue(
                        DateTime.now(),
                        receivable: config.type == NoteListType.receivables,
                      ) ==
                      true) &&
              '${note.title} ${note.financialEntry?.counterparty ?? ''}'
                  .toLowerCase()
                  .contains(_query.toLowerCase()),
        )
        .toList();
    final missing = allRecords
        .where((note) => note.financialEntry == null)
        .length;
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      key: const ValueKey('financial-list-board'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            FinancialIconBadge(icon: FinancialStyle.typeIcon(config.type)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    config.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${allRecords.length} registros',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Tooltip(
              message: FinancialStyle.currencyLabel(config.currency),
              child: Chip(
                avatar: Icon(
                  FinancialStyle.currencyIcon(config.currency),
                  size: 18,
                ),
                label: Text(config.currency),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<String>(
              key: const ValueKey('financial-month'),
              value: _month ?? 'all',
              items: [
                const DropdownMenuItem(
                  value: 'all',
                  child: Text('Todos los meses'),
                ),
                ...months.map(
                  (m) => DropdownMenuItem(
                    value: m,
                    child: Text(
                      DateFormat(
                        'MMMM yyyy',
                        'es',
                      ).format(DateTime.parse('$m-01')),
                    ),
                  ),
                ),
              ],
              onChanged: (v) => setState(() {
                _month = v == 'all' ? null : v;
                _visibleCount = 40;
              }),
            ),
            if (widget.onSave != null &&
                [
                  NoteListType.expenses,
                  NoteListType.custom,
                ].contains(config.type))
              OutlinedButton.icon(
                onPressed: () => showFinancialBudgetDialog(
                  context,
                  currency: config.currency,
                  notes: widget.notes,
                  save: widget.onSave!,
                  month: _month,
                ),
                icon: const Icon(Icons.savings_outlined),
                label: const Text('Presupuesto'),
              ),
            PopupMenuButton<String>(
              enabled: !_exporting,
              tooltip: 'Exportar registros del período seleccionado',
              onSelected: _export,
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'pdf', child: Text('Informe PDF')),
                const PopupMenuItem(
                  value: 'xlsx',
                  child: Text('Excel: registros, abonos y reparto'),
                ),
                const PopupMenuItem(
                  value: 'zip',
                  child: Text('Rendición ZIP con comprobantes'),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _exporting
                          ? Icons.hourglass_top
                          : Icons.file_download_outlined,
                    ),
                    const SizedBox(width: 6),
                    Text(_exporting ? 'Exportando…' : 'Exportar'),
                  ],
                ),
              ),
            ),
          ],
        ),
        Text(
          _month == null
              ? 'Resumen de toda la lista'
              : 'Resumen de registros del mes',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 10),
        for (final note in budgets.values)
          _budget(context, note.financialEntry!),
        if (transfers.isNotEmpty)
          FinancialSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Saldos compartidos acumulados',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Text(
                  'Saldos de toda la lista, independientes del mes. Registra los pagos entre participantes para actualizarlos.',
                ),
                for (final t in transfers)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${t.from} → ${t.to}: ${FinancialEntry.formatAmount(t.amountMinor, t.currency)}',
                        ),
                        if (widget.onSave != null)
                          TextButton(
                            onPressed: () => _settle(t),
                            child: const Text('Registrar pago'),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (config.type == NoteListType.quotations && quotes.isNotEmpty)
          _comparison(context, quotes),
        for (final group in totals.entries)
          FinancialSurface(
            padding: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Wrap(
                spacing: 28,
                runSpacing: 14,
                children: [
                  _total(
                    context,
                    'Total registrado',
                    group.value['total']!,
                    group.key,
                  ),
                  _total(
                    context,
                    config.type == NoteListType.receivables
                        ? 'Por cobrar'
                        : config.type == NoteListType.expenses
                        ? 'Por pagar'
                        : 'Pendiente',
                    group.value['pending']!,
                    group.key,
                  ),
                  _total(
                    context,
                    config.type == NoteListType.quotations
                        ? 'Aceptado'
                        : config.type == NoteListType.receivables
                        ? 'Cobrado'
                        : 'Pagado',
                    group.value[config.type == NoteListType.quotations
                        ? 'accepted'
                        : 'paid']!,
                    group.key,
                  ),
                  if (config.type == NoteListType.quotations)
                    _total(
                      context,
                      'Descartado',
                      group.value['rejected']!,
                      group.key,
                    ),
                ],
              ),
            ),
          ),
        if (allRecords.isEmpty)
          FinancialSurface(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Column(
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 42,
                    color: primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Empieza con tu primer registro',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Guarda montos y comprobantes. Puedes invitar a otras personas desde el menú de la lista.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: widget.onAdd,
                    icon: const Icon(Icons.add),
                    label: Text(config.entryLabel),
                  ),
                ],
              ),
            ),
          ),
        if (missing > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '$missing ${missing == 1 ? 'nota sin monto' : 'notas sin monto'}: no se incluyen en los totales. Ábrelas para completar sus datos.',
            ),
          ),
        if (allRecords.isNotEmpty) ...[
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('financial-search'),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Buscar concepto, persona o proveedor',
            ),
            onChanged: (query) => setState(() => _query = query),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilterChip(
                avatar: const Icon(Icons.event_busy_outlined, size: 16),
                label: Text('Vencidos ($overdueCount)'),
                selected: _overdue,
                onSelected: (v) => setState(() => _overdue = v),
              ),
              ChoiceChip(
                label: const Text('Todos'),
                selected: _status == null,
                onSelected: (_) => setState(() => _status = null),
              ),
              ...config.statuses.map(
                (status) => ChoiceChip(
                  avatar: Icon(FinancialStyle.statusIcon(status), size: 16),
                  label: Text(config.statusLabel(status)),
                  selected: _status == status,
                  onSelected: (_) => setState(() => _status = status),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (notes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No hay registros con este filtro.'),
            ),
          for (final note in notes.take(_visibleCount))
            FinancialSurface(
              padding: EdgeInsets.zero,
              key: ValueKey('financial-entry-${note.id}'),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: Icon(
                  note.photoAttachments.isEmpty
                      ? Icons.payments_outlined
                      : Icons.receipt_long_outlined,
                  color: primary,
                ),
                title: Text(
                  note.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (note.financialEntry case final entry?) ...[
                      const SizedBox(height: 4),
                      Text(
                        entry.formattedAmount,
                        style: TextStyle(
                          fontSize: 18,
                          color: primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (entry.payments.isNotEmpty)
                        Text(
                          'Abonado: ${FinancialEntry.formatAmount(entry.paidMinor, entry.currency)} · Saldo: ${FinancialEntry.formatAmount(entry.balanceMinor, entry.currency)}',
                        ),
                      if (entry.isOverdue(
                        DateTime.now(),
                        receivable: config.type == NoteListType.receivables,
                      ))
                        Text(
                          'Vencido · saldo ${FinancialEntry.formatAmount(entry.balanceMinor, entry.currency)}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      if (entry.dueDate != null)
                        Text(
                          'Vence: ${DateFormat('dd/MM/yyyy').format(entry.dueDate!)}',
                        ),
                      if (entry.participants.isNotEmpty)
                        Text(
                          '${entry.paidBy} pagó · ${entry.participants.length} participantes',
                        ),
                      Text(
                        [
                          if (entry.counterparty.isNotEmpty) entry.counterparty,
                          DateFormat('dd/MM/yyyy').format(entry.date),
                          config.statusLabel(entry.status),
                        ].join(' · '),
                      ),
                    ] else
                      const Text('Completar monto y datos financieros'),
                    if (note.photoAttachments.isNotEmpty)
                      Text('${note.photoAttachments.length} comprobante(s)'),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => widget.onEdit(note),
              ),
            ),
        ],
        if (notes.length > _visibleCount)
          TextButton.icon(
            onPressed: () => setState(() => _visibleCount += 40),
            icon: const Icon(Icons.expand_more_rounded),
            label: const Text('Ver más registros'),
          ),
        const SizedBox(height: 110),
      ],
    );
  }

  Widget _budget(BuildContext context, FinancialEntry budget) {
    final spent = budgetSpent(widget.notes, budget);
    final remaining = budget.amountMinor - spent;
    return FinancialSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Presupuesto ${budget.currency} · ${budget.period == 'all' ? 'Toda la lista' : budget.period}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: (spent / budget.amountMinor).clamp(0, 1),
            color: remaining < 0 ? Theme.of(context).colorScheme.error : null,
          ),
          const SizedBox(height: 8),
          Text(
            '${FinancialEntry.formatAmount(spent, budget.currency)} de ${budget.formattedAmount}',
          ),
          Text(
            '${remaining < 0 ? 'Excedido' : 'Disponible'}: ${FinancialEntry.formatAmount(remaining.abs(), budget.currency)}',
            style: TextStyle(
              color: remaining < 0 ? Theme.of(context).colorScheme.error : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _comparison(
    BuildContext context,
    List<Note> quotes,
  ) => FinancialSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Comparar cotizaciones',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Text(
          'Compara propuestas para el mismo trabajo o producto. Las vencidas se identifican; la selección se cambia desde el registro.',
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Proveedor / concepto')),
              DataColumn(label: Text('Precio')),
              DataColumn(label: Text('Entrega')),
              DataColumn(label: Text('Estado / validez')),
              DataColumn(label: Text('Adjuntos')),
            ],
            rows: [
              for (final note
                  in (List<Note>.from(quotes)..sort((a, b) {
                    final c = a.financialEntry!.currency.compareTo(
                      b.financialEntry!.currency,
                    );
                    return c != 0
                        ? c
                        : a.financialEntry!.amountMinor.compareTo(
                            b.financialEntry!.amountMinor,
                          );
                  })))
                DataRow(
                  selected: note.financialEntry!.status == 'accepted',
                  onSelectChanged: (_) => widget.onEdit(note),
                  cells: [
                    DataCell(
                      SizedBox(
                        width: 170,
                        child: Text(
                          '${note.financialEntry!.counterparty}\n${note.title}',
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        '${note.financialEntry!.formattedAmount}${!quotes.any((q) => q.financialEntry!.currency == note.financialEntry!.currency && q.financialEntry!.amountMinor < note.financialEntry!.amountMinor) ? '\nMenor precio (${note.financialEntry!.currency})' : ''}',
                      ),
                    ),
                    DataCell(
                      Text(
                        note.financialEntry!.deliveryDays == null
                            ? 'Sin plazo'
                            : '${note.financialEntry!.deliveryDays} días',
                      ),
                    ),
                    DataCell(
                      Text(
                        '${note.financialEntry!.status == 'accepted' ? '✓ Elegida' : note.financialEntry!.statusLabel}${note.financialEntry!.validUntil == null ? '' : '\nHasta ${DateFormat('dd/MM/yyyy').format(note.financialEntry!.validUntil!)}'}${note.financialEntry!.validUntil != null && note.financialEntry!.validUntil!.isBefore(DateUtils.dateOnly(DateTime.now())) ? '\nVencida' : ''}',
                      ),
                    ),
                    DataCell(Text('${note.photoAttachments.length}')),
                  ],
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _total(
    BuildContext context,
    String label,
    int minor,
    String currency,
  ) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 6),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            FinancialStyle.currencyIcon(currency),
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            FinancialEntry.formatAmount(minor, currency),
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    ],
  );
}
