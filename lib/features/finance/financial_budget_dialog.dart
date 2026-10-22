import 'package:nocknock/features/finance/financial_style.dart';
import 'package:flutter/material.dart';
import 'package:nocknock/features/finance/financial_entry.dart';
import 'package:nocknock/features/finance/financial_reports.dart';
import 'package:nocknock/features/finance/list_configuration.dart';
import 'package:nocknock/features/notes/domain/note.dart';

Future<void> showFinancialBudgetDialog(
  BuildContext context, {
  required String currency,
  required List<Note> notes,
  required Future<void> Function(NoteDraft, Note?) save,
  String? month,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      _BudgetDialog(currency: currency, notes: notes, save: save, month: month),
);

class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog({
    required this.currency,
    required this.notes,
    required this.save,
    this.month,
  });
  final String currency;
  final List<Note> notes;
  final String? month;
  final Future<void> Function(NoteDraft, Note?) save;
  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  late String _currency = widget.currency;
  late String _period = widget.month ?? 'all';
  bool _saving = false;
  String? _error;
  Note? get _existing {
    final matches =
        widget.notes
            .where(
              (n) =>
                  n.deletedAt == null &&
                  n.financialEntry?.isBudget == true &&
                  n.financialEntry!.currency == _currency &&
                  n.financialEntry!.period == _period,
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return matches.firstOrNull;
  }

  void _load() =>
      _amount.text = _existing?.financialEntry?.editableAmount ?? '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final entry = FinancialEntry(
        kind: 'budget',
        period: _period,
        amountMinor: FinancialEntry.parseAmount(_amount.text, _currency)!,
        currency: _currency,
        counterparty: '',
        date: DateTime.now(),
      );
      await widget.save(
        NoteDraft(
          title:
              'Presupuesto $_currency · ${_period == 'all' ? 'Toda la lista' : _period}',
          content: 'Límite de gasto compartido de la lista.',
          color: NoteColor.green,
          category: NoteCategory.finance,
          authorName: _existing?.authorName ?? 'Presupuesto',
          financialData: entry.encoded,
        ),
        _existing,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo guardar. Reabre el presupuesto si otra persona lo modificó.';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: FinancialDialog(
      title: 'Presupuesto de la lista',
      icon: Icons.savings_outlined,
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Se comparte con los miembros de la lista. Suma los montos registrados, salvo los descartados.',
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _currency,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Moneda'),
              items: ListConfiguration.currencies
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: _saving
                  ? null
                  : (v) => setState(() {
                      _currency = v!;
                      _load();
                    }),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _period,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Período'),
              items: [
                const DropdownMenuItem(
                  value: 'all',
                  child: Text('Toda la lista'),
                ),
                for (final m in {
                  financialMonth(DateTime.now()),
                  if (widget.month != null) widget.month!,
                  ...widget.notes
                      .where((n) => n.financialEntry != null)
                      .map((n) => financialMonth(n.financialEntry!.date)),
                }.toList()..sort((a, b) => b.compareTo(a)))
                  DropdownMenuItem(value: m, child: Text(m)),
              ],
              onChanged: _saving
                  ? null
                  : (v) => setState(() {
                      _period = v!;
                      _load();
                    }),
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const ValueKey('budget-amount'),
              controller: _amount,
              enabled: !_saving,
              decoration: InputDecoration(labelText: 'Límite ($_currency)'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) =>
                  FinancialEntry.parseAmount(v ?? '', _currency) == null
                  ? 'Ingresa un límite mayor que cero'
                  : null,
            ),
            if (_error != null) Text(_error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Guardando…' : 'Guardar'),
        ),
      ],
    ),
  );
}
