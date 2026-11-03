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
        title: const Text('Agenda de pagos y cobros'),
        actions: [
          IconButton(
            tooltip: 'Actualizar agenda',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                sliver: SliverList.list(
                  children: [
                    const Text(
                      'Vencimientos de tus listas de gastos y cuentas por cobrar, incluidas las compartidas.',
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final period in AgendaPeriod.values)
                          ChoiceChip(
                            label: Text(
                              period == AgendaPeriod.overdue && overdue > 0
                                  ? 'Vencidos ($overdue)'
                                  : period.label,
                            ),
                            selected: _period == period,
                            onSelected: (_) => setState(() => _period = period),
                          ),
                      ],
                    ),
                    if (widget.cubit.state.syncConflictCount > 0)
                      const Text(
                        'Hay cambios en conflicto. Revisa el estado de sincronización antes de repetir un abono.',
                      )
                    else if (widget.cubit.state.pendingSyncCount > 0)
                      const Text(
                        'Hay cambios guardados en este dispositivo pendientes de sincronizar.',
                      ),
                    if (_loading) const LinearProgressIndicator(),
                    if (_failed)
                      ListTile(
                        title: const Text(
                          'No se pudo cargar la agenda completa.',
                        ),
                        trailing: TextButton(
                          onPressed: _load,
                          child: const Text('Reintentar'),
                        ),
                      ),
                    if (!_failed && !_loading && visible.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No hay vencimientos pendientes en este período. Agrega una fecha de vencimiento a un gasto o cobro para verlo aquí.',
                        ),
                      ),
                    for (final currency in totals.keys.toList()..sort())
                      Card(
                        child: ListTile(
                          title: Text(currency),
                          subtitle: Text(
                            'Por pagar: ${FinancialEntry.formatAmount(totals[currency]!.pay, currency)}\nPor cobrar: ${FinancialEntry.formatAmount(totals[currency]!.collect, currency)}',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                          padding: const EdgeInsets.only(top: 18, bottom: 6),
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
    );
  }

  Widget _row(AgendaDue due, DateTime today) {
    final note = due.source.note;
    final limit = (note.financialEntry?.payments.length ?? 0) >= 50;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(note.title, style: Theme.of(context).textTheme.titleMedium),
            Text(
              [
                due.source.list.name,
                if (due.counterparty.isNotEmpty) due.counterparty,
              ].join(' · '),
            ),
            Text(
              [
                due.receivable ? 'Por cobrar' : 'Por pagar',
                FinancialEntry.formatAmount(due.balance, due.currency),
                if (due.installment != null)
                  'Cuota ${due.installment} de ${due.count}',
                if (due.date.isBefore(today)) 'Vencido',
              ].join(' · '),
            ),
            if (!due.source.list.canEdit)
              const Text('Solo lectura')
            else if (!due.firstUnpaid)
              const Text(
                'Los abonos se aplican primero a la cuota pendiente más antigua.',
              )
            else if (limit)
              const Text('Este registro alcanzó el límite de 50 abonos.')
            else
              TextButton.icon(
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
