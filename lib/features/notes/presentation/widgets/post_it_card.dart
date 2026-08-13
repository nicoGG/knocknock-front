import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nocknock/core/input_formatters/initial_uppercase_text_formatter.dart';
import 'package:nocknock/core/input_formatters/money_text_input_formatter.dart';
import 'package:nocknock/core/theme/app_theme.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/presentation/note_category_style.dart';
import 'package:nocknock/features/notes/presentation/note_hero.dart';
import 'package:nocknock/features/notes/presentation/note_palette.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_checklist.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_link.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_rich_text.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_reactions.dart';
import 'package:uuid/uuid.dart';

enum PostItCardLayout { grid, compact, large }

enum PostItInlineEditTarget { none, title, description, checklist }

typedef PostItInlineSave = Future<bool> Function(NoteDraft draft);
typedef NoteAttachmentLoader =
    Future<NoteAttachment> Function(String attachmentId);

const noteMosaicLinkBlue = Color(0xFF64B5F6);
const noteMosaicLinkBlueOnLight = Color(0xFF1565C0);

TextStyle gridNoteDescriptionTextStyle(BuildContext context, {Color? color}) {
  final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
  return base.copyWith(color: color ?? base.color, fontSize: 14, height: 1.35);
}

Color gridNoteLinkColor(Color foregroundColor) =>
    foregroundColor.computeLuminance() > 0.5
    ? noteMosaicLinkBlue
    : noteMosaicLinkBlueOnLight;

