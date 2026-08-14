import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:nocknock/core/input_formatters/initial_uppercase_text_formatter.dart';
import 'package:nocknock/core/input_formatters/money_text_input_formatter.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/presentation/note_category_style.dart';
import 'package:nocknock/features/notes/presentation/note_attachment_picker.dart';
import 'package:nocknock/features/notes/presentation/note_palette.dart';
import 'package:nocknock/features/notes/presentation/widgets/post_it_card.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_rich_text.dart';
import 'package:nocknock/features/notes/presentation/widgets/reminder_picker.dart';
import 'package:uuid/uuid.dart';

typedef NotePreviewCardBuilder =
    Widget Function(
      BuildContext context,
      VoidCallback editAssignee,
      VoidCallback? editAttachment,
      ValueNotifier<PostItInlineEditTarget> editTarget,
      Future<bool> Function(NoteDraft draft) saveInline,
    );
typedef NotePreviewNoteProvider = Note Function();
typedef NotePreviewAssigneesProvider = List<ListCollaborator> Function();
typedef NoteQuickSaveCallback =
    Future<void> Function(Note note, NoteDraft draft);
typedef NotePreviewDeleteCallback = Future<void> Function(Note note);

int _previewImageCacheWidth(
  BuildContext context,
  double logicalWidth, {
  int maximum = 1024,
}) => (logicalWidth * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(
  1,
  maximum,
);

Future<bool> showNotePreviewDialog({
  required BuildContext context,
  required NotePreviewCardBuilder cardBuilder,
  required NotePreviewNoteProvider noteProvider,
  required NotePreviewAssigneesProvider assigneesProvider,
  required NoteQuickSaveCallback onSave,
  required NotePreviewDeleteCallback onDelete,
}) async {
  final disableAnimations = MediaQuery.disableAnimationsOf(context);
  final shouldOpen = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar vista previa de la nota',
    barrierColor: Colors.black.withValues(alpha: 0.48),
    transitionDuration: disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 230),
    pageBuilder: (dialogContext, animation, _) => _NotePreviewDialog(
      transitionAnimation: animation,
      disableAnimations: disableAnimations,
      cardBuilder: cardBuilder,
      noteProvider: noteProvider,
      assigneesProvider: assigneesProvider,
      onSave: onSave,
      onDelete: onDelete,
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) => child,
  );
  return shouldOpen ?? false;
}

Future<NoteDraft?> showCreateNoteDialog({
  required BuildContext context,
  required String defaultAuthorName,
  required bool showAuthorField,
  required List<ListCollaborator> assignees,
  Note? initialNote,
}) {
  final disableAnimations = MediaQuery.disableAnimationsOf(context);
  final now = DateTime.now();
  final emptyNote =
      initialNote ??
      Note(
        id: 'new-note',
        boardId: '',
        title: '',
        content: '',
        color: NoteColor.none,
        authorName: defaultAuthorName,
        isCompleted: false,
        positionX: 0,
        positionY: 0,
        createdAt: now,
        updatedAt: now,
      );
  return showGeneralDialog<NoteDraft>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar creación de nota',
    barrierColor: Colors.black.withValues(alpha: 0.48),
    transitionDuration: disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 320),
    pageBuilder: (dialogContext, _, _) => _CreateNoteDialog(
      note: emptyNote,
      assignees: assignees,
      showAuthorField: showAuthorField,
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      if (disableAnimations) return child;
      final entrance = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1).animate(entrance),
          child: child,
        ),
      );
    },
  );
}

class _CreateNoteDialog extends StatelessWidget {
  const _CreateNoteDialog({
    required this.note,
    required this.assignees,
    required this.showAuthorField,
  });

