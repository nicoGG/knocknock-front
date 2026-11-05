import 'expense_style.dart';
import 'expense_dashboard.dart';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'personal_expenses_client.dart';

String _money(dynamic value) {
  final amount = (value as num?) ?? 0;
  return '${amount < 0 ? '-' : ''}\$${NumberFormat.decimalPattern('es_CL').format(amount.abs())}';
}

String _date(dynamic value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  return parsed == null ? 'Sin fecha' : DateFormat('dd/MM/yyyy').format(parsed);
}

List<Map<String, dynamic>> _rows(dynamic value) =>
    (value as List).map((v) => Map<String, dynamic>.from(v as Map)).toList();

class PersonalExpensesPage extends StatefulWidget {
  const PersonalExpensesPage({super.key, required this.client});
  final PersonalExpensesClient client;
  @override
  State<PersonalExpensesPage> createState() => _PersonalExpensesPageState();
}

class _PersonalExpensesPageState extends State<PersonalExpensesPage> {
  List<Map<String, dynamic>> _statements = [];
  bool _loading = true;
  bool _importing = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    widget.client.close();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final result = await widget.client.list();
      if (mounted) {
        setState(() {
          _statements = result;
          _loading = false;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _message(error);
        });
      }
    }
  }

  String _message(Object error) => error is PersonalExpensesFailure
      ? error.message
      : 'No se pudo procesar el archivo. Inténtalo nuevamente.';
  Future<void> _import() async {
    setState(() => _importing = true);
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Estado de cuenta PDF',
            extensions: ['pdf'],
            uniformTypeIdentifiers: ['com.adobe.pdf'],
          ),
        ],
      );
      if (file == null) return;
      if (await file.length() > 5 * 1024 * 1024) {
        throw const PersonalExpensesFailure(
          'El PDF debe pesar como máximo 5 MB.',
        );
      }
      final bytes = await file.readAsBytes();
      final result = await widget.client.preview(bytes);
      if (!mounted) return;
      if (result['duplicate'] == true) {
        throw const PersonalExpensesFailure(
          'Ya hay un estado de esta cuenta para ese mes. Puedes eliminarlo para reemplazarlo.',
        );
      }
      final save = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PersonalStatementPage(
            statement: Map<String, dynamic>.from(result['statement'] as Map),
            preview: true,
          ),
        ),
      );
      if (save != true || !mounted) return;
      await widget.client.save(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Estado de cuenta importado')),
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_message(error))));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> statement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar estado de cuenta?'),
        content: const Text(
          'Se eliminarán todos sus movimientos de Gastos personales.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.client.remove(statement['id'] as String);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_message(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final empty = !_loading && _error == null && _statements.isEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Gastos personales')),
      body: ExpenseBackground(
        child: SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 14,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'SOLO PARA TI',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.primary,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Tu gasto, mes a mes',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Tus compras, cuotas y cargos, en un solo lugar.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  ExpenseSurface(
                    child: Column(
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          color: colors.onSurfaceVariant,
                          size: 32,
                        ),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  )
                else if (empty) ...[
                  ExpenseSurface(
                    highlighted: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _StatementIllustration(),
                        const SizedBox(height: 20),
                        Text(
                          'Empieza con tu primer mes',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Importa tu estado de cuenta CMR y descubre cómo se distribuyen tus gastos.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _importButton(),
                        const SizedBox(height: 10),
                        Text(
                          'PDF CMR · Hasta 5 MB',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Así de simple', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  const ExpenseSurface(
                    child: Column(
                      children: [
                        _ImportStep(
                          icon: Icons.upload_file_rounded,
                          title: 'Elige tu PDF',
                          detail: 'Usa el estado original de tu tarjeta CMR.',
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Divider(height: 1),
                        ),
                        _ImportStep(
                          icon: Icons.fact_check_outlined,
                          title: 'Revisa y confirma',
                          detail: 'Comprueba el desglose antes de guardarlo.',
                        ),
                      ],
                    ),
                  ),
                ],
                if (_statements.isNotEmpty) ...[
                  ExpenseDashboard(
                    statements: _statements,
                    onImport: _importing ? null : _import,
                    onDelete: _importing ? null : _delete,
                    onOpen: (statement) => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            PersonalStatementPage(statement: statement),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                if (!empty) _importButton(),
                const SizedBox(height: 16),
                Theme(
                  data: theme.copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                    childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                    leading: Icon(
                      Icons.verified_user_outlined,
                      size: 20,
                      color: colors.onSurfaceVariant,
                    ),
                    title: Text(
                      'Tu información, privada',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: [
                      Text(
                        'Solo tú puedes ver estos movimientos. NockNock procesa el PDF y no lo conserva; guarda el desglose en tu cuenta.\n\nUsa un PDF CMR original, sin contraseña, de hasta 5 MB y 30 páginas.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
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

  Widget _importButton() => FilledButton.icon(
    onPressed: _importing ? null : _import,
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    icon: _importing
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.upload_file_rounded, size: 21),
    label: Text(
      _importing ? 'Procesando PDF…' : 'Subir estado PDF',
      textAlign: TextAlign.center,
    ),
  );
}

class _ImportStep extends StatelessWidget {
  const _ImportStep({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, size: 21, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 3),
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatementIllustration extends StatelessWidget {
  const _StatementIllustration();
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: SizedBox(
        height: 112,
        child: Center(
          child: SizedBox(
            width: 144,
            height: 112,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.primary.withValues(alpha: .08),
                  ),
                ),
                Transform.rotate(
                  angle: -.12,
                  child: Container(
                    width: 68,
                    height: 88,
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colors.primary.withValues(alpha: .3),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colors.shadow.withValues(alpha: .12),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.receipt_long_rounded,
                      size: 44,
                      color: colors.primary,
                    ),
                  ),
                ),
                Positioned(
                  right: 14,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: colors.surface, width: 3),
                    ),
                    child: Icon(
                      Icons.insights_rounded,
                      color: colors.onPrimaryContainer,
                      size: 24,
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
}

class PersonalStatementPage extends StatefulWidget {
  const PersonalStatementPage({
    super.key,
    required this.statement,
    this.preview = false,
  });
  final Map<String, dynamic> statement;
  final bool preview;
  @override
  State<PersonalStatementPage> createState() => _PersonalStatementPageState();
}

class _PersonalStatementPageState extends State<PersonalStatementPage> {
  String _search = '';
  String? _card;
  String? _kind;
  static const _kinds = {
    'purchase': 'Compras',
    'refund': 'Devoluciones',
    'payment': 'Pagos',
    'charge': 'Cargos e impuestos',
  };
  @override
  Widget build(BuildContext context) {
    final s = widget.statement;
    final totals = s['totals'] as Map;
    final cards = _rows(s['cards']);
    final movements = _rows(s['movements'])
        .where(
          (m) =>
              (_card == null ||
                  (_card == 'unknown'
                      ? m['cardLast4'] == null
                      : m['cardLast4'] == _card)) &&
              (_kind == null || m['kind'] == _kind) &&
              '${m['description']} ${m['location']}'.toLowerCase().contains(
                _search.toLowerCase(),
              ),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.preview ? 'Revisar importación' : 'Estado de cuenta',
        ),
      ),
      bottomNavigationBar: widget.preview
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Icon(Icons.check),
                  label: const Text('Confirmar e importar movimientos'),
                ),
              ),
            )
          : null,
      body: ExpenseBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              ExpenseSurface(
                highlighted: true,
                padding: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ExpenseEyebrow(
                        icon: Icons.credit_card_rounded,
                        label: 'ESTADO DE CUENTA',
                      ),
                      const SizedBox(height: 14),
                      Text(
                        s['issuer'] as String,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        cards.isEmpty
                            ? 'Tarjeta no identificada'
                            : cards
                                  .map(
                                    (c) => '${c['role']} · •••• ${c['last4']}',
                                  )
                                  .join('  '),
                      ),
                      Text('Contrato •••• ${s['contractLast4']}'),
                      const SizedBox(height: 20),
                      const Divider(height: 28),
                      const Text('Total facturado'),
                      Text(
                        _money(s['totalBilled']),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text('Pago mínimo ${_money(s['minimumPayment'])}'),
                      const SizedBox(height: 12),
                      ExpenseNotice(
                        icon: Icons.event_outlined,
                        text: 'Vence ${_date(s['dueDate'])}',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Período ${_date(s['periodStart'])} al ${_date(s['periodEnd'])}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ExpenseMetricGrid(
                values: {
                  'Compras del mes': _money(totals['purchases']),
                  'Devoluciones': _money(totals['refunds']),
                  'Cargos': _money(totals['charges']),
                  'Pagos realizados': _money(totals['payments']),
                },
              ),
              const SizedBox(height: 12),
              ExpenseNotice(
                text:
                    'Suma de cargos del mes: ${_money(totals['billed'])} · Diferencia con facturado: ${_money(totals['difference'])}',
              ),
              const SizedBox(height: 8),
              const ExpenseNotice(
                text: 'Los pagos realizados no se descuentan otra vez del cargo mensual. Las cuotas 00 aún no se facturan.',
              ),
              for (final warning in s['warnings'] as List)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ExpenseNotice(
                    icon: Icons.info_outline_rounded,
                    text: '$warning',
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                'Movimientos',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Buscar comercio o ciudad',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('Todas las tarjetas'),
                    selected: _card == null,
                    onSelected: (_) => setState(() => _card = null),
                  ),
                  for (final c in cards)
                    ChoiceChip(
                      label: Text('•••• ${c['last4']}'),
                      selected: _card == c['last4'],
                      onSelected: (_) =>
                          setState(() => _card = c['last4'] as String),
                    ),
                  ChoiceChip(
                    label: const Text('Sin asignar'),
                    selected: _card == 'unknown',
                    onSelected: (_) => setState(() => _card = 'unknown'),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('Todos'),
                    selected: _kind == null,
                    onSelected: (_) => setState(() => _kind = null),
                  ),
                  for (final kind in _kinds.entries)
                    ChoiceChip(
                      label: Text(kind.value),
                      selected: _kind == kind.key,
                      onSelected: (_) => setState(() => _kind = kind.key),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '${movements.length} movimientos',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (movements.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No hay movimientos con estos filtros.'),
                ),
              for (final m in movements)
                ExpenseSurface(
                  padding: EdgeInsets.zero,
                  margin: const EdgeInsets.only(top: 10),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    title: Text(m['description'] as String),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 6),
                        Text(
                          '${_date(m['date'])} · ${m['cardLast4'] == null ? 'Sin tarjeta indicada' : '•••• ${m['cardLast4']}'}\n${_kinds[m['kind']]}${m['installments'] == null ? '' : ' · Cuota ${m['installment']}/${m['installments']}'}',
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _money(
                            m['kind'] == 'payment'
                                ? m['operationAmount']
                                : m['billedAmount'],
                          ),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: (m['operationAmount'] as num) < 0
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                        ),
                      ],
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            [
                              'Sección: ${m['section']}',
                              if ((m['location'] as String).isNotEmpty)
                                'Lugar: ${m['location']}',
                              'Monto operación: ${_money(m['operationAmount'])}',
                              'Total a pagar de la operación: ${_money(m['totalAmount'])}',
                              'Cargo en este estado: ${_money(m['billedAmount'])}',
                              if (m['firstCharge'] != null)
                                'Primer cargo: ${m['firstCharge']}',
                              if (m['installment'] == 0)
                                'Pendiente de facturar',
                            ].join('\n'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