double gridNotePhotoHeight(double cardWidth) =>
    (cardWidth * 0.72).clamp(112.0, 180.0).toDouble();

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
    this.compactSubtitle,
    this.compactReadOnly = false,
    this.compactOpenIndicator = false,
    this.showPin = true,
    this.enableHero = true,
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
    this.attachmentLoader,
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
  final String? compactSubtitle;
  final bool compactReadOnly;
  final bool compactOpenIndicator;
  final bool showPin;
  final bool enableHero;
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
  final NoteAttachmentLoader? attachmentLoader;

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
    final pinClearance = showPin
        ? switch (layout) {
            PostItCardLayout.compact => 4.0,
            PostItCardLayout.grid => 10.0,
            PostItCardLayout.large => 16.0,
          }
        : 0.0;
    final gridPhotos = layout == PostItCardLayout.grid
        ? note.photoAttachments
              .where((attachment) => attachment.isImage)
              .toList()
        : const <NoteAttachment>[];
    final body = switch (layout) {
      PostItCardLayout.compact => _CompactNoteBody(
        note: note,
        onToggle: onToggle,
        assignee: assignee,
        authorPhotoUrl: authorPhotoUrl,
        originListName: originListName,
        subtitle: compactSubtitle,
        readOnly: compactReadOnly,
        showOpenIndicator: compactOpenIndicator,
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
                attachmentLoader: attachmentLoader,
                editTarget: inlineEditTarget,
                onSave: onInlineSave!,
              )
            : _NoteBody(
                note: note,
                isGrid: layout == PostItCardLayout.grid,
                onOpen: onOpen,
                onToggle: onToggle,
                assignee: assignee,
                authorPhotoUrl: authorPhotoUrl,
                originListName: originListName,
                contentMaxLines: layout == PostItCardLayout.grid ? null : 7,
                foregroundColor: foregroundColor,
                onChecklistToggle: onChecklistToggle,
                currentUserId: currentUserId,
                reactionAuthorNames: reactionAuthorNames,
                isSavingReaction: isSavingReaction,
                onToggleReaction: onToggleReaction,
                completedChecklistExpanded: completedChecklistExpanded,
                onCompletedChecklistExpansionChanged:
                    onCompletedChecklistExpansionChanged,
                onAssigneeTap: onAssigneeTap,
                attachmentLoader: attachmentLoader,
              ),
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
                enabled: enableHero && !MediaQuery.disableAnimationsOf(context),
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
                    PostItCardLayout.compact => EdgeInsets.fromLTRB(
                      compactReadOnly ? 14 : 6,
                      4,
                      showPin ? 38 : 12,
                      4,
                    ),
                    PostItCardLayout.grid =>
                      gridPhotos.isEmpty
                          ? const EdgeInsets.fromLTRB(20, 14, 12, 12)
                          : EdgeInsets.zero,
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
                    child: gridPhotos.isEmpty
                        ? body
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _MosaicPhotoHeader(
                                noteId: note.id,
                                attachments: gridPhotos,
                                loader: attachmentLoader,
                                borderRadius: borderRadius,
                                foregroundColor: foregroundColor,
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    12,
                                    12,
                                    12,
                                  ),
                                  child: body,
                                ),
                              ),
                            ],
                          ),
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
          if (showPin)
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
    required this.onOpen,
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
    required this.attachmentLoader,
  });

  final Note note;
  final bool isGrid;
  final VoidCallback onOpen;
  final VoidCallback onToggle;
  final ListCollaborator? assignee;
  final String? authorPhotoUrl;
  final String? originListName;
  final int? contentMaxLines;
  final Color foregroundColor;
  final ValueChanged<NoteChecklistItem> onChecklistToggle;
  final String? currentUserId;
  final Map<String, String> reactionAuthorNames;
  final bool isSavingReaction;
  final Future<void> Function(String emoji)? onToggleReaction;
  final bool? completedChecklistExpanded;
  final ValueChanged<bool>? onCompletedChecklistExpansionChanged;
  final VoidCallback? onAssigneeTap;
  final NoteAttachmentLoader? attachmentLoader;

  @override
  Widget build(BuildContext context) {
    final hasBody = note.checklist.isNotEmpty || note.content.isNotEmpty;
    final hasGridPhoto =
        isGrid && note.photoAttachments.any((attachment) => attachment.isImage);
    final showGridColorIndicator =
        isGrid && NoteCategoryStyle.assetPath(note.category) != null;
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
        if (isGrid && !hasGridPhoto && note.photoAttachments.isNotEmpty)
          Tooltip(
            message: note.photoAttachments.length == 1
                ? 'Tiene una foto'
                : 'Tiene ${note.photoAttachments.length} fotos',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                Icons.attach_file_rounded,
                key: ValueKey('grid-attachment-${note.id}'),
                size: 19,
                color: foregroundColor.withValues(alpha: 0.86),
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
    if (isGrid && !hasBody && assignee == null && !showGridColorIndicator) {
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
          child: isGrid
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (note.content.isNotEmpty)
                      NoteLinkifiedText(
                        key: ValueKey('grid-description-${note.id}'),
                        plainText: note.content,
                        deltaJson: note.contentDelta,
                        style: gridNoteDescriptionTextStyle(
                          context,
                          color: foregroundColor.withValues(alpha: 0.9),
                        ),
                        linkColor: gridNoteLinkColor(foregroundColor),
                        maxLines: contentMaxLines,
                        overflow: contentMaxLines == null
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                      ),
                    if (note.content.isNotEmpty && note.checklist.isNotEmpty)
                      const SizedBox(height: 10),
                    if (note.checklist.isNotEmpty)
                      Expanded(
                        child: NoteChecklistPreview(
                          items: note.checklist,
                          foregroundColor: foregroundColor,
                          onToggle: onChecklistToggle,
                          maxItems: 10,
                          showOpenHint: true,
                          completedExpanded: completedChecklistExpanded,
                          onCompletedExpansionChanged:
                              onCompletedChecklistExpansionChanged,
                        ),
                      ),
                  ],
                )
              : note.checklist.isNotEmpty
              ? NoteChecklistPreview(
                  items: note.checklist,
                  foregroundColor: foregroundColor,
                  onToggle: onChecklistToggle,
                  maxItems: 6,
                  completedExpanded: completedChecklistExpanded,
                  onCompletedExpansionChanged:
                      onCompletedChecklistExpansionChanged,
                )
              : note.content.isEmpty
              ? const SizedBox.shrink()
              : SingleChildScrollView(
                  child: NoteRichTextViewer(
                    key: ValueKey('preview-rich-content-${note.id}'),
                    plainText: note.content,
                    deltaJson: note.contentDelta,
                    foregroundColor: foregroundColor.withValues(alpha: 0.9),
                    onTapOutsideLink: onOpen,
                  ),
                ),
        ),
        if (!isGrid && note.photoAttachments.isNotEmpty) ...[
          const SizedBox(height: 8),
          _NoteAttachmentsPreview(
            attachments: note.photoAttachments,
            foregroundColor: foregroundColor,
            loader: attachmentLoader,
          ),
        ],
        if (visibleReminder case final reminder?) ...[
          if (isGrid) const SizedBox(height: 8),
          Row(
            key: isGrid ? ValueKey('grid-reminder-${note.id}') : null,
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
              if (assignee != null || showGridColorIndicator) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (showGridColorIndicator)
                      _GridColorIndicator(
                        noteId: note.id,
                        color: NotePalette.color(note.color),
                      )
                    else
                      const SizedBox.shrink(),
                    if (assignee case final person?)
                      _GridAssignee(noteId: note.id, person: person),
                  ],
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

class _MosaicPhotoHeader extends StatefulWidget {
  const _MosaicPhotoHeader({
    required this.noteId,
    required this.attachments,
    required this.loader,
    required this.borderRadius,
    required this.foregroundColor,
  });

  final String noteId;
  final List<NoteAttachment> attachments;
  final NoteAttachmentLoader? loader;
  final double borderRadius;
  final Color foregroundColor;

  @override
  State<_MosaicPhotoHeader> createState() => _MosaicPhotoHeaderState();
}

class _MosaicPhotoHeaderState extends State<_MosaicPhotoHeader> {
  Future<NoteAttachment>? _loadedAttachment;

  NoteAttachment get _attachment => widget.attachments.first;

  @override
  void initState() {
    super.initState();
    _startLoading();
  }

  @override
  void didUpdateWidget(covariant _MosaicPhotoHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachments.first.id != widget.attachments.first.id ||
        oldWidget.attachments.first.dataBase64 !=
            widget.attachments.first.dataBase64) {
      _startLoading();
    }
  }

  void _startLoading() {
    _loadedAttachment = _attachment.dataBase64 != null
        ? Future.value(_attachment)
        : widget.loader?.call(_attachment.id);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SizedBox(
      height: gridNotePhotoHeight(constraints.maxWidth),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(widget.borderRadius),
        ),
        child: Semantics(
          button: true,
          image: true,
          label: widget.attachments.length == 1
              ? 'Ver foto de la nota en grande'
              : 'Ver ${widget.attachments.length} fotos de la nota en grande',
          child: GestureDetector(
            key: ValueKey('mosaic-photo-${widget.noteId}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _showPhotoViewer(
              context,
              attachments: widget.attachments,
              initialIndex: 0,
              loader: widget.loader,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: widget.foregroundColor.withValues(alpha: 0.1),
                  child: _MosaicPhotoContent(
                    attachment: _attachment,
                    future: _loadedAttachment,
                    foregroundColor: widget.foregroundColor,
                  ),
                ),
                if (widget.attachments.length > 1)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      key: ValueKey('mosaic-photo-count-${widget.noteId}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.68),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Text(
                        '+1',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
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

class _MosaicPhotoContent extends StatelessWidget {
  const _MosaicPhotoContent({
    required this.attachment,
    required this.future,
    required this.foregroundColor,
  });

  final NoteAttachment attachment;
  final Future<NoteAttachment>? future;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final loading = future;
    if (loading == null) {
      return _PhotoUnavailable(foregroundColor: foregroundColor);
    }
    return FutureBuilder<NoteAttachment>(
      future: loading,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: foregroundColor,
            ),
          );
        }
        final loaded = snapshot.data;
        if (loaded == null || loaded.dataBase64 == null) {
          return _PhotoUnavailable(foregroundColor: foregroundColor);
        }
        try {
          return Image.memory(
            base64Decode(loaded.dataBase64!),
            key: ValueKey('mosaic-photo-image-${attachment.id}'),
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) =>
                _PhotoUnavailable(foregroundColor: foregroundColor),
          );
        } on FormatException {
          return _PhotoUnavailable(foregroundColor: foregroundColor);
        }
      },
    );
  }
}

