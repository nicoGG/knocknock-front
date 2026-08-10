import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:nocknock/core/input_formatters/initial_uppercase_text_formatter.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_checklist.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_rich_text.dart';

typedef NotePreviewCardBuilder =
    Widget Function(BuildContext context, VoidCallback openNote);
typedef NotePreviewNoteProvider = Note Function();
typedef NoteQuickSaveCallback =
    Future<void> Function(Note note, NoteDraft draft);

Future<bool> showNotePreviewDialog({
  required BuildContext context,
  required NotePreviewCardBuilder cardBuilder,
  required NotePreviewNoteProvider noteProvider,
  required NoteQuickSaveCallback onSave,
}) async {
  final disableAnimations = MediaQuery.disableAnimationsOf(context);
  final shouldOpen = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar vista previa de la nota',
    barrierColor: Colors.black.withValues(alpha: 0.48),
    transitionDuration: disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 360),
    pageBuilder: (dialogContext, _, _) => _NotePreviewDialog(
      cardBuilder: cardBuilder,
      noteProvider: noteProvider,
      onSave: onSave,
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      if (disableAnimations) return child;
      final entrance = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      );
      final fade = CurvedAnimation(
        parent: animation,
        curve: const Interval(0, 0.72, curve: Curves.easeOut),
        reverseCurve: Curves.easeIn,
      );
      return FadeTransition(
        key: const ValueKey('note-preview-fade-transition'),
        opacity: fade,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.055),
            end: Offset.zero,
          ).animate(entrance),
          child: ScaleTransition(
            key: const ValueKey('note-preview-scale-transition'),
            scale: Tween<double>(begin: 0.86, end: 1).animate(entrance),
            child: child,
          ),
        ),
      );
    },
  );
  return shouldOpen ?? false;
}

class _NotePreviewDialog extends StatefulWidget {
  const _NotePreviewDialog({
    required this.cardBuilder,
    required this.noteProvider,
    required this.onSave,
  });

  final NotePreviewCardBuilder cardBuilder;
  final NotePreviewNoteProvider noteProvider;
  final NoteQuickSaveCallback onSave;

  @override
  State<_NotePreviewDialog> createState() => _NotePreviewDialogState();
}

class _NotePreviewDialogState extends State<_NotePreviewDialog> {
  bool _isEditing = false;
  bool _isSaving = false;
  Note? _editingNote;
  int _editSession = 0;

  void _openNote() => Navigator.of(context).pop(true);

