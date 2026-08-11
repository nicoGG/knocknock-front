import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nocknock/core/input_formatters/initial_uppercase_text_formatter.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:nocknock/features/notes/logic/notes_state.dart';
import 'package:nocknock/features/notes/presentation/note_category_style.dart';
import 'package:nocknock/features/notes/presentation/note_hero.dart';
import 'package:nocknock/features/notes/presentation/note_palette.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_checklist.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_editor_sheet.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_reactions.dart';
import 'package:nocknock/features/notes/presentation/widgets/reminder_picker.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_rich_text.dart';

class NoteDetailPage extends StatelessWidget {
  const NoteDetailPage({
    required this.noteId,
    required this.initialNote,
    required this.listName,
    required this.defaultAuthorName,
    this.heroTag,
    this.currentUserId,
    this.currentUserPhotoUrl,
    super.key,
  });

  final String noteId;
  final Note initialNote;
  final String listName;
  final String defaultAuthorName;
  final Object? heroTag;
  final String? currentUserId;
  final String? currentUserPhotoUrl;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotesCubit, NotesState>(
      builder: (context, state) {
        final note = _noteFrom(state) ?? initialNote;
        final currentList = _listFrom(state, note) ?? state.selectedList;
        final currentListName = currentList?.name ?? listName;
        final assignees =
            currentList?.collaborators ?? const <ListCollaborator>[];
        final signedInUserId = currentUserId;
        final reactionAuthorNames = <String, String>{
          for (final person in assignees)
            person.uid: person.displayName.trim().isNotEmpty
                ? person.displayName.trim()
                : person.email.trim(),
          ?signedInUserId: 'Tú',
          localNoteReactionUserId: 'Tú',
        };
        final assignee = assignees
            .where((person) => person.uid == note.assigneeUid)
            .firstOrNull;
        final assigneePhotoUrl = _firstPhotoUrl(
          assignee?.uid == currentUserId ? currentUserPhotoUrl : null,
          assignee?.photoUrl,
        );
        final normalizedAuthorName = note.authorName.trim().toLowerCase();
        final author = assignees
            .where(
              (person) =>
                  person.displayName.trim().toLowerCase() ==
                  normalizedAuthorName,
            )
            .firstOrNull;
        final currentUserAuthorPhoto =
            defaultAuthorName.trim().toLowerCase() == normalizedAuthorName
            ? currentUserPhotoUrl
            : null;
        final authorPhotoUrl = _firstPhotoUrl(
          currentUserAuthorPhoto,
          author?.photoUrl,
        );
        return Scaffold(
          key: const ValueKey('note-detail-page'),
          appBar: AppBar(
            leading: IconButton(
              key: const ValueKey('detail-close-button'),
              tooltip: 'Cerrar',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, size: 23),
            ),
            title: Text(
              currentListName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                key: const ValueKey('detail-edit-button'),
                tooltip: 'Editar nota',
                onPressed: state.isSaving ? null : () => _edit(context, note),
                icon: const Icon(Icons.edit_outlined),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: _DetailBody(
            note: note,
            assignee: assignee,
            assigneePhotoUrl: assigneePhotoUrl,
            authorPhotoUrl: authorPhotoUrl,
            currentUserId: currentUserId,
            reactionAuthorNames: reactionAuthorNames,
            heroTag: heroTag ?? noteHeroTag(note.id),
            isSaving: state.isSaving,
            onToggle: () => context.read<NotesCubit>().toggleNote(note),
            onSaveTitle: (title) =>
                context.read<NotesCubit>().updateNoteTitle(note, title),
            onSaveContent: (content) => _saveContent(context, note, content),
            onEditReminder: () => _editReminder(context, note),
            onRemoveReminder: () => _removeReminder(context, note),
            onEditCategory: () => _editCategory(context, note),
            onEditColor: () => _editColor(context, note),
            onChecklistChanged: (items) =>
                context.read<NotesCubit>().updateChecklist(note, items),
            onEditChecklist: () => _edit(context, note),
            onEditAssignee: () => _editAssignee(context, note),
            onToggleReaction: (emoji) => context
                .read<NotesCubit>()
                .toggleReaction(note, emoji, currentUserId),
          ),
          bottomNavigationBar: _DetailFooter(
            note: note,
            isSaving: state.isSaving,
            onDelete: () => _confirmDelete(context, note),
          ),
        );
      },
    );
  }