class _PhotoUnavailable extends StatelessWidget {
  const _PhotoUnavailable({required this.foregroundColor});

  final Color foregroundColor;

  @override
  Widget build(BuildContext context) => Center(
    child: Icon(
      Icons.broken_image_outlined,
      color: foregroundColor.withValues(alpha: 0.76),
      size: 32,
    ),
  );
}

Future<void> _showPhotoViewer(
  BuildContext context, {
  required List<NoteAttachment> attachments,
  required int initialIndex,
  required NoteAttachmentLoader? loader,
}) => Navigator.of(context, rootNavigator: true).push<void>(
  PageRouteBuilder<void>(
    opaque: true,
    barrierColor: Colors.black,
    pageBuilder: (_, _, _) => _FullscreenPhotoViewer(
      attachments: attachments,
      initialIndex: initialIndex,
      loader: loader,
    ),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.disableAnimationsOf(context)) return child;
      return FadeTransition(opacity: animation, child: child);
    },
  ),
);

class _FullscreenPhotoViewer extends StatefulWidget {
  const _FullscreenPhotoViewer({
    required this.attachments,
    required this.initialIndex,
    required this.loader,
  });

  final List<NoteAttachment> attachments;
  final int initialIndex;
  final NoteAttachmentLoader? loader;

  @override
  State<_FullscreenPhotoViewer> createState() => _FullscreenPhotoViewerState();
}

