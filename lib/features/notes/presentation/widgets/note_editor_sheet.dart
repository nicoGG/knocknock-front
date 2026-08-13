import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nocknock/core/input_formatters/initial_uppercase_text_formatter.dart';
import 'package:nocknock/core/input_formatters/money_text_input_formatter.dart';
import 'package:nocknock/core/theme/app_theme.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/presentation/note_category_style.dart';
import 'package:nocknock/features/notes/presentation/note_attachment_picker.dart';
import 'package:nocknock/features/notes/presentation/note_palette.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_checklist.dart';
import 'package:nocknock/features/notes/presentation/widgets/reminder_picker.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_rich_text.dart';

Future<NoteDraft?> showNoteEditor(
  BuildContext context, {
  Note? note,
  String defaultAuthorName = 'Invitado',
  bool showAuthorField = true,
  List<ListCollaborator> assignees = const [],
}) {
  return showModalBottomSheet<NoteDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.38),
    builder: (_) => NoteEditorSheet(
      note: note,
      defaultAuthorName: defaultAuthorName,
      showAuthorField: showAuthorField,
      assignees: assignees,
    ),
  );
}

class NoteEditorSheet extends StatefulWidget {
  const NoteEditorSheet({
    required this.defaultAuthorName,
    this.showAuthorField = true,
    this.assignees = const [],
    this.note,
    super.key,
  });

  final Note? note;
  final String defaultAuthorName;
  final bool showAuthorField;
  final List<ListCollaborator> assignees;

  @override
  State<NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends State<NoteEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _authorController;
  late final TextEditingController _customAssigneeController;
  late NoteRichContent _content;
  late NoteColor _color;
  late NoteCategory _category;
  late List<NoteChecklistItem> _checklist;
  String? _assigneeUid;
  late bool _usesCustomAssignee;
  late List<NoteAttachment> _attachments;
  DateTime? _reminderAt;

