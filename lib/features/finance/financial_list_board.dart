import 'package:nocknock/features/notes/presentation/widgets/scroll_edge_fade.dart';
import 'package:nocknock/core/widgets/liquid_dropdown.dart';
import 'package:nocknock/features/finance/financial_reports.dart';
import 'package:nocknock/features/finance/financial_summary_page.dart';
import 'package:nocknock/features/finance/financial_budget_dialog.dart';
import 'package:nocknock/features/finance/financial_export.dart';
import 'package:nocknock/features/finance/financial_style.dart';
import 'package:nocknock/features/notes/presentation/note_category_style.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nocknock/features/finance/financial_entry.dart';
import 'package:nocknock/features/finance/list_configuration.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';

/// Totals always use the complete list, independently of the visible status filter.
Map<String, Map<String, int>> financialTotals(
  Iterable<Note> notes, {
  String? month,
}) {
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
    group['total'] = group['total']! + entry.amountInMonth(month);
    if (['accepted', 'rejected'].contains(entry.status)) {
      group[entry.status] = group[entry.status]! + entry.amountInMonth(month);
    } else {
      group['paid'] = group['paid']! + entry.paidInMonth(month);
      group['pending'] = group['pending']! + entry.balanceInMonth(month);
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
    this.listView = false,
    this.onViewChanged,
    this.loadAttachment,
    super.key,
  });
  final NoteList list;
  final bool listView;
  final ValueChanged<bool>? onViewChanged;
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
  late bool _listView = widget.listView;

  @override
  void didUpdateWidget(covariant FinancialListBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.list.id != widget.list.id ||
        oldWidget.listView != widget.listView) {
      _listView = widget.listView;
    }
  }

  bool _exporting = false;
  Future<void> _settle(SharedTransfer transfer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => FinancialDialog(
        title: 'Registrar transferencia',
        icon: Icons.swap_horiz,
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
      final saved = await saveFinancialExport(
        list: widget.list,
        notes: widget.notes,
        format: format,
        month: _month,
        loadAttachment: widget.loadAttachment,
      );
      if (mounted && saved != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Archivo ${format.toUpperCase()} guardado.')),
        );
      }
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

  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _status = null;
      _month = null;
      _overdue = false;
      _visibleCount = 40;
    });
  }

  int _visibleCount = 40;
  @override
  Widget build(BuildContext context) {
    final config = widget.list.configuration;
    final allRecords = financialRecords(widget.notes);
    final records = financialRecords(widget.notes, month: _month);
    final totals = financialTotals(records, month: _month);
    final months = {
      financialMonth(DateTime.now()),
      ?_month,
      ...allRecords
          .where((n) => n.financialEntry != null)
          .expand((n) => n.financialEntry!.periodDates.map(financialMonth)),
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
                  .contains(_query.trim().toLowerCase()),
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
        FinancialSurface(
          backgroundIcon: FinancialStyle.typeIcon(config.type),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  FinancialIconBadge(
                    icon: FinancialStyle.typeIcon(config.type),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          config.type == NoteListType.expenses
                              ? 'Tus gastos'
                              : config.label,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${allRecords.length} ${allRecords.length == 1 ? 'registro' : 'registros'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: FinancialStyle.currencyLabel(config.currency),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: primary.withValues(alpha: .18),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            FinancialStyle.currencyIcon(config.currency),
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            config.currency,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
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
                  SizedBox(
                    width: double.infinity,
                    child: LiquidDropdownFormField<String>(
                      key: const ValueKey('financial-month'),
                      initialValue: _month ?? 'all',
                      decoration: const InputDecoration(
                        labelText: 'Período',
                        isDense: true,
                        prefixIcon: Icon(
                          Icons.calendar_month_rounded,
                          size: 20,
                        ),
                      ),
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
                  ),
                  if (widget.onSave != null &&
                      [
                        NoteListType.expenses,
                        NoteListType.custom,
                      ].contains(config.type))
                    FinancialActionButton(
                      width: ((MediaQuery.sizeOf(context).width - 80) / 2)
                          .clamp(110, 200),
                      onPressed: () => showFinancialBudgetDialog(
                        context,
                        currency: config.currency,
                        notes: widget.notes,
                        save: widget.onSave!,
                        month: _month,
                      ),
                      icon: Icons.savings_rounded,
                      label: 'Presupuesto',
                    ),
                  FinancialActionButton(
                    width: ((MediaQuery.sizeOf(context).width - 80) / 2).clamp(
                      110,
                      200,
                    ),
                    busy: _exporting,
                    onPressed: _exporting
                        ? null
                        : () async {
                            final format = await showLiquidSelection<String>(
                              context: context,
                              title: 'Exportar registros',
                              items: const [
                                DropdownMenuItem(
                                  value: 'pdf',
                                  child: FinancialOptionLabel(
                                    icon: Icons.picture_as_pdf_rounded,
                                    label: 'Informe PDF',
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'xlsx',
                                  child: FinancialOptionLabel(
                                    icon: Icons.table_chart_rounded,
                                    label: 'Excel: registros, abonos y reparto',
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'zip',
                                  child: FinancialOptionLabel(
                                    icon: Icons.folder_zip_rounded,
                                    label: 'Rendición ZIP con comprobantes',
                                  ),
                                ),
                              ],
                            );
                            if (mounted && format != null) {
                              await _export(format);
                            }
                          },
                    icon: Icons.file_download_rounded,
                    label: _exporting ? 'Exportando…' : 'Exportar',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.centerLeft,
            children: [...previous, ?current],
          ),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          child: Text(
            key: ValueKey(_month),
            _month == null
                ? 'Resumen de toda la lista'
                : 'Resumen de registros del mes',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        const SizedBox(height: 10),
        for (final group in totals.entries)
          if (config.type == NoteListType.expenses)
            _expenseSummary(context, group.key, group.value)
          else
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
          FinancialLiquidControl(
            child: TextField(
              key: const ValueKey('financial-search'),
              controller: _searchController,
              decoration: InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                prefixIcon: Icon(Icons.search_rounded, color: primary),
                suffixIcon: IconButton(
                  tooltip: 'Cancelar búsqueda',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _searchController.clear();
                    FocusManager.instance.primaryFocus?.unfocus();
                    setState(() => _query = '');
                  },
                ),
                hintText: 'Buscar movimientos',
                hintStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              textInputAction: TextInputAction.search,
              onChanged: (query) => setState(() => _query = query),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            runAlignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (overdueCount > 0 || _overdue)
                FinancialLiquidFilter(
                  icon: Icons.event_busy_rounded,
                  label: 'Vencidos ($overdueCount)',
                  selected: _overdue,
                  onPressed: () => setState(() => _overdue = !_overdue),
                ),
              FinancialLiquidFilter(
                icon: _status == null
                    ? Icons.check_circle_rounded
                    : Icons.apps_rounded,
                label: 'Todos',
                selected: _status == null,
                onPressed: () => setState(() => _status = null),
              ),
              ...config.statuses.map(
                (status) => FinancialLiquidFilter(
                  icon: FinancialStyle.statusIcon(status),
                  label: config.statusLabel(status),
                  selected: _status == status,
                  onPressed: () => setState(() => _status = status),
                ),
              ),
            ],
          ),
          if (_query.isNotEmpty ||
              _status != null ||
              _overdue ||
              _month != null)
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${notes.length} ${notes.length == 1 ? 'resultado' : 'resultados'}',
                ),
                TextButton.icon(
                  onPressed: _resetFilters,
                  icon: const Icon(Icons.filter_alt_off),
                  label: const Text('Limpiar filtros'),
                ),
              ],
            ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              Text(
                'Movimientos',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.dashboard_rounded),
                    tooltip: 'Ver tarjetas',
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.view_list_rounded),
                    tooltip: 'Ver lista',
                  ),
                ],
                selected: {_listView},
                onSelectionChanged: (v) {
                  setState(() => _listView = v.single);
                  widget.onViewChanged?.call(v.single);
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (notes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No hay registros con este filtro.'),
            ),
          if (_listView && notes.isNotEmpty)
            FinancialSurface(
              key: const ValueKey('financial-movements-list'),
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (
                    var index = 0;
                    index < notes.take(_visibleCount).length;
                    index++
                  ) ...[
                    if (index > 0)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                    FinancialEntryEntrance(
                      key: ValueKey(
                        'financial-list-entrance-${notes[index].id}',
                      ),
                      index: index,
                      child: ListTile(
                        key: ValueKey(
                          'financial-list-entry-${notes[index].id}',
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 2,
                        ),
                        minLeadingWidth: 22,
                        horizontalTitleGap: 12,
                        leading: Icon(
                          FinancialStyle.statusIcon(
                            notes[index].financialEntry?.status ?? 'pending',
                          ),
                          size: 21,
                        ),
                        title: Text(
                          notes[index].title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          [
                            if (notes[index].financialEntry
                                case final entry?) ...[
                              entry.formattedAmount,
                              config.statusLabel(entry.status),
                              if (entry.paymentMethod != null)
                                entry.isDeferred
                                    ? 'Diferido · ${entry.paymentLabel}'
                                    : entry.paymentLabel,
                              DateFormat('dd-MM-yyyy').format(entry.date),
                            ],
                          ].join(' · '),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                        ),
                        onTap: () => widget.onEdit(notes[index]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (!_listView)
            for (final (index, note) in notes.take(_visibleCount).indexed)
              _recordSurface(
                note: note,
                index: index,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: Icon(
                    note.photoAttachments.isEmpty
                        ? Icons.payments_outlined
                        : Icons.receipt_long_outlined,
                    color: config.type == NoteListType.expenses
                        ? NoteCategoryStyle.foregroundColor(note.category)
                        : primary,
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
                            color: config.type == NoteListType.expenses
                                ? NoteCategoryStyle.foregroundColor(
                                    note.category,
                                  )
                                : primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (entry.isDeferred)
                          Text(
                            'Diferido · ${entry.installments} cuotas mensuales · ${FinancialEntry.formatAmount(entry.installmentSchedule.first.amountMinor, entry.currency)} por cuota',
                          ),
                        if (_month != null && entry.isDeferred)
                          Text(
                            'Cuota del mes: ${FinancialEntry.formatAmount(entry.amountInMonth(_month), entry.currency)}',
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
                            'Vence: ${DateFormat('dd-MM-yyyy').format(entry.dueDate!)}',
                          ),
                        if (entry.participants.isNotEmpty)
                          Text(
                            '${entry.paidBy} pagó · ${entry.participants.length} participantes',
                          ),
                        Text(
                          [
                            if (entry.counterparty.isNotEmpty)
                              entry.counterparty,
                            DateFormat('dd-MM-yyyy').format(entry.date),
                            config.statusLabel(entry.status),
                            if (entry.paymentMethod != null)
                              entry.isDeferred
                                  ? 'Diferido · ${entry.paymentLabel}'
                                  : entry.paymentLabel,
                          ].join(' · '),
                        ),
                      ] else
                        const Text('Completar monto y datos financieros'),
                      if (note.photoAttachments.isNotEmpty)
                        Text('${note.photoAttachments.length} comprobante(s)'),
                    ],
                  ),
                  trailing: Icon(
                    note.financialEntry?.status == 'paid'
                        ? Icons.check_circle_rounded
                        : Icons.chevron_right_rounded,
                    color: note.financialEntry?.status == 'paid'
                        ? (config.type == NoteListType.expenses
                              ? NoteCategoryStyle.foregroundColor(note.category)
                              : Theme.of(context).colorScheme.primary)
                        : null,
                  ),
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
      backgroundIcon: Icons.savings_rounded,
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
        const SizedBox(height: 12),
        if (MediaQuery.sizeOf(context).width < 600)
          ..._sortedQuotes(quotes)
              .map((note) => _compactQuote(context, note, quotes))
        else
          ScrollEdgeFade(
            axis: Axis.horizontal,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                showCheckboxColumn: false,
                columns: const [
                  DataColumn(label: Text('Proveedor / concepto')),
                  DataColumn(label: Text('Precio')),
                  DataColumn(label: Text('Entrega')),
                  DataColumn(label: Text('Estado / validez')),
                  DataColumn(label: Text('Adjuntos')),
                ],
                rows: [
                  for (final note in _sortedQuotes(quotes))
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
                            '${note.financialEntry!.status == 'accepted' ? '✓ Elegida' : note.financialEntry!.statusLabel}${note.financialEntry!.validUntil == null ? '' : '\nHasta ${DateFormat('dd-MM-yyyy').format(note.financialEntry!.validUntil!)}'}${note.financialEntry!.validUntil != null && note.financialEntry!.validUntil!.isBefore(DateUtils.dateOnly(DateTime.now())) ? '\nVencida' : ''}',
                          ),
                        ),
                        DataCell(Text('${note.photoAttachments.length}')),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  List<Note> _sortedQuotes(List<Note> quotes) =>
      List<Note>.from(quotes)..sort((a, b) {
        final currency = a.financialEntry!.currency.compareTo(
          b.financialEntry!.currency,
        );
        return currency != 0
            ? currency
            : a.financialEntry!.amountMinor.compareTo(
                b.financialEntry!.amountMinor,
              );
      });

  Widget _compactQuote(BuildContext context, Note note, List<Note> quotes) {
    final entry = note.financialEntry!;
    final cheapest = !quotes.any(
      (q) =>
          q.financialEntry!.currency == entry.currency &&
          q.financialEntry!.amountMinor < entry.amountMinor,
    );
    final expired =
        entry.validUntil != null &&
        entry.validUntil!.isBefore(DateUtils.dateOnly(DateTime.now()));
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: entry.status == 'accepted'
            ? colors.primary.withValues(alpha: .10)
            : colors.surface.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: ValueKey('quote-comparison-${note.id}'),
          borderRadius: BorderRadius.circular(18),
          onTap: () => widget.onEdit(note),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.counterparty.isEmpty ? note.title : entry.counterparty,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (entry.counterparty.isNotEmpty)
                  Text(
                    note.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 8),
                Text(
                  entry.formattedAmount,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (cheapest)
                  Text(
                    'Menor precio (${entry.currency})',
                    style: TextStyle(color: colors.primary),
                  ),
                const SizedBox(height: 8),
                Text(
                  entry.deliveryDays == null
                      ? 'Entrega: sin plazo'
                      : 'Entrega: ${entry.deliveryDays} días',
                ),
                if (entry.validUntil != null)
                  Text(
                    'Válida hasta ${DateFormat('dd-MM-yyyy').format(entry.validUntil!)}${expired ? ' · Vencida' : ''}',
                    style: TextStyle(color: expired ? colors.error : null),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Chip(
                      avatar: Icon(
                        FinancialStyle.statusIcon(entry.status),
                        size: 16,
                      ),
                      label: Text(
                        entry.status == 'accepted'
                            ? 'Elegida'
                            : entry.statusLabel,
                      ),
                    ),
                    if (note.photoAttachments.isNotEmpty)
                      Chip(
                        avatar: const Icon(Icons.attach_file, size: 16),
                        label: Text('${note.photoAttachments.length} adjuntos'),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Abrir cotización',
                        style: TextStyle(color: colors.primary),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: colors.primary),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _recordSurface({
    required Note note,
    required Widget child,
    required int index,
  }) {
    final key = ValueKey('financial-entry-${note.id}');
    return FinancialEntryEntrance(
      key: key,
      index: index,
      child: widget.list.configuration.type == NoteListType.expenses
          ? FinancialNoteSurface(note: note, child: child)
          : FinancialSurface(padding: EdgeInsets.zero, child: child),
    );
  }

  Widget _expenseSummary(
    BuildContext context,
    String currency,
    Map<String, int> totals,
  ) {
    final colors = Theme.of(context).colorScheme;
    final total = totals['total']!;
    final paid = totals['paid']!;
    final pending = totals['pending']!;
    return FinancialSurface(
      key: ValueKey('expense-summary-$currency'),
      backgroundIcon: Icons.account_balance_wallet_rounded,
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => FinancialSummaryPage(
              list: widget.list,
              notes: List.of(widget.notes),
              currency: currency,
              month: _month,
              onEdit: (note) {
                Navigator.of(context).pop();
                widget.onEdit(note);
              },
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  FinancialIconBadge(
                    icon: Icons.account_balance_wallet_rounded,
                    size: 34,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Resumen de gastos',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.primary.withValues(alpha: .12),
                    ),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 17,
                      color: colors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Total registrado',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Text(
                FinancialEntry.formatAmount(total, currency),
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.6),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      total == 0
                          ? 'Sin montos registrados'
                          : pending == 0
                          ? 'Todo pagado'
                          : 'Avance de pagos',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    '${total == 0 ? 0 : (paid * 100 / total).round()} %',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              FinancialPaymentProgress(value: total == 0 ? 0 : paid / total),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cells = [
                    _expenseMetric(
                      context,
                      'Pagado',
                      paid,
                      currency,
                      Icons.check_circle_rounded,
                    ),
                    _expenseMetric(
                      context,
                      'Por pagar',
                      pending,
                      currency,
                      Icons.schedule_rounded,
                    ),
                  ];
                  final amountStyle = Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700);
                  double amountWidth(int value) {
                    final painter = TextPainter(
                      text: TextSpan(
                        text: FinancialEntry.formatAmount(value, currency),
                        style: amountStyle,
                      ),
                      textDirection: Directionality.of(context),
                      textScaler: MediaQuery.textScalerOf(context),
                    )..layout();
                    final width = painter.width;
                    painter.dispose();
                    return width;
                  }

                  if (amountWidth(paid) > (constraints.maxWidth - 16) / 2 ||
                      amountWidth(pending) > (constraints.maxWidth - 16) / 2 ||
                      constraints.maxWidth < 270 ||
                      MediaQuery.textScalerOf(context).scale(16) > 22) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        cells[0],
                        const SizedBox(height: 12),
                        cells[1],
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cells[0]),
                      const SizedBox(width: 16),
                      Expanded(child: cells[1]),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _expenseMetric(
    BuildContext context,
    String label,
    int amount,
    String currency,
    IconData icon,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, size: 15, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
      const SizedBox(height: 5),
      Text(
        FinancialEntry.formatAmount(amount, currency).replaceAll(' ', '\u00a0'),
        maxLines: 1,
        softWrap: false,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    ],
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
