import 'package:nocknock/features/finance/financial_style.dart';
import 'package:nocknock/features/notes/presentation/widgets/reminder_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:nocknock/features/notes/presentation/widgets/liquid_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nocknock/features/finance/financial_entry.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/logic/notes_error_message.dart';
import 'package:nocknock/features/notes/presentation/note_attachment_picker.dart';
import 'package:nocknock/features/notes/presentation/note_attachment_download.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_pdf_viewer.dart';

Future<bool?> showFinancialEntryEditor({
  required BuildContext context,
  required NoteList list,
  required String author,
  required Future<void> Function(NoteDraft) onSave,
  Note? note,
  Future<NoteAttachment> Function(String)? attachmentLoader,
  Future<void> Function()? onDelete,
  Future<bool> Function()? onHistory,
}) => showLiquidBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 680),
  builder: (_) => FinancialEntryEditor(
    list: list,
    author: author,
    onSave: onSave,
    note: note,
    attachmentLoader: attachmentLoader,
    onDelete: onDelete,
    onHistory: onHistory,
  ),
);

class FinancialEntryEditor extends StatefulWidget {
  const FinancialEntryEditor({
    required this.list,
    required this.author,
    required this.onSave,
    this.note,
    this.attachmentLoader,
    this.onDelete,
    this.onHistory,
    super.key,
  });
  final NoteList list;
  final String author;
  final Note? note;
  final Future<void> Function(NoteDraft) onSave;
  final Future<NoteAttachment> Function(String)? attachmentLoader;
  final Future<void> Function()? onDelete;
  final Future<bool> Function()? onHistory;
  @override
  State<FinancialEntryEditor> createState() => _FinancialEntryEditorState();
}