  Note? _noteFrom(NotesState state) {
    for (final note in [
      ...state.notes,
      ...state.pinnedNotes,
      ...state.reminderNotes,
    ]) {
      if (note.id == noteId) return note;
    }
    return null;
  }

  NoteList? _listFrom(NotesState state, Note note) {
    return state.lists.where((list) => list.id == note.boardId).firstOrNull;
  }

  Future<void> _edit(BuildContext context, Note note) async {
    final cubit = context.read<NotesCubit>();
    final draft = await showNoteEditor(
      context,
      note: note,
      defaultAuthorName: defaultAuthorName,
      showAuthorField: currentUserId == null,
      assignees:
          _listFrom(cubit.state, note)?.collaborators ??
          const <ListCollaborator>[],
    );
    if (draft == null || !context.mounted) return;
    await cubit.editNote(note, draft);
  }

  Future<void> _saveContent(
    BuildContext context,
    Note note,
    NoteRichContent content,
  ) async {
    final normalizedContent = normalizeNoteRichContent(content);
    await context.read<NotesCubit>().updateNoteContent(
      note,
      normalizedContent.plainText,
      normalizedContent.deltaJson,
    );
  }

  Future<void> _editAssignee(BuildContext context, Note note) async {
    final cubit = context.read<NotesCubit>();
    final assignees =
        _listFrom(cubit.state, note)?.collaborators ??
        const <ListCollaborator>[];
    final selectedUid = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'Asignar responsable',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
            ),
            ListTile(
              key: const ValueKey('assignee-option-unassigned'),
              leading: const CircleAvatar(
                child: Icon(Icons.person_off_outlined),
              ),
              title: const Text('Sin responsable'),
              trailing: note.assigneeUid == null
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.pop(sheetContext, ''),
            ),
            ...assignees.map((person) {
              final label = person.displayName.trim().isNotEmpty
                  ? person.displayName.trim()
                  : person.email.trim().isNotEmpty
                  ? person.email.trim()
                  : 'Persona';
              final photoUrl = person.photoUrl?.trim();
              final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
              return ListTile(
                key: ValueKey('assignee-option-${person.uid}'),
                leading: CircleAvatar(
                  foregroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
                  onForegroundImageError: hasPhoto ? (_, _) {} : null,
                  child: Text(label.characters.first.toUpperCase()),
                ),
                title: Text(label),
                subtitle: person.email.isEmpty || person.email == label
                    ? null
                    : Text(person.email),
                trailing: note.assigneeUid == person.uid
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(sheetContext, person.uid),
              );
            }),
          ],
        ),
      ),
    );
    if (selectedUid == null || !context.mounted) return;
    await cubit.updateNoteAssignee(
      note,
      selectedUid.isEmpty ? null : selectedUid,
    );
  }

  Future<void> _editReminder(BuildContext context, Note note) async {
    final reminder = await showReminderPicker(
      context,
      currentReminder: note.reminderAt,
    );
    if (reminder == null || !context.mounted) return;
    await context.read<NotesCubit>().updateNoteReminder(note, reminder);
  }

  Future<void> _removeReminder(BuildContext context, Note note) async {
    await context.read<NotesCubit>().updateNoteReminder(note, null);
  }

  Future<void> _editColor(BuildContext context, Note note) async {
    final color = await showModalBottomSheet<NoteColor>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _ColorPickerSheet(selected: note.color),
    );
    if (color == null || color == note.color || !context.mounted) return;
    await context.read<NotesCubit>().updateNoteColor(note, color);
  }

  Future<void> _editCategory(BuildContext context, Note note) async {
    final category = await showModalBottomSheet<NoteCategory>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _CategoryPickerSheet(selected: note.category),
    );
    if (category == null || category == note.category || !context.mounted) {
      return;
    }
    await context.read<NotesCubit>().updateNoteCategory(note, category);
  }

  Future<void> _confirmDelete(BuildContext context, Note note) async {
    final cubit = context.read<NotesCubit>();
    final navigator = Navigator.of(context);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Eliminar esta nota?'),
        content: Text(
          'Se eliminará “${note.title}” para todos los colaboradores.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('confirm-detail-delete-button'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (accepted != true || !context.mounted) return;
    navigator.pop();
    await cubit.deleteNote(note);
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.note,
    required this.assignee,
    required this.assigneePhotoUrl,
    required this.authorPhotoUrl,
    required this.currentUserId,
    required this.reactionAuthorNames,
    required this.heroTag,
    required this.isSaving,
    required this.onToggle,
    required this.onSaveTitle,
    required this.onSaveContent,
    required this.onEditReminder,
    required this.onRemoveReminder,
    required this.onEditCategory,
    required this.onEditColor,
    required this.onChecklistChanged,
    required this.onEditChecklist,
    required this.onEditAssignee,
    required this.onToggleReaction,
  });

  final Note note;
  final ListCollaborator? assignee;
  final String? assigneePhotoUrl;
  final String? authorPhotoUrl;
  final String? currentUserId;
  final Map<String, String> reactionAuthorNames;
  final Object heroTag;
  final bool isSaving;
  final VoidCallback onToggle;
  final Future<void> Function(String title) onSaveTitle;
  final Future<void> Function(NoteRichContent content) onSaveContent;
  final VoidCallback onEditReminder;
  final VoidCallback onRemoveReminder;
  final VoidCallback onEditCategory;
  final VoidCallback onEditColor;
  final ValueChanged<List<NoteChecklistItem>> onChecklistChanged;
  final VoidCallback onEditChecklist;
  final VoidCallback onEditAssignee;
  final Future<void> Function(String emoji) onToggleReaction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final noteColor = note.category == NoteCategory.general
        ? NotePalette.color(note.color)
        : NoteCategoryStyle.baseColor(note.category);
    final noteForeground = NoteCategoryStyle.foregroundColor(note.category);
    final backgroundAsset = NoteCategoryStyle.assetPath(note.category);
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  key: const ValueKey('note-task-container'),
                  children: [
                    Positioned.fill(
                      child: HeroMode(
                        enabled: !MediaQuery.disableAnimationsOf(context),
                        child: Hero(
                          tag: heroTag,
                          transitionOnUserGestures: true,
                          createRectTween: (begin, end) =>
                              MaterialRectCenterArcTween(
                                begin: begin,
                                end: end,
                              ),
                          child: DecoratedBox(
                            key: const ValueKey('note-task-background'),
                            decoration: BoxDecoration(
                              color: noteColor.withValues(
                                alpha:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? 0.86
                                    : 1,
                              ),
                              image: backgroundAsset == null
                                  ? null
                                  : DecorationImage(
                                      image: AssetImage(backgroundAsset),
                                      fit: BoxFit.cover,
                                      colorFilter: ColorFilter.mode(
                                        Colors.black.withValues(alpha: 0.18),
                                        BlendMode.darken,
                                      ),
                                    ),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: noteColor.withValues(alpha: 0.28),
                                  blurRadius: 28,
                                  offset: const Offset(0, 14),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _EditableNoteHeader(
                            key: const ValueKey('note-detail-header'),
                            note: note,
                            foregroundColor: noteForeground,
                            isSaving: isSaving,
                            onToggle: onToggle,
                            onSaveTitle: onSaveTitle,
                          ),
                          _ExpandableContentRow(
                            key: const ValueKey('detail-content-row'),
                            note: note,
                            isSaving: isSaving,
                            foregroundColor: noteForeground,
                            onSave: onSaveContent,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Divider(
                              height: 1,
                              color: noteForeground.withValues(alpha: 0.2),
                            ),
                          ),
                          NoteChecklistDetail(
                            items: note.checklist,
                            isSaving: isSaving,
                            onChanged: onChecklistChanged,
                            onEdit: onEditChecklist,
                            backgroundColor: Colors.transparent,
                            foregroundColor: noteForeground,
                            dragProxyColor: noteColor,
                            borderRadius: BorderRadius.zero,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                NoteReactionsBar(
                  note: note,
                  currentUserId: currentUserId,
                  reactionAuthorNames: reactionAuthorNames,
                  isSaving: isSaving,
                  onToggle: onToggleReaction,
                ),
                const SizedBox(height: 22),
                _DetailGroup(
                  children: [
                    _DetailRow(
                      key: const ValueKey('detail-assignee-row'),
                      icon: Icons.assignment_ind_outlined,
                      title: 'Responsable',
                      value: assignee?.displayName ?? 'Sin responsable',
                      valueMuted: assignee == null,
                      trailing: assignee == null
                          ? const Icon(Icons.person_add_alt_1_outlined)
                          : _PersonAvatar(
                              key: const ValueKey('detail-assignee-avatar'),
                              label: assignee!.displayName,
                              color: noteColor,
                              photoUrl: assigneePhotoUrl,
                            ),
                      onTap: isSaving ? null : onEditAssignee,
                    ),
                    _DetailRow(
                      key: const ValueKey('detail-reminder-row'),
                      icon: Icons.notifications_none_rounded,
                      title: 'Recordatorio',
                      value: note.reminderAt == null
                          ? 'Agregar recordatorio'
                          : _formatReminder(note.reminderAt!),
                      valueMuted: note.reminderAt == null,
                      trailing: note.reminderAt == null
                          ? null
                          : IconButton(
                              key: const ValueKey(
                                'remove-detail-reminder-button',
                              ),
                              tooltip: 'Quitar recordatorio',
                              onPressed: isSaving ? null : onRemoveReminder,
                              icon: const Icon(
                                Icons.notifications_off_outlined,
                              ),
                            ),
                      onTap: isSaving ? null : onEditReminder,
                    ),
                    _DetailRow(
                      key: const ValueKey('detail-category-row'),
                      icon: NoteCategoryStyle.icon(note.category),
                      title: 'Categoría',
                      value: NoteCategoryStyle.label(note.category),
                      onTap: isSaving ? null : onEditCategory,
                    ),
                    if (note.category == NoteCategory.general)
                      _DetailRow(
                        key: const ValueKey('detail-color-row'),
                        icon: Icons.palette_outlined,
                        title: 'Color',
                        value: _colorName(note.color),
                        trailing: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: noteColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.16,
                              ),
                            ),
                          ),
                        ),
                        onTap: isSaving ? null : onEditColor,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _DetailGroup(
                  children: [
                    _DetailRow(
                      key: const ValueKey('detail-author-row'),
                      icon: Icons.person_outline_rounded,
                      title: 'Creada por',
                      value: note.authorName,
                      trailing: _PersonAvatar(
                        key: const ValueKey('detail-author-avatar'),
                        label: note.authorName,
                        color: noteColor,
                        photoUrl: authorPhotoUrl,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    'Actualizada ${_formatDateTime(note.updatedAt)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.56),
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

class _DetailGroup extends StatelessWidget {
  const _DetailGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              Divider(
                height: 1,
                indent: 62,
                color: colorScheme.onSurface.withValues(alpha: 0.08),
              ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.title,
    required this.value,
    this.valueMuted = false,
    this.trailing,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool valueMuted;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 17, 18, 17),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 24,
              color: colorScheme.onSurface.withValues(alpha: 0.68),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.58),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurface.withValues(
                        alpha: valueMuted ? 0.52 : 0.9,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              Padding(padding: const EdgeInsets.only(top: 8), child: trailing!),
            ],
            if (onTap != null) ...[
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurface.withValues(alpha: 0.38),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EditableNoteHeader extends StatefulWidget {
  const _EditableNoteHeader({
    required this.note,
    required this.foregroundColor,
    required this.isSaving,
    required this.onToggle,
    required this.onSaveTitle,
    super.key,
  });

  final Note note;
  final Color foregroundColor;
  final bool isSaving;
  final VoidCallback onToggle;
  final Future<void> Function(String title) onSaveTitle;

  @override
  State<_EditableNoteHeader> createState() => _EditableNoteHeaderState();
}

class _EditableNoteHeaderState extends State<_EditableNoteHeader> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.note.title,
  );
  final FocusNode _focusNode = FocusNode();
  bool _isEditing = false;

  @override
  void didUpdateWidget(covariant _EditableNoteHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && oldWidget.note.title != widget.note.title) {
      _controller.text = widget.note.title;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startEditing() {
    if (widget.isSaving || _isEditing) return;
    setState(() {
      _controller.text = widget.note.title;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
      _isEditing = true;
    });
    _focusNode.requestFocus();
  }

  void _cancelEditing() {
    _focusNode.unfocus();
    setState(() {
      _controller.text = widget.note.title;
      _isEditing = false;
    });
  }

  Future<void> _saveTitle() async {
    final title = _controller.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe un título para la nota.')),
      );
      return;
    }
    await widget.onSaveTitle(title);
    if (!mounted) return;
    _focusNode.unfocus();
    setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.headlineMedium?.copyWith(
      color: widget.foregroundColor,
      fontWeight: FontWeight.w800,
      height: 1.15,
      decoration: widget.note.isCompleted ? TextDecoration.lineThrough : null,
    );
    final actionIconColor =
        ThemeData.estimateBrightnessForColor(widget.foregroundColor) ==
            Brightness.dark
        ? Colors.white
        : Colors.black87;
    return InkWell(
      onTap: _startEditing,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              button: true,
              label: widget.note.isCompleted
                  ? 'Marcar como pendiente'
                  : 'Marcar como completada',
              child: IconButton(
                key: const ValueKey('detail-complete-toggle'),
                tooltip: widget.note.isCompleted
                    ? 'Marcar como pendiente'
                    : 'Marcar como completada',
                onPressed: widget.isSaving ? null : widget.onToggle,
                color: widget.foregroundColor,
                iconSize: 34,
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    widget.note.isCompleted
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    key: ValueKey(widget.note.isCompleted),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isEditing)
                      TextField(
                        key: const ValueKey('detail-title-field'),
                        controller: _controller,
                        focusNode: _focusNode,
                        maxLength: 80,
                        textCapitalization: TextCapitalization.sentences,
                        inputFormatters: const [
                          InitialUppercaseTextFormatter(),
                        ],
                        minLines: 1,
                        maxLines: null,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _saveTitle(),
                        style: titleStyle,
                        decoration: InputDecoration(
                          counterText: '',
                          isDense: true,
                          contentPadding: const EdgeInsets.fromLTRB(
                            12,
                            10,
                            12,
                            10,
                          ),
                          filled: true,
                          fillColor: widget.foregroundColor.withValues(
                            alpha: 0.08,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: widget.foregroundColor.withValues(
                                alpha: 0.18,
                              ),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: widget.foregroundColor.withValues(
                                alpha: 0.18,
                              ),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: widget.foregroundColor.withValues(
                                alpha: 0.58,
                              ),
                              width: 1.5,
                            ),
                          ),
                        ),
                      )
                    else
                      Text(widget.note.title, style: titleStyle),
                    if (_isEditing) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            key: const ValueKey('cancel-detail-title-button'),
                            tooltip: 'Cancelar',
                            onPressed: widget.isSaving ? null : _cancelEditing,
                            color: widget.foregroundColor,
                            style: IconButton.styleFrom(
                              minimumSize: const Size(40, 40),
                              maximumSize: const Size(40, 40),
                              backgroundColor: widget.foregroundColor
                                  .withValues(alpha: 0.08),
                              side: BorderSide(
                                color: widget.foregroundColor.withValues(
                                  alpha: 0.16,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.close_rounded, size: 21),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            key: const ValueKey('save-detail-title-button'),
                            tooltip: 'Guardar título',
                            onPressed: widget.isSaving ? null : _saveTitle,
                            color: actionIconColor,
                            style: IconButton.styleFrom(
                              minimumSize: const Size(40, 40),
                              maximumSize: const Size(40, 40),
                              backgroundColor: widget.foregroundColor,
                            ),
                            icon: const Icon(Icons.check_rounded, size: 21),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          NoteCategoryStyle.icon(widget.note.category),
                          size: 16,
                          color: widget.foregroundColor.withValues(alpha: 0.86),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          NoteCategoryStyle.label(widget.note.category),
                          style: TextStyle(
                            color: widget.foregroundColor.withValues(
                              alpha: 0.86,
                            ),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpandableContentRow extends StatefulWidget {
  const _ExpandableContentRow({
    required this.note,
    required this.isSaving,
    required this.foregroundColor,
    required this.onSave,
    super.key,
  });

  final Note note;
  final bool isSaving;
  final Color foregroundColor;
  final Future<void> Function(NoteRichContent content) onSave;

  @override
  State<_ExpandableContentRow> createState() => _ExpandableContentRowState();
}

class _ExpandableContentRowState extends State<_ExpandableContentRow> {
  bool _isExpanded = false;
  int _editorVersion = 0;
  late NoteRichContent _content = _initialContent();

  NoteRichContent _initialContent() => NoteRichContent(
    plainText: widget.note.content,
    deltaJson:
        widget.note.contentDelta ??
        noteRichContentFromDocument(
          noteDocumentFromContent(plainText: widget.note.content),
        ).deltaJson,
  );

  void _toggle() {
    if (widget.isSaving) return;
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _content = _initialContent();
        _editorVersion++;
      }
    });
  }

  void _collapse() {
    setState(() {
      _isExpanded = false;
      _content = _initialContent();
    });
  }

  Future<void> _save() async {
    if (_content.plainText.length > noteContentMaxLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El detalle puede tener hasta 500 caracteres.'),
        ),
      );
      return;
    }
    await widget.onSave(_content);
    if (mounted) setState(() => _isExpanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final actionForeground =
        ThemeData.estimateBrightnessForColor(widget.foregroundColor) ==
            Brightness.dark
        ? Colors.white
        : Colors.black87;
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        children: [
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 18, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.subject_rounded,
                    size: 24,
                    color: widget.foregroundColor.withValues(alpha: 0.72),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: widget.note.content.isEmpty
                        ? Text(
                            'Agregar contenido',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: widget.foregroundColor.withValues(
                                    alpha: 0.52,
                                  ),
                                ),
                          )
                        : NoteRichTextViewer(
                            key: ValueKey(
                              widget.note.contentDelta ?? widget.note.content,
                            ),
                            plainText: widget.note.content,
                            deltaJson: widget.note.contentDelta,
                            foregroundColor: widget.foregroundColor,
                          ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _isExpanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: widget.foregroundColor.withValues(alpha: 0.48),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded) ...[
            Divider(
              height: 1,
              indent: 62,
              endIndent: 20,
              color: widget.foregroundColor.withValues(alpha: 0.16),
            ),
            Padding(
              key: const ValueKey('detail-content-field'),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: NoteRichTextEditor(
                key: ValueKey('detail-content-editor-$_editorVersion'),
                editorKey: const ValueKey('detail-content-editor'),
                initialPlainText: _content.plainText,
                initialDeltaJson: _content.deltaJson,
                autoFocus: true,
                minEditorHeight: 150,
                maxEditorHeight: 260,
                foregroundColor: widget.foregroundColor,
                backgroundColor: widget.foregroundColor.withValues(alpha: 0.08),
                onChanged: (content) => _content = content,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const ValueKey('collapse-detail-content-button'),
                    onPressed: widget.isSaving ? null : _collapse,
                    style: TextButton.styleFrom(
                      foregroundColor: widget.foregroundColor,
                    ),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('save-detail-content-button'),
                    onPressed: widget.isSaving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.foregroundColor,
                      foregroundColor: actionForeground,
                    ),
                    child: const Text('Guardar'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryPickerSheet extends StatelessWidget {
  const _CategoryPickerSheet({required this.selected});

  final NoteCategory selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final availableHeight =
        mediaQuery.size.height - mediaQuery.padding.vertical;

    return SafeArea(
      child: SizedBox(
        height: availableHeight * 0.78,
        child: ListView(
          key: const ValueKey('detail-category-list'),
          primary: false,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Cambiar categoría',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Elige cómo quieres identificar esta nota.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.62),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            for (final category in NoteCategory.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color: category == selected
                      ? colorScheme.primaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    key: ValueKey('detail-category-${category.name}'),
                    onTap: () => Navigator.pop(context, category),
                    leading: CircleAvatar(
                      backgroundColor: NoteCategoryStyle.baseColor(category),
                      foregroundColor: NoteCategoryStyle.foregroundColor(
                        category,
                      ),
                      child: Icon(NoteCategoryStyle.icon(category), size: 20),
                    ),
                    title: Text(
                      NoteCategoryStyle.label(category),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: category == selected
                        ? Icon(
                            Icons.check_circle_rounded,
                            color: colorScheme.primary,
                          )
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ColorPickerSheet extends StatelessWidget {
  const _ColorPickerSheet({required this.selected});

  final NoteColor selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cambiar color',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Elige el color que tendrá esta nota.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.62),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: NoteColor.values.map((color) {
                final isSelected = color == selected;
                final noteColor = NotePalette.color(color);
                return Semantics(
                  button: true,
                  selected: isSelected,
                  label: 'Color ${_colorName(color)}',
                  child: InkWell(
                    key: ValueKey('detail-color-${color.name}'),
                    onTap: () => Navigator.pop(context, color),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      width: 104,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: noteColor.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isSelected
                              ? colorScheme.onSurface
                              : colorScheme.onSurface.withValues(alpha: 0.12),
                          width: isSelected ? 2.5 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSelected
                                ? Icons.check_circle_rounded
                                : Icons.circle_outlined,
                            color: const Color(0xFF282621),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            _colorName(color),
                            style: const TextStyle(
                              color: Color(0xFF282621),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar({
    required this.label,
    required this.color,
    this.photoUrl,
    super.key,
  });

  final String label;
  final Color color;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final trimmedLabel = label.trim();
    final normalizedPhotoUrl = photoUrl?.trim();
    final hasPhoto =
        normalizedPhotoUrl != null && normalizedPhotoUrl.isNotEmpty;
    return CircleAvatar(
      radius: 16,
      backgroundColor: color,
      foregroundColor: const Color(0xFF282621),
      foregroundImage: hasPhoto ? NetworkImage(normalizedPhotoUrl) : null,
      onForegroundImageError: hasPhoto ? (_, _) {} : null,
      child: Text(
        trimmedLabel.isEmpty
            ? '?'
            : trimmedLabel.characters.first.toUpperCase(),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

String? _firstPhotoUrl(String? primary, String? fallback) {
  final normalizedPrimary = primary?.trim();
  if (normalizedPrimary != null && normalizedPrimary.isNotEmpty) {
    return normalizedPrimary;
  }
  final normalizedFallback = fallback?.trim();
  return normalizedFallback == null || normalizedFallback.isEmpty
      ? null
      : normalizedFallback;
}

class _DetailFooter extends StatelessWidget {
  const _DetailFooter({
    required this.note,
    required this.isSaving,
    required this.onDelete,
  });

  final Note note;
  final bool isSaving;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: colorScheme.onSurface.withValues(alpha: 0.1),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Creada ${_formatDateTime(note.createdAt)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.58),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('detail-delete-button'),
              tooltip: 'Eliminar nota',
              onPressed: isSaving ? null : onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatReminder(DateTime date) {
  final minute = date.minute.toString().padLeft(2, '0');
  return '${_weekdayName(date.weekday)}, ${date.day} de '
      '${_monthName(date.month)} · ${date.hour}:$minute';
}

String _formatDateTime(DateTime date) {
  final localDate = date.toLocal();
  final hour = localDate.hour.toString().padLeft(2, '0');
  final minute = localDate.minute.toString().padLeft(2, '0');
  return 'el ${localDate.day} de ${_monthName(localDate.month)} de '
      '${localDate.year} a las $hour:$minute';
}

String _weekdayName(int weekday) => const [
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo',
][weekday - 1];

String _monthName(int month) => const [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
][month - 1];

String _colorName(NoteColor color) => switch (color) {
  NoteColor.yellow => 'Amarillo',
  NoteColor.pink => 'Rosado',
  NoteColor.blue => 'Azul',
  NoteColor.green => 'Verde',
  NoteColor.purple => 'Morado',
  NoteColor.orange => 'Naranjo',
  NoteColor.mint => 'Menta',
  NoteColor.coral => 'Coral',
  NoteColor.gray => 'Gris',
  NoteColor.red => 'Rojo',
  NoteColor.teal => 'Turquesa',
  NoteColor.brown => 'Café',
};
