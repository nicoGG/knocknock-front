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
    if (note.deletedAt != null || entry == null) continue;
    final group = totals.putIfAbsent(
      entry.currency,
      () => {'total': 0, 'pending': 0, 'paid': 0, 'accepted': 0, 'rejected': 0},
    );
    group['total'] = group['total']! + entry.amountMinor;
    group[entry.status] = group[entry.status]! + entry.amountMinor;
  }
  return totals;
}

class FinancialListBoard extends StatefulWidget {
  const FinancialListBoard({
    required this.list,
    required this.notes,
    required this.onEdit,
    required this.onAdd,
    super.key,
  });
  final NoteList list;
  final List<Note> notes;
  final ValueChanged<Note> onEdit;
  final VoidCallback onAdd;
  @override
  State<FinancialListBoard> createState() => _FinancialListBoardState();
}

class _FinancialListBoardState extends State<FinancialListBoard> {
  String? _status;
  String _query = '';
  int _visibleCount = 40;
  @override
  Widget build(BuildContext context) {
    final config = widget.list.configuration;
    final totals = financialTotals(widget.notes);
    final notes = widget.notes
        .where(
          (note) =>
              (_status == null || note.financialEntry?.status == _status) &&
              '${note.title} ${note.financialEntry?.counterparty ?? ''}'
                  .toLowerCase()
                  .contains(_query.toLowerCase()),
        )
        .toList();
    final missing = widget.notes
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
                    '${widget.notes.length} registros',
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
        if (widget.notes.isEmpty)
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
        if (widget.notes.isNotEmpty) ...[
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