class _FullscreenPhotoViewerState extends State<_FullscreenPhotoViewer> {
  late final PageController _controller;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.attachments[_currentIndex];
    return Scaffold(
      key: const ValueKey('fullscreen-photo-viewer'),
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          key: const ValueKey('close-fullscreen-photo'),
          tooltip: 'Cerrar',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(
          current.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (widget.attachments.length > 1)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 18),
                child: Text(
                  '${_currentIndex + 1}/${widget.attachments.length}',
                  key: const ValueKey('fullscreen-photo-count'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.attachments.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) => _FullscreenPhoto(
          attachment: widget.attachments[index],
          loader: widget.loader,
        ),
      ),
    );
  }
}

class _FullscreenPhoto extends StatefulWidget {
  const _FullscreenPhoto({required this.attachment, required this.loader});

  final NoteAttachment attachment;
  final NoteAttachmentLoader? loader;

  @override
  State<_FullscreenPhoto> createState() => _FullscreenPhotoState();
}

class _FullscreenPhotoState extends State<_FullscreenPhoto> {
  Future<NoteAttachment>? _loadedAttachment;

  @override
  void initState() {
    super.initState();
    _startLoading();
  }

  void _startLoading() {
    _loadedAttachment = widget.attachment.dataBase64 != null
        ? Future.value(widget.attachment)
        : widget.loader?.call(widget.attachment.id);
  }

  @override
  Widget build(BuildContext context) {
    final future = _loadedAttachment;
    if (future == null) {
      return const _FullscreenPhotoError();
    }
    return FutureBuilder<NoteAttachment>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        final loaded = snapshot.data;
        if (loaded == null || loaded.dataBase64 == null) {
          return const _FullscreenPhotoError();
        }
        try {
          return InteractiveViewer(
            key: ValueKey('fullscreen-photo-${loaded.id}'),
            minScale: 0.8,
            maxScale: 5,
            child: Center(
              child: Image.memory(
                base64Decode(loaded.dataBase64!),
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const _FullscreenPhotoError(),
              ),
            ),
          );
        } on FormatException {
          return const _FullscreenPhotoError();
        }
      },
    );
  }
}

class _FullscreenPhotoError extends StatelessWidget {
  const _FullscreenPhotoError();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.broken_image_outlined, color: Colors.white70, size: 42),
        SizedBox(height: 10),
        Text(
          'No se pudo cargar la foto',
          style: TextStyle(color: Colors.white),
        ),
      ],
    ),
  );
}

