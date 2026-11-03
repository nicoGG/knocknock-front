import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nocknock/features/finance/financial_amount_input.dart';
import 'package:nocknock/features/finance/financial_entry.dart';
import 'package:nocknock/features/finance/list_configuration.dart';
import 'package:nocknock/features/finance/monthly_finance_series.dart';
import 'package:nocknock/features/notes/data/list_protection_controller.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:nocknock/features/notes/logic/notes_error_message.dart';
import 'package:nocknock/features/notes/logic/notes_state.dart';
import 'package:uuid/uuid.dart';

class MonthlyFinancePage extends StatefulWidget {
  const MonthlyFinancePage({
    super.key,
    required this.list,
    required this.cubit,
    required this.protection,
    required this.author,
  });
  final NoteList list;
  final NotesCubit cubit;
  final ListProtectionController protection;
  final String author;
  @override
  State<MonthlyFinancePage> createState() => _MonthlyFinancePageState();
}

class _MonthlyFinancePageState extends State<MonthlyFinancePage> {
  final _title = TextEditingController(),
      _amount = TextEditingController(),
      _party = TextEditingController();
  final _form = GlobalKey<FormState>();
  DateTime _first = DateUtils.dateOnly(DateTime.now());
  String _id = const Uuid().v4();
  bool _editing = false, _busy = false;
  late Future<List<Note>> _rules;
  late final StreamSubscription<NotesState> _sub;
  bool get _accessible =>
      widget.protection.canAccess(widget.list.id) &&
      widget.cubit.state.lists.any(
        (l) => l.id == widget.list.id && l.canEdit && !l.isEncryptionKeyPending,
      );

  @override
  void initState() {
    super.initState();
    _rules = widget.cubit.monthlyRules(widget.list.id);
    widget.protection.addListener(_accessChanged);
    _sub = widget.cubit.stream.listen((_) => _accessChanged());
  }

  void _accessChanged() {
    if (!mounted || _accessible) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final nav = Navigator.of(context);
    nav.popUntil((r) => r == route);
    nav.pop();
  }

  @override
  void dispose() {
    widget.protection.removeListener(_accessChanged);
    _sub.cancel();
    _title.dispose();
    _amount.dispose();
    _party.dispose();
    super.dispose();
  }

  void _reload() {
    final next = widget.cubit.monthlyRules(widget.list.id);
    setState(() {
      _rules = next;
    });
  }

  Future<void> _save() async {
    if (_busy || !_accessible || !_form.currentState!.validate()) return;
    final currency = widget.list.configuration.currency;
    final rule = MonthlyFinanceRule(
      start: _first,
      amount: parseFinancialAmountInput(_amount.text, currency)!,
      currency: currency,
      counterparty: _party.text.trim(),
    );
    setState(() => _busy = true);
    try {
      await widget.cubit.createMonthlyRule(
        widget.list.id,
        NoteDraft(
          title: _title.text.trim(),
          content: '',
          authorName: widget.author,
          color: NoteColor.green,
          category: NoteCategory.finance,
          financialData: rule.encode(),
          clientNoteId: _id,
          clientMutationId: _id,
        ),
      );
      if (!mounted) return;
      _editing = false;
      _id = const Uuid().v4();
      _title.clear();
      _party.clear();
      _amount.clear();
      _first = DateUtils.dateOnly(DateTime.now());
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(notesErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop(Note rule) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('¿Detener ${rule.title}?'),
        content: const Text(
          'Se conservarán los registros ya creados, con sus abonos y comprobantes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Detener serie'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted || !_accessible) return;
    setState(() => _busy = true);
    try {
      await widget.cubit.stopMonthlyRule(rule);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(notesErrorMessage(e))));
      }
    } finally {
      if (mounted) {
        _busy = false;
        _reload();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.list.configuration;
    final collecting = config.type == NoteListType.receivables;
    final initialCount = MonthlyFinanceRule.periodsThroughNextMonth(
      _first,
      DateTime.now(),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Series mensuales'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _busy ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.list.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Cada mes tiene su propio registro. Al abrir la lista o la agenda se preparan los meses pendientes y el próximo mes.',
            ),
            const SizedBox(height: 12),
            if (!_editing)
              FilledButton.icon(
                onPressed: _busy ? null : () => setState(() => _editing = true),
                icon: const Icon(Icons.add),
                label: Text(
                  collecting ? 'Nuevo cobro mensual' : 'Nuevo gasto mensual',
                ),
              ),
            if (_editing)
              Form(
                key: _form,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _title,
                      maxLength: 80,
                      decoration: const InputDecoration(
                        labelText: 'Nombre de la serie',
                      ),
                      validator: (s) =>
                          (s ?? '').trim().isEmpty ? 'Ingresa un nombre' : null,
                    ),
                    TextFormField(
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        if (config.currency == 'CLP')
                          ClpThousandsInputFormatter(),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Monto mensual (${config.currency})',
                      ),
                      validator: (s) =>
                          parseFinancialAmountInput(s ?? '', config.currency) ==
                              null
                          ? 'Ingresa un monto válido'
                          : null,
                    ),
                    TextFormField(
                      controller: _party,
                      maxLength: 120,
                      decoration: InputDecoration(
                        labelText: config.counterpartyLabel,
                      ),
                      validator: (s) => collecting && (s ?? '').trim().isEmpty
                          ? 'Ingresa quién debe pagar'
                          : null,
                    ),
                    ListTile(
                      title: const Text('Primer vencimiento'),
                      subtitle: Text(DateFormat('dd/MM/yyyy').format(_first)),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _first,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100, 12, 31),
                        );
                        if (date != null && mounted) {
                          setState(() => _first = date);
                        }
                      },
                    ),
                    const Text('Si el mes es más corto, se usa su último día.'),
                    Text(
                      initialCount == 1
                          ? 'Se creará el primer registro.'
                          : 'Se crearán $initialCount registros mensuales, cada uno con saldo pendiente.',
                    ),
                    OverflowBar(
                      children: [
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _editing = false),
                          child: const Text('Cancelar'),
                        ),
                        FilledButton(
                          onPressed: _busy ? null : _save,
                          child: const Text('Crear serie'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            const Divider(),
            FutureBuilder<List<Note>>(
              future: _rules,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LinearProgressIndicator();
                }
                if (snapshot.hasError) {
                  return TextButton(
                    onPressed: _reload,
                    child: const Text(
                      'No se pudieron cargar las series. Reintentar',
                    ),
                  );
                }
                final rules = snapshot.data ?? [];
                if (rules.isEmpty) {
                  return const Text(
                    'Aún no hay series mensuales en esta lista.',
                  );
                }
                return Column(
                  children: [
                    for (final note in rules)
                      Builder(
                        builder: (_) {
                          final rule = MonthlyFinanceRule.decode(
                            note.financialData,
                          )!;
                          return ListTile(
                            title: Text(note.title),
                            subtitle: Text(
                              '${FinancialEntry.formatAmount(rule.amount, rule.currency)} · Día ${rule.start.day} de cada mes',
                            ),
                            trailing: IconButton(
                              tooltip: 'Detener serie',
                              icon: const Icon(Icons.stop_circle_outlined),
                              onPressed: _busy ? null : () => _stop(note),
                            ),
                          );
                        },
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
