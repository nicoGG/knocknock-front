import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nocknock/core/input_formatters/initial_uppercase_text_formatter.dart';
import 'package:nocknock/core/theme/app_theme.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/presentation/note_category_style.dart';
import 'package:nocknock/features/notes/presentation/note_hero.dart';
import 'package:nocknock/features/notes/presentation/note_palette.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_checklist.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_rich_text.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_reactions.dart';
import 'package:uuid/uuid.dart';

enum PostItCardLayout { grid, compact, large }

enum PostItInlineEditTarget { none, title, description, checklist }

typedef PostItInlineSave = Future<bool> Function(NoteDraft draft);

class PostItCard extends StatelessWidget {
  const PostItCard({
    required this.note,
    required this.onToggle,
    required this.onPin,
    required this.onOpen,
    required this.onChecklistToggle,
    this.assignee,
    this.authorPhotoUrl,
    this.originListName,
    this.layout = PostItCardLayout.grid,
    this.currentUserId,
    this.reactionAuthorNames = const {},
    this.isSavingReaction = false,
    this.onToggleReaction,
    this.completedChecklistExpanded,
    this.onCompletedChecklistExpansionChanged,
    this.onAssigneeTap,
    this.inlineEditTarget,
    this.onInlineSave,
    super.key,
  });

  final Note note;
  final VoidCallback onToggle;
  final VoidCallback onPin;
  final VoidCallback onOpen;
  final ValueChanged<NoteChecklistItem> onChecklistToggle;
  final ListCollaborator? assignee;
  final String? authorPhotoUrl;
  final String? originListName;
  final PostItCardLayout layout;
  final String? currentUserId;
  final Map<String, String> reactionAuthorNames;
  final bool isSavingReaction;
  final Future<void> Function(String emoji)? onToggleReaction;
  final bool? completedChecklistExpanded;
  final ValueChanged<bool>? onCompletedChecklistExpansionChanged;
  final VoidCallback? onAssigneeTap;
  final ValueNotifier<PostItInlineEditTarget>? inlineEditTarget;
  final PostItInlineSave? onInlineSave;