class _NoteAttachmentsPreview extends StatelessWidget {
  const _NoteAttachmentsPreview({
    required this.attachments,
    required this.foregroundColor,
    required this.loader,
  });

  final List<NoteAttachment> attachments;
  final Color foregroundColor;
  final NoteAttachmentLoader? loader;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 88,
    child: Row(
      children: [
        for (final (index, attachment) in attachments.indexed) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: _NoteAttachmentPreview(
              attachment: attachment,
              attachments: attachments,
              foregroundColor: foregroundColor,
              loader: loader,
            ),
          ),
        ],
      ],
    ),
  );
}

class _NoteAttachmentPreview extends StatefulWidget {
  const _NoteAttachmentPreview({
    required this.attachment,
    required this.attachments,
    required this.foregroundColor,
    required this.loader,
  });

  final NoteAttachment attachment;
  final List<NoteAttachment> attachments;
  final Color foregroundColor;
  final NoteAttachmentLoader? loader;

  @override
  State<_NoteAttachmentPreview> createState() => _NoteAttachmentPreviewState();
}

class _NoteAttachmentPreviewState extends State<_NoteAttachmentPreview> {
  Future<NoteAttachment>? _loadedAttachment;

  @override
  void initState() {
    super.initState();
    _startLoading();
  }

  @override
  void didUpdateWidget(covariant _NoteAttachmentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.id != widget.attachment.id) {
      _startLoading();
    }
  }

  void _startLoading() {
    final attachment = widget.attachment;
    _loadedAttachment = !attachment.isImage
        ? null
        : attachment.dataBase64 != null
        ? Future.value(attachment)
        : widget.loader?.call(attachment.id);
  }

  @override
  Widget build(BuildContext context) {
    final foregroundColor = widget.foregroundColor;
    final future = _loadedAttachment;
    return Semantics(
      label: 'Adjunto ${widget.attachment.name}',
      image: widget.attachment.isImage,
      button: widget.attachment.isImage,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.attachment.isImage
            ? () {
                final photos = widget.attachments
                    .where((attachment) => attachment.isImage)
                    .toList(growable: false);
                _showPhotoViewer(
                  context,
                  attachments: photos,
                  initialIndex: photos.indexWhere(
                    (attachment) => attachment.id == widget.attachment.id,
                  ),
                  loader: widget.loader,
                );
              }
            : null,
        child: Container(
          key: ValueKey('attachment-preview-${widget.attachment.id}'),
          height: 82,
          decoration: BoxDecoration(
            color: foregroundColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: foregroundColor.withValues(alpha: 0.18)),
          ),
          clipBehavior: Clip.antiAlias,
          child: future == null
              ? _AttachmentFileTile(
                  attachment: widget.attachment,
                  foregroundColor: foregroundColor,
                )
              : FutureBuilder<NoteAttachment>(
                  future: future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return Center(
                        child: SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: foregroundColor,
                          ),
                        ),
                      );
                    }
                    final loaded = snapshot.data;
                    if (loaded == null || loaded.dataBase64 == null) {
                      return _AttachmentFileTile(
                        attachment: widget.attachment,
                        foregroundColor: foregroundColor,
                        unavailable: true,
                      );
                    }
                    if (!loaded.isImage) {
                      return _AttachmentFileTile(
                        attachment: loaded,
                        foregroundColor: foregroundColor,
                      );
                    }
                    try {
                      return Image.memory(
                        base64Decode(loaded.dataBase64!),
                        key: ValueKey('attachment-image-${loaded.id}'),
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => Icon(
                          Icons.broken_image_outlined,
                          color: foregroundColor,
                        ),
                      );
                    } on FormatException {
                      return _AttachmentFileTile(
                        attachment: loaded,
                        foregroundColor: foregroundColor,
                        unavailable: true,
                      );
                    }
                  },
                ),
        ),
      ),
    );
  }
}

