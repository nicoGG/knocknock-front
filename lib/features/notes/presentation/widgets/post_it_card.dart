import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nocknock/core/theme/app_theme.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/presentation/note_category_style.dart';
import 'package:nocknock/features/notes/presentation/note_hero.dart';
import 'package:nocknock/features/notes/presentation/note_palette.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_checklist.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_rich_text.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_reactions.dart';

enum PostItCardLayout { grid, compact, large }

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
                onTap: onOpen,
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
                      PostItCardLayout.grid ||
                      PostItCardLayout.large => _NoteBody(
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
                        : NoteReactionsSummary(
                            key: ValueKey(
                              'floating-reactions-${note.id}-$reactionFingerprint',
                            ),
                            note: note,
                            foregroundColor: foregroundColor,
                            maxVisible: 2,
                            floating: true,
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

class _LargeNotePeopleFooter extends StatelessWidget {
  const _LargeNotePeopleFooter({
    required this.note,
    required this.authorPhotoUrl,
    required this.assignee,
    required this.foregroundColor,
  });

  final Note note;
  final String? authorPhotoUrl;
  final ListCollaborator? assignee;
  final Color foregroundColor;

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
              _AssigneeIndicator(noteId: note.id, person: person),
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
      ],
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
  });

  final String noteId;
  final ListCollaborator person;
  final double dimension;

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
        child: SizedBox.square(
          key: ValueKey('assignee-$noteId'),
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
    );
  }
}

String _personLabel(ListCollaborator person) {
  final displayName = person.displayName.trim();
  if (displayName.isNotEmpty) return displayName;
  final email = person.email.trim();
  return email.isEmpty ? 'otra persona' : email;
}