class _FinancialEntryEditorState extends State<FinancialEntryEditor> {
  final _form = GlobalKey<FormState>();
  late final _existing = widget.note?.financialEntry;
  late final _title = TextEditingController(text: widget.note?.title ?? '');
  late final _amount = TextEditingController(
    text: _existing?.editableAmount ?? '',
  );
  late final _party = TextEditingController(
    text: _existing?.counterparty ?? '',
  );
  late final _detail = TextEditingController(text: widget.note?.content ?? '');
  late DateTime _date = _existing?.date ?? DateTime.now();
  late String _status =
      widget.list.configuration.statuses.contains(_existing?.status)
      ? _existing!.status
      : 'pending';
  late final _currency =
      _existing?.currency ?? widget.list.configuration.currency;
  late final List<NoteAttachment> _attachments = [
    ...?widget.note?.photoAttachments,
  ];
  late final List<FinancialPayment> _payments = [...?_existing?.payments];
  late final _participants = TextEditingController(
    text: _existing?.participants.join(', ') ?? '',
  );
  late final _payer = TextEditingController(text: _existing?.paidBy ?? '');
  late final _delivery = TextEditingController(
    text: _existing?.deliveryDays?.toString() ?? '',
  );
  late DateTime? _due = _existing?.effectiveDueDate(
    receivable: widget.list.configuration.type.name == 'receivables',
  );
  late DateTime? _validUntil = _existing?.validUntil;
  late DateTime? _reminder = widget.note?.reminderAt;
  late ReminderRecurrence? _recurrence = widget.note?.reminderRecurrence;
  late bool _shared = _existing?.participants.isNotEmpty ?? false;
  List<String> get _people => _participants.text
      .split(',')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  int get _paid => _payments.fold(0, (sum, p) => sum + p.amountMinor);
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _party.dispose();
    _detail.dispose();
    _participants.dispose();
    _payer.dispose();
    _delivery.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final amount = FinancialEntry.parseAmount(_amount.text, _currency)!;
    if (_paid > amount ||
        (_payments.isNotEmpty && _status == 'paid' && _paid != amount)) {
      setState(
        () => _error = 'Los abonos deben coincidir con el monto al marcar como pagado. Registra el saldo restante o conserva Pendiente.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final entry = FinancialEntry(
      amountMinor: FinancialEntry.parseAmount(_amount.text, _currency)!,
      currency: _currency,
      counterparty: _party.text.trim(),
      date: _date,
      status: _paid == amount ? 'paid' : _status,
      kind: _existing?.kind ?? 'entry',
      payments: _payments,
      participants: _shared ? _people : const [],
      paidBy: _shared || _existing?.isSettlement == true
          ? _payer.text.trim()
          : '',
      dueDate: _due,
      validUntil: _validUntil,
      deliveryDays: int.tryParse(_delivery.text),
    );
    if (FinancialEntry.tryDecode(entry.encoded) == null) {
      setState(() {
        _saving = false;
        _error =
            'Revisa el monto, los participantes y los abonos antes de guardar.';
      });
      return;
    }
    try {
      final previous = widget.note;
      await widget.onSave(
        NoteDraft(
          title: _title.text.trim(),
          content: _detail.text.trim(),
          financialData: entry.encoded,
          contentDelta: _detail.text.trim() == previous?.content
              ? previous?.contentDelta
              : null,
          color: previous?.color ?? NoteColor.green,
          category: NoteCategory.finance,
          authorName: previous?.authorName ?? widget.author,
          attachments: List.of(_attachments),
          checklist: previous?.checklist ?? const [],
          assigneeUids: previous?.assignedUserIds,
          customAssigneeNames: previous?.assignedCustomNames,
          reminderAt: entry.isClosed ? null : _reminder,
          reminderRecurrence: entry.isClosed ? null : _recurrence,
          isCompleted: previous?.isCompleted ?? false,
          isPinned: previous?.isPinned ?? false,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = notesErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate(
    String label,
    DateTime? value,
    ValueChanged<DateTime> update,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      helpText: label,
    );
    if (picked != null && mounted) setState(() => update(picked));
  }

  Future<void> _addPayment() async {
    final total = FinancialEntry.parseAmount(_amount.text, _currency);
    if (total == null || total <= _paid) {
      setState(() => _error = 'Ingresa un monto válido con saldo pendiente.');
      return;
    }
    final payment = await showDialog<FinancialPayment>(
      context: context,
      builder: (_) => _PaymentDialog(
        currency: _currency,
        balance: total - _paid,
        attachments: _attachments,
      ),
    );
    if (payment != null && mounted) {
      setState(() {
        _payments.add(payment);
        _status = _paid == total ? 'paid' : 'pending';
        _error = null;
      });
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar este registro?'),
        content: const Text(
          'Se moverá a la papelera y dejará de sumar en los totales.',
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
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onDelete!();
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = notesErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _attach() async {
    try {
      final picked = await pickNoteAttachments(
        context: context,
        remaining: noteAttachmentMaxCount - _attachments.length,
      );
      if (mounted) setState(() => _attachments.addAll(picked));
    } on NoteAttachmentPickFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _view(NoteAttachment attachment) async {
    if (attachment.isPdf) {
      await showNotePdfViewer(
        context,
        attachment: attachment,
        loader: widget.attachmentLoader,
      );
      return;
    }
    try {
      final source = attachment.dataBase64 != null
          ? attachment
          : await widget.attachmentLoader?.call(attachment.id) ?? attachment;
      final bytes = decodeNoteAttachmentBytes(source);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              Flexible(
                child: InteractiveViewer(
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudo abrir el comprobante. Reintenta con conexión.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.list.configuration;
    return PopScope(
      canPop: !_saving,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          12,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              key: const ValueKey('financial-entry-editor'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    FinancialIconBadge(
                      icon: FinancialStyle.typeIcon(config.type),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.note == null
                            ? config.entryLabel
                            : 'Editar registro',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(
                  '${config.label} · ${widget.list.name}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const ValueKey('financial-title'),
                  controller: _title,
                  enabled: !_saving,
                  autofocus: widget.note == null,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Concepto',
                    prefixIcon: Icon(Icons.description_outlined),
                    hintText: 'Ej. Materiales, reparación o préstamo',
                  ),
                  validator: (value) => value?.trim().isEmpty != false
                      ? 'Escribe un concepto'
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const ValueKey('financial-amount'),
                  controller: _amount,
                  enabled: !_saving,
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: _currency != 'CLP',
                  ),
                  decoration: InputDecoration(
                    labelText: 'Monto ($_currency)',
                    prefixIcon: Icon(FinancialStyle.currencyIcon(_currency)),
                    hintText: _currency == 'CLP' ? '15000' : '15000,50',
                    helperText: _currency == 'CLP'
                        ? 'Pesos enteros, sin puntos ni comas.'
                        : 'Usa coma o punto para los decimales, sin separadores de miles.',
                  ),
                  validator: (value) =>
                      FinancialEntry.parseAmount(value ?? '', _currency) == null
                      ? 'Ingresa un monto mayor que cero y válido para $_currency'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('financial-counterparty'),
                  controller: _party,
                  enabled: !_saving,
                  maxLength: 120,
                  decoration: InputDecoration(
                    labelText: config.counterpartyLabel,
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                  ),
                  validator: (value) =>
                      config.type.name == 'receivables' &&
                          value?.trim().isEmpty != false
                      ? 'Indica quién debe este monto'
                      : null,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: const ValueKey('financial-status'),
                  initialValue: _status,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Estado',
                    prefixIcon: Icon(Icons.flag_outlined),
                  ),
                  items: config.statuses
                      .map(
                        (status) => DropdownMenuItem(
                          value: status,
                          child: FinancialOptionLabel(
                            icon: FinancialStyle.statusIcon(status),
                            label: config.statusLabel(status),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _status = value!),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: Text('Fecha del registro'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(_date)),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: _saving
                      ? null
                      : () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100, 12, 31),
                          );
                          if (date != null && mounted) {
                            setState(() => _date = date);
                          }
                        },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_busy_outlined),
                  title: const Text('Vencimiento'),
                  subtitle: Text(
                    _due == null
                        ? 'Sin vencimiento'
                        : DateFormat('dd/MM/yyyy').format(_due!),
                  ),
                  onTap: _saving
                      ? null
                      : () => _pickDate(
                          'Vencimiento',
                          _due,
                          (date) => _due = date,
                        ),
                  trailing: _due == null
                      ? const Icon(Icons.add)
                      : IconButton(
                          tooltip: 'Quitar vencimiento',
                          icon: const Icon(Icons.close),
                          onPressed: _saving
                              ? null
                              : () => setState(() {
                                  _due = null;
                                  _reminder = null;
                                  _recurrence = null;
                                }),
                        ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Alerta de pago o cobro'),
                  subtitle: Text(
                    _reminder == null
                        ? 'Agregar recordatorio'
                        : DateFormat('dd/MM/yyyy HH:mm').format(_reminder!),
                  ),
                  onTap: _saving
                      ? null
                      : () async {
                          final choice = await showReminderSchedulePicker(
                            context,
                            currentReminder: _reminder,
                          );
                          if (choice != null && mounted) {
                            setState(() {
                              _reminder = choice.reminderAt;
                              _recurrence = choice.recurrence;
                            });
                          }
                        },
                  trailing: _reminder == null
                      ? const Icon(Icons.add)
                      : IconButton(
                          tooltip: 'Quitar alerta',
                          icon: const Icon(Icons.close),
                          onPressed: _saving
                              ? null
                              : () => setState(() {
                                  _reminder = null;
                                  _recurrence = null;
                                }),
                        ),
                ),
                if (_due != null &&
                    _reminder == null &&
                    DateTime(
                      _due!.year,
                      _due!.month,
                      _due!.day - 1,
                      9,
                    ).isAfter(DateTime.now()))
                  TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _reminder = DateTime(
                              _due!.year,
                              _due!.month,
                              _due!.day - 1,
                              9,
                            );
                            _recurrence = null;
                          }),
                    icon: const Icon(Icons.alarm_add),
                    label: const Text('Avisarme un día antes a las 09:00'),
                  ),
                if (config.type.name == 'quotations') ...[
                  TextFormField(
                    controller: _delivery,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Plazo de entrega (días)',
                      prefixIcon: Icon(Icons.local_shipping_outlined),
                    ),
                    validator: (v) =>
                        v == null ||
                            v.isEmpty ||
                            (int.tryParse(v) != null &&
                                int.parse(v) >= 0 &&
                                int.parse(v) <= 3650)
                        ? null
                        : 'Ingresa de 0 a 3650 días',
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_available_outlined),
                    title: const Text('Cotización válida hasta'),
                    subtitle: Text(
                      _validUntil == null
                          ? 'Sin fecha límite'
                          : DateFormat('dd/MM/yyyy').format(_validUntil!),
                    ),
                    onTap: _saving
                        ? null
                        : () => _pickDate(
                            'Validez de la cotización',
                            _validUntil,
                            (date) => _validUntil = date,
                          ),
                    trailing: _validUntil == null
                        ? null
                        : IconButton(
                            tooltip: 'Quitar validez',
                            icon: const Icon(Icons.close),
                            onPressed: _saving
                                ? null
                                : () => setState(() => _validUntil = null),
                          ),
                  ),
                ] else if (_existing?.isSettlement != true) ...[
                  const Divider(),
                  Text(
                    'Abonos e historial de pagos',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    'Abonado: ${FinancialEntry.formatAmount(_paid, _currency)}',
                  ),
                  for (final payment in _payments)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.payments_outlined),
                      title: Text(
                        FinancialEntry.formatAmount(
                          payment.amountMinor,
                          _currency,
                        ),
                      ),
                      subtitle: Text(
                        [
                          DateFormat('dd/MM/yyyy').format(payment.date),
                          if (payment.detail.isNotEmpty) payment.detail,
                          if (payment.receiptId != null) 'Comprobante asociado',
                        ].join(' · '),
                      ),
                      onTap: payment.receiptId == null
                          ? null
                          : () async {
                              final receipt = _attachments
                                  .where((a) => a.id == payment.receiptId)
                                  .firstOrNull;
                              if (receipt != null) await _view(receipt);
                            },
                      trailing: IconButton(
                        tooltip: 'Quitar abono (se guardará en el historial)',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _saving
                            ? null
                            : () => setState(() {
                                _payments.remove(payment);
                                _status = 'pending';
                              }),
                      ),
                    ),
                  OutlinedButton.icon(
                    key: const ValueKey('financial-add-payment'),
                    onPressed: _saving || _payments.length >= 50
                        ? null
                        : _addPayment,
                    icon: const Icon(Icons.add_card),
                    label: const Text('Registrar abono'),
                  ),
                  if (config.type.name != 'receivables')
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Dividir gasto entre personas'),
                      subtitle: const Text(
                        'Reparto en partes iguales, con ajuste exacto de centavos.',
                      ),
                      value: _shared,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _shared = v),
                    ),
                  if (_shared) ...[
                    TextFormField(
                      key: const ValueKey('financial-participants'),
                      controller: _participants,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Participantes separados por coma',
                        hintText: 'Ana, Pedro, María',
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (_) =>
                          _people.length < 2 ||
                              _people.length > 30 ||
                              _people.toSet().length != _people.length ||
                              _people.any((p) => p.length > 120) ||
                              (FinancialEntry.parseAmount(
                                        _amount.text,
                                        _currency,
                                      ) ??
                                      0) <
                                  _people.length
                          ? 'Indica de 2 a 30 nombres distintos y un monto suficiente para repartir'
                          : null,
                    ),
                    Wrap(
                      spacing: 6,
                      children: widget.list.collaborators
                          .map(
                            (p) => ActionChip(
                              label: Text(p.displayName),
                              onPressed: _saving
                                  ? null
                                  : () => setState(() {
                                      if (!_people.contains(p.displayName)) {
                                        _participants.text = [
                                          ..._people,
                                          p.displayName,
                                        ].join(', ');
                                      }
                                    }),
                            ),
                          )
                          .toList(),
                    ),
                    TextFormField(
                      key: const ValueKey('financial-paid-by'),
                      controller: _payer,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Quién pagó (nombre del participante)',
                      ),
                      validator: (v) => !_people.contains(v?.trim())
                          ? 'Elige un nombre incluido en los participantes'
                          : null,
                    ),
                    const Text(
                      'Cada participante debe su parte a quien pagó. El resumen muestra los saldos acumulados por moneda.',
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('financial-detail'),
                  controller: _detail,
                  enabled: !_saving,
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Detalle (opcional)',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Boletas, capturas y documentos',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  'Hasta $noteAttachmentMaxCount adjuntos. Fotos y PDF de hasta 5 MB.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                ..._attachments.map(
                  (attachment) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      attachment.isPdf
                          ? Icons.picture_as_pdf_outlined
                          : Icons.receipt_long_outlined,
                    ),
                    title: Text(
                      attachment.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _view(attachment),
                    trailing: IconButton(
                      tooltip: 'Quitar adjunto',
                      onPressed: _saving
                          ? null
                          : () =>
                                setState(() => _attachments.remove(attachment)),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('financial-attach'),
                  onPressed:
                      _saving || _attachments.length >= noteAttachmentMaxCount
                      ? null
                      : _attach,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Adjuntar boleta, captura o PDF'),
                ),
                if (widget.onHistory != null)
                  TextButton.icon(
                    icon: const Icon(Icons.history),
                    label: const Text('Historial del registro'),
                    onPressed: _saving
                        ? null
                        : () async {
                            final restored = await widget.onHistory!();
                            if (restored && context.mounted) {
                              Navigator.pop(context, true);
                            }
                          },
                  ),
                if (widget.onDelete != null)
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Eliminar registro'),
                    onPressed: _saving ? null : _delete,
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const ValueKey('financial-save'),
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Guardando…' : 'Guardar registro'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({
    required this.currency,
    required this.balance,
    required this.attachments,
  });
  final String currency;
  final int balance;
  final List<NoteAttachment> attachments;
  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _detail = TextEditingController();
  DateTime _date = DateTime.now();
  String? _receipt;
  @override
  void dispose() {
    _amount.dispose();
    _detail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Registrar abono'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Saldo: ${FinancialEntry.formatAmount(widget.balance, widget.currency)}',
            ),
            TextFormField(
              key: const ValueKey('payment-amount'),
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Monto (${widget.currency})',
              ),
              validator: (v) {
                final a = FinancialEntry.parseAmount(v ?? '', widget.currency);
                return a == null || a > widget.balance
                    ? 'Ingresa un abono mayor que cero y menor o igual al saldo'
                    : null;
              },
            ),
            TextFormField(
              controller: _detail,
              maxLength: 160,
              decoration: const InputDecoration(
                labelText: 'Detalle / referencia',
              ),
            ),
            ListTile(
              title: Text(DateFormat('dd/MM/yyyy').format(_date)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (d != null && mounted) setState(() => _date = d);
              },
            ),
            DropdownButtonFormField<String>(
              initialValue: _receipt,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Comprobante (opcional)',
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Sin comprobante'),
                ),
                ...widget.attachments.map(
                  (a) => DropdownMenuItem(
                    value: a.id,
                    child: Text(a.name, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (v) => _receipt = v == '' ? null : v,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const ValueKey('payment-save'),
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(
              context,
              FinancialPayment(
                id: const Uuid().v4(),
                amountMinor: FinancialEntry.parseAmount(
                  _amount.text,
                  widget.currency,
                )!,
                date: _date,
                detail: _detail.text.trim(),
                receiptId: _receipt,
              ),
            );
          }
        },
        child: const Text('Agregar'),
      ),
    ],
  );
}