class _AttachmentFileTile extends StatelessWidget {
  const _AttachmentFileTile({
    required this.attachment,
    required this.foregroundColor,
    this.unavailable = false,
  });

  final NoteAttachment attachment;
  final Color foregroundColor;
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final kilobytes = (attachment.sizeBytes / 1024).ceil();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(
            attachment.isPdf
                ? Icons.picture_as_pdf_outlined
                : Icons.image_outlined,
            color: foregroundColor,
            size: 26,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foregroundColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  unavailable
                      ? 'No disponible sin conexión'
                      : '${attachment.isPdf ? 'PDF' : 'Imagen'} · $kilobytes KB',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foregroundColor.withValues(alpha: 0.72),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
    required this.attachmentLoader,
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
  final NoteAttachmentLoader? attachmentLoader;
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

  Future<void> _editDescriptionLink(String url) async {
    if (_isSaving || _editingDescription) return;
    final note = widget.note;
    final match = noteRichLinkMatchForUrl(
      plainText: note.content,
      deltaJson: note.contentDelta,
      url: url,
    );
    if (match == null) {
      _beginDescriptionEditing();
      return;
    }
    final result = await showNoteLinkDialog(
      context,
      initialLabel: match.label,
      initialUrl: match.url,
      canRemoveLink: true,
    );
    if (!mounted || result == null) return;
    final content = applyNoteRichLinkEdit(
      plainText: note.content,
      deltaJson: note.contentDelta,
      match: match,
      result: result,
    );
    setState(() => _isSaving = true);
    final saved = await widget.onSave(_draft(content: content));
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      if (saved) _content = content;
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
      customAssigneeName: note.customAssigneeName,
      attachments: note.photoAttachments,
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
                          keyboardType: note.category == NoteCategory.money
                              ? TextInputType.number
                              : TextInputType.text,
                          inputFormatters: note.category == NoteCategory.money
                              ? [MoneyTextInputFormatter()]
                              : const [InitialUppercaseTextFormatter()],
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => _saveTitle(),
                          style: titleStyle,
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: fieldFill,
                            counterText: '',
                            hintText: note.category == NoteCategory.money
                                ? r'$0'
                                : 'Título',
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
                            : NoteRichTextViewer(
                                key: ValueKey(
                                  'preview-rich-content-${note.id}',
                                ),
                                plainText: note.content,
                                deltaJson: note.contentDelta,
                                foregroundColor: foregroundColor.withValues(
                                  alpha: 0.9,
                                ),
                                onEditLink: _editDescriptionLink,
                                onTapOutsideLink: _beginDescriptionEditing,
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
        if (note.photoAttachments.isNotEmpty) ...[
          const SizedBox(height: 8),
          _NoteAttachmentsPreview(
            attachments: note.photoAttachments,
            foregroundColor: foregroundColor,
            loader: widget.attachmentLoader,
          ),
        ],
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
  final Map<String, TextEditingController> _textControllers = {};
  final Map<String, String> _linkUrls = {};

  @override
  void didUpdateWidget(covariant SimpleNoteChecklistEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final activeIds = widget.items.map((item) => item.id).toSet();
    for (final item in widget.items) {
      final controller = _textControllers[item.id];
      final link = noteChecklistLinkFromText(item.text);
      if (link != null) {
        _linkUrls[item.id] = link.url;
      } else if (item.text.isNotEmpty) {
        _linkUrls.remove(item.id);
      }
      final displayText = noteChecklistDisplayText(item.text);
      if (controller != null && controller.text != displayText) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              _textControllers[item.id] != controller ||
              controller.text == displayText) {
            return;
          }
          controller.value = TextEditingValue(
            text: displayText,
            selection: TextSelection.collapsed(offset: displayText.length),
          );
        });
      }
    }
    for (final id in _textControllers.keys.toList()) {
      if (!activeIds.contains(id)) _textControllers.remove(id)?.dispose();
    }
    for (final id in _focusNodes.keys.toList()) {
      if (!activeIds.contains(id)) _focusNodes.remove(id)?.dispose();
    }
    _linkUrls.removeWhere((id, _) => !activeIds.contains(id));
  }

  @override
  void dispose() {
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    for (final controller in _textControllers.values) {
      controller.dispose();
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
              final controller = _textControllers.putIfAbsent(
                item.id,
                () => TextEditingController(
                  text: noteChecklistDisplayText(item.text),
                ),
              );
              final parsedLink = noteChecklistLinkFromText(item.text);
              if (parsedLink != null) _linkUrls[item.id] = parsedLink.url;
              final itemLinkUrl = _linkUrls[item.id];
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
                        controller: controller,
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
                        onChanged: (text) =>
                            _updateLabel(index, item, text, itemLinkUrl),
                        onFieldSubmitted: (text) {
                          if (text.trim().isNotEmpty) _addItem(index + 1);
                        },
                      ),
                    ),
                    IconButton(
                      key: ValueKey('edit-inline-checklist-link-${item.id}'),
                      tooltip: itemLinkUrl == null
                          ? 'Convertir en vínculo'
                          : 'Editar vínculo',
                      onPressed: () => _editLink(index, item, controller),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        itemLinkUrl == null
                            ? Icons.link_rounded
                            : Icons.link_off_rounded,
                        color: itemLinkUrl == null
                            ? widget.foregroundColor.withValues(alpha: 0.72)
                            : widget.foregroundColor,
                        size: 21,
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

  void _updateLabel(
    int index,
    NoteChecklistItem item,
    String text,
    String? linkUrl,
  ) {
    final label = capitalizeInitialLetter(text);
    final storedText = linkUrl == null || label.trim().isEmpty
        ? label
        : noteChecklistStoredLink(NoteLinkValue(label: label, url: linkUrl));
    _replace(index, item.copyWith(text: storedText));
  }

  Future<void> _editLink(
    int index,
    NoteChecklistItem item,
    TextEditingController controller,
  ) async {
    final currentUrl = _linkUrls[item.id];
    final currentText = currentUrl == null
        ? controller.text
        : noteChecklistStoredLink(
            NoteLinkValue(label: controller.text, url: currentUrl),
          );
    final result = await showNoteChecklistLinkDialog(
      context,
      currentText: currentText,
    );
    if (!mounted || result == null) return;
    if (result.removeLink) {
      _linkUrls.remove(item.id);
      _replace(index, item.copyWith(text: controller.text));
      return;
    }
    final link = result.value!;
    _linkUrls[item.id] = link.url;
    controller.value = TextEditingValue(
      text: link.label,
      selection: TextSelection.collapsed(offset: link.label.length),
    );
    _replace(index, item.copyWith(text: noteChecklistStoredLink(link)));
  }

  void _remove(int index) {
    final updated = [...widget.items]..removeAt(index);
    widget.onChanged(updated);
  }

  void _addItem(int index) {
    final item = NoteChecklistItem(id: const Uuid().v4(), text: '');
    final focusNode = _focusNodes.putIfAbsent(item.id, FocusNode.new);
    _textControllers.putIfAbsent(item.id, TextEditingController.new);
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

String _formatSpanishTimestamp(DateTime value) {
  const months = <String>[
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sept',
    'oct',
    'nov',
    'dic',
  ];
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day ${months[local.month - 1]} ${local.year} $hour:$minute';
}

String formatRelativeNoteEdit(DateTime value, {DateTime? relativeTo}) {
  final now = relativeTo ?? DateTime.now();
  final elapsed = now.difference(value.toLocal());
  if (elapsed.isNegative || elapsed.inMinutes < 1) return 'hace un momento';

  final minutes = elapsed.inMinutes;
  if (minutes < 60) {
    return 'hace $minutes ${minutes == 1 ? 'minuto' : 'minutos'}';
  }

  final hours = elapsed.inHours;
  if (hours < 24) return 'hace $hours ${hours == 1 ? 'hora' : 'horas'}';

  final days = elapsed.inDays;
  if (days < 30) return 'hace $days ${days == 1 ? 'día' : 'días'}';

  final months = days ~/ 30;
  return 'hace $months ${months == 1 ? 'mes' : 'meses'}';
}

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
    final timestampStyle = TextStyle(
      color: foregroundColor.withValues(alpha: 0.42),
      fontSize: 8,
      fontStyle: FontStyle.italic,
      letterSpacing: 0.1,
    );
    final createdAt = _formatSpanishTimestamp(note.createdAt);
    final updatedAt = formatRelativeNoteEdit(note.updatedAt);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
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
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                'Creación $createdAt',
                key: ValueKey('preview-created-at-${note.id}'),
                style: timestampStyle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Última edición $updatedAt',
                key: ValueKey('preview-updated-at-${note.id}'),
                textAlign: TextAlign.right,
                style: timestampStyle,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GridColorIndicator extends StatelessWidget {
  const _GridColorIndicator({required this.noteId, required this.color});

  final String noteId;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Color de la nota',
    image: true,
    child: Container(
      key: ValueKey('grid-color-indicator-$noteId'),
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.58)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.ink.withValues(alpha: 0.18),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    ),
  );
}