  @override
  Widget build(BuildContext context) {
    final color = note.category == NoteCategory.general
        ? NotePalette.color(note.color)
        : NoteCategoryStyle.baseColor(note.category);
    final foregroundColor = NoteCategoryStyle.foregroundColor(note.category);
    final backgroundAsset = NoteCategoryStyle.assetPath(note.category);
    final cardColor = note.isCompleted
        ? Color.alphaBlend(AppTheme.ink.withValues(alpha: 0.08), color)
        : color;
    final completionDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 260);
    final reactionAnimationDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 380);
    final reactionFingerprint = note.reactions
        .map((reaction) => '${reaction.emoji}:${reaction.count}')
        .join('|');
    final borderRadius = switch (layout) {
      PostItCardLayout.grid => 10.0,
      PostItCardLayout.compact => 10.0,
      PostItCardLayout.large => 18.0,
    };
    final pinClearance = switch (layout) {
      PostItCardLayout.compact => 4.0,
      PostItCardLayout.grid => 10.0,
      PostItCardLayout.large => 16.0,
    };
    return _InteractivePostIt(
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(top: pinClearance),
              child: HeroMode(
                enabled: !MediaQuery.disableAnimationsOf(context),
                child: Hero(
                  tag: noteHeroTag(note.id, variant: layout.name),
                  transitionOnUserGestures: true,
                  createRectTween: (begin, end) =>
                      MaterialRectCenterArcTween(begin: begin, end: end),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: cardColor,
                      image: backgroundAsset == null
                          ? null
                          : DecorationImage(
                              image: AssetImage(backgroundAsset),
                              fit: BoxFit.cover,
                              colorFilter: ColorFilter.mode(
                                Colors.black.withValues(
                                  alpha: note.isCompleted ? 0.32 : 0.16,
                                ),
                                BlendMode.darken,
                              ),
                            ),
                      borderRadius: BorderRadius.circular(borderRadius),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.ink.withValues(alpha: 0.1),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: pinClearance),
            child: Material(
              key: ValueKey('note-surface-${note.id}'),
              color: cardColor,
              borderRadius: BorderRadius.circular(borderRadius),
              elevation: 0,
              child: InkWell(
                key: ValueKey('note-${note.id}'),
                enableFeedback: false,
                onTap: onInlineSave == null ? onOpen : null,
                borderRadius: BorderRadius.circular(borderRadius),
                child: Ink(
                  padding: switch (layout) {
                    PostItCardLayout.compact => const EdgeInsets.fromLTRB(
                      6,
                      4,
                      38,
                      4,
                    ),
                    PostItCardLayout.grid => const EdgeInsets.fromLTRB(
                      20,
                      14,
                      12,
                      12,
                    ),
                    PostItCardLayout.large => const EdgeInsets.fromLTRB(
                      20,
                      16,
                      12,
                      14,
                    ),
                  },
                  decoration: BoxDecoration(
                    color: cardColor,
                    image: backgroundAsset == null
                        ? null
                        : DecorationImage(
                            image: AssetImage(backgroundAsset),
                            fit: BoxFit.cover,
                            colorFilter: ColorFilter.mode(
                              Colors.black.withValues(
                                alpha: note.isCompleted ? 0.32 : 0.16,
                              ),
                              BlendMode.darken,
                            ),
                          ),
                    borderRadius: BorderRadius.circular(borderRadius),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.ink.withValues(alpha: 0.1),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: AnimatedOpacity(
                    opacity: note.isCompleted ? 0.82 : 1,
                    duration: completionDuration,
                    curve: Curves.easeOutCubic,
                    child: switch (layout) {
                      PostItCardLayout.compact => _CompactNoteBody(
                        note: note,
                        onToggle: onToggle,
                        assignee: assignee,
                        authorPhotoUrl: authorPhotoUrl,
                        originListName: originListName,
                        foregroundColor: foregroundColor,
                      ),
                      PostItCardLayout.grid || PostItCardLayout.large =>
                        layout == PostItCardLayout.large && onInlineSave != null
                            ? _EditableLargeNoteBody(
                                note: note,
                                onToggle: onToggle,
                                assignee: assignee,
                                authorPhotoUrl: authorPhotoUrl,
                                originListName: originListName,
                                foregroundColor: foregroundColor,
                                onChecklistToggle: onChecklistToggle,
                                currentUserId: currentUserId,
                                reactionAuthorNames: reactionAuthorNames,
                                isSavingReaction: isSavingReaction,
                                onToggleReaction: onToggleReaction,
                                onAssigneeTap: onAssigneeTap,
                                editTarget: inlineEditTarget,
                                onSave: onInlineSave!,
                              )
                            : _NoteBody(
                                note: note,
                                isGrid: layout == PostItCardLayout.grid,
                                onToggle: onToggle,
                                assignee: assignee,
                                authorPhotoUrl: authorPhotoUrl,
                                originListName: originListName,
                                contentMaxLines: 7,
                                foregroundColor: foregroundColor,
                                onChecklistToggle: onChecklistToggle,
                                currentUserId: currentUserId,
                                reactionAuthorNames: reactionAuthorNames,
                                isSavingReaction: isSavingReaction,
                                onToggleReaction: onToggleReaction,
                                completedChecklistExpanded:
                                    completedChecklistExpanded,
                                onCompletedChecklistExpansionChanged:
                                    onCompletedChecklistExpansionChanged,
                                onAssigneeTap: onAssigneeTap,
                              ),
                    },
                  ),
                ),
              ),
            ),
          ),
          if (layout == PostItCardLayout.grid)
            Positioned(
              top: -3,
              left: 10,
              right: 46,
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: AnimatedSwitcher(
                    duration: reactionAnimationDuration,
                    reverseDuration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 240),
                    layoutBuilder: (currentChild, previousChildren) => Stack(
                      alignment: Alignment.topLeft,
                      children: [...previousChildren, ?currentChild],
                    ),
                    transitionBuilder: (child, animation) =>
                        _FloatingReactionTransition(
                          animation: animation,
                          child: child,
                        ),
                    child: note.reactions.isEmpty
                        ? SizedBox.shrink(
                            key: ValueKey('no-reactions-${note.id}'),
                          )
                        : RepaintBoundary(
                            key: ValueKey(
                              'floating-reactions-${note.id}-$reactionFingerprint',
                            ),
                            child: NoteReactionsSummary(
                              note: note,
                              foregroundColor: foregroundColor,
                              maxVisible: 2,
                              floating: true,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: layout == PostItCardLayout.grid ? -5 : 0,
            right: 0,
            child: _FloatingPinButton(
              note: note,
              color: cardColor,
              foregroundColor: foregroundColor,
              onPressed: onPin,
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingReactionTransition extends StatelessWidget {
  const _FloatingReactionTransition({
    required this.animation,
    required this.child,
  });

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.32),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.7, end: 1).animate(curved),
          child: child,
        ),
      ),
    );
  }
}

class _InteractivePostIt extends StatefulWidget {
  const _InteractivePostIt({required this.child});

  final Widget child;

  @override
  State<_InteractivePostIt> createState() => _InteractivePostItState();
}

class _InteractivePostItState extends State<_InteractivePostIt> {
  bool _isHovered = false;
  bool _isPressed = false;

  void _setHovered(bool value) {
    if (!mounted) return;
    setState(() => _isHovered = value);
  }

