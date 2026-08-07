import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nocknock/core/input_formatters/initial_uppercase_text_formatter.dart';
import 'package:nocknock/core/theme/app_theme.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/presentation/note_category_style.dart';
import 'package:nocknock/features/notes/presentation/note_palette.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_checklist.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_rich_text.dart';

Future<NoteDraft?> showNoteEditor(
  BuildContext context, {
  Note? note,
  String defaultAuthorName = 'Invitado',
  List<ListCollaborator> assignees = const [],
}) {
  return showModalBottomSheet<NoteDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => NoteEditorSheet(
      note: note,
      defaultAuthorName: defaultAuthorName,
      assignees: assignees,
    ),
  );
}

class NoteEditorSheet extends StatefulWidget {
  const NoteEditorSheet({
    required this.defaultAuthorName,
    this.assignees = const [],
    this.note,
    super.key,
  });

  final Note? note;
  final String defaultAuthorName;
  final List<ListCollaborator> assignees;

  @override
  State<NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends State<NoteEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _authorController;
  late NoteRichContent _content;
  late NoteColor _color;
  late NoteCategory _category;
  late List<NoteChecklistItem> _checklist;
  String? _assigneeUid;
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
    _color = note?.color ?? NoteColor.yellow;
    _category = note?.category ?? NoteCategory.general;
    _checklist = [...?note?.checklist];
    _assigneeUid =
        widget.assignees.any((person) => person.uid == note?.assigneeUid)
        ? note?.assigneeUid
        : null;
    _reminderAt = note?.reminderAt;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: EdgeInsets.only(top: MediaQuery.sizeOf(context).height * 0.08),
      padding: EdgeInsets.fromLTRB(24, 14, 24, 24 + bottomInset),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
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
                Text(
                  widget.note == null ? 'Nueva nota' : 'Editar nota',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const ValueKey('note-title-field'),
                  controller: _titleController,
                  autofocus: widget.note == null,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: const [InitialUppercaseTextFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Título',
                    hintText: 'Ej. Comprar entradas',
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
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _authorController,
                  maxLength: 50,
                  decoration: const InputDecoration(
                    labelText: 'Tu nombre',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Indica quién crea la nota'
                      : null,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: const ValueKey('note-assignee-field'),
                  initialValue: _assigneeUid ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Responsable',
                    prefixIcon: Icon(Icons.assignment_ind_outlined),
                    helperText: 'Aparecerá en la tarjeta de esta tarea.',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Sin responsable'),
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
                  onChanged: (value) => setState(
                    () => _assigneeUid = value == null || value.isEmpty
                        ? null
                        : value,
                  ),
                ),
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
                      onSelected: (_) => setState(() => _category = category),
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
                            duration: const Duration(milliseconds: 160),
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
                OutlinedButton.icon(
                  onPressed: _selectReminder,
                  icon: const Icon(Icons.notifications_none_rounded),
                  label: Text(
                    _reminderAt == null
                        ? 'Agregar recordatorio'
                        : DateFormat(
                            "EEE d MMM · HH:mm",
                            'es',
                          ).format(_reminderAt!),
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

  Future<void> _selectReminder() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _reminderAt ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_reminderAt ?? now),
    );
    if (time == null) return;
    setState(() {
      _reminderAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
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
        authorName: _authorController.text.trim(),
        assigneeUid: _assigneeUid,
        reminderAt: _reminderAt,
      ),
    );
  }
}