class _GridAssignee extends StatelessWidget {
  const _GridAssignee({required this.noteId, required this.person});

  final String noteId;
  final ListCollaborator person;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox.square(
        key: ValueKey('grid-assignee-$noteId'),
        dimension: 28,
        child: _AssigneeIndicator(
          noteId: noteId,
          person: person,
          dimension: 28,
        ),
      ),
    );
  }
}

class _CompactNoteBody extends StatelessWidget {
  const _CompactNoteBody({
    required this.note,
    required this.onToggle,
    required this.assignee,
    required this.authorPhotoUrl,
    required this.originListName,
    required this.subtitle,
    required this.readOnly,
    required this.showOpenIndicator,
    required this.foregroundColor,
  });

  final Note note;
  final VoidCallback onToggle;
  final ListCollaborator? assignee;
  final String? authorPhotoUrl;
  final String? originListName;
  final String? subtitle;
  final bool readOnly;
  final bool showOpenIndicator;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (readOnly)
          Semantics(
            label: note.isCompleted ? 'Nota completada' : 'Nota pendiente',
            image: true,
            child: Container(
              key: ValueKey('compact-note-status-${note.id}'),
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: foregroundColor.withValues(alpha: 0.14),
                shape: BoxShape.circle,
                border: Border.all(
                  color: foregroundColor.withValues(alpha: 0.18),
                ),
              ),
              child: Icon(
                note.isCompleted
                    ? Icons.check_rounded
                    : Icons.sticky_note_2_outlined,
                color: foregroundColor,
                size: 20,
              ),
            ),
          )
        else
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
        SizedBox(width: readOnly ? 10 : 2),
        Expanded(
          child: subtitle == null
              ? Text(
                  note.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: foregroundColor,
                    fontWeight: FontWeight.w700,
                    decoration: note.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            note.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: foregroundColor,
                                  fontWeight: FontWeight.w800,
                                  decoration: note.isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                          ),
                        ),
                        if (readOnly) ...[
                          const SizedBox(width: 8),
                          Container(
                            key: ValueKey('compact-note-category-${note.id}'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: foregroundColor.withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: foregroundColor.withValues(alpha: 0.16),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  NoteCategoryStyle.icon(note.category),
                                  color: foregroundColor,
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  NoteCategoryStyle.label(note.category),
                                  style: TextStyle(
                                    color: foregroundColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: foregroundColor.withValues(alpha: 0.78),
                        height: 1.18,
                      ),
                    ),
                  ],
                ),
        ),
        if (assignee case final person?) ...[
          const SizedBox(width: 8),
          _CompactAssigneeAvatar(noteId: note.id, person: person),
        ],
        if (showOpenIndicator) ...[
          const SizedBox(width: 8),
          Icon(
            Icons.chevron_right_rounded,
            key: ValueKey('compact-open-indicator-${note.id}'),
            color: foregroundColor.withValues(alpha: 0.72),
          ),
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
