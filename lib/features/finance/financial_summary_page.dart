import 'package:nocknock/features/finance/financial_charts.dart';
import 'package:nocknock/core/widgets/liquid_dropdown.dart';
import 'package:nocknock/features/notes/presentation/widgets/scroll_edge_fade.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nocknock/features/finance/financial_entry.dart';
import 'package:nocknock/features/finance/financial_reports.dart';
import 'package:nocknock/features/finance/financial_style.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';

/// Read-only breakdown of the period selected on the board, by currency.
class FinancialSummaryPage extends StatefulWidget {
  const FinancialSummaryPage({
    required this.list,
    required this.notes,
    required this.currency,
    required this.month,
    required this.onEdit,
    super.key,
  });
  final NoteList list;
  final List<Note> notes;
  final String currency;
  final String? month;
  final ValueChanged<Note> onEdit;

  @override
  State<FinancialSummaryPage> createState() => _FinancialSummaryPageState();
}

class _FinancialSummaryPageState extends State<FinancialSummaryPage> {
  late String? _month = widget.month;
  late String _currency = widget.currency;
  String _breakdown = 'people';
  NoteList get list => widget.list;
  List<Note> get notes => widget.notes;
  String get currency => _currency;
  String? get month => _month;
  ValueChanged<Note> get onEdit => widget.onEdit;

  @override
  Widget build(BuildContext context) {
    final records =
        financialRecords(notes, month: month)
            .where(
              (n) =>
                  n.financialEntry?.currency == currency &&
                  n.financialEntry?.isSettlement != true,
            )
            .toList()
          ..sort(
            (a, b) => b.financialEntry!.date.compareTo(a.financialEntry!.date),
          );
    final total = records.fold<int>(
      0,
      (v, n) => v + n.financialEntry!.amountInMonth(month),
    );
    final paid = records.fold<int>(
      0,
      (v, n) => v + n.financialEntry!.paidInMonth(month),
    );
    final pending = records.fold<int>(
      0,
      (v, n) => v + n.financialEntry!.balanceInMonth(month),
    );
    final groups = <String, int>{};
    for (final note in records) {
      final e = note.financialEntry!;
      final name = e.counterparty.trim().isEmpty
          ? 'Sin persona o comercio'
          : e.counterparty.trim();
      groups[name] = (groups[name] ?? 0) + e.amountInMonth(month);
    }
    final months =
        financialRecords(notes)
            .where(
              (n) =>
                  n.financialEntry != null &&
                  n.financialEntry?.isSettlement != true,
            )
            .expand((n) => n.financialEntry!.periodDates.map(financialMonth))
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    final currencies = {
      widget.currency,
      ...financialRecords(notes)
          .where(
            (n) =>
                n.financialEntry != null &&
                n.financialEntry?.isSettlement != true,
          )
          .map((n) => n.financialEntry!.currency),
    }.toList()..sort();
    final dated = <String, int>{};
    for (final note in records) {
      final e = note.financialEntry!;
      for (final date in e.periodDates) {
        final period = financialMonth(date);
        if (month != null && period != month) continue;
        final label = month == null
            ? DateFormat('MMMM yyyy', 'es').format(date)
            : DateFormat('dd-MM-yyyy').format(date);
        dated[label] =
            (dated[label] ?? 0) +
            (e.isDeferred ? e.amountInMonth(period) : e.amountMinor);
      }
    }
    final chartGroups = _breakdown == 'people'
        ? groups
        : _breakdown == 'payments'
        ? {'Pagado': paid, 'Por pagar': pending}
        : dated;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de gastos')),
      body: SafeArea(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.surface,
                Color.alphaBlend(
                  colors.primary.withValues(alpha: .08),
                  colors.surface,
                ),
                colors.surface,
              ],
            ),
          ),
          child: ScrollEdgeFade(
            fadeExtent: 44,
            overlayColor: colors.surface,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
              children: [
                Row(
                  children: [
                    const FinancialIconBadge(
                      icon: Icons.receipt_long_rounded,
                      size: 48,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        list.name,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${month == null ? 'Todos los meses' : DateFormat('MMMM yyyy', 'es').format(DateTime.parse('$month-01'))} · $currency',
                ),
                const SizedBox(height: 14),
                FinancialSurface(
                  child: Column(
                    children: [
                      LiquidDropdownFormField<String>(
                        initialValue: month ?? 'all',
                        decoration: const InputDecoration(
                          labelText: 'Período',
                          prefixIcon: Icon(Icons.calendar_month_rounded),
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
                        onChanged: (v) =>
                            setState(() => _month = v == 'all' ? null : v),
                      ),
                      if (currencies.length > 1) ...[
                        const SizedBox(height: 12),
                        LiquidDropdownFormField<String>(
                          initialValue: currency,
                          decoration: const InputDecoration(
                            labelText: 'Moneda',
                          ),
                          items: currencies
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(FinancialStyle.currencyLabel(c)),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _currency = v);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                FinancialEntryEntrance(
                  index: 0,
                  child: FinancialSurface(
                    backgroundIcon: Icons.account_balance_wallet_rounded,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Total registrado',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          FinancialEntry.formatAmount(total, currency),
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 16),
                        FinancialPaymentProgress(
                          value: total == 0 ? 0 : paid / total,
                        ),
                        const SizedBox(height: 14),
                        for (final metric in [
                          ('Pagado', paid),
                          ('Por pagar', pending),
                        ])
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              spacing: 12,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      metric.$1 == 'Pagado'
                                          ? Icons.check_circle_rounded
                                          : Icons.schedule_rounded,
                                      size: 18,
                                      color: colors.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(metric.$1),
                                  ],
                                ),
                                Text(
                                  FinancialEntry.formatAmount(
                                    metric.$2,
                                    currency,
                                  ),
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          '${records.length} ${records.length == 1 ? 'movimiento' : 'movimientos'} · ${total == 0 ? 0 : (paid * 100 / total).round()} % pagado',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                LiquidDropdownFormField<String>(
                  initialValue: _breakdown,
                  decoration: const InputDecoration(
                    labelText: 'Analizar gastos por',
                    prefixIcon: Icon(Icons.insights_rounded),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'people',
                      child: Text('Persona o comercio'),
                    ),
                    DropdownMenuItem(
                      value: 'payments',
                      child: Text('Estado de pago'),
                    ),
                    DropdownMenuItem(value: 'dates', child: Text('Fechas')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _breakdown = v);
                  },
                ),
                FinancialExpenseChart(
                  groups: chartGroups,
                  currency: currency,
                  title: 'Distribución de gastos',
                ),
                const SizedBox(height: 18),
                Text(
                  'Movimientos del período',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                if (records.isNotEmpty)
                  FinancialSurface(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final (index, note) in records.indexed) ...[
                          if (index > 0)
                            const Divider(height: 1, indent: 16, endIndent: 16),
                          FinancialEntryEntrance(
                            index: index,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              leading: FinancialIconBadge(
                                icon: FinancialStyle.statusIcon(
                                  note.financialEntry!.status,
                                ),
                                size: 34,
                              ),
                              title: Text(
                                note.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '${FinancialEntry.formatAmount(note.financialEntry!.amountInMonth(month), currency)} · ${list.configuration.statusLabel(note.financialEntry!.status)}${note.financialEntry!.paymentMethod == null ? '' : ' · ${note.financialEntry!.paymentLabel}'}\n${DateFormat('dd-MM-yyyy').format(note.financialEntry!.date)}',
                              ),
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                              ),
                              onTap: () => onEdit(note),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
