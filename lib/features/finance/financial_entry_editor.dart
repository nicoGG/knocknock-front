import 'package:nocknock/features/finance/financial_installment_preview.dart';
import 'package:nocknock/features/finance/receipt_scanner.dart';
import 'package:nocknock/features/finance/payment_method_field.dart';
import 'package:nocknock/features/notes/presentation/widgets/scroll_edge_fade.dart';
import 'package:nocknock/features/finance/financial_amount_input.dart';
import 'package:nocknock/core/widgets/liquid_dropdown.dart';
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
  late String? _method = _existing?.paymentMethod;
  late final _installments = TextEditingController(
    text: _existing?.installments?.toString() ?? '',
  );
  late final _existing = widget.note?.financialEntry;
  late final _title = TextEditingController(text: widget.note?.title ?? '');
  late final _amount = TextEditingController(
    text: financialAmountInput(_existing?.editableAmount ?? '', _currency),
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
  late DateTime? _due = _existing?.isDeferred == true
      ? _existing?.dueDate
      : _existing?.effectiveDueDate(
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
  bool get _isClosed => ['paid', 'accepted', 'rejected'].contains(_status);
  int get _paid => _payments.fold(0, (sum, p) => sum + p.amountMinor);
  bool _readingReceipt = false;
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _installments.dispose();
    _party.dispose();
    _detail.dispose();
    _participants.dispose();
    _payer.dispose();
    _delivery.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_readingReceipt) return;
    if (!_form.currentState!.validate()) return;
    final amount = parseFinancialAmountInput(_amount.text, _currency)!;
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
      paymentMethod: _method,
      installments: _method == 'credit'
          ? int.tryParse(_installments.text)
          : null,
      amountMinor: parseFinancialAmountInput(_amount.text, _currency)!,
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

  Future<void> _addPayment({FinancialPayment? existing}) async {
    final total = parseFinancialAmountInput(_amount.text, _currency);
    if (total == null || (existing == null && total <= _paid)) {
      setState(() => _error = 'Ingresa un monto válido con saldo pendiente.');
      return;
    }
    final result = await showDialog<(FinancialPayment, List<NoteAttachment>)>(
      context: context,
      builder: (_) => _PaymentDialog(
        currency: _currency,
        balance: total - _paid + (existing?.amountMinor ?? 0),
        existing: existing,
        attachments: _attachments,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        if (existing == null) {
          _payments.add(result.$1);
        } else {
          final index = _payments.indexWhere((p) => p.id == existing.id);
          if (index >= 0) _payments[index] = result.$1;
        }
        _attachments.addAll(result.$2);
        _status = _paid == total ? 'paid' : 'pending';
        _error = null;
      });
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => FinancialDialog(
        title: '¿Eliminar este registro?',
        icon: Icons.delete_outline,
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
        includeCamera: true,
      );
      if (!mounted || picked.isEmpty) return;
      setState(() {
        _attachments.addAll(picked);
        _readingReceipt = true;
      });
      try {
        final total = await suggestReceiptTotal(
          context,
          picked.first,
          _currency,
        );
        if (mounted && total != null) {
          setState(
            () => _amount.text = financialAmountInput(
              FinancialEntry(
                amountMinor: total,
                currency: _currency,
                counterparty: '',
                date: _date,
              ).editableAmount,
              _currency,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _readingReceipt = false);
      }
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final radius = BorderRadius.circular(22);
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: colors.surfaceContainerHigh.withValues(alpha: .38),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
          border: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(
              color: colors.outline.withValues(alpha: .20),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(
              color: colors.outline.withValues(alpha: .20),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(
              color: colors.primary.withValues(alpha: .7),
              width: 1.5,
            ),
          ),
        ),
        listTileTheme: theme.listTileTheme.copyWith(
          iconColor: colors.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          titleTextStyle: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          subtitleTextStyle: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ),
      child: PopScope(
        canPop: !_saving,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            12,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ScrollEdgeFade(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
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
                      textCapitalization: TextCapitalization.sentences,
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
                      inputFormatters: _currency == 'CLP'
                          ? [ClpThousandsInputFormatter()]
                          : null,
                      onChanged: (_) => setState(() {}),
                      enabled: !_saving,
                      keyboardType: TextInputType.numberWithOptions(
                        decimal: _currency != 'CLP',
                      ),
                      decoration: InputDecoration(
                        labelText: 'Monto ($_currency)',
                        prefixText: _currency == 'EUR' ? '€ ' : r'$ ',
                        prefixIcon: Icon(
                          FinancialStyle.currencyIcon(_currency),
                        ),
                        hintText: _currency == 'CLP' ? '15.000' : '15000,50',
                        helperText: _currency == 'CLP'
                            ? 'Pesos enteros; los miles se separan automáticamente.'
                            : 'Usa coma o punto para los decimales, sin separadores de miles.',
                      ),
                      validator: (value) =>
                          parseFinancialAmountInput(value ?? '', _currency) ==
                              null
                          ? 'Ingresa un monto mayor que cero y válido para $_currency'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    FinancialPaymentMethodField(
                      method: _method,
                      installments: _installments,
                      enabled: !_saving,
                      onChanged: (v) => setState(() {
                        _method = v;
                        if (v != 'credit') _installments.clear();
                      }),
                    ),
                    if (_method == 'credit')
                      FinancialInstallmentPreview(
                        amount: _amount,
                        installments: _installments,
                        currency: _currency,
                        firstDate: _due ?? financialMonthOffset(_date, 1),
                        paidMinor: _status == 'paid'
                            ? parseFinancialAmountInput(
                                    _amount.text,
                                    _currency,
                                  ) ??
                                  0
                            : _paid,
                      ),
                    TextFormField(
                      key: const ValueKey('financial-counterparty'),
                      controller: _party,
                      textCapitalization: TextCapitalization.sentences,
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
                    if (config.statuses.length == 2)
                      Column(
                        key: const ValueKey('financial-status-options'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Estado',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: config.statuses
                                .map(
                                  (status) => FinancialLiquidFilter(
                                    icon: FinancialStyle.statusIcon(status),
                                    label: config.statusLabel(status),
                                    selected: _status == status,
                                    onPressed: _saving
                                        ? null
                                        : () =>
                                              setState(() => _status = status),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      )
                    else
                      LiquidDropdownFormField<String>(
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
                      subtitle: Text(DateFormat('dd-MM-yyyy').format(_date)),
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
                      title: Text(
                        _method == 'credit'
                            ? 'Fecha de primera cuota'
                            : 'Vencimiento',
                      ),
                      subtitle: Text(
                        _due == null
                            ? (_method == 'credit'
                                  ? DateFormat('dd-MM-yyyy')
                                        .format(financialMonthOffset(_date, 1))
                                  : 'Sin vencimiento')
                            : DateFormat('dd-MM-yyyy').format(_due!),
                      ),
                      onTap: _saving
                          ? null
                          : () => _pickDate(
                              _method == 'credit'
                                  ? 'Fecha de primera cuota'
                                  : 'Vencimiento',
                              _due ??
                                  (_method == 'credit'
                                      ? financialMonthOffset(_date, 1)
                                      : null),
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
                        _isClosed
                            ? 'Sin alertas: el registro está cerrado'
                            : _reminder == null
                            ? 'Agregar recordatorio'
                            : DateFormat('dd/MM/yyyy HH:mm').format(_reminder!),
                      ),
                      onTap: _saving || _isClosed
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
                      trailing: _isClosed
                          ? null
                          : _reminder == null
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
                    if (!_isClosed &&
                        _due != null &&
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
                              : DateFormat('dd-MM-yyyy').format(_validUntil!),
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
                              DateFormat('dd-MM-yyyy').format(payment.date),
                              if (payment.detail.isNotEmpty) payment.detail,
                              if (payment.paymentMethod != null)
                                payment.paymentLabel,
                              if (payment.receiptId != null)
                                'Comprobante asociado',
                            ].join(' · '),
                          ),
                          onTap: _saving
                              ? null
                              : () => _addPayment(existing: payment),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (payment.receiptId != null)
                                IconButton(
                                  tooltip: 'Ver comprobante del abono',
                                  icon: const Icon(Icons.receipt_long_rounded),
                                  onPressed: () async {
                                    final receipt = _attachments
                                        .where((a) => a.id == payment.receiptId)
                                        .firstOrNull;
                                    if (receipt != null) await _view(receipt);
                                  },
                                ),
                              IconButton(
                                tooltip: 'Quitar abono (se guardará en el historial)',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: _saving
                                    ? null
                                    : () => setState(() {
                                        _payments.remove(payment);
                                        _status = 'pending';
                                      }),
                              ),
                            ],
                          ),
                        ),
                      OutlinedButton.icon(
                        key: const ValueKey('financial-add-payment'),
                        onPressed:
                            _saving ||
                                _payments.length >= 50 ||
                                (parseFinancialAmountInput(
                                          _amount.text,
                                          _currency,
                                        ) ??
                                        0) <=
                                    _paid
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
                        FormField<List<String>>(
                          key: const ValueKey('financial-participants'),
                          validator: (_) =>
                              _people.length < 2 ||
                                  _people.length > 30 ||
                                  _people.toSet().length != _people.length ||
                                  _people.any((p) => p.length > 120) ||
                                  (parseFinancialAmountInput(
                                            _amount.text,
                                            _currency,
                                          ) ??
                                          0) <
                                      _people.length
                              ? 'Selecciona de 2 a 30 personas y un monto suficiente para repartir'
                              : null,
                          builder: (field) => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Participantes · ${_people.length} seleccionados',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              for (final person in widget.list.collaborators)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: FinancialParticipantOption(
                                    name: person.displayName,
                                    photoUrl: person.photoUrl,
                                    selected: _people.contains(
                                      person.displayName,
                                    ),
                                    onPressed: _saving
                                        ? null
                                        : () {
                                            setState(() {
                                              final names = List<String>.of(
                                                _people,
                                              );
                                              if (names.contains(
                                                person.displayName,
                                              )) {
                                                names.remove(
                                                  person.displayName,
                                                );
                                              } else if (names.length < 30) {
                                                names.add(person.displayName);
                                              }
                                              _participants.text = names.join(
                                                ', ',
                                              );
                                              if (!names.contains(
                                                _payer.text.trim(),
                                              )) {
                                                _payer.text = names.isEmpty
                                                    ? ''
                                                    : names.first;
                                              }
                                            });
                                            field.didChange(_people);
                                          },
                                  ),
                                ),
                              for (final name in _people.where(
                                (n) => !widget.list.collaborators.any(
                                  (p) => p.displayName == n,
                                ),
                              ))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: FinancialParticipantOption(
                                    name: name,
                                    selected: true,
                                    onPressed: _saving
                                        ? null
                                        : () => setState(() {
                                            _participants.text = _people
                                                .where((n) => n != name)
                                                .join(', ');
                                            if (_payer.text == name) {
                                              _payer.text = _people.isEmpty
                                                  ? ''
                                                  : _people.first;
                                            }
                                          }),
                                  ),
                                ),
                              if (field.hasError)
                                Text(
                                  field.errorText!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text('Agregar otras personas'),
                          subtitle: const Text(
                            'Para gastos con personas que no están en la lista',
                          ),
                          children: [
                            TextFormField(
                              key: const ValueKey(
                                'financial-manual-participants',
                              ),
                              controller: _participants,
                              textCapitalization: TextCapitalization.words,
                              enabled: !_saving,
                              decoration: const InputDecoration(
                                labelText: 'Nombres separados por coma',
                              ),
                              onChanged: (_) => setState(() {
                                if (!_people.contains(_payer.text.trim())) {
                                  _payer.text = _people.isEmpty
                                      ? ''
                                      : _people.first;
                                }
                              }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        FormField<String>(
                          key: const ValueKey('financial-paid-by'),
                          validator: (_) =>
                              !_people.contains(_payer.text.trim())
                              ? 'Elige quién pagó entre los participantes'
                              : null,
                          builder: (field) => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Quién pagó',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              if (_people.isEmpty)
                                const Text(
                                  'Selecciona participantes para elegir quién pagó.',
                                ),
                              for (final name in _people)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: FinancialParticipantOption(
                                    name: name,
                                    photoUrl: widget.list.collaborators
                                        .where((p) => p.displayName == name)
                                        .firstOrNull
                                        ?.photoUrl,
                                    selected: _payer.text.trim() == name,
                                    onPressed: _saving
                                        ? null
                                        : () {
                                            setState(() => _payer.text = name);
                                            field.didChange(name);
                                          },
                                  ),
                                ),
                              if (field.hasError)
                                Text(
                                  field.errorText!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                            ],
                          ),
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
                      textCapitalization: TextCapitalization.sentences,
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
                              : () => setState(() {
                                  _attachments.remove(attachment);
                                  for (var i = 0; i < _payments.length; i++) {
                                    final payment = _payments[i];
                                    if (payment.receiptId == attachment.id) {
                                      _payments[i] = FinancialPayment(
                                        id: payment.id,
                                        amountMinor: payment.amountMinor,
                                        date: payment.date,
                                        detail: payment.detail,
                                        paymentMethod: payment.paymentMethod,
                                        installments: payment.installments,
                                      );
                                    }
                                  }
                                }),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('financial-attach'),
                      onPressed:
                          _saving ||
                              _readingReceipt ||
                              _attachments.length >= noteAttachmentMaxCount
                          ? null
                          : _attach,
                      icon: const Icon(Icons.attach_file),
                      label: Text(
                        _readingReceipt
                            ? 'Leyendo total…'
                            : 'Escanear o adjuntar boleta',
                      ),
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
                      onPressed: _saving || _readingReceipt ? null : _save,
                      child: Text(_saving ? 'Guardando…' : 'Guardar registro'),
                    ),
                  ],
                ),
              ),
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
    this.existing,
  });
  final FinancialPayment? existing;
  final String currency;
  final int balance;
  final List<NoteAttachment> attachments;
  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _form = GlobalKey<FormState>();
  late String? _method = widget.existing?.paymentMethod;
  late final _installments = TextEditingController(
    text: widget.existing?.installments?.toString() ?? '',
  );
  final _amount = TextEditingController();
  final _detail = TextEditingController();
  DateTime _date = DateTime.now();
  String? _receipt;
  final List<NoteAttachment> _newAttachments = [];
  bool _picking = false;
  String? _attachmentError;

  Future<void> _attachReceipt() async {
    setState(() {
      _picking = true;
      _attachmentError = null;
    });
    try {
      final picked = await pickNoteAttachments(
        context: context,
        remaining: 1,
        includeCamera: true,
      );
      if (!mounted || picked.isEmpty) return;
      setState(() {
        _newAttachments.addAll(picked);
        _receipt = picked.first.id;
      });
      final total = await suggestReceiptTotal(
        context,
        picked.first,
        widget.currency,
      );
      if (mounted && total != null) {
        setState(
          () => _amount.text = financialAmountInput(
            FinancialEntry(
              amountMinor: total,
              currency: widget.currency,
              counterparty: '',
              date: _date,
            ).editableAmount,
            widget.currency,
          ),
        );
      }
    } on NoteAttachmentPickFailure catch (e) {
      if (mounted) setState(() => _attachmentError = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _attachmentError =
              'No se pudo adjuntar el comprobante. Reintenta.',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  void initState() {
    super.initState();
    final payment = widget.existing;
    if (payment != null) {
      _amount.text = financialAmountInput(
        FinancialEntry(
          amountMinor: payment.amountMinor,
          counterparty: '',
          currency: widget.currency,
          date: payment.date,
        ).editableAmount,
        widget.currency,
      );
      _detail.text = payment.detail;
      _date = payment.date;
      _receipt = payment.receiptId;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _installments.dispose();
    _detail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FinancialDialog(
    title: widget.existing == null ? 'Registrar abono' : 'Editar abono',
    icon: Icons.payments_outlined,
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Saldo: ${FinancialEntry.formatAmount(widget.balance, widget.currency)}',
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('payment-amount'),
            controller: _amount,
            inputFormatters: widget.currency == 'CLP'
                ? [ClpThousandsInputFormatter()]
                : null,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Monto (${widget.currency})',
              prefixText: widget.currency == 'EUR' ? '€ ' : r'$ ',
            ),
            validator: (v) {
              final a = parseFinancialAmountInput(v ?? '', widget.currency);
              return a == null || a > widget.balance
                  ? 'Ingresa un abono mayor que cero y menor o igual al saldo'
                  : null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _detail,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 160,
            decoration: const InputDecoration(
              labelText: 'Detalle / referencia',
            ),
          ),
          FinancialPaymentMethodField(
            method: _method,
            installments: _installments,
            enabled: !_picking,
            onChanged: (v) => setState(() {
              _method = v;
              if (v != 'credit') _installments.clear();
            }),
          ),
          if (_method == 'credit')
            FinancialInstallmentPreview(
              amount: _amount,
              installments: _installments,
              currency: widget.currency,
              firstDate: financialMonthOffset(_date, 1),
            ),
          ListTile(
            title: Text(DateFormat('dd-MM-yyyy').format(_date)),
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
          OutlinedButton.icon(
            key: const ValueKey('payment-attach-receipt'),
            onPressed:
                _picking ||
                    widget.attachments.length + _newAttachments.length >=
                        noteAttachmentMaxCount
                ? null
                : _attachReceipt,
            icon: const Icon(Icons.add_photo_alternate_rounded),
            label: Text(
              _picking ? 'Adjuntando…' : 'Adjuntar comprobante del abono',
            ),
          ),
          Text(
            'Foto o PDF · Hasta $noteAttachmentMaxCount adjuntos por registro, incluidos los abonos.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_attachmentError != null)
            Text(
              _attachmentError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 12),
          for (final attachment in [
            ...widget.attachments,
            ..._newAttachments,
          ].where((a) => a.id == _receipt))
            FinancialSurface(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(
                  attachment.isPdf
                      ? Icons.picture_as_pdf_rounded
                      : Icons.image_rounded,
                ),
                title: Text(
                  attachment.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: const Text('Comprobante del abono'),
                trailing: IconButton(
                  tooltip: 'Quitar comprobante del abono',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _picking
                      ? null
                      : () => setState(() {
                          _receipt = null;
                          _newAttachments.removeWhere(
                            (a) => a.id == attachment.id,
                          );
                        }),
                ),
              ),
            ),
          if (widget.attachments.any((a) => a.id != _receipt))
            TextButton.icon(
              icon: const Icon(Icons.attach_file_rounded),
              label: const Text('Usar comprobante existente'),
              onPressed: _picking
                  ? null
                  : () async {
                      final id = await showLiquidSelection<String>(
                        context: context,
                        title: 'Elegir comprobante existente',
                        items: widget.attachments
                            .where((a) => a.id != _receipt)
                            .map(
                              (a) => DropdownMenuItem(
                                value: a.id,
                                child: FinancialOptionLabel(
                                  icon: a.isPdf
                                      ? Icons.picture_as_pdf_rounded
                                      : Icons.image_rounded,
                                  label: a.name,
                                ),
                              ),
                            )
                            .toList(),
                      );
                      if (id != null && mounted) {
                        setState(() => _receipt = id);
                      }
                    },
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const ValueKey('payment-save'),
        onPressed: _picking
            ? null
            : () {
                if (_form.currentState!.validate()) {
                  Navigator.pop(context, (
                    FinancialPayment(
                      paymentMethod: _method,
                      installments: _method == 'credit'
                          ? int.tryParse(_installments.text)
                          : null,
                      id: widget.existing?.id ?? const Uuid().v4(),
                      amountMinor: parseFinancialAmountInput(
                        _amount.text,
                        widget.currency,
                      )!,
                      date: _date,
                      detail: _detail.text.trim(),
                      receiptId: _receipt,
                    ),
                    List<NoteAttachment>.of(_newAttachments),
                  ));
                }
              },
        child: Text(widget.existing == null ? 'Agregar' : 'Guardar cambios'),
      ),
    ],
  );
}
