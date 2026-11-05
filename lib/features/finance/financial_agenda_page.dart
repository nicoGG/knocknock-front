import '../personal_expenses/expense_style.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nocknock/features/finance/financial_agenda.dart';
import 'package:nocknock/features/finance/financial_entry.dart';
import 'package:nocknock/features/finance/financial_entry_editor.dart';
import 'package:nocknock/features/notes/data/list_protection_controller.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:nocknock/features/notes/logic/notes_error_message.dart';
import 'package:nocknock/features/notes/logic/notes_state.dart';

class FinancialAgendaPage extends StatefulWidget {
  const FinancialAgendaPage({
    required this.cubit,
    required this.protection,
    super.key,
  });
  final NotesCubit cubit;
  final ListProtectionController protection;
  @override
  State<FinancialAgendaPage> createState() => _FinancialAgendaPageState();
}

class _FinancialAgendaPageState extends State<FinancialAgendaPage>
    with WidgetsBindingObserver {
  var _period = AgendaPeriod.week;
  var _dues = <AgendaDue>[];
  var _loading = true;
  var _failed = false;
  int _generation = 0;
  String? _payingList;
  Timer? _timer;
  late final StreamSubscription<NotesState> _changes;

  bool _visible(String id) =>
      widget.protection.canAccess(id) &&
      widget.cubit.state.lists.any(
        (list) =>
            list.id == id &&
            !list.isEncryptionKeyPending &&
            isAgendaType(list.configuration.type),
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.protection.addListener(_changed);
    var previous = widget.cubit.state;
    _changes = widget.cubit.stream.listen((next) {
      final changed =
          previous.lists != next.lists ||
          previous.notes != next.notes ||
          previous.pendingSyncCount != next.pendingSyncCount ||
          previous.syncConflictCount != next.syncConflictCount ||
          previous.isRealtimeConnected != next.isRealtimeConnected;
      previous = next;
      if (changed) _changed();
    });
    // Other boards do not necessarily share the selected board's socket room.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!_loading &&
          ModalRoute.of(context)?.isCurrent == true &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _load();
      }
    });
    _load();
  }

  void _changed() {
    if (!mounted) return;
    if (_payingList != null &&
        (!_visible(_payingList!) ||
            !widget.cubit.state.lists.any(
              (l) => l.id == _payingList && l.canEdit,
            ))) {
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).popUntil((r) => r == route);
      }
    }
    _dues.removeWhere((d) => !_visible(d.source.list.id));
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() => _loading = true);
    try {
      final records = await widget.cubit.fetchVisibleListNotes(
        canShowList: _visible,
      );
      if (!mounted || generation != _generation) return;
      final dues = agendaDues(records.where((r) => _visible(r.list.id)));
      setState(() {
        _dues = dues;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _dues = [];
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _pay(AgendaDue due) async {
    final source = due.source;
    if (_payingList != null ||
        !source.list.canEdit ||
        !_visible(source.list.id)) {
      return;
    }
    setState(() => _payingList = source.list.id);
    try {
      final result = await showFinancialPaymentDialog(
        context: context,
        currency: due.currency,
        balance: due.balance,
        attachments: source.note.photoAttachments,
        agendaLabel: 'Abonar a ${source.note.title}',
      );
      if (result == null ||
          !mounted ||
          !_visible(source.list.id) ||
          !widget.cubit.state.lists.any(
            (l) => l.id == source.list.id && l.canEdit,
          )) {
        return;
      }
      await widget.cubit.recordAgendaPayment(source, result.$1, result.$2);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Abono registrado.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(notesErrorMessage(e))));
      }
    } finally {
      if (mounted) {
        _payingList = null;
        await _load();
      }
    }
  }

  @override
  void dispose() {
    _changes.cancel();
    _timer?.cancel();
    widget.protection.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final visible = _dues
        .where((d) => _period.includes(d.date, today))
        .toList();
    final totals = <String, ({int pay, int collect})>{};
    for (final due in visible) {
      final previous = totals[due.currency] ?? (pay: 0, collect: 0);
      totals[due.currency] = (
        pay: previous.pay + (due.receivable ? 0 : due.balance),
        collect: previous.collect + (due.receivable ? due.balance : 0),
      );
    }
    final overdue = _dues.where((d) => d.date.isBefore(today)).length;
    final dateFormat = DateFormat.yMMMMEEEEd('es');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagos y cobros'),
        actions: [
          IconButton(
            tooltip: 'Actualizar agenda',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ExpenseBackground(
        child: SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: _load,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  sliver: SliverList.list(
                    children: [
                      const ExpenseEyebrow(
                        icon: Icons.calendar_month_outlined,
                        label: 'TU AGENDA',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Cada vencimiento, a tiempo',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tus pagos y cobros en un solo lugar, también los de tus listas compartidas.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final period in AgendaPeriod.values)
                            ChoiceChip(
                              label: Text(
                                period == AgendaPeriod.overdue && overdue > 0
                                    ? 'Vencidos ($overdue)'
                                    : period.label,
                              ),
                              selected: _period == period,
                              onSelected: (_) =>
                                  setState(() => _period = period),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (widget.cubit.state.syncConflictCount > 0)
                        const ExpenseNotice(
                          text: 'Hay cambios en conflicto. Revisa el estado de sincronización antes de repetir un abono.',
                        )
                      else if (widget.cubit.state.pendingSyncCount > 0)
                        const ExpenseNotice(
                          text: 'Hay cambios guardados en este dispositivo pendientes de sincronizar.',
                        ),
                      if (_loading) const LinearProgressIndicator(),
                      if (_failed)
                        ExpenseSurface(
                          child: Column(
                            children: [
                              Icon(
                                Icons.cloud_off_rounded,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                size: 36,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No se pudo cargar la agenda completa.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              TextButton(
                                onPressed: _load,
                                child: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        ),
                      if (!_failed && !_loading && visible.isEmpty)
                        _AgendaEmptyState(period: _period),
                      for (final currency in totals.keys.toList()..sort())
                        ExpenseSurface(
                          highlighted: true,
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ExpenseEyebrow(
                                icon: Icons.account_balance_wallet_outlined,
                                label: currency,
                              ),
                              const SizedBox(height: 16),
                              ExpenseMetricGrid(
                                values: {
                                  'Por pagar': FinancialEntry.formatAmount(
                                    totals[currency]!.pay,
                                    currency,
                                  ),
                                  'Por cobrar': FinancialEntry.formatAmount(
                                    totals[currency]!.collect,
                                    currency,
                                  ),
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
                  sliver: SliverList.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, i) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (i == 0 ||
                            !DateUtils.isSameDay(
                              visible[i - 1].date,
                              visible[i].date,
                            ))
                          Padding(
                            padding: const EdgeInsets.only(top: 20, bottom: 12),
                            child: Text(
                              dateFormat.format(visible[i].date),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        _row(visible[i], today),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(AgendaDue due, DateTime today) {
    final note = due.source.note;
    final limit = (note.financialEntry?.payments.length ?? 0) >= 50;
    return ExpenseSurface(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExpenseEyebrow(
              icon: due.receivable
                  ? Icons.south_west_rounded
                  : Icons.north_east_rounded,
              label: due.receivable ? 'POR COBRAR' : 'POR PAGAR',
            ),
            const SizedBox(height: 12),
            Text(note.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              [
                due.source.list.name,
                if (due.counterparty.isNotEmpty) due.counterparty,
              ].join(' · '),
            ),
            const SizedBox(height: 16),
            Text(
              FinancialEntry.formatAmount(due.balance, due.currency),
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (due.installment != null) ...[
              const SizedBox(height: 6),
              Text(
                'Cuota ${due.installment} de ${due.count}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (due.date.isBefore(today)) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Vencido',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            if (!due.source.list.canEdit)
              const Text('Solo lectura')
            else if (!due.firstUnpaid)
              const Text(
                'Los abonos se aplican primero a la cuota pendiente más antigua.',
              )
            else if (limit)
              const Text('Este registro alcanzó el límite de 50 abonos.')
            else
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _payingList == null ? () => _pay(due) : null,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Registrar abono'),
              ),
          ],
        ),
      ),
    );
  }
}

class _AgendaEmptyState extends StatelessWidget {
  const _AgendaEmptyState({required this.period});
  final AgendaPeriod period;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = switch (period) {
      AgendaPeriod.week => 'Tu semana, sin pendientes',
      AgendaPeriod.nextWeek => 'La próxima semana está libre',
      AgendaPeriod.overdue => 'Sin vencimientos atrasados',
      AgendaPeriod.all => 'Aún no hay vencimientos',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExpenseSurface(
          highlighted: true,
          child: Column(
            children: [
              SizedBox(
                height: 110,
                child: Center(
                  child: SizedBox(
                    width: 120,
                    height: 104,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.primary.withValues(alpha: .08),
                          ),
                        ),
                        Transform.rotate(
                          angle: -.1,
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: colors.primary.withValues(alpha: .25),
                              ),
                            ),
                            child: Icon(
                              Icons.calendar_month_rounded,
                              size: 44,
                              color: colors.primary,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colors.surface,
                                width: 3,
                              ),
                            ),
                            child: Icon(
                              Icons.check_rounded,
                              color: colors.onPrimaryContainer,
                              size: 22,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'No hay pagos ni cobros pendientes con fecha de vencimiento en este período.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ExpenseSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ExpenseEyebrow(
                icon: Icons.event_available_outlined,
                label: 'ORGANIZA LO QUE VIENE',
              ),
              const SizedBox(height: 12),
              Text(
                'Agrega una fecha de vencimiento',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Abre un gasto o cobro en tus listas y asigna su vencimiento. Aparecerá aquí automáticamente.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