  final Note note;
  final List<ListCollaborator> assignees;
  final bool showAuthorField;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final availableHeight =
        mediaQuery.size.height -
        mediaQuery.padding.vertical -
        mediaQuery.viewInsets.vertical -
        40;
    final dialogHeight = math.min(680.0, math.max(300.0, availableHeight));
    final dialogWidth = math.min(480.0, mediaQuery.size.width - 32);
    return Stack(
      fit: StackFit.expand,
      children: [
        BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: const ColoredBox(color: Colors.transparent),
        ),
        Padding(
          key: const ValueKey('note-create-keyboard-viewport'),
          padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
          child: SafeArea(
            child: Center(
              child: Material(
                key: const ValueKey('note-create-transparent-shell'),
                type: MaterialType.transparency,
                child: SizedBox(
                  key: const ValueKey('note-create-dialog'),
                  width: dialogWidth,
                  height: dialogHeight,
                  child: Column(
                    children: [
                      _PreviewHeader(
                        isEditing: true,
                        isSaving: false,
                        editingLabel: 'Nueva nota',
                        closeButtonKey: const ValueKey(
                          'close-note-editor-button',
                        ),
                        onClose: () => Navigator.pop(context),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: _QuickNoteEditor(
                          note: note,
                          assignees: assignees,
                          isSaving: false,
                          isCreating: true,
                          showAuthorField: showAuthorField,
                          onCancel: () => Navigator.pop(context),
                          onSave: (draft) => Navigator.pop(context, draft),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NotePreviewDialog extends StatefulWidget {
  const _NotePreviewDialog({
    required this.transitionAnimation,
    required this.disableAnimations,
    required this.cardBuilder,
    required this.noteProvider,
    required this.assigneesProvider,
    required this.onSave,
    required this.onDelete,
  });

  final Animation<double> transitionAnimation;
  final bool disableAnimations;
  final NotePreviewCardBuilder cardBuilder;
  final NotePreviewNoteProvider noteProvider;
  final NotePreviewAssigneesProvider assigneesProvider;
  final NoteQuickSaveCallback onSave;
  final NotePreviewDeleteCallback onDelete;

  @override
  State<_NotePreviewDialog> createState() => _NotePreviewDialogState();
}

class _NotePreviewDialogState extends State<_NotePreviewDialog> {
  static const _historyLimit = 5;
  final _inlineEditTarget = ValueNotifier(PostItInlineEditTarget.none);
  final _undoHistory = <NoteDraft>[];
  final _redoHistory = <NoteDraft>[];
  bool _isSaving = false;

  Future<bool> _saveInlineDraft(NoteDraft draft) =>
      _persistDraft(widget.noteProvider(), draft);

  @override
  void dispose() {
    _inlineEditTarget.dispose();
    super.dispose();
  }

  Future<bool> _persistDraft(
    Note note,
    NoteDraft draft, {
    bool recordHistory = true,
  }) async {
    if (_isSaving) return false;
    final previousDraft = _draftFromNote(note);
    if (previousDraft == draft) return true;
    setState(() => _isSaving = true);
    try {
      await widget.onSave(note, draft);
      if (recordHistory && mounted) {
        setState(() {
          _addHistoryEntry(_undoHistory, previousDraft);
          _redoHistory.clear();
        });
      }
      return true;
    } on Object {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pudimos guardar los cambios. Inténtalo otra vez.'),
        ),
      );
      return false;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _undo() async {
    if (_isSaving || _undoHistory.isEmpty) return;
    final note = widget.noteProvider();
    final currentDraft = _draftFromNote(note);
    final previousDraft = _undoHistory.last;
    final saved = await _persistDraft(
      note,
      previousDraft,
      recordHistory: false,
    );
    if (!saved || !mounted) return;
    setState(() {
      _undoHistory.removeLast();
      _addHistoryEntry(_redoHistory, currentDraft);
    });
  }

  Future<void> _redo() async {
    if (_isSaving || _redoHistory.isEmpty) return;
    final note = widget.noteProvider();
    final currentDraft = _draftFromNote(note);
    final nextDraft = _redoHistory.last;
    final saved = await _persistDraft(note, nextDraft, recordHistory: false);
    if (!saved || !mounted) return;
    setState(() {
      _redoHistory.removeLast();
      _addHistoryEntry(_undoHistory, currentDraft);
    });
  }

  void _addHistoryEntry(List<NoteDraft> history, NoteDraft draft) {
    history.add(draft);
    if (history.length > _historyLimit) history.removeAt(0);
  }

  Future<void> _confirmDelete() async {
    if (_isSaving) return;
    final note = widget.noteProvider();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Eliminar esta nota?'),
        content: Text(
          'Se eliminará “${note.title}” para todos los colaboradores. '
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('cancel-preview-delete-button'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('confirm-preview-delete-button'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isSaving = true);
    try {
      await widget.onDelete(note);
      if (mounted) Navigator.of(context).pop(false);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pudimos eliminar la nota. Inténtalo otra vez.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _editColor() async {
    final initialNote = widget.noteProvider();
    final color = await showModalBottomSheet<NoteColor>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) =>
          _PreviewColorPickerSheet(selected: initialNote.color),
    );
    if (!mounted || color == null || color == initialNote.color) return;
    final note = widget.noteProvider();
    await _persistDraft(note, _draftFromNote(note, color: color));
  }

  Future<void> _editCategory() async {
    final initialNote = widget.noteProvider();
    final category = await showModalBottomSheet<NoteCategory>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) =>
          _PreviewCategoryPickerSheet(selected: initialNote.category),
    );
    if (!mounted || category == null || category == initialNote.category) {
      return;
    }
    final note = widget.noteProvider();
    await _persistDraft(note, _draftFromNote(note, category: category));
  }

  Future<void> _editReminder() async {
    final initialNote = widget.noteProvider();
    if (initialNote.reminderAt != null) {
      final action = await showModalBottomSheet<_PreviewReminderAction>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => _PreviewReminderActionsSheet(
          reminderAt: initialNote.reminderAt!,
          recurrence: initialNote.reminderRecurrence,
        ),
      );
      if (!mounted || action == null) return;
      if (action == _PreviewReminderAction.remove) {
        final note = widget.noteProvider();
        await _persistDraft(note, _draftFromNote(note, replaceReminder: true));
        return;
      }
    }

    if (!mounted) return;
    final schedule = await showReminderSchedulePicker(
      context,
      currentReminder: initialNote.reminderAt,
      currentRecurrence: initialNote.reminderRecurrence,
    );
    if (!mounted || schedule == null) return;
    final note = widget.noteProvider();
    await _persistDraft(
      note,
      _draftFromNote(
        note,
        reminderAt: schedule.reminderAt,
        reminderRecurrence: schedule.recurrence,
        replaceReminder: true,
      ),
    );
  }

  Future<void> _editAssignee() async {
    final initialNote = widget.noteProvider();
    final selection = await showModalBottomSheet<_AssigneeSelection>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _PreviewAssigneePickerSheet(
        selectedUid: initialNote.assigneeUid,
        customName: initialNote.customAssigneeName,
        assignees: widget.assigneesProvider(),
      ),
    );
    if (!mounted || selection == null) return;
    if (selection.uid == initialNote.assigneeUid &&
        selection.customName == initialNote.customAssigneeName) {
      return;
    }
    final note = widget.noteProvider();
    await _persistDraft(
      note,
      _draftFromNote(
        note,
        assigneeUid: selection.uid,
        customAssigneeName: selection.customName,
        replaceAssignee: true,
      ),
    );
  }

  Future<void> _editAttachment() async {
    if (_isSaving) return;
    final note = widget.noteProvider();
    if (note.photoAttachments.isNotEmpty) {
      final action = await showModalBottomSheet<_PhotoAction>(
        context: context,
        showDragHandle: true,
        builder: (_) => _PhotoActionsSheet(attachments: note.photoAttachments),
      );
      if (!mounted || action == null) return;
      if (action.removeId case final id?) {
        await _persistDraft(
          note,
          _draftFromNote(
            note,
            attachments: note.photoAttachments
                .where((entry) => entry.id != id)
                .toList(),
            replaceAttachments: true,
          ),
        );
        return;
      }
    }
    if (!mounted) return;
    try {
      final attachments = await pickNoteAttachments(
        context: context,
        remaining: noteAttachmentMaxCount - note.photoAttachments.length,
      );
      if (!mounted || attachments.isEmpty) return;
      final latest = widget.noteProvider();
      await _persistDraft(
        latest,
        _draftFromNote(
          latest,
          attachments: [
            ...latest.photoAttachments,
            ...attachments,
          ].take(noteAttachmentMaxCount).toList(),
          replaceAttachments: true,
        ),
      );
    } on NoteAttachmentPickFailure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final useBackdropBlur =
        Theme.of(context).platform != TargetPlatform.android;
    final availableHeight =
        mediaQuery.size.height -
        mediaQuery.padding.vertical -
        mediaQuery.viewInsets.vertical -
        40;
    final dialogHeight = math.min(680.0, math.max(300.0, availableHeight));
    final dialogWidth = math.min(480.0, mediaQuery.size.width - 32);
    final note = widget.noteProvider();
    final cardColor = NoteCategoryStyle.baseColor(note.category);
    final foregroundColor = NoteCategoryStyle.foregroundColor(note.category);
    final background = BackdropFilter(
      key: const ValueKey('note-preview-background-blur'),
      enabled: useBackdropBlur,
      filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
      child: const ColoredBox(color: Colors.transparent),
    );
    final content = RepaintBoundary(
      key: const ValueKey('note-preview-transition-boundary'),
      child: Padding(
        key: const ValueKey('note-preview-keyboard-viewport'),
        padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
        child: SafeArea(
          child: Center(
            child: Semantics(
              namesRoute: true,
              label: 'Vista previa editable de la nota',
              child: Material(
                key: const ValueKey('note-preview-transparent-shell'),
                type: MaterialType.transparency,
                child: SizedBox(
                  key: const ValueKey('note-preview-dialog'),
                  width: dialogWidth,
                  height: dialogHeight,
                  child: Column(
                    children: [
                      Expanded(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: RepaintBoundary(
                                key: const ValueKey('note-preview-card'),
                                child: widget.cardBuilder(
                                  context,
                                  _editAssignee,
                                  _isSaving ? null : _editAttachment,
                                  _inlineEditTarget,
                                  _saveInlineDraft,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              right: 10,
                              child: _FloatingPreviewCloseButton(
                                isSaving: _isSaving,
                                color: cardColor,
                                foregroundColor: foregroundColor,
                                onClose: () => Navigator.of(context).pop(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _PreviewEditingDock(
                        note: widget.noteProvider(),
                        isSaving: _isSaving,
                        canUndo: _undoHistory.isNotEmpty,
                        canRedo: _redoHistory.isNotEmpty,
                        onUndo: _undo,
                        onRedo: _redo,
                        onColor: _editColor,
                        onCategory: _editCategory,
                        onReminder: _editReminder,
                        onAttachment: _editAttachment,
                        onDelete: _confirmDelete,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.disableAnimations) {
      return Stack(fit: StackFit.expand, children: [background, content]);
    }

    final entrance = CurvedAnimation(
      parent: widget.transitionAnimation,
      curve: const Cubic(0.16, 1, 0.3, 1),
      reverseCurve: Curves.easeInCubic,
    );
    final fade = CurvedAnimation(
      parent: widget.transitionAnimation,
      curve: const Interval(0, 0.76, curve: Curves.easeOutCubic),
      reverseCurve: Curves.easeInCubic,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        FadeTransition(opacity: fade, child: background),
        FadeTransition(
          key: const ValueKey('note-preview-fade-transition'),
          opacity: fade,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.018),
              end: Offset.zero,
            ).animate(entrance),
            child: useBackdropBlur
                ? ScaleTransition(
                    key: const ValueKey('note-preview-scale-transition'),
                    scale: Tween<double>(
                      begin: 0.975,
                      end: 1,
                    ).animate(entrance),
                    child: content,
                  )
                : KeyedSubtree(
                    key: const ValueKey('note-preview-scale-transition'),
                    child: content,
                  ),
          ),
        ),
      ],
    );
  }
}

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({
    required this.isEditing,
    required this.isSaving,
    required this.onClose,
    this.editingLabel = 'Edición rápida',
    this.closeButtonKey = const ValueKey('close-note-preview-button'),
  });

  final bool isEditing;
  final bool isSaving;
  final VoidCallback onClose;
  final String editingLabel;
  final Key closeButtonKey;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          if (isEditing) ...[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 16,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Icon(
                Icons.edit_note_rounded,
                size: 20,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                editingLabel,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 12),
                  ],
                ),
              ),
            ),
          ] else
            const Spacer(),
          IconButton(
            key: closeButtonKey,
            tooltip: 'Cerrar',
            onPressed: isSaving ? null : onClose,
            color: Colors.white,
            disabledColor: Colors.white38,
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.34),
              disabledBackgroundColor: Colors.black.withValues(alpha: 0.2),
              minimumSize: const Size(44, 44),
            ),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _FloatingPreviewCloseButton extends StatelessWidget {
  const _FloatingPreviewCloseButton({
    required this.isSaving,
    required this.color,
    required this.foregroundColor,
    required this.onClose,
  });

  final bool isSaving;
  final Color color;
  final Color foregroundColor;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Cerrar',
      child: Material(
        color: color,
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.28),
        shape: CircleBorder(
          side: BorderSide(color: foregroundColor.withValues(alpha: 0.2)),
        ),
        child: InkWell(
          key: const ValueKey('close-note-preview-button'),
          onTap: isSaving ? null : onClose,
          customBorder: const CircleBorder(),
          child: SizedBox.square(
            dimension: 30,
            child: Icon(
              Icons.close_rounded,
              color: isSaving
                  ? foregroundColor.withValues(alpha: 0.38)
                  : foregroundColor,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickNoteEditor extends StatefulWidget {
  const _QuickNoteEditor({
    required this.note,
    required this.assignees,
    required this.isSaving,
    required this.onCancel,
    required this.onSave,
    this.isCreating = false,
    this.showAuthorField = false,
  });

  final Note note;
  final List<ListCollaborator> assignees;
  final bool isSaving;
  final VoidCallback onCancel;
  final ValueChanged<NoteDraft> onSave;
  final bool isCreating;
  final bool showAuthorField;

  @override
  State<_QuickNoteEditor> createState() => _QuickNoteEditorState();
}

class _QuickNoteEditorState extends State<_QuickNoteEditor> {
  final _formKey = GlobalKey<FormState>();
  final _contentSectionKey = GlobalKey();
  final _checklistSectionKey = GlobalKey();
  late final TextEditingController _titleController;
  late final TextEditingController _authorController;
  late NoteRichContent _content;
  late List<NoteChecklistItem> _checklist;
  late NoteColor _color;
  late NoteCategory _category;
  late String? _assigneeUid;
  late String? _customAssigneeName;
  late List<NoteAttachment> _attachments;
  late DateTime? _reminderAt;
  late ReminderRecurrence? _reminderRecurrence;
  late bool _descriptionExpanded;

  @override
  void initState() {
    super.initState();
    final note = widget.note;
    _titleController = TextEditingController(
      text: capitalizeInitialLetter(note.title),
    );
    _authorController = TextEditingController(text: note.authorName);
    _content = normalizeNoteRichContent(
      NoteRichContent(
        plainText: capitalizeInitialLetter(note.content),
        deltaJson:
            note.contentDelta ??
            noteRichContentFromDocument(
              noteDocumentFromContent(
                plainText: capitalizeInitialLetter(note.content),
              ),
            ).deltaJson,
      ),
    );
    _checklist = [...note.checklist];
    _color = note.color;
    _category = note.category;
    _assigneeUid = note.assigneeUid;
    _customAssigneeName = note.customAssigneeName;
    _attachments = [...note.photoAttachments];
    _reminderAt = note.reminderAt;
    _reminderRecurrence = note.reminderRecurrence;
    _descriptionExpanded = note.content.trim().isNotEmpty;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    super.dispose();
  }

  int _titleInputLineCount(
    BuildContext context,
    double maxWidth,
    TextStyle style,
  ) {
    final text = _titleController.text.isEmpty
        ? 'Título de la nota'
        : _titleController.text;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final availableTextWidth = (maxWidth - 28)
        .clamp(1.0, double.infinity)
        .toDouble();
    return text.contains('\n') || painter.width > availableTextWidth ? 2 : 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hidePhotoPreviewForKeyboard =
        widget.isCreating && MediaQuery.viewInsetsOf(context).bottom > 0;
    final cardColor = _category == NoteCategory.general
        ? NotePalette.color(_color)
        : NoteCategoryStyle.baseColor(_category);
    final foregroundColor = NoteCategoryStyle.foregroundColor(_category);
    final backgroundAsset = NoteCategoryStyle.assetPath(_category);
    final useDarkFieldFill = foregroundColor.computeLuminance() > 0.5;
    final fieldFill = useDarkFieldFill
        ? Colors.black.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.34);
    final editorTheme = theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        primary: foregroundColor,
        onPrimary: cardColor,
        surface: cardColor,
        onSurface: foregroundColor,
        onSurfaceVariant: foregroundColor.withValues(alpha: 0.72),
        surfaceContainerHighest: fieldFill,
      ),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: fieldFill,
        labelStyle: TextStyle(color: foregroundColor.withValues(alpha: 0.76)),
        hintStyle: TextStyle(color: foregroundColor.withValues(alpha: 0.56)),
        prefixIconColor: foregroundColor.withValues(alpha: 0.8),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: foregroundColor.withValues(alpha: 0.16),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: foregroundColor, width: 1.6),
        ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Material(
        key: const ValueKey('quick-note-editor'),
        color: cardColor,
        child: Ink(
          key: const ValueKey('quick-note-editor-surface'),
          decoration: BoxDecoration(
            color: cardColor,
            image: backgroundAsset == null
                ? null
                : DecorationImage(
                    image: ResizeImage(
                      AssetImage(backgroundAsset),
                      width: _previewImageCacheWidth(
                        context,
                        MediaQuery.sizeOf(context).width,
                      ),
                    ),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                      Colors.black.withValues(alpha: 0.22),
                      BlendMode.darken,
                    ),
                  ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(
                    alpha: backgroundAsset == null ? 0.02 : 0.12,
                  ),
                ],
              ),
            ),
            child: Theme(
              data: editorTheme,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                child: AbsorbPointer(
                  absorbing: widget.isSaving,
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    const titleStyle = TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    );
                                    final lineCount = _titleInputLineCount(
                                      context,
                                      constraints.maxWidth,
                                      titleStyle,
                                    );
                                    return TextFormField(
                                      key: ValueKey(
                                        widget.isCreating
                                            ? 'note-title-field'
                                            : 'quick-edit-title-field',
                                      ),
                                      controller: _titleController,
                                      autofocus: widget.isCreating,
                                      maxLength: 80,
                                      minLines: lineCount,
                                      maxLines: lineCount,
                                      style: titleStyle.copyWith(
                                        color: foregroundColor,
                                      ),
                                      cursorColor: foregroundColor,
                                      textCapitalization:
                                          TextCapitalization.sentences,
                                      keyboardType:
                                          _category == NoteCategory.money
                                          ? TextInputType.number
                                          : TextInputType.text,
                                      inputFormatters:
                                          _category == NoteCategory.money
                                          ? [MoneyTextInputFormatter()]
                                          : const [
                                              InitialUppercaseTextFormatter(),
                                            ],
                                      onChanged: (_) => setState(() {}),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        hintText:
                                            _category == NoteCategory.money
                                            ? r'$0'
                                            : 'Título de la nota',
                                        counterText: '',
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 10,
                                            ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                      validator: (value) =>
                                          value == null || value.trim().isEmpty
                                          ? 'Escribe un título para la nota'
                                          : null,
                                    );
                                  },
                                ),
                                if (widget.showAuthorField) ...[
                                  const SizedBox(height: 2),
                                  TextFormField(
                                    key: const ValueKey('note-author-field'),
                                    controller: _authorController,
                                    maxLength: 50,
                                    style: TextStyle(color: foregroundColor),
                                    cursorColor: foregroundColor,
                                    decoration: const InputDecoration(
                                      labelText: 'Tu nombre',
                                      prefixIcon: Icon(
                                        Icons.person_outline_rounded,
                                      ),
                                    ),
                                    validator: (value) =>
                                        value == null || value.trim().isEmpty
                                        ? 'Indica quién crea la nota'
                                        : null,
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Container(
                                  key: _contentSectionKey,
                                  child: _descriptionExpanded
                                      ? NoteRichTextEditor(
                                          key: ValueKey(
                                            widget.isCreating
                                                ? 'note-content-field'
                                                : 'quick-edit-content-field',
                                          ),
                                          editorKey: ValueKey(
                                            widget.isCreating
                                                ? 'note-content-editor'
                                                : 'quick-edit-content-editor',
                                          ),
                                          initialPlainText: _content.plainText,
                                          initialDeltaJson: _content.deltaJson,
                                          autoFocus: true,
                                          minEditorHeight: 76,
                                          maxEditorHeight: 132,
                                          foregroundColor: foregroundColor,
                                          backgroundColor: fieldFill,
                                          onChanged: (content) =>
                                              _content = content,
                                        )
                                      : Align(
                                          alignment: Alignment.centerLeft,
                                          child: TextButton.icon(
                                            key: const ValueKey(
                                              'add-description-button',
                                            ),
                                            onPressed: _expandDescription,
                                            style: TextButton.styleFrom(
                                              foregroundColor: foregroundColor
                                                  .withValues(alpha: 0.72),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 2,
                                                    vertical: 8,
                                                  ),
                                            ),
                                            icon: const Icon(
                                              Icons.notes_rounded,
                                              size: 18,
                                            ),
                                            label: const Text(
                                              'Agregar descripción',
                                            ),
                                          ),
                                        ),
                                ),
                                Container(
                                  key: const ValueKey(
                                    'description-subtasks-divider',
                                  ),
                                  height: 1,
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  color: foregroundColor.withValues(
                                    alpha: 0.24,
                                  ),
                                ),
                                Column(
                                  key: _checklistSectionKey,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      'Subtareas',
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            color: foregroundColor.withValues(
                                              alpha: 0.72,
                                            ),
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    if (_checklist.isEmpty)
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: TextButton.icon(
                                          key: const ValueKey(
                                            'add-checklist-item',
                                          ),
                                          onPressed: _openChecklist,
                                          style: TextButton.styleFrom(
                                            foregroundColor: foregroundColor,
                                          ),
                                          icon: const Icon(
                                            Icons.add_rounded,
                                            size: 18,
                                          ),
                                          label: const Text('Agregar subtarea'),
                                        ),
                                      )
                                    else
                                      SimpleNoteChecklistEditor(
                                        key: const ValueKey(
                                          'quick-edit-checklist-editor',
                                        ),
                                        items: _checklist,
                                        foregroundColor: foregroundColor,
                                        onChanged: (items) =>
                                            setState(() => _checklist = items),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_attachments.isNotEmpty &&
                          !hidePhotoPreviewForKeyboard) ...[
                        const SizedBox(height: 10),
                        _QuickPhotoStrip(
                          attachments: _attachments,
                          foregroundColor: foregroundColor,
                          onOpen: (attachment) => showNotePhotoViewer(
                            context,
                            attachments: _attachments,
                            initialIndex: _attachments.indexWhere(
                              (entry) => entry.id == attachment.id,
                            ),
                            loader: null,
                          ),
                          onRemove: (attachment) => setState(
                            () => _attachments.removeWhere(
                              (entry) => entry.id == attachment.id,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      _QuickEditorTools(
                        color: _color,
                        category: _category,
                        reminderAt: _reminderAt,
                        reminderRecurrence: _reminderRecurrence,
                        assignee: _selectedAssignee,
                        attachmentCount: _attachments.length,
                        foregroundColor: foregroundColor,
                        onStyles: _expandDescription,
                        onChecklist: _openChecklist,
                        onColor: _pickColor,
                        onCategory: _pickCategory,
                        onReminder: _pickReminder,
                        onAssignee: _pickAssignee,
                        onAttachment: _pickAttachment,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              key: const ValueKey('cancel-quick-edit-button'),
                              onPressed: widget.onCancel,
                              style: TextButton.styleFrom(
                                foregroundColor: foregroundColor,
                                minimumSize: const Size.fromHeight(46),
                              ),
                              child: const Text('Cancelar'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              key: ValueKey(
                                widget.isCreating
                                    ? 'save-note-button'
                                    : 'save-quick-edit-button',
                              ),
                              onPressed: _submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: foregroundColor,
                                foregroundColor: cardColor,
                                minimumSize: const Size.fromHeight(46),
                              ),
                              icon: widget.isSaving
                                  ? SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: cardColor,
                                      ),
                                    )
                                  : const Icon(Icons.check_rounded),
                              label: Text(
                                widget.isSaving
                                    ? 'Guardando…'
                                    : widget.isCreating
                                    ? 'Crear nota'
                                    : 'Guardar cambios',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  ListCollaborator? get _selectedAssignee {
    for (final person in widget.assignees) {
      if (person.uid == _assigneeUid) return person;
    }
    final customName = _customAssigneeName?.trim();
    if (customName != null && customName.isNotEmpty) {
      return ListCollaborator(
        uid: 'custom:new-note',
        email: '',
        displayName: customName,
        role: ListMemberRole.editor,
        joinedAt: DateTime.now(),
      );
    }
    return null;
  }

  void _expandDescription() {
    if (_descriptionExpanded) {
      _showSection(_contentSectionKey);
      return;
    }
    setState(() => _descriptionExpanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showSection(_contentSectionKey);
    });
  }

  void _openChecklist() {
    if (_checklist.isEmpty) {
      setState(() {
        _checklist = [NoteChecklistItem(id: const Uuid().v4(), text: '')];
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showSection(_checklistSectionKey);
    });
  }

  void _showSection(GlobalKey sectionKey) {
    FocusManager.instance.primaryFocus?.unfocus();
    final sectionContext = sectionKey.currentContext;
    if (sectionContext == null) return;
    Scrollable.ensureVisible(
      sectionContext,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  Future<void> _pickColor() async {
    final color = await showModalBottomSheet<NoteColor>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _PreviewColorPickerSheet(selected: _color),
    );
    if (!mounted || color == null) return;
    setState(() => _color = color);
  }

  Future<void> _pickCategory() async {
    final category = await showModalBottomSheet<NoteCategory>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) =>
          _PreviewCategoryPickerSheet(selected: _category),
    );
    if (!mounted || category == null) return;
    setState(() {
      _category = category;
      if (category == NoteCategory.money) {
        _titleController.value = MoneyTextInputFormatter().formatEditUpdate(
          _titleController.value,
          _titleController.value,
        );
      }
    });
  }

  Future<void> _pickReminder() async {
    if (_reminderAt case final reminder?) {
      final action = await showModalBottomSheet<_PreviewReminderAction>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => _PreviewReminderActionsSheet(
          reminderAt: reminder,
          recurrence: _reminderRecurrence,
        ),
      );
      if (!mounted || action == null) return;
      if (action == _PreviewReminderAction.remove) {
        setState(() {
          _reminderAt = null;
          _reminderRecurrence = null;
        });
        return;
      }
    }
    if (!mounted) return;
    final schedule = await showReminderSchedulePicker(
      context,
      currentReminder: _reminderAt,
      currentRecurrence: _reminderRecurrence,
    );
    if (!mounted || schedule == null) return;
    setState(() {
      _reminderAt = schedule.reminderAt;
      _reminderRecurrence = schedule.recurrence;
    });
  }

  Future<void> _pickAssignee() async {
    final selection = await showModalBottomSheet<_AssigneeSelection>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _PreviewAssigneePickerSheet(
        selectedUid: _assigneeUid,
        customName: _customAssigneeName,
        assignees: widget.assignees,
      ),
    );
    if (!mounted || selection == null) return;
    setState(() {
      _assigneeUid = selection.uid;
      _customAssigneeName = selection.customName;
    });
  }

  Future<void> _pickAttachment() async {
    if (_attachments.isNotEmpty) {
      final action = await showModalBottomSheet<_PhotoAction>(
        context: context,
        showDragHandle: true,
        builder: (_) => _PhotoActionsSheet(attachments: _attachments),
      );
      if (!mounted || action == null) return;
      if (action.removeId case final id?) {
        setState(() => _attachments.removeWhere((entry) => entry.id == id));
        return;
      }
    }
    try {
      final attachments = await pickNoteAttachments(
        context: context,
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

  void _submit() {
    if (!_formKey.currentState!.validate() || widget.isSaving) return;
    final normalizedContent = normalizeNoteRichContent(_content);
    if (normalizedContent.plainText.length > noteContentMaxLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El contenido puede tener hasta 500 caracteres.'),
        ),
      );
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final note = widget.note;
    widget.onSave(
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
        authorName: widget.showAuthorField
            ? _authorController.text.trim()
            : note.authorName,
        assigneeUid: _assigneeUid,
        customAssigneeName: _customAssigneeName,
        attachments: _attachments,
        reminderAt: _reminderAt,
        reminderRecurrence: _reminderRecurrence,
      ),
    );
  }
}

class _QuickEditorTools extends StatelessWidget {
  const _QuickEditorTools({
    required this.color,
    required this.category,
    required this.reminderAt,
    required this.reminderRecurrence,
    required this.assignee,
    required this.attachmentCount,
    required this.foregroundColor,
    required this.onStyles,
    required this.onChecklist,
    required this.onColor,
    required this.onCategory,
    required this.onReminder,
    required this.onAssignee,
    required this.onAttachment,
  });

  final NoteColor color;
  final NoteCategory category;
  final DateTime? reminderAt;
  final ReminderRecurrence? reminderRecurrence;
  final ListCollaborator? assignee;
  final int attachmentCount;
  final Color foregroundColor;
  final VoidCallback onStyles;
  final VoidCallback onChecklist;
  final VoidCallback onColor;
  final VoidCallback onCategory;
  final VoidCallback onReminder;
  final VoidCallback onAssignee;
  final VoidCallback onAttachment;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Controles de edición dentro de la nota',
      child: Container(
        key: const ValueKey('quick-editor-tools'),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: foregroundColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: foregroundColor.withValues(alpha: 0.18)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const actionCount = 7;
            const preferredActionExtent = 44.0;
            const minimumSingleRowExtent = 40.0;
            final availableActionExtent = constraints.maxWidth / actionCount;
            final useSingleRow =
                availableActionExtent >= minimumSingleRowExtent;
            final actionExtent = useSingleRow
                ? math.min(preferredActionExtent, availableActionExtent)
                : preferredActionExtent;
            final actions = [
              _PreviewDockAction(
                key: const ValueKey('quick-editor-styles-action'),
                tooltip: 'Editar contenido y estilos',
                icon: Icons.format_shapes_rounded,
                dimension: actionExtent,
                onPressed: onStyles,
              ),
              _PreviewDockAction(
                key: const ValueKey('quick-editor-checklist-action'),
                tooltip: 'Agregar o editar subtareas',
                icon: Icons.checklist_rounded,
                dimension: actionExtent,
                onPressed: onChecklist,
              ),
              _PreviewDockAction(
                key: const ValueKey('quick-editor-color-action'),
                tooltip: 'Cambiar color',
                icon: Icons.palette_outlined,
                dimension: actionExtent,
                indicatorColor: NotePalette.color(color),
                onPressed: onColor,
              ),
              _PreviewDockAction(
                key: const ValueKey('quick-editor-category-action'),
                tooltip: 'Categoría y fondo',
                icon: NoteCategoryStyle.icon(category),
                dimension: actionExtent,
                selected: category != NoteCategory.general,
                onPressed: onCategory,
              ),
              _PreviewDockAction(
                key: const ValueKey('quick-editor-reminder-action'),
                tooltip: reminderAt == null
                    ? 'Agregar recordatorio'
                    : reminderRecurrence == null
                    ? 'Cambiar recordatorio'
                    : 'Cambiar recordatorio recurrente',
                icon: reminderRecurrence != null
                    ? Icons.repeat_rounded
                    : reminderAt == null
                    ? Icons.notifications_none_rounded
                    : Icons.notifications_active_rounded,
                dimension: actionExtent,
                selected: reminderAt != null,
                onPressed: onReminder,
              ),
              _PreviewAssigneeDockAction(
                key: const ValueKey('quick-editor-assignee-action'),
                assignee: assignee,
                dimension: actionExtent,
                onPressed: onAssignee,
              ),
              _PreviewDockAction(
                key: const ValueKey('quick-editor-attachment-action'),
                tooltip: attachmentCount == 0
                    ? 'Agregar fotos o PDF'
                    : 'Administrar adjuntos ($attachmentCount/2)',
                icon: Icons.add_photo_alternate_outlined,
                dimension: actionExtent,
                selected: attachmentCount > 0,
                onPressed: onAttachment,
              ),
            ];

            if (useSingleRow) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: actions,
              );
            }
            return Wrap(alignment: WrapAlignment.center, children: actions);
          },
        ),
      ),
    );
  }
}

class _QuickPhotoStrip extends StatelessWidget {
  const _QuickPhotoStrip({
    required this.attachments,
    required this.foregroundColor,
    required this.onOpen,
    required this.onRemove,
  });

  final List<NoteAttachment> attachments;
  final Color foregroundColor;
  final ValueChanged<NoteAttachment> onOpen;
  final ValueChanged<NoteAttachment> onRemove;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 82,
    child: Row(
      children: [
        for (final (index, attachment) in attachments.indexed) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Tooltip(
                  message: 'Ver foto en grande',
                  child: Semantics(
                    button: true,
                    image: true,
                    label: 'Ver ${attachment.name} en grande',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: ValueKey('quick-open-photo-${attachment.id}'),
                        borderRadius: BorderRadius.circular(13),
                        onTap: () => onOpen(attachment),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: _thumbnail(attachment),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 3,
                  right: 3,
                  child: IconButton.filledTonal(
                    key: ValueKey('quick-remove-photo-${attachment.id}'),
                    tooltip: 'Quitar adjunto',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onRemove(attachment),
                    icon: const Icon(Icons.close_rounded, size: 17),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );

  Widget _thumbnail(NoteAttachment attachment) {
    final encoded = attachment.dataBase64;
    if (attachment.isImage && encoded != null) {
      try {
        return Image.memory(
          base64Decode(encoded),
          key: ValueKey('quick-photo-${attachment.id}'),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallback(attachment),
        );
      } on FormatException {
        return _fallback(attachment);
      }
    }
    return _fallback(attachment);
  }

  Widget _fallback(NoteAttachment attachment) => ColoredBox(
    color: foregroundColor.withValues(alpha: 0.1),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          attachment.name,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: foregroundColor, fontSize: 11),
        ),
      ),
    ),
  );
}

NoteDraft _draftFromNote(
  Note note, {
  NoteColor? color,
  NoteCategory? category,
  String? assigneeUid,
  String? customAssigneeName,
  bool replaceAssignee = false,
  List<NoteAttachment>? attachments,
  bool replaceAttachments = false,
  DateTime? reminderAt,
  ReminderRecurrence? reminderRecurrence,
  bool replaceReminder = false,
}) => NoteDraft(
  title: note.title,
  content: note.content,
  contentDelta: note.contentDelta,
  color: color ?? note.color,
  category: category ?? note.category,
  checklist: List.of(note.checklist),
  authorName: note.authorName,
  assigneeUid: replaceAssignee ? assigneeUid : note.assigneeUid,
  customAssigneeName: replaceAssignee
      ? customAssigneeName
      : note.customAssigneeName,
  attachments: replaceAttachments
      ? attachments ?? const []
      : note.photoAttachments,
  reminderAt: replaceReminder ? reminderAt : note.reminderAt,
  reminderRecurrence: replaceReminder
      ? reminderRecurrence
      : note.reminderRecurrence,
);

class _PreviewEditingDock extends StatelessWidget {
  const _PreviewEditingDock({
    required this.note,
    required this.isSaving,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    required this.onColor,
    required this.onCategory,
    required this.onReminder,
    required this.onAttachment,
    required this.onDelete,
  });

  final Note note;
  final bool isSaving;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onColor;
  final VoidCallback onCategory;
  final VoidCallback onReminder;
  final VoidCallback onAttachment;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final noteColor = NotePalette.color(note.color);
    final useBackdropBlur =
        Theme.of(context).platform != TargetPlatform.android;
    return Semantics(
      container: true,
      label: 'Herramientas de edición de la nota',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.32),
              blurRadius: 24,
              offset: const Offset(0, 11),
            ),
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.14),
              blurRadius: 18,
              spreadRadius: -4,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            key: const ValueKey('note-preview-dock-blur'),
            enabled: useBackdropBlur,
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Material(
              key: const ValueKey('note-preview-editing-dock'),
              color: colorScheme.surface.withValues(
                alpha: useBackdropBlur ? 0.82 : 0.94,
              ),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.1),
                      colorScheme.surfaceContainerHigh.withValues(alpha: 0.54),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) => SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: constraints.maxWidth,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _PreviewDockAction(
                                  key: const ValueKey('preview-color-action'),
                                  tooltip: 'Cambiar color',
                                  icon: Icons.palette_outlined,
                                  indicatorColor: noteColor,
                                  onPressed: isSaving ? null : onColor,
                                ),
                                const SizedBox(width: 2),
                                _PreviewDockAction(
                                  key: const ValueKey(
                                    'preview-category-action',
                                  ),
                                  tooltip: 'Categoría y fondo',
                                  icon: NoteCategoryStyle.icon(note.category),
                                  selected:
                                      note.category != NoteCategory.general,
                                  onPressed: isSaving ? null : onCategory,
                                ),
                                const SizedBox(width: 2),
                                _PreviewDockAction(
                                  key: const ValueKey(
                                    'preview-reminder-action',
                                  ),
                                  tooltip: note.reminderAt == null
                                      ? 'Agregar recordatorio'
                                      : note.reminderRecurrence == null
                                      ? 'Cambiar recordatorio'
                                      : 'Cambiar recordatorio recurrente',
                                  icon: note.reminderRecurrence != null
                                      ? Icons.repeat_rounded
                                      : note.reminderAt == null
                                      ? Icons.notifications_none_rounded
                                      : Icons.notifications_active_rounded,
                                  selected: note.reminderAt != null,
                                  onPressed: isSaving ? null : onReminder,
                                ),
                                const SizedBox(width: 2),
                                _PreviewDockAction(
                                  key: const ValueKey(
                                    'preview-attachment-action',
                                  ),
                                  tooltip: note.photoAttachments.isEmpty
                                      ? 'Adjuntar foto o PDF'
                                      : 'Administrar adjuntos '
                                            '(${note.photoAttachments.length}/2)',
                                  icon: Icons.attach_file_rounded,
                                  selected: note.photoAttachments.isNotEmpty,
                                  onPressed: isSaving ? null : onAttachment,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    _PreviewHistoryAction(
                      key: const ValueKey('preview-history-action'),
                      isSaving: isSaving,
                      canUndo: canUndo,
                      canRedo: canRedo,
                      onUndo: onUndo,
                      onRedo: onRedo,
                    ),
                    const SizedBox(width: 2),
                    _PreviewDockAction(
                      key: const ValueKey('preview-delete-action'),
                      tooltip: 'Eliminar nota',
                      icon: Icons.delete_outline_rounded,
                      destructive: true,
                      onPressed: isSaving ? null : onDelete,
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

enum _PreviewHistoryCommand { undo, redo }

class _PreviewHistoryAction extends StatelessWidget {
  const _PreviewHistoryAction({
    required this.isSaving,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    super.key,
  });

  final bool isSaving;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 44,
      child: PopupMenuButton<_PreviewHistoryCommand>(
        tooltip: 'Deshacer o rehacer',
        enabled: !isSaving && (canUndo || canRedo),
        position: PopupMenuPosition.under,
        constraints: const BoxConstraints(minWidth: 164, maxWidth: 184),
        menuPadding: const EdgeInsets.symmetric(vertical: 4),
        color: colorScheme.surfaceContainerHigh,
        elevation: 8,
        onSelected: (command) {
          switch (command) {
            case _PreviewHistoryCommand.undo:
              onUndo();
            case _PreviewHistoryCommand.redo:
              onRedo();
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            key: const ValueKey('preview-undo-action'),
            value: _PreviewHistoryCommand.undo,
            enabled: canUndo,
            height: 42,
            child: const Row(
              children: [
                Icon(Icons.undo_rounded, size: 20),
                SizedBox(width: 12),
                Text('Deshacer'),
              ],
            ),
          ),
          PopupMenuItem(
            key: const ValueKey('preview-redo-action'),
            value: _PreviewHistoryCommand.redo,
            enabled: canRedo,
            height: 42,
            child: const Row(
              children: [
                Icon(Icons.redo_rounded, size: 20),
                SizedBox(width: 12),
                Text('Rehacer'),
              ],
            ),
          ),
        ],
        icon: const Icon(Icons.history_rounded, size: 21),
        style: IconButton.styleFrom(
          minimumSize: const Size.square(44),
          foregroundColor: colorScheme.onSurface,
          disabledForegroundColor: colorScheme.onSurface.withValues(
            alpha: 0.32,
          ),
        ),
      ),
    );
  }
}

class _PreviewDockAction extends StatelessWidget {
  const _PreviewDockAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.dimension = 44,
    this.selected = false,
    this.destructive = false,
    this.indicatorColor,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final double dimension;
  final bool selected;
  final bool destructive;
  final Color? indicatorColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: dimension,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              minimumSize: Size.square(dimension),
              foregroundColor: destructive
                  ? colorScheme.error
                  : selected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurface,
              backgroundColor: selected
                  ? colorScheme.primaryContainer.withValues(alpha: 0.88)
                  : Colors.transparent,
              disabledForegroundColor: colorScheme.onSurface.withValues(
                alpha: 0.32,
              ),
            ),
            icon: Icon(icon, size: 21),
          ),
          if (indicatorColor case final color?)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: colorScheme.surface, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PreviewAssigneeDockAction extends StatelessWidget {
  const _PreviewAssigneeDockAction({
    required this.assignee,
    required this.onPressed,
    this.dimension = 44,
    super.key,
  });

  final ListCollaborator? assignee;
  final VoidCallback? onPressed;
  final double dimension;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final person = assignee;
    final photoUrl = person?.photoUrl?.trim();
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    final tooltip = person == null
        ? 'Agregar responsable'
        : 'Responsable: ${_collaboratorLabel(person)}';
    return SizedBox.square(
      dimension: dimension,
      child: Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: tooltip,
          child: Material(
            color: person == null
                ? Colors.transparent
                : colorScheme.primaryContainer.withValues(alpha: 0.88),
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onPressed,
              customBorder: const CircleBorder(),
              child: Center(
                child: person == null
                    ? Icon(
                        Icons.person_add_alt_1_rounded,
                        size: 21,
                        color: onPressed == null
                            ? colorScheme.onSurface.withValues(alpha: 0.32)
                            : colorScheme.onSurface,
                      )
                    : CircleAvatar(
                        radius: 15,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        foregroundImage: hasPhoto
                            ? NetworkImage(photoUrl)
                            : null,
                        onForegroundImageError: hasPhoto ? (_, _) {} : null,
                        child: Text(
                          _collaboratorInitial(person),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
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

class _PreviewColorPickerSheet extends StatelessWidget {
  const _PreviewColorPickerSheet({required this.selected});

  final NoteColor selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Color de la nota',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 10,
              children: [
                for (final color in NoteColor.values)
                  Tooltip(
                    message: _noteColorName(color),
                    child: InkWell(
                      key: ValueKey('preview-color-${color.name}'),
                      onTap: () => Navigator.pop(context, color),
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: NotePalette.color(color),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color == selected
                                ? colorScheme.primary
                                : colorScheme.onSurface.withValues(alpha: 0.16),
                            width: color == selected ? 3 : 1,
                          ),
                        ),
                        child: color == selected
                            ? Icon(
                                Icons.check_rounded,
                                color: colorScheme.onPrimaryContainer,
                              )
                            : color == NoteColor.none
                            ? Icon(
                                Icons.block_rounded,
                                color: colorScheme.onSurfaceVariant,
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewCategoryPickerSheet extends StatelessWidget {
  const _PreviewCategoryPickerSheet({required this.selected});

  final NoteCategory selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Categoría y fondo',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 12,
              children: [
                for (final category in NoteCategory.values)
                  Tooltip(
                    message: NoteCategoryStyle.label(category),
                    child: InkWell(
                      key: ValueKey('preview-category-${category.name}'),
                      onTap: () => Navigator.pop(context, category),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: NoteCategoryStyle.baseColor(category),
                          image: NoteCategoryStyle.assetPath(category) == null
                              ? null
                              : DecorationImage(
                                  image: ResizeImage(
                                    AssetImage(
                                      NoteCategoryStyle.assetPath(category)!,
                                    ),
                                    width: _previewImageCacheWidth(
                                      context,
                                      58,
                                      maximum: 256,
                                    ),
                                  ),
                                  fit: BoxFit.cover,
                                  colorFilter: ColorFilter.mode(
                                    Colors.black.withValues(alpha: 0.2),
                                    BlendMode.darken,
                                  ),
                                ),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: category == selected
                                ? colorScheme.primary
                                : colorScheme.onSurface.withValues(alpha: 0.14),
                            width: category == selected ? 3 : 1,
                          ),
                        ),
                        child: Icon(
                          category == selected
                              ? Icons.check_rounded
                              : NoteCategoryStyle.icon(category),
                          color: NoteCategoryStyle.foregroundColor(category),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AssigneeSelection {
  const _AssigneeSelection({this.uid, this.customName});

  final String? uid;
  final String? customName;
}

class _PreviewAssigneePickerSheet extends StatelessWidget {
  const _PreviewAssigneePickerSheet({
    required this.selectedUid,
    required this.customName,
    required this.assignees,
  });

  final String? selectedUid;
  final String? customName;
  final List<ListCollaborator> assignees;

  Future<void> _pickCustomName(BuildContext context) async {
    var enteredName = customName ?? '';
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Responsable personalizado'),
        content: TextFormField(
          key: const ValueKey('custom-assignee-name-field'),
          initialValue: enteredName,
          autofocus: true,
          maxLength: 50,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nombre',
            hintText: 'Ej. Camila',
            helperText: 'No necesita tener una cuenta en NockNock.',
          ),
          onChanged: (value) => enteredName = value,
          onFieldSubmitted: (value) {
            final normalized = value.trim();
            if (normalized.isNotEmpty) {
              Navigator.pop(dialogContext, normalized);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('save-custom-assignee-button'),
            onPressed: () {
              final normalized = enteredName.trim();
              if (normalized.isNotEmpty) {
                Navigator.pop(dialogContext, normalized);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (!context.mounted || name == null) return;
    Navigator.pop(context, _AssigneeSelection(customName: name));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              'Asignar responsable',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          ListTile(
            key: const ValueKey('preview-assignee-unassigned'),
            leading: const CircleAvatar(child: Icon(Icons.person_off_outlined)),
            title: const Text('Sin responsable'),
            trailing: selectedUid == null && customName == null
                ? const Icon(Icons.check_rounded)
                : null,
            onTap: () => Navigator.pop(context, const _AssigneeSelection()),
          ),
          ListTile(
            key: const ValueKey('preview-assignee-custom'),
            leading: const CircleAvatar(
              child: Icon(Icons.manage_accounts_outlined),
            ),
            title: Text(
              customName?.trim().isNotEmpty == true
                  ? customName!.trim()
                  : 'Responsable personalizado',
            ),
            subtitle: const Text('Agrega a alguien aunque no use NockNock.'),
            trailing: customName?.trim().isNotEmpty == true
                ? const Icon(Icons.check_rounded)
                : null,
            onTap: () => _pickCustomName(context),
          ),
          if (assignees.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.group_add_outlined),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Aún no hay personas en esta lista. Invita colaboradores para poder asignarles la nota.',
                    ),
                  ),
                ],
              ),
            ),
          for (final person in assignees)
            ListTile(
              key: ValueKey('preview-assignee-${person.uid}'),
              leading: CircleAvatar(
                foregroundImage: person.photoUrl?.trim().isNotEmpty == true
                    ? NetworkImage(person.photoUrl!.trim())
                    : null,
                onForegroundImageError:
                    person.photoUrl?.trim().isNotEmpty == true
                    ? (_, _) {}
                    : null,
                child: Text(_collaboratorInitial(person)),
              ),
              title: Text(_collaboratorLabel(person)),
              subtitle: person.email.trim().isEmpty
                  ? null
                  : Text(person.email.trim()),
              trailing: selectedUid == person.uid
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () =>
                  Navigator.pop(context, _AssigneeSelection(uid: person.uid)),
            ),
        ],
      ),
    );
  }
}

class _PhotoAction {
  const _PhotoAction.add() : removeId = null;
  const _PhotoAction.remove(this.removeId);

  final String? removeId;
}

class _PhotoActionsSheet extends StatelessWidget {
  const _PhotoActionsSheet({required this.attachments});

  final List<NoteAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('Adjuntos · ${attachments.length}/2'),
              subtitle: const Text('Comprimidas para ocupar menos espacio'),
            ),
            if (attachments.length < noteAttachmentMaxCount)
              ListTile(
                key: const ValueKey('replace-note-attachment'),
                leading: const Icon(Icons.add_photo_alternate_outlined),
                title: const Text('Agregar otro adjunto'),
                onTap: () => Navigator.pop(context, const _PhotoAction.add()),
              ),
            for (final (index, attachment) in attachments.indexed)
              ListTile(
                key: index == 0
                    ? const ValueKey('remove-note-attachment')
                    : ValueKey('remove-note-attachment-${attachment.id}'),
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Quitar ${attachment.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () =>
                    Navigator.pop(context, _PhotoAction.remove(attachment.id)),
              ),
          ],
        ),
      ),
    );
  }
}

enum _PreviewReminderAction { change, remove }

class _PreviewReminderActionsSheet extends StatelessWidget {
  const _PreviewReminderActionsSheet({
    required this.reminderAt,
    required this.recurrence,
  });

  final DateTime reminderAt;
  final ReminderRecurrence? recurrence;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Recordatorio activo',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              recurrence == null
                  ? '${MaterialLocalizations.of(context).formatMediumDate(reminderAt)} · ${TimeOfDay.fromDateTime(reminderAt).format(context)}'
                  : reminderRecurrenceLabel(
                      recurrence!,
                      reminderAt,
                      includeTime: true,
                    ),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            ListTile(
              key: const ValueKey('preview-change-reminder'),
              leading: const Icon(Icons.edit_calendar_rounded),
              title: const Text('Cambiar fecha y hora'),
              onTap: () =>
                  Navigator.pop(context, _PreviewReminderAction.change),
            ),
            ListTile(
              key: const ValueKey('preview-remove-reminder'),
              leading: const Icon(Icons.notifications_off_outlined),
              title: const Text('Quitar recordatorio'),
              onTap: () =>
                  Navigator.pop(context, _PreviewReminderAction.remove),
            ),
          ],
        ),
      ),
    );
  }
}

String _collaboratorLabel(ListCollaborator person) {
  final displayName = person.displayName.trim();
  if (displayName.isNotEmpty) return displayName;
  final email = person.email.trim();
  return email.isEmpty ? 'Persona' : email;
}

String _collaboratorInitial(ListCollaborator person) =>
    _collaboratorLabel(person).characters.first.toUpperCase();

String _noteColorName(NoteColor color) => switch (color) {
  NoteColor.none => 'Sin color',
  NoteColor.yellow => 'Amarillo',
  NoteColor.pink => 'Rosa',
  NoteColor.blue => 'Azul',
  NoteColor.green => 'Verde',
  NoteColor.purple => 'Morado',
  NoteColor.orange => 'Naranja',
  NoteColor.mint => 'Menta',
  NoteColor.coral => 'Coral',
  NoteColor.gray => 'Gris',
  NoteColor.red => 'Rojo',
  NoteColor.teal => 'Turquesa',
  NoteColor.brown => 'Café',
};
