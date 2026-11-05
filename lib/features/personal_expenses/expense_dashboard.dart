import 'expense_style.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'expense_history.dart';

String expenseMoney(num n) =>
    '${n < 0 ? '-' : ''}\$${NumberFormat.decimalPattern('es_CL').format(n.abs())}';
String expenseMonthLabel(String key) {
  const names = [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];
  final date = DateTime.parse('$key-01');
  return '${names[date.month - 1]} ${date.year}';
}

class ExpenseDashboard extends StatefulWidget {
  const ExpenseDashboard({
    super.key,
    required this.statements,
    required this.onOpen,
    required this.onDelete,
    required this.onImport,
  });
  final List<Map<String, dynamic>> statements;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final ValueChanged<Map<String, dynamic>>? onDelete;
  final VoidCallback? onImport;
  @override
  State<ExpenseDashboard> createState() => _ExpenseDashboardState();
}

class _ExpenseDashboardState extends State<ExpenseDashboard> {
  String? _month;
  int _view = 0;
  Widget _heading(String label) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(label, style: Theme.of(context).textTheme.titleLarge),
  );
  Widget _metric(String title, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: ExpenseSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    ),
  );
  Widget _note(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: ExpenseNotice(text: text),
  );
  Widget _step(String title, String text) => ExpenseSurface(
    margin: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final history = ExpenseHistory(widget.statements);
    if (history.months.isEmpty) return const SizedBox.shrink();
    final current = history.month(_month ?? '') ?? history.months.first;
    final annual = history.months
        .where((m) => m.key.startsWith(current.key.substring(0, 4)))
        .toList();
    final annualTotal = annual.fold<int>(0, (s, m) => s + m.net);
    final delta = history.delta(current);
    final percent = history.percent(current);
    final recurring = history.recurringMerchants(current);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('expense-month-${current.key}'),
          initialValue: current.key,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Mes de facturación',
            prefixIcon: Icon(Icons.calendar_month_outlined),
          ),
          items: history.months
              .map(
                (m) => DropdownMenuItem(
                  value: m.key,
                  child: Text(expenseMonthLabel(m.key)),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _month = v),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final entry in {
              0: 'Resumen',
              1: 'Historial',
              2: 'Guía de gastos',
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: _view == entry.key,
                onSelected: (_) => setState(() => _view = entry.key),
              ),
          ],
        ),
        if (_view == 0) ...[
          _heading(expenseMonthLabel(current.key)),
          ExpenseSurface(
            highlighted: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ExpenseEyebrow(
                  icon: Icons.insights_rounded,
                  label: 'RESUMEN DEL MES',
                ),
                const SizedBox(height: 16),
                const Text('Gasto neto facturado del mes'),
                const SizedBox(height: 8),
                Text(
                  expenseMoney(current.net),
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  '${current.statements.length} ${current.statements.length == 1 ? 'estado' : 'estados'} · ${current.movements.length} movimientos',
                ),
                const SizedBox(height: 16),
                ExpenseNotice(
                  text: delta == null
                      ? 'Sin comparación: falta el mes anterior o cambian las cuentas importadas.'
                      : '${delta > 0
                            ? 'Subió'
                            : delta < 0
                            ? 'Bajó'
                            : 'Sin cambios'} ${expenseMoney(delta.abs())}${percent == null ? '' : ' (${percent.abs().toStringAsFixed(1)}%)'} respecto al mes anterior.',
                ),
              ],
            ),
          ),
          _note(
            'Compras y cuotas cobradas + cargos − devoluciones. Los pagos realizados se muestran aparte. Solo incluye estados importados; no incluye efectivo ni otras cuentas.',
          ),
          ExpenseMetricGrid(
            values: {
              'Compras y cuotas cobradas': expenseMoney(
                current.sum('purchases'),
              ),
              'Devoluciones': expenseMoney(current.sum('refunds')),
              'Cargos e impuestos': expenseMoney(current.sum('charges')),
              'Pagos registrados en los estados': expenseMoney(
                current.sum('payments'),
              ),
            },
          ),
          if (current.invoiced != current.net)
            _note(
              'El total indicado por el banco es ${expenseMoney(current.invoiced)}. Hay una diferencia de ${expenseMoney(current.invoiced - current.net)}: revisa los estados antes de interpretar el resumen.',
            ),
          _heading('Evolución mensual'),
          _note(
            'Toca un mes para abrirlo. Un mes sin estado no equivale a gasto cero.',
          ),
          for (final month in annual.reversed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: InkWell(
                onTap: () => setState(() => _month = month.key),
                borderRadius: BorderRadius.circular(26),
                child: ExpenseSurface(
                  highlighted: month.key == current.key,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${expenseMonthLabel(month.key)} · ${expenseMoney(month.net)}',
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: annual.every((m) => m.net <= 0)
                            ? 0
                            : (month.net /
                                      annual
                                          .map((m) => m.net)
                                          .reduce((a, b) => a > b ? a : b))
                                  .clamp(0, 1),
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(8),
                        semanticsLabel:
                            '${expenseMonthLabel(month.key)}: ${expenseMoney(month.net)}',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          _metric(
            'Acumulado ${current.key.substring(0, 4)} · ${annual.length} meses importados',
            expenseMoney(annualTotal),
          ),
          _metric(
            'Promedio por mes importado',
            expenseMoney((annualTotal / annual.length).round()),
          ),
          _heading('Dónde se concentra tu gasto'),
          _note(
            'Secciones del PDF y montos de compras cobrados este mes, antes de devoluciones.',
          ),
          for (final section in current.sections.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(section.key),
              subtitle: Text(expenseMoney(section.value)),
            ),
          _heading('Comercios con mayor gasto'),
          for (final merchant in current.merchants.entries.take(5))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.storefront_outlined),
              title: Text(merchant.key),
              subtitle: Text(expenseMoney(merchant.value)),
            ),
          _heading('Cuotas y gastos habituales'),
          _metric(
            'Cuotas cobradas en este mes',
            expenseMoney(current.installmentCharges),
          ),
          _note(
            '${current.pendingPurchases} compras con cuota 00, aún sin facturar. Los próximos cargos no se estiman a partir del monto original.',
          ),
          if (recurring.isNotEmpty)
            _note(
              'Comercios presentes también el mes anterior: ${recurring.take(10).join(', ')}. No necesariamente son suscripciones; se excluyen compras en varias cuotas.',
            )
          else
            _note(
              'Aún no hay comercios habituales detectados entre meses consecutivos comparables.',
            ),
          _heading('Estados de este mes'),
          ..._statements(current),
        ],
        if (_view == 1) ...[
          _heading('Tu historial de ${current.key.substring(0, 4)}'),
          _note(
            'Puedes subir cada mes un estado por cuenta. El mes se obtiene del PDF, aunque lo subas después. Los estados anteriores se conservan.',
          ),
          OutlinedButton.icon(
            onPressed: widget.onImport,
            icon: const Icon(Icons.upload_file),
            label: const Text('Subir otro mes'),
          ),
          for (var number = 12; number >= 1; number--)
            Builder(
              builder: (context) {
                final key =
                    '${current.key.substring(0, 4)}-${number.toString().padLeft(2, '0')}';
                final month = history.month(key);
                return ExpenseSurface(
                  padding: EdgeInsets.zero,
                  margin: const EdgeInsets.only(top: 10),
                  highlighted: month != null,
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary
                            .withValues(alpha: month == null ? .04 : .12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        month == null
                            ? Icons.calendar_today_outlined
                            : Icons.receipt_long_outlined,
                        size: 22,
                        color: month == null
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    key: ValueKey('history-$key'),
                    title: Text(expenseMonthLabel(key)),
                    subtitle: Text(
                      month == null
                          ? 'Sin estado importado'
                          : '${expenseMoney(month.net)} · ${month.statements.length} ${month.statements.length == 1 ? 'estado' : 'estados'}',
                    ),
                    children: month == null
                        ? [
                            TextButton(
                              onPressed: widget.onImport,
                              child: const Text('Subir PDF de este mes'),
                            ),
                          ]
                        : _statements(month),
                  ),
                );
              },
            ),
        ],
        if (_view == 2) ...[
          _heading('Tu guía de gastos personales'),
          _note(
            'Una rutina para entender tus estados y seguir los cambios de mes a mes.',
          ),
          _step(
            '1. Completa tu historial',
            'Sube el PDF de cada cuenta cuando esté disponible. El mes corresponde a la fecha de facturación, no al día en que subes el archivo. ${annual.length} meses tienen datos en ${current.key.substring(0, 4)}. Revisa los espacios sin estado en Historial.',
          ),
          _step(
            '2. Revisa el desglose',
            'Abre cada estado y comprueba comercios, devoluciones y tarjeta. Una operación sin tarjeta indicada permanece sin asignar. ${current.movements.where((m) => m['cardLast4'] == null).length} movimientos de este mes están sin asignar.',
          ),
          _step(
            '3. Distingue compra, cuota y pago',
            'Una compra en cuotas aparece por el cargo mensual, no por el precio completo. Este mes hay ${expenseMoney(current.installmentCharges)} en cuotas cobradas. Los pagos de tarjeta no se cuentan otra vez como gasto.',
          ),
          _step(
            '4. Observa qué cambió',
            delta == null
                ? 'Carga el mes anterior para las mismas cuentas antes de comparar. Comparar cuentas distintas puede dar una impresión equivocada del cambio.'
                : 'La diferencia frente al mes anterior es ${expenseMoney(delta)}. Revisa los comercios principales y los cargos para entender qué explica el cambio.',
          ),
          _step(
            '5. Revisa cargos y comercios habituales',
            'Este mes figuran ${expenseMoney(current.sum('charges'))} en cargos e impuestos. ${recurring.isEmpty ? 'Con más meses podrás reconocer comercios repetidos.' : 'Se repiten ${recurring.length} comercios respecto del mes anterior.'} Abre el detalle para identificar qué corresponde a cada movimiento.',
          ),
          _step(
            '6. Consulta los vencimientos',
            'Cada estado conserva su fecha de vencimiento, total facturado y pago mínimo. La importación no confirma si ya pagaste: consulta el estado actual en tu banco.',
          ),
          _step(
            '7. Cierra el mes y vuelve a comparar',
            'Elige un gasto que quieras observar el próximo mes y revisa su evolución cuando subas el nuevo PDF. Completa el panorama con tus gastos en efectivo y otras cuentas, que no aparecen en estos resúmenes.',
          ),
          OutlinedButton(
            onPressed: () => setState(() => _view = 1),
            child: const Text('Revisar meses pendientes'),
          ),
        ],
      ],
    );
  }

  List<Widget> _statements(ExpenseMonth month) => [
    for (final statement in month.statements)
      ExpenseSurface(
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          leading: const Icon(Icons.credit_card),
          title: Text(
            '${statement['issuer']} · cuenta •••• ${statement['contractLast4']}',
          ),
          subtitle: Text(
            '${(statement['cards'] as List).map((c) => '•••• ${c['last4']}').join(', ')}\n${expenseMoney(statement['totalBilled'] as num)} · Vence ${_statementDate(statement['dueDate'])}',
          ),
          onTap: () => widget.onOpen(statement),
          trailing: IconButton(
            tooltip: 'Eliminar estado',
            onPressed: widget.onDelete == null
                ? null
                : () => widget.onDelete!(statement),
            icon: const Icon(Icons.delete_outline),
          ),
        ),
      ),
  ];
}

String _statementDate(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null ? 'Sin fecha' : DateFormat('dd/MM/yyyy').format(date);
}