  void _setPressed(bool value) {
    if (!mounted) return;
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final scale = _isPressed ? 0.985 : (_isHovered ? 1.015 : 1.0);
    final offset = _isPressed
        ? const Offset(0, 0.006)
        : (_isHovered ? const Offset(0, -0.018) : Offset.zero);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) {
        if (!mounted) return;
        setState(() {
          _isHovered = false;
          _isPressed = false;
        });
      },
      child: Listener(
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: AnimatedSlide(
          offset: offset,
          duration: duration,
          curve: Curves.easeOutCubic,
          child: AnimatedScale(
            scale: scale,
            duration: duration,
            curve: Curves.easeOutCubic,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _FloatingPinButton extends StatelessWidget {
  const _FloatingPinButton({
    required this.note,
    required this.color,
    required this.foregroundColor,
    required this.onPressed,
  });

  final Note note;
  final Color color;
  final Color foregroundColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tooltip = note.isPinned ? 'Desanclar nota' : 'Anclar arriba';
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: color,
          elevation: 3,
          shadowColor: AppTheme.ink.withValues(alpha: 0.28),
          shape: CircleBorder(
            side: BorderSide(color: foregroundColor.withValues(alpha: 0.2)),
          ),
          child: InkWell(
            key: ValueKey('pin-note-${note.id}'),
            enableFeedback: false,
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox.square(
              dimension: 30,
              child: AnimatedSwitcher(
                duration: duration,
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => RotationTransition(
                  turns: Tween(begin: -0.12, end: 0.0).animate(animation),
                  child: ScaleTransition(scale: animation, child: child),
                ),
                child: Icon(
                  note.isPinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  key: ValueKey(note.isPinned),
                  color: foregroundColor,
                  size: 17,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoteBody extends StatelessWidget {
  const _NoteBody({
    required this.note,
    required this.isGrid,
    required this.onToggle,
    required this.assignee,
    required this.authorPhotoUrl,
    required this.originListName,
    required this.contentMaxLines,
    required this.foregroundColor,
    required this.onChecklistToggle,
    required this.currentUserId,
    required this.reactionAuthorNames,
    required this.isSavingReaction,
    required this.onToggleReaction,
    required this.completedChecklistExpanded,
    required this.onCompletedChecklistExpansionChanged,
    required this.onAssigneeTap,
  });

  final Note note;
  final bool isGrid;
  final VoidCallback onToggle;
  final ListCollaborator? assignee;
  final String? authorPhotoUrl;
  final String? originListName;
  final int contentMaxLines;
  final Color foregroundColor;
  final ValueChanged<NoteChecklistItem> onChecklistToggle;
  final String? currentUserId;
  final Map<String, String> reactionAuthorNames;
  final bool isSavingReaction;
  final Future<void> Function(String emoji)? onToggleReaction;
  final bool? completedChecklistExpanded;
  final ValueChanged<bool>? onCompletedChecklistExpansionChanged;
  final VoidCallback? onAssigneeTap;

  @override
  Widget build(BuildContext context) {
    final hasBody = note.checklist.isNotEmpty || note.content.isNotEmpty;
    final showMetadata = !isGrid || hasBody;
    final showReactionControls = !isGrid && onToggleReaction != null;
    final visibleOriginListName = showMetadata ? originListName : null;
    final visibleReminder = showMetadata ? note.reminderAt : null;
    final titleRow = Row(
      children: [
        Expanded(
          child: Text(
            note.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w800,
              decoration: note.isCompleted ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        Checkbox(
          value: note.isCompleted,
          onChanged: (_) => onToggle(),
          activeColor: foregroundColor,
          checkColor: note.category == NoteCategory.general
              ? Colors.white
              : Colors.black87,
          side: BorderSide(color: foregroundColor, width: 1.5),
        ),
      ],
    );
    if (isGrid && !hasBody && assignee == null) {
      return titleRow;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        titleRow,
        if (visibleOriginListName case final listName?) ...[
          _OriginListBadge(
            noteId: note.id,
            listName: listName,
            foregroundColor: foregroundColor,
          ),
          SizedBox(height: contentMaxLines == 7 ? 7 : 5),
        ],
        if (showMetadata && note.category != NoteCategory.general) ...[
          if (isGrid) const SizedBox(height: 8),
          Container(
            key: ValueKey('note-category-${note.id}'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  NoteCategoryStyle.icon(note.category),
                  color: foregroundColor,
                  size: 14,
                ),
                const SizedBox(width: 5),
                Text(
                  NoteCategoryStyle.label(note.category),
                  style: TextStyle(
                    color: foregroundColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: isGrid ? 10 : 7),
        ] else if (showMetadata)
          SizedBox(height: isGrid ? 6 : 8),
        Expanded(
          child: note.checklist.isNotEmpty
              ? NoteChecklistPreview(
                  items: note.checklist,
                  foregroundColor: foregroundColor,
                  onToggle: onChecklistToggle,
                  maxItems: isGrid ? 10 : 6,
                  showOpenHint: isGrid,
                  completedExpanded: completedChecklistExpanded,
                  onCompletedExpansionChanged:
                      onCompletedChecklistExpansionChanged,
                )
              : note.content.isEmpty
              ? const SizedBox.shrink()
              : isGrid
              ? Text(
                  note.content,
                  maxLines: contentMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: foregroundColor.withValues(alpha: 0.9),
                  ),
                )
              : SingleChildScrollView(
                  child: NoteRichTextViewer(
                    key: ValueKey('preview-rich-content-${note.id}'),
                    plainText: note.content,
                    deltaJson: note.contentDelta,
                    foregroundColor: foregroundColor.withValues(alpha: 0.9),
                  ),
                ),
        ),
        if (visibleReminder case final reminder?) ...[
          Row(
            children: [
              Icon(
                Icons.notifications_none_rounded,
                size: 17,
                color: foregroundColor.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  DateFormat('dd MMM · HH:mm', 'es').format(reminder),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foregroundColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isGrid ? 4 : 8),
        ],
        if (showReactionControls) ...[
          NoteReactionsBar(
            note: note,
            currentUserId: currentUserId,
            reactionAuthorNames: reactionAuthorNames,
            isSaving: isSavingReaction,
            onToggle: onToggleReaction!,
          ),
          const SizedBox(height: 10),
        ] else if (!isGrid && note.reactions.isNotEmpty) ...[
          NoteReactionsSummary(note: note, foregroundColor: foregroundColor),
          SizedBox(height: isGrid ? 6 : 10),
        ],
        if (isGrid && hasBody && assignee != null) const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final showAuthor = constraints.maxWidth >= 220;
            if (isGrid) {
              if (assignee case final person?) {
                return _GridAssignee(
                  noteId: note.id,
                  person: person,
                  foregroundColor: foregroundColor,
                );
              }
              if (!hasBody) return const SizedBox.shrink();
            } else {
              return _LargeNotePeopleFooter(
                note: note,
                authorPhotoUrl: authorPhotoUrl,
                assignee: assignee,
                foregroundColor: foregroundColor,
                onAssigneeTap: onAssigneeTap,
              );
            }
            return Row(
              children: [
                if (showAuthor) ...[
                  _AuthorAvatar(
                    note: note,
                    photoUrl: authorPhotoUrl,
                    foregroundColor: foregroundColor,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      note.authorName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foregroundColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
                if (assignee case final person?) ...[
                  const SizedBox(width: 4),
                  _AssigneeIndicator(noteId: note.id, person: person),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _EditableLargeNoteBody extends StatefulWidget {
  const _EditableLargeNoteBody({
    required this.note,
    required this.onToggle,
    required this.assignee,
    required this.authorPhotoUrl,
    required this.originListName,
    required this.foregroundColor,
    required this.onChecklistToggle,
    required this.currentUserId,
    required this.reactionAuthorNames,
    required this.isSavingReaction,
    required this.onToggleReaction,
    required this.onAssigneeTap,
    required this.editTarget,
    required this.onSave,
  });

  final Note note;
  final VoidCallback onToggle;
  final ListCollaborator? assignee;
  final String? authorPhotoUrl;
  final String? originListName;
  final Color foregroundColor;
  final ValueChanged<NoteChecklistItem> onChecklistToggle;
  final String? currentUserId;
  final Map<String, String> reactionAuthorNames;
  final bool isSavingReaction;
  final Future<void> Function(String emoji)? onToggleReaction;
  final VoidCallback? onAssigneeTap;
  final ValueNotifier<PostItInlineEditTarget>? editTarget;
  final PostItInlineSave onSave;

  @override
  State<_EditableLargeNoteBody> createState() => _EditableLargeNoteBodyState();
}

class _EditableLargeNoteBodyState extends State<_EditableLargeNoteBody> {
  late final TextEditingController _titleController;
  late final FocusNode _titleFocusNode;
  late NoteRichContent _content;
  late List<NoteChecklistItem> _checklist;
  int _descriptionRevision = 0;
  bool _editingTitle = false;
  bool _editingDescription = false;
  bool _editingChecklist = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note.title);
    _titleFocusNode = FocusNode();
    _content = _richContentFromNote(widget.note);
    _checklist = [...widget.note.checklist];
    widget.editTarget?.addListener(_handleRequestedEdit);
  }

  @override
  void didUpdateWidget(covariant _EditableLargeNoteBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editTarget != widget.editTarget) {
      oldWidget.editTarget?.removeListener(_handleRequestedEdit);
      widget.editTarget?.addListener(_handleRequestedEdit);
    }
    if (!_editingTitle && _titleController.text != widget.note.title) {
      _titleController.text = widget.note.title;
    }
    if (!_editingDescription) _content = _richContentFromNote(widget.note);
    if (!_editingChecklist) _checklist = [...widget.note.checklist];
  }

  @override
  void dispose() {
    widget.editTarget?.removeListener(_handleRequestedEdit);
    _titleController.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  void _handleRequestedEdit() {
    final notifier = widget.editTarget;
    if (notifier == null || notifier.value == PostItInlineEditTarget.none) {
      return;
    }
    switch (notifier.value) {
      case PostItInlineEditTarget.none:
        break;
      case PostItInlineEditTarget.title:
        _beginTitleEditing();
        break;
      case PostItInlineEditTarget.description:
        _beginDescriptionEditing();
        break;
      case PostItInlineEditTarget.checklist:
        _beginChecklistEditing();
        break;
    }
    notifier.value = PostItInlineEditTarget.none;
  }

  void _beginTitleEditing() {
    if (_isSaving || _editingTitle) return;
    setState(() {
      _editingTitle = true;
      _editingDescription = false;
      _editingChecklist = false;
      _titleController.text = widget.note.title;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _titleFocusNode.requestFocus();
    });
  }

  void _beginDescriptionEditing() {
    if (_isSaving || _editingDescription) return;
    setState(() {
      _editingTitle = false;
      _editingDescription = true;
      _editingChecklist = false;
      _content = _richContentFromNote(widget.note);
      _descriptionRevision += 1;
    });
  }

  void _beginChecklistEditing() {
    if (_isSaving || _editingChecklist) return;
    final checklist = widget.note.checklist;
    setState(() {
      _editingTitle = false;
      _editingDescription = false;
      _editingChecklist = true;
      _checklist = checklist.isEmpty
          ? [NoteChecklistItem(id: const Uuid().v4(), text: '')]
          : [...checklist];
    });
  }

  void _cancelEditing() {
    if (_isSaving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _editingTitle = false;
      _editingDescription = false;
      _editingChecklist = false;
      _titleController.text = widget.note.title;
      _content = _richContentFromNote(widget.note);
      _checklist = [...widget.note.checklist];
    });
  }

  Future<void> _saveTitle() async {
    final title = capitalizeInitialLetter(_titleController.text.trim());
    if (title.isEmpty || _isSaving) return;
    setState(() => _isSaving = true);
    final saved = await widget.onSave(_draft(title: title));
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      if (saved) {
        _editingTitle = false;
        _titleController.text = title;
      }
    });
  }

  Future<void> _saveDescription() async {
    if (_isSaving) return;
    final content = normalizeNoteRichContent(_content);
    if (content.plainText.length > noteContentMaxLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El contenido puede tener hasta 500 caracteres.'),
        ),
      );
      return;
    }
    setState(() => _isSaving = true);
    final saved = await widget.onSave(_draft(content: content));
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      if (saved) {
        _editingDescription = false;
        _content = content;
      }
    });
  }

  void _clearDescription() {
    if (_isSaving) return;
    setState(() {
      _content = _emptyRichContent();
      _descriptionRevision += 1;
    });
  }

  Future<void> _saveChecklist() async {
    if (_isSaving) return;
    final checklist = normalizeNoteChecklist(
      _checklist,
      trimText: true,
      removeEmpty: true,
    );
    setState(() => _isSaving = true);
    final saved = await widget.onSave(_draft(checklist: checklist));
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      if (saved) {
        _editingChecklist = false;
        _checklist = checklist;
      }
    });
  }

  NoteDraft _draft({
    String? title,
    NoteRichContent? content,
    List<NoteChecklistItem>? checklist,
  }) {
    final note = widget.note;
    return NoteDraft(
      title: title ?? note.title,
      content: content?.plainText ?? note.content,
      contentDelta: content?.deltaJson ?? note.contentDelta,
      color: note.color,
      category: note.category,
      checklist: checklist ?? note.checklist,
      authorName: note.authorName,
      assigneeUid: note.assigneeUid,
      reminderAt: note.reminderAt,
    );
  }

  int _titleInputLineCount(
    BuildContext context,
    double maxWidth,
    TextStyle? style,
  ) {
    final text = _titleController.text.isEmpty
        ? 'Título'
        : _titleController.text;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final availableTextWidth = (maxWidth - 62)
        .clamp(1.0, double.infinity)
        .toDouble();
    return text.contains('\n') || painter.width > availableTextWidth ? 2 : 1;
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final foregroundColor = widget.foregroundColor;
    final fieldFill = foregroundColor.computeLuminance() > 0.5
        ? Colors.black.withValues(alpha: 0.16)
        : Colors.white.withValues(alpha: 0.3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _editingTitle
                  ? LayoutBuilder(
                      builder: (context, constraints) {
                        final titleStyle = Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(
                              color: foregroundColor,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            );
                        final lineCount = _titleInputLineCount(
                          context,
                          constraints.maxWidth,
                          titleStyle,
                        );
                        return TextField(
                          key: const ValueKey('quick-edit-title-field'),
                          controller: _titleController,
                          focusNode: _titleFocusNode,
                          enabled: !_isSaving,
                          maxLength: 80,
                          minLines: lineCount,
                          maxLines: lineCount,
                          textInputAction: TextInputAction.done,
                          textCapitalization: TextCapitalization.sentences,
                          inputFormatters: const [
                            InitialUppercaseTextFormatter(),
                          ],
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => _saveTitle(),
                          style: titleStyle,
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: fieldFill,
                            counterText: '',
                            hintText: 'Título',
                            contentPadding: const EdgeInsets.fromLTRB(
                              14,
                              8,
                              4,
                              8,
                            ),
                            suffixIconConstraints: const BoxConstraints(
                              minWidth: 44,
                              minHeight: 44,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            suffixIcon: IconButton(
                              key: const ValueKey('save-inline-title-button'),
                              tooltip: 'Guardar título',
                              onPressed: _isSaving ? null : _saveTitle,
                              icon: const Icon(Icons.check_rounded),
                            ),
                          ),
                        );
                      },
                    )
                  : Semantics(
                      button: true,
                      label: 'Editar título',
                      child: InkWell(
                        key: ValueKey('inline-title-hit-target-${note.id}'),
                        onTap: _beginTitleEditing,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            note.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: foregroundColor,
                                  fontWeight: FontWeight.w800,
                                  decoration: note.isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                          ),
                        ),
                      ),
                    ),
            ),
            Checkbox(
              value: note.isCompleted,
              onChanged: (_) => widget.onToggle(),
              activeColor: foregroundColor,
              checkColor: note.category == NoteCategory.general
                  ? Colors.white
                  : Colors.black87,
              side: BorderSide(color: foregroundColor, width: 1.5),
            ),
          ],
        ),
        if (widget.originListName != null ||
            note.category != NoteCategory.general) ...[
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (widget.originListName case final listName?)
                _OriginListBadge(
                  noteId: note.id,
                  listName: listName,
                  foregroundColor: foregroundColor,
                ),
              if (note.category != NoteCategory.general)
                Container(
                  key: ValueKey('note-category-${note.id}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        NoteCategoryStyle.icon(note.category),
                        color: foregroundColor,
                        size: 14,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        NoteCategoryStyle.label(note.category),
                        style: TextStyle(
                          color: foregroundColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Expanded(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_editingDescription) ...[
                  KeyedSubtree(
                    key: ValueKey(
                      'inline-description-revision-$_descriptionRevision',
                    ),
                    child: NoteRichTextEditor(
                      key: const ValueKey('quick-edit-content-field'),
                      editorKey: const ValueKey('quick-edit-content-editor'),
                      initialPlainText: _content.plainText,
                      initialDeltaJson: _content.deltaJson,
                      autoFocus: true,
                      minEditorHeight: 76,
                      maxEditorHeight: 132,
                      foregroundColor: foregroundColor,
                      backgroundColor: fieldFill,
                      onChanged: (content) => _content = content,
                    ),
                  ),
                  _InlineFieldActions(
                    keyPrefix: 'description',
                    isSaving: _isSaving,
                    onDelete: _clearDescription,
                    deleteColor: foregroundColor,
                    onCancel: _cancelEditing,
                    onSave: _saveDescription,
                  ),
                ] else
                  Semantics(
                    button: true,
                    label: note.content.trim().isEmpty
                        ? 'Agregar descripción'
                        : 'Editar descripción',
                    child: InkWell(
                      key: ValueKey('inline-description-hit-target-${note.id}'),
                      onTap: _beginDescriptionEditing,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 6,
                        ),
                        child: note.content.trim().isEmpty
                            ? Row(
                                children: [
                                  Icon(
                                    Icons.notes_rounded,
                                    size: 18,
                                    color: foregroundColor.withValues(
                                      alpha: 0.72,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Agregar descripción',
                                    style: TextStyle(
                                      color: foregroundColor.withValues(
                                        alpha: 0.72,
                                      ),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              )
                            : IgnorePointer(
                                child: NoteRichTextViewer(
                                  key: ValueKey(
                                    'preview-rich-content-${note.id}',
                                  ),
                                  plainText: note.content,
                                  deltaJson: note.contentDelta,
                                  foregroundColor: foregroundColor.withValues(
                                    alpha: 0.9,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                Divider(
                  key: ValueKey(
                    'inline-description-subtasks-divider-${note.id}',
                  ),
                  height: 26,
                  color: foregroundColor.withValues(alpha: 0.28),
                ),
                if (!_editingChecklist)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Subtareas',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: foregroundColor.withValues(alpha: 0.72),
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                      if (note.checklist.isNotEmpty)
                        IconButton(
                          key: const ValueKey('edit-inline-checklist-button'),
                          tooltip: 'Editar subtareas',
                          onPressed: _beginChecklistEditing,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.edit_rounded, size: 18),
                        ),
                    ],
                  )
                else
                  const SizedBox(height: 2),
                if (_editingChecklist) ...[
                  SimpleNoteChecklistEditor(
                    key: const ValueKey('quick-edit-checklist-editor'),
                    items: _checklist,
                    foregroundColor: foregroundColor,
                    onChanged: (items) => setState(() => _checklist = items),
                  ),
                  _InlineFieldActions(
                    keyPrefix: 'checklist',
                    isSaving: _isSaving,
                    onCancel: _cancelEditing,
                    onSave: _saveChecklist,
                  ),
                ] else ...[
                  if (note.checklist.isNotEmpty)
                    NoteChecklistPreview(
                      items: note.checklist,
                      foregroundColor: foregroundColor,
                      onToggle: widget.onChecklistToggle,
                      maxItems: 10,
                      showOpenHint: false,
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('add-inline-subtask-button'),
                      onPressed: _beginChecklistEditing,
                      style: TextButton.styleFrom(
                        foregroundColor: foregroundColor,
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(
                        note.checklist.isEmpty
                            ? 'Agregar subtarea'
                            : 'Agregar otra subtarea',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (note.reminderAt case final reminder?) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.notifications_none_rounded,
                size: 17,
                color: foregroundColor.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  DateFormat('dd MMM · HH:mm', 'es').format(reminder),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foregroundColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (widget.onToggleReaction != null) ...[
          NoteReactionsBar(
            note: note,
            currentUserId: widget.currentUserId,
            reactionAuthorNames: widget.reactionAuthorNames,
            isSaving: widget.isSavingReaction,
            onToggle: widget.onToggleReaction!,
          ),
          const SizedBox(height: 10),
        ] else if (note.reactions.isNotEmpty) ...[
          NoteReactionsSummary(note: note, foregroundColor: foregroundColor),
          const SizedBox(height: 10),
        ],
        _LargeNotePeopleFooter(
          note: note,
          authorPhotoUrl: widget.authorPhotoUrl,
          assignee: widget.assignee,
          foregroundColor: foregroundColor,
          onAssigneeTap: widget.onAssigneeTap,
        ),
      ],
    );
  }
}

class SimpleNoteChecklistEditor extends StatefulWidget {
  const SimpleNoteChecklistEditor({
    required this.items,
    required this.foregroundColor,
    required this.onChanged,
    super.key,
  });

  final List<NoteChecklistItem> items;
  final Color foregroundColor;
  final ValueChanged<List<NoteChecklistItem>> onChanged;

  @override
  State<SimpleNoteChecklistEditor> createState() =>
      _SimpleNoteChecklistEditorState();
}

class _SimpleNoteChecklistEditorState extends State<SimpleNoteChecklistEditor> {
  final Map<String, FocusNode> _focusNodes = {};

  @override
  void dispose() {
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.items.isNotEmpty)
          ReorderableListView.builder(
            key: const ValueKey('checklist-editor'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: widget.items.length,
            onReorderStart: (_) =>
                FocusManager.instance.primaryFocus?.unfocus(),
            onReorderItem: _reorder,
            proxyDecorator: (child, index, animation) => Material(
              color: Colors.transparent,
              child: FadeTransition(opacity: animation, child: child),
            ),
            itemBuilder: (context, index) {
              final item = widget.items[index];
              final focusNode = _focusNodes.putIfAbsent(item.id, FocusNode.new);
              return Padding(
                key: ValueKey('checklist-editor-${item.id}'),
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: index,
                      child: Tooltip(
                        message: 'Arrastrar subtarea',
                        child: SizedBox.square(
                          dimension: 34,
                          child: Icon(
                            Icons.drag_indicator_rounded,
                            color: widget.foregroundColor.withValues(
                              alpha: 0.58,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Checkbox(
                      value: item.isCompleted,
                      onChanged: (value) => _replace(
                        index,
                        item.copyWith(isCompleted: value ?? false),
                      ),
                      visualDensity: VisualDensity.compact,
                      activeColor: widget.foregroundColor,
                      checkColor: Colors.black87,
                      side: BorderSide(
                        color: widget.foregroundColor.withValues(alpha: 0.72),
                        width: 1.5,
                      ),
                    ),
                    Expanded(
                      child: TextFormField(
                        key: ValueKey('checklist-text-${item.id}'),
                        initialValue: item.text,
                        focusNode: focusNode,
                        autofocus:
                            widget.items.length == 1 && item.text.isEmpty,
                        maxLength: 120,
                        textCapitalization: TextCapitalization.sentences,
                        inputFormatters: const [
                          InitialUppercaseTextFormatter(),
                        ],
                        textInputAction: TextInputAction.next,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: widget.foregroundColor,
                          decoration: item.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Elemento de la lista',
                          hintStyle: TextStyle(
                            color: widget.foregroundColor.withValues(
                              alpha: 0.58,
                            ),
                          ),
                          counterText: '',
                          border: InputBorder.none,
                          filled: false,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 12,
                          ),
                        ),
                        onChanged: (text) => _replace(
                          index,
                          item.copyWith(text: capitalizeInitialLetter(text)),
                        ),
                        onFieldSubmitted: (text) {
                          if (text.trim().isNotEmpty) _addItem(index + 1);
                        },
                      ),
                    ),
                    IconButton(
                      key: ValueKey('delete-inline-checklist-${item.id}'),
                      tooltip: 'Eliminar subtarea',
                      onPressed: () => _remove(index),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.close_rounded,
                        color: widget.foregroundColor,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('add-checklist-item'),
            onPressed: () => _addItem(widget.items.length),
            style: TextButton.styleFrom(
              foregroundColor: widget.foregroundColor.withValues(alpha: 0.72),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Elemento de la lista'),
          ),
        ),
      ],
    );
  }

  void _replace(int index, NoteChecklistItem item) {
    final updated = [...widget.items]..[index] = item;
    widget.onChanged(updated);
  }

  void _remove(int index) {
    final updated = [...widget.items]..removeAt(index);
    widget.onChanged(updated);
  }

  void _addItem(int index) {
    final item = NoteChecklistItem(id: const Uuid().v4(), text: '');
    final focusNode = _focusNodes.putIfAbsent(item.id, FocusNode.new);
    final updated = [...widget.items]..insert(index, item);
    widget.onChanged(updated);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.items.any((entry) => entry.id == item.id)) return;
      focusNode.requestFocus();
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final updated = [...widget.items];
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    widget.onChanged(updated);
  }
}

class _InlineFieldActions extends StatelessWidget {
  const _InlineFieldActions({
    required this.keyPrefix,
    required this.isSaving,
    required this.onCancel,
    required this.onSave,
    this.onDelete,
    this.deleteColor,
  });

  final String keyPrefix;
  final bool isSaving;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final VoidCallback? onDelete;
  final Color? deleteColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          if (onDelete != null)
            IconButton(
              key: ValueKey('delete-inline-$keyPrefix-button'),
              tooltip: 'Borrar contenido',
              onPressed: isSaving ? null : onDelete,
              icon: Icon(Icons.close_rounded, color: deleteColor),
            ),
          const Spacer(),
          TextButton(
            key: ValueKey('cancel-inline-$keyPrefix-button'),
            onPressed: isSaving ? null : onCancel,
            child: const Text('Cancelar'),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            key: ValueKey('save-inline-$keyPrefix-button'),
            onPressed: isSaving ? null : onSave,
            icon: isSaving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

NoteRichContent _richContentFromNote(Note note) => normalizeNoteRichContent(
  NoteRichContent(
    plainText: note.content,
    deltaJson:
        note.contentDelta ??
        noteRichContentFromDocument(
          noteDocumentFromContent(plainText: note.content),
        ).deltaJson,
  ),
);

NoteRichContent _emptyRichContent() => normalizeNoteRichContent(
  NoteRichContent(
    plainText: '',
    deltaJson: noteRichContentFromDocument(
      noteDocumentFromContent(plainText: ''),
    ).deltaJson,
  ),
);

class _LargeNotePeopleFooter extends StatelessWidget {
  const _LargeNotePeopleFooter({
    required this.note,
    required this.authorPhotoUrl,
    required this.assignee,
    required this.foregroundColor,
    required this.onAssigneeTap,
  });

  final Note note;
  final String? authorPhotoUrl;
  final ListCollaborator? assignee;
  final Color foregroundColor;
  final VoidCallback? onAssigneeTap;

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      color: foregroundColor.withValues(alpha: 0.62),
      fontSize: 9.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Creado por',
                key: ValueKey('preview-created-by-${note.id}'),
                style: labelStyle,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _AuthorAvatar(
                    note: note,
                    photoUrl: authorPhotoUrl,
                    foregroundColor: foregroundColor,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      note.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foregroundColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (assignee case final person?) ...[
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Asignado a',
                key: ValueKey('preview-assigned-to-${note.id}'),
                style: labelStyle,
              ),
              const SizedBox(height: 4),
              _AssigneeIndicator(
                noteId: note.id,
                person: person,
                onTap: onAssigneeTap,
              ),
            ],
          ),
        ] else if (onAssigneeTap != null) ...[
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Responsable',
                key: ValueKey('preview-add-assignee-label-${note.id}'),
                style: labelStyle,
              ),
              const SizedBox(height: 4),
              _AddAssigneeIndicator(
                noteId: note.id,
                foregroundColor: foregroundColor,
                onTap: onAssigneeTap!,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _GridAssignee extends StatelessWidget {
  const _GridAssignee({
    required this.noteId,
    required this.person,
    required this.foregroundColor,
  });

  final String noteId;
  final ListCollaborator person;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: ValueKey('grid-assignee-$noteId'),
      children: [
        _AssigneeIndicator(noteId: noteId, person: person, dimension: 28),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            _firstName(person),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

String _firstName(ListCollaborator person) {
  final label = _personLabel(person).trim();
  if (label.isEmpty) return 'Persona';
  return label.split(RegExp(r'\s+')).first;
}

class _CompactNoteBody extends StatelessWidget {
  const _CompactNoteBody({
    required this.note,
    required this.onToggle,
    required this.assignee,
    required this.authorPhotoUrl,
    required this.originListName,
    required this.foregroundColor,
  });

  final Note note;
  final VoidCallback onToggle;
  final ListCollaborator? assignee;
  final String? authorPhotoUrl;
  final String? originListName;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(
          value: note.isCompleted,
          onChanged: (_) => onToggle(),
          activeColor: foregroundColor,
          checkColor: note.category == NoteCategory.general
              ? Colors.white
              : Colors.black87,
          side: BorderSide(color: foregroundColor, width: 1.5),
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 2),
        Expanded(
          child: Text(
            note.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w700,
              decoration: note.isCompleted ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        if (assignee case final person?) ...[
          const SizedBox(width: 8),
          _CompactAssigneeAvatar(noteId: note.id, person: person),
        ],
      ],
    );
  }
}

class _CompactAssigneeAvatar extends StatelessWidget {
  const _CompactAssigneeAvatar({required this.noteId, required this.person});

  final String noteId;
  final ListCollaborator person;

  @override
  Widget build(BuildContext context) {
    final personLabel = _personLabel(person);
    final label = 'Responsable: $personLabel';
    final photoUrl = person.photoUrl?.trim();
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    return Tooltip(
      message: label,
      child: Semantics(
        key: ValueKey('assignee-$noteId'),
        label: label,
        image: true,
        child: CircleAvatar(
          key: ValueKey('assignee-avatar-$noteId'),
          radius: 12,
          backgroundColor: AppTheme.ink.withValues(alpha: 0.14),
          foregroundColor: AppTheme.ink,
          foregroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
          onForegroundImageError: hasPhoto ? (_, _) {} : null,
          child: hasPhoto
              ? null
              : Text(
                  personLabel.characters.first.toUpperCase(),
                  style: const TextStyle(
                    color: AppTheme.ink,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
        ),
      ),
    );
  }
}

class _OriginListBadge extends StatelessWidget {
  const _OriginListBadge({
    required this.noteId,
    required this.listName,
    required this.foregroundColor,
  });

  final String noteId;
  final String listName;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('note-list-$noteId'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: foregroundColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_outlined, size: 13, color: foregroundColor),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              listName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foregroundColor,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({
    required this.note,
    required this.photoUrl,
    required this.foregroundColor,
  });

  final Note note;
  final String? photoUrl;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final normalizedPhotoUrl = photoUrl?.trim();
    final hasPhoto =
        normalizedPhotoUrl != null && normalizedPhotoUrl.isNotEmpty;
    return CircleAvatar(
      key: ValueKey('author-avatar-${note.id}'),
      radius: 12,
      backgroundColor: foregroundColor.withValues(alpha: 0.14),
      foregroundImage: hasPhoto ? NetworkImage(normalizedPhotoUrl) : null,
      onForegroundImageError: hasPhoto ? (_, _) {} : null,
      child: Text(
        note.authorName.characters.first.toUpperCase(),
        style: TextStyle(
          color: foregroundColor,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _AssigneeIndicator extends StatelessWidget {
  const _AssigneeIndicator({
    required this.noteId,
    required this.person,
    this.dimension = 34,
    this.onTap,
  });

  final String noteId;
  final ListCollaborator person;
  final double dimension;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final personLabel = _personLabel(person);
    final label = 'Responsable: $personLabel';
    final initial = personLabel.characters.first.toUpperCase();
    final photoUrl = person.photoUrl?.trim();
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        button: onTap != null,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            key: ValueKey('assignee-$noteId'),
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox.square(
              dimension: dimension,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    key: ValueKey('assignee-avatar-$noteId'),
                    radius: 16,
                    backgroundColor: AppTheme.ink.withValues(alpha: 0.14),
                    foregroundColor: AppTheme.ink,
                    foregroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
                    onForegroundImageError: hasPhoto ? (_, _) {} : null,
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: AppTheme.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(
                        color: AppTheme.ink,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.assignment_ind_rounded,
                        size: 9,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddAssigneeIndicator extends StatelessWidget {
  const _AddAssigneeIndicator({
    required this.noteId,
    required this.foregroundColor,
    required this.onTap,
  });

  final String noteId;
  final Color foregroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Agregar responsable',
      child: Semantics(
        button: true,
        label: 'Agregar responsable',
        child: Material(
          color: foregroundColor.withValues(alpha: 0.14),
          shape: CircleBorder(
            side: BorderSide(color: foregroundColor.withValues(alpha: 0.36)),
          ),
          child: InkWell(
            key: ValueKey('add-assignee-$noteId'),
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox.square(
              dimension: 34,
              child: Icon(
                Icons.person_add_alt_1_rounded,
                size: 18,
                color: foregroundColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _personLabel(ListCollaborator person) {
  final displayName = person.displayName.trim();
  if (displayName.isNotEmpty) return displayName;
  final email = person.email.trim();
  return email.isEmpty ? 'otra persona' : email;
}