  void _startEditing() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _editingNote = widget.noteProvider();
      _editSession += 1;
      _isEditing = true;
    });
  }

  void _cancelEditing() {
    if (_isSaving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _editingNote = null;
      _isEditing = false;
    });
  }

  Future<void> _saveDraft(NoteDraft draft) async {
    final note = _editingNote;
    if (note == null || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      await widget.onSave(note, draft);
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        _editingNote = null;
        _isEditing = false;
      });
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pudimos guardar los cambios. Inténtalo otra vez.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

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
    final colorScheme = Theme.of(context).colorScheme;
    final duration = mediaQuery.disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 260);

    return Stack(
      fit: StackFit.expand,
      children: [
        BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: const ColoredBox(color: Colors.transparent),
        ),
        SafeArea(
          child: Center(
            child: Semantics(
              namesRoute: true,
              label: _isEditing
                  ? 'Edición rápida de la nota'
                  : 'Vista previa de la nota',
              child: Material(
                key: const ValueKey('note-preview-transparent-shell'),
                type: MaterialType.transparency,
                child: SizedBox(
                  key: const ValueKey('note-preview-dialog'),
                  width: dialogWidth,
                  height: dialogHeight,
                  child: Column(
                    children: [
                      _PreviewHeader(
                        isEditing: _isEditing,
                        isSaving: _isSaving,
                        onEdit: _startEditing,
                        onClose: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: duration,
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.025),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: _isEditing
                              ? _QuickNoteEditor(
                                  key: ValueKey(
                                    'quick-note-editor-$_editSession',
                                  ),
                                  note: _editingNote!,
                                  isSaving: _isSaving,
                                  onCancel: _cancelEditing,
                                  onSave: _saveDraft,
                                )
                              : RepaintBoundary(
                                  key: const ValueKey('note-preview-card'),
                                  child: widget.cardBuilder(context, _openNote),
                                ),
                        ),
                      ),
                      if (!_isEditing) ...[
                        const SizedBox(height: 12),
                        _OpenNoteButton(
                          colorScheme: colorScheme,
                          onPressed: _openNote,
                        ),
                      ],
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

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({
    required this.isEditing,
    required this.isSaving,
    required this.onEdit,
    required this.onClose,
  });

  final bool isEditing;
  final bool isSaving;
  final VoidCallback onEdit;
  final VoidCallback onClose;

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
                'Edición rápida',
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
          if (!isEditing) ...[
            IconButton(
              key: const ValueKey('quick-edit-note-button'),
              tooltip: 'Edición rápida',
              onPressed: onEdit,
              color: colorScheme.onPrimaryContainer,
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.primaryContainer,
                minimumSize: const Size(44, 44),
              ),
              icon: const Icon(Icons.edit_rounded, size: 21),
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            key: const ValueKey('close-note-preview-button'),
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

class _QuickNoteEditor extends StatefulWidget {
  const _QuickNoteEditor({
    required this.note,
    required this.isSaving,
    required this.onCancel,
    required this.onSave,
    super.key,
  });

  final Note note;
  final bool isSaving;
  final VoidCallback onCancel;
  final ValueChanged<NoteDraft> onSave;

  @override
  State<_QuickNoteEditor> createState() => _QuickNoteEditorState();
}

class _QuickNoteEditorState extends State<_QuickNoteEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late NoteRichContent _content;
  late List<NoteChecklistItem> _checklist;

  @override
  void initState() {
    super.initState();
    final note = widget.note;
    _titleController = TextEditingController(
      text: capitalizeInitialLetter(note.title),
    );
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
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Material(
          key: const ValueKey('quick-note-editor'),
          color: colorScheme.surface.withValues(alpha: 0.94),
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
                            TextFormField(
                              key: const ValueKey('quick-edit-title-field'),
                              controller: _titleController,
                              maxLength: 80,
                              textCapitalization: TextCapitalization.sentences,
                              inputFormatters: const [
                                InitialUppercaseTextFormatter(),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Título',
                                prefixIcon: Icon(Icons.title_rounded),
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Escribe un título para la nota'
                                  : null,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Contenido',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.72,
                                    ),
                                  ),
                            ),
                            const SizedBox(height: 8),
                            NoteRichTextEditor(
                              key: const ValueKey('quick-edit-content-field'),
                              editorKey: const ValueKey(
                                'quick-edit-content-editor',
                              ),
                              initialPlainText: _content.plainText,
                              initialDeltaJson: _content.deltaJson,
                              minEditorHeight: 88,
                              maxEditorHeight: 132,
                              onChanged: (content) => _content = content,
                            ),
                            const SizedBox(height: 18),
                            NoteChecklistEditor(
                              key: const ValueKey(
                                'quick-edit-checklist-editor',
                              ),
                              items: _checklist,
                              onChanged: (items) =>
                                  setState(() => _checklist = items),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          key: const ValueKey('cancel-quick-edit-button'),
                          onPressed: widget.onCancel,
                          style: TextButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          key: const ValueKey('save-quick-edit-button'),
                          onPressed: _submit,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          icon: widget.isSaving
                              ? SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colorScheme.onPrimary,
                                  ),
                                )
                              : const Icon(Icons.check_rounded),
                          label: Text(
                            widget.isSaving ? 'Guardando…' : 'Guardar cambios',
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
    );
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
        color: note.color,
        category: note.category,
        checklist: normalizeNoteChecklist(
          _checklist,
          trimText: true,
          removeEmpty: true,
        ),
        authorName: note.authorName,
        assigneeUid: note.assigneeUid,
        reminderAt: note.reminderAt,
      ),
    );
  }
}

class _OpenNoteButton extends StatelessWidget {
  const _OpenNoteButton({required this.colorScheme, required this.onPressed});

  final ColorScheme colorScheme;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            colorScheme.primaryContainer,
            Color.lerp(
              colorScheme.primaryContainer,
              colorScheme.secondaryContainer,
              0.52,
            )!,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.2),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          key: const ValueKey('open-note-from-preview-button'),
          onTap: onPressed,
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 54,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.open_in_full_rounded,
                  color: colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 10),
                Text(
                  'Abrir nota',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
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
