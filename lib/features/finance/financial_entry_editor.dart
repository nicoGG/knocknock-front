import 'package:nocknock/features/finance/financial_style.dart';
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
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _party.dispose();
    _detail.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final entry = FinancialEntry(
      amountMinor: FinancialEntry.parseAmount(_amount.text, _currency)!,
      currency: _currency,
      counterparty: _party.text.trim(),
      date: _date,
      status: _status,
    );
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
          reminderAt: previous?.reminderAt,
          reminderRecurrence: previous?.reminderRecurrence,
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
                  title: Text(
                    config.type.name == 'receivables'
                        ? 'Fecha de vencimiento'
                        : 'Fecha del registro',
                  ),
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