  @override
  void initState() {
    super.initState();
    final note = widget.note;
    _titleController = TextEditingController(
      text: capitalizeInitialLetter(note?.title ?? ''),
    );
    _content = normalizeNoteRichContent(
      NoteRichContent(
        plainText: capitalizeInitialLetter(note?.content ?? ''),
        deltaJson:
            note?.contentDelta ??
            noteRichContentFromDocument(
              noteDocumentFromContent(
                plainText: capitalizeInitialLetter(note?.content ?? ''),
              ),
            ).deltaJson,
      ),
    );
    _authorController = TextEditingController(
      text: note?.authorName ?? widget.defaultAuthorName,
    );
    _customAssigneeController = TextEditingController(
      text: note?.customAssigneeName ?? '',
    );
    _color = note?.color ?? NoteColor.yellow;
    _category = note?.category ?? NoteCategory.general;
    _checklist = [...?note?.checklist];
    _assigneeUid =
        widget.assignees.any((person) => person.uid == note?.assigneeUid)
        ? note?.assigneeUid
        : null;
    _usesCustomAssignee = note?.customAssigneeName?.trim().isNotEmpty == true;
    _attachments = [...?note?.photoAttachments];
    _reminderAt = note?.reminderAt;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _customAssigneeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassInputColor = colorScheme.surface.withValues(
      alpha: isDark ? 0.3 : 0.42,
    );
    return _GlassNoteEditorSurface(
      bottomInset: bottomInset,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.note == null ? 'Nueva nota' : 'Editar nota',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('close-note-editor-button'),
                      tooltip: 'Cerrar',
                      style: IconButton.styleFrom(
                        backgroundColor: colorScheme.surface.withValues(
                          alpha: isDark ? 0.3 : 0.42,
                        ),
                        side: BorderSide(
                          color: Colors.white.withValues(
                            alpha: isDark ? 0.12 : 0.46,
                          ),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const ValueKey('note-title-field'),
                  controller: _titleController,
                  autofocus: widget.note == null,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.sentences,
                  keyboardType: _category == NoteCategory.money
                      ? TextInputType.number
                      : TextInputType.text,
                  inputFormatters: _category == NoteCategory.money
                      ? [MoneyTextInputFormatter()]
                      : const [InitialUppercaseTextFormatter()],
                  decoration: _glassInputDecoration(
                    context,
                    labelText: _category == NoteCategory.money
                        ? 'Monto (CLP)'
                        : 'Título',
                    hintText: _category == NoteCategory.money
                        ? r'$5.000'
                        : 'Ej. Comprar entradas',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Escribe un título para la nota'
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  'Detalle',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 8),
                NoteRichTextEditor(
                  key: const ValueKey('note-content-field'),
                  editorKey: const ValueKey('note-content-editor'),
                  initialPlainText: _content.plainText,
                  initialDeltaJson: _content.deltaJson,
                  onChanged: (content) => _content = content,
                  backgroundColor: glassInputColor,
                ),
                const SizedBox(height: 4),
                if (widget.showAuthorField) ...[
                  TextFormField(
                    key: const ValueKey('note-author-field'),
                    controller: _authorController,
                    maxLength: 50,
                    decoration: _glassInputDecoration(
                      context,
                      labelText: 'Tu nombre',
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Indica quién crea la nota'
                        : null,
                  ),
                  const SizedBox(height: 10),
                ],
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    'note-assignee-field-${_usesCustomAssignee ? 'custom' : _assigneeUid ?? 'none'}',
                  ),
                  initialValue: _usesCustomAssignee
                      ? '__custom__'
                      : _assigneeUid ?? '',
                  isExpanded: true,
                  decoration: _glassInputDecoration(
                    context,
                    labelText: 'Responsable',
                    prefixIcon: const Icon(Icons.assignment_ind_outlined),
                    helperText: 'Aparecerá en la tarjeta de esta tarea.',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Sin responsable'),
                    ),
                    const DropdownMenuItem(
                      value: '__custom__',
                      child: Row(
                        children: [
                          Icon(Icons.manage_accounts_outlined),
                          SizedBox(width: 10),
                          Text('Responsable personalizado'),
                        ],
                      ),
                    ),
                    ...widget.assignees.map((person) {
                      final label = person.displayName.trim().isNotEmpty
                          ? person.displayName.trim()
                          : person.email;
                      final photoUrl = person.photoUrl?.trim();
                      final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
                      return DropdownMenuItem(
                        value: person.uid,
                        child: Row(
                          children: [
                            CircleAvatar(
                              key: ValueKey(
                                'assignee-option-avatar-${person.uid}',
                              ),
                              radius: 12,
                              foregroundImage: hasPhoto
                                  ? NetworkImage(photoUrl)
                                  : null,
                              onForegroundImageError: hasPhoto
                                  ? (_, _) {}
                                  : null,
                              child: Text(label.characters.first.toUpperCase()),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                  onChanged: (value) => setState(() {
                    _usesCustomAssignee = value == '__custom__';
                    _assigneeUid =
                        value == null || value.isEmpty || value == '__custom__'
                        ? null
                        : value;
                  }),
                ),
                if (_usesCustomAssignee) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    key: const ValueKey('note-custom-assignee-field'),
                    controller: _customAssigneeController,
                    maxLength: 50,
                    textCapitalization: TextCapitalization.words,
                    decoration: _glassInputDecoration(
                      context,
                      labelText: 'Nombre del responsable',
                      hintText: 'Ej. Camila',
                      helperText: 'No necesita tener una cuenta en NockNock.',
                      prefixIcon: const Icon(Icons.manage_accounts_outlined),
                    ),
                    validator: (value) =>
                        _usesCustomAssignee &&
                            (value == null || value.trim().isEmpty)
                        ? 'Escribe el nombre del responsable'
                        : null,
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'Categoría',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: NoteCategory.values.map((category) {
                    return ChoiceChip(
                      key: ValueKey('note-category-${category.name}'),
                      selected: category == _category,
                      avatar: Icon(NoteCategoryStyle.icon(category), size: 18),
                      label: Text(NoteCategoryStyle.label(category)),
                      onSelected: (_) => setState(() {
                        _category = category;
                        if (category == NoteCategory.money) {
                          _titleController.value = MoneyTextInputFormatter()
                              .formatEditUpdate(
                                _titleController.value,
                                _titleController.value,
                              );
                        }
                      }),
                    );
                  }).toList(),
                ),
                if (_category == NoteCategory.general) ...[
                  const SizedBox(height: 18),
                  Text('Color', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: NoteColor.values.map((color) {
                      final selected = color == _color;
                      return Semantics(
                        label: 'Color ${color.name}',
                        selected: selected,
                        child: InkWell(
                          onTap: () => setState(() => _color = color),
                          customBorder: const CircleBorder(),
                          child: AnimatedContainer(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 160),
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: NotePalette.color(color),
                              border: selected
                                  ? Border.all(color: AppTheme.ink, width: 3)
                                  : null,
                            ),
                            child: selected
                                ? const Icon(
                                    Icons.check_rounded,
                                    size: 20,
                                    color: AppTheme.ink,
                                  )
                                : null,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 22),
                NoteChecklistEditor(
                  items: _checklist,
                  onChanged: (items) => setState(() => _checklist = items),
                ),
                const SizedBox(height: 18),
                _GlassReminderButton(
                  reminderAt: _reminderAt,
                  onPressed: _selectReminder,
                ),
                const SizedBox(height: 12),
                _NotePhotosField(
                  key: const ValueKey('note-attachment-field'),
                  attachments: _attachments,
                  onAdd: _attachments.length < noteAttachmentMaxCount
                      ? _pickAttachment
                      : null,
                  onRemove: (attachment) => setState(
                    () => _attachments.removeWhere(
                      (entry) => entry.id == attachment.id,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    key: const ValueKey('save-note-button'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                    ),
                    onPressed: _submit,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(
                      widget.note == null ? 'Crear nota' : 'Guardar cambios',
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

  InputDecoration _glassInputDecoration(
    BuildContext context, {
    required String labelText,
    String? hintText,
    String? helperText,
    Widget? prefixIcon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(18);
    final restingBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(
        color: Colors.white.withValues(alpha: isDark ? 0.14 : 0.42),
      ),
    );
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      helperText: helperText,
      prefixIcon: prefixIcon,
      filled: true,
      fillColor: colorScheme.surface.withValues(alpha: isDark ? 0.3 : 0.42),
      border: restingBorder,
      enabledBorder: restingBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
    );
  }

  Future<void> _selectReminder() async {
    final reminder = await showReminderPicker(
      context,
      currentReminder: _reminderAt,
    );
    if (reminder == null || !mounted) return;
    setState(() => _reminderAt = reminder);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final normalizedContent = normalizeNoteRichContent(_content);
    if (normalizedContent.plainText.length > noteContentMaxLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El detalle puede tener hasta 500 caracteres.'),
        ),
      );
      return;
    }
    Navigator.of(context).pop(
      NoteDraft(
        title: capitalizeInitialLetter(_titleController.text.trim()),
        content: normalizedContent.plainText,
        contentDelta: normalizedContent.deltaJson,
        color: _color,
        category: _category,
        checklist: normalizeNoteChecklist(
          _checklist,
          trimText: true,
          removeEmpty: true,
        ),
        authorName: _authorController.text.trim().isEmpty
            ? widget.defaultAuthorName.trim()
            : _authorController.text.trim(),
        assigneeUid: _assigneeUid,
        customAssigneeName: _usesCustomAssignee
            ? _customAssigneeController.text.trim()
            : null,
        attachments: _attachments,
        reminderAt: _reminderAt,
      ),
    );
  }

  Future<void> _pickAttachment() async {
    try {
      final attachments = await pickNotePhotos(
        remaining: noteAttachmentMaxCount - _attachments.length,
      );
      if (!mounted || attachments.isEmpty) return;
      setState(() => _attachments = [..._attachments, ...attachments]);
    } on NoteAttachmentPickFailure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _NotePhotosField extends StatelessWidget {
  const _NotePhotosField({
    required this.attachments,
    required this.onAdd,
    required this.onRemove,
    super.key,
  });

  final List<NoteAttachment> attachments;
  final VoidCallback? onAdd;
  final ValueChanged<NoteAttachment> onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.photo_library_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Fotos · ${attachments.length}/$noteAttachmentMaxCount',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (onAdd != null)
              TextButton.icon(
                key: const ValueKey('add-note-photo-button'),
                onPressed: onAdd,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(attachments.isEmpty ? 'Agregar' : 'Otra'),
              ),
          ],
        ),
        if (attachments.isEmpty)
          Text(
            'Se guardan comprimidas para usar menos espacio.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          SizedBox(
            height: 92,
            child: Row(
              children: [
                for (final (index, attachment) in attachments.indexed) ...[
                  if (index > 0) const SizedBox(width: 10),
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: _editorPhoto(
                            attachment,
                            colorScheme.surfaceContainerHighest,
                          ),
                        ),
                        Positioned(
                          top: 3,
                          right: 3,
                          child: IconButton.filledTonal(
                            key: index == 0
                                ? const ValueKey(
                                    'remove-note-attachment-button',
                                  )
                                : ValueKey(
                                    'remove-note-attachment-${attachment.id}',
                                  ),
                            tooltip: 'Quitar foto',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => onRemove(attachment),
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _editorPhoto(NoteAttachment attachment, Color fallbackColor) {
    final encoded = attachment.dataBase64;
    if (attachment.isImage && encoded != null) {
      try {
        return Image.memory(
          base64Decode(encoded),
          key: ValueKey('note-editor-photo-${attachment.id}'),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallback(attachment, fallbackColor),
        );
      } on FormatException {
        return _fallback(attachment, fallbackColor);
      }
    }
    return _fallback(attachment, fallbackColor);
  }

  Widget _fallback(NoteAttachment attachment, Color color) => ColoredBox(
    color: color,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          attachment.name,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ),
  );
}

class _GlassNoteEditorSurface extends StatelessWidget {
  const _GlassNoteEditorSurface({
    required this.bottomInset,
    required this.child,
  });

  final double bottomInset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const radius = BorderRadius.vertical(top: Radius.circular(32));
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.sizeOf(context).height * 0.08),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: isDark ? 0.48 : 0.3),
              blurRadius: 40,
              offset: const Offset(0, -10),
            ),
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.1),
              blurRadius: 28,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            key: const ValueKey('note-editor-glass-blur'),
            filter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: DecoratedBox(
              key: const ValueKey('note-editor-glass-surface'),
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: Colors.white.withValues(alpha: isDark ? 0.18 : 0.52),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: isDark ? 0.09 : 0.36),
                    colorScheme.surface.withValues(alpha: isDark ? 0.72 : 0.66),
                  ],
                ),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 14, 24, 24 + bottomInset),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassReminderButton extends StatelessWidget {
  const _GlassReminderButton({
    required this.reminderAt,
    required this.onPressed,
  });

  final DateTime? reminderAt;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(20);
    final title = reminderAt == null
        ? 'Agregar recordatorio'
        : DateFormat("EEE d MMM · HH:mm", 'es').format(reminderAt!);

    return Semantics(
      button: true,
      label: title,
      child: SizedBox(
        key: const ValueKey('note-reminder-button'),
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: BackdropFilter(
              key: const ValueKey('note-reminder-glass-blur'),
              filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Material(
                color: Colors.transparent,
                child: Ink(
                  key: const ValueKey('note-reminder-glass-surface'),
                  decoration: BoxDecoration(
                    borderRadius: borderRadius,
                    border: Border.all(
                      color: Colors.white.withValues(
                        alpha: isDark ? 0.16 : 0.44,
                      ),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        colorScheme.primary.withValues(
                          alpha: isDark ? 0.22 : 0.18,
                        ),
                        colorScheme.surface.withValues(
                          alpha: isDark ? 0.32 : 0.4,
                        ),
                      ],
                    ),
                  ),
                  child: InkWell(
                    onTap: onPressed,
                    borderRadius: borderRadius,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(
                                alpha: 0.16,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.notifications_none_rounded,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  reminderAt == null
                                      ? 'Opciones rápidas o fecha exacta'
                                      : 'Toca para cambiarlo',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colorScheme.onSurface.withValues(
                                          alpha: 0.62,
                                        ),
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
