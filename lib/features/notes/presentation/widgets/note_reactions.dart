import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nocknock/features/notes/domain/note.dart';

class NoteReactionsBar extends StatelessWidget {
  const NoteReactionsBar({
    required this.note,
    required this.isSaving,
    required this.onToggle,
    this.currentUserId,
    this.reactionAuthorNames = const {},
    super.key,
  });

  final Note note;
  final String? currentUserId;
  final Map<String, String> reactionAuthorNames;
  final bool isSaving;
  final Future<void> Function(String emoji) onToggle;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final duration = disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 360);
    final fingerprint = note.reactions
        .map(
          (reaction) =>
              '${reaction.emoji}:${reaction.count}:${reaction.isSelectedBy(currentUserId)}',
        )
        .join('|');
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: AnimatedSwitcher(
        duration: duration,
        reverseDuration: disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 240),
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: Alignment.topLeft,
          children: [...previousChildren, ?currentChild],
        ),
        transitionBuilder: (child, animation) =>
            _ReactionSetTransition(animation: animation, child: child),
        child: KeyedSubtree(
          key: ValueKey('note-reactions-set-$fingerprint'),
          child: Wrap(
            key: const ValueKey('note-reactions-bar'),
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final reaction in note.reactions)
                _ReactionChip(
                  noteId: note.id,
                  reaction: reaction,
                  authorNames: _authorNamesFor(reaction),
                  selected: reaction.isSelectedBy(currentUserId),
                  enabled: !isSaving,
                  onPressed: () => onToggle(reaction.emoji),
                ),
              IconButton(
                key: const ValueKey('add-note-reaction-button'),
                tooltip: 'Elegir una reacción',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 40,
                  height: 40,
                ),
                padding: EdgeInsets.zero,
                onPressed: isSaving ? null : () => _showPicker(context),
                icon: const Icon(Icons.add_reaction_outlined, size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _authorNamesFor(NoteReaction reaction) {
    final names = reaction.userUids
        .map((userUid) => reactionAuthorNames[userUid] ?? 'Colaborador')
        .toSet()
        .toList();
    names.sort((first, second) {
      if (first == 'Tú') return -1;
      if (second == 'Tú') return 1;
      return first.toLowerCase().compareTo(second.toLowerCase());
    });
    return names;
  }

  Future<void> _showPicker(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reaccionar a la nota',
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Toca un emoji para agregarlo o quitar tu reacción.',
                style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final emoji in supportedNoteReactionEmojis)
                    _EmojiOption(
                      emoji: emoji,
                      selected: note.reactions.any(
                        (reaction) =>
                            reaction.emoji == emoji &&
                            reaction.isSelectedBy(currentUserId),
                      ),
                      onPressed: () => Navigator.pop(sheetContext, emoji),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && context.mounted) await onToggle(selected);
  }
}

class NoteReactionsSummary extends StatelessWidget {
  const NoteReactionsSummary({
    required this.note,
    required this.foregroundColor,
    this.maxVisible = 4,
    this.floating = false,
    super.key,
  }) : assert(maxVisible > 0);

  final Note note;
  final Color foregroundColor;
  final int maxVisible;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    if (note.reactions.isEmpty) return const SizedBox.shrink();
    final visible = note.reactions.take(maxVisible).toList();
    final hidden = note.reactions.length - visible.length;
    final reactionCounts = <Widget>[
      for (final reaction in visible)
        _ReactionCount(
          emoji: reaction.emoji,
          count: reaction.count,
          foregroundColor: foregroundColor,
          floating: floating,
          motionId:
              '${floating ? 'floating' : 'summary'}-${note.id}-${reaction.emoji}',
        ),
      if (hidden > 0)
        _ReactionCount(
          emoji: '+$hidden',
          count: 0,
          foregroundColor: foregroundColor,
          floating: floating,
          motionId: null,
        ),
    ];
    if (floating) {
      // Grid cards already animate as a whole. Keeping these badges static
      // avoids starting an extra ticker for every visible emoji on home load.
      return Row(
        key: ValueKey('note-reactions-summary-${note.id}'),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < reactionCounts.length; index++) ...[
            if (index > 0) const SizedBox(width: 2),
            reactionCounts[index],
          ],
        ],
      );
    }
    return Wrap(
      key: ValueKey('note-reactions-summary-${note.id}'),
      spacing: 5,
      runSpacing: 5,
      children: reactionCounts,
    );
  }
}

class _ReactionSetTransition extends StatelessWidget {
  const _ReactionSetTransition({required this.animation, required this.child});

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
          begin: const Offset(0, 0.22),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.82, end: 1).animate(curved),
          child: child,
        ),
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.noteId,
    required this.reaction,
    required this.authorNames,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final String noteId;
  final NoteReaction reaction;
  final List<String> authorNames;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = reaction.count == 1
        ? '1 reacción ${reaction.emoji}'
        : '${reaction.count} reacciones ${reaction.emoji}';
    final authors = _formatAuthorNames(authorNames);
    final tooltipMessage = '${reaction.emoji}  $authors';
    return Semantics(
      button: true,
      selected: selected,
      label: '$label. $authors',
      hint: 'Mantén presionado para ver quién reaccionó',
      child: Tooltip(
        key: ValueKey('reaction-authors-tooltip-$noteId-${reaction.emoji}'),
        message: tooltipMessage,
        triggerMode: TooltipTriggerMode.longPress,
        waitDuration: const Duration(milliseconds: 350),
        showDuration: const Duration(seconds: 3),
        preferBelow: false,
        verticalOffset: 18,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        margin: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.72),
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.18),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        excludeFromSemantics: true,
        child: ActionChip(
          key: ValueKey('note-reaction-$noteId-${reaction.emoji}'),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AnimatedEmojiGlyph(
                key: ValueKey(
                  'reaction-emoji-motion-$noteId-${reaction.emoji}-${reaction.count}-$selected',
                ),
                id: 'chip-$noteId-${reaction.emoji}',
                emoji: reaction.emoji,
                fontSize: 17,
                enabled: !MediaQuery.disableAnimationsOf(context),
              ),
              const SizedBox(width: 6),
              Text('${reaction.count}'),
            ],
          ),
          backgroundColor: selected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          side: BorderSide(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.72)
                : colorScheme.outlineVariant,
          ),
          labelStyle: TextStyle(
            color: selected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
          onPressed: enabled ? onPressed : null,
        ),
      ),
    );
  }

  String _formatAuthorNames(List<String> names) {
    if (names.isEmpty) return 'Colaborador';
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names.first} y ${names.last}';
    if (names.length == 3) {
      return '${names[0]}, ${names[1]} y ${names[2]}';
    }
    return '${names[0]}, ${names[1]} y ${names.length - 2} más';
  }
}

class _EmojiOption extends StatelessWidget {
  const _EmojiOption({
    required this.emoji,
    required this.selected,
    required this.onPressed,
  });

  final String emoji;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Reacción $emoji',
      child: Material(
        color: selected
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        shape: CircleBorder(
          side: BorderSide(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          ),
        ),
        child: InkWell(
          key: ValueKey('reaction-option-$emoji'),
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 54,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _AnimatedEmojiGlyph(
                  key: ValueKey('picker-emoji-motion-$emoji'),
                  id: 'picker-$emoji',
                  emoji: emoji,
                  fontSize: 27,
                  enabled: !MediaQuery.disableAnimationsOf(context),
                ),
                if (selected)
                  Positioned(
                    right: 3,
                    bottom: 3,
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: colorScheme.primary,
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

class _ReactionCount extends StatelessWidget {
  const _ReactionCount({
    required this.emoji,
    required this.count,
    required this.foregroundColor,
    required this.floating,
    required this.motionId,
  });

  final String emoji;
  final int count;
  final Color foregroundColor;
  final bool floating;
  final String? motionId;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = TextStyle(
      color: floating ? colorScheme.onSurface : foregroundColor,
      fontSize: 11,
      fontWeight: FontWeight.w800,
    );
    return Container(
      key: floating ? ValueKey('floating-reaction-content-$emoji') : null,
      constraints: floating
          ? const BoxConstraints(minHeight: 26)
          : const BoxConstraints(),
      padding: EdgeInsets.symmetric(horizontal: floating ? 4 : 7, vertical: 3),
      decoration: BoxDecoration(
        color: floating
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.96)
            : Colors.black.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: floating
              ? colorScheme.outlineVariant.withValues(alpha: 0.74)
              : foregroundColor.withValues(alpha: 0.16),
        ),
        boxShadow: floating
            ? [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.22),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: count > 0
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AnimatedEmojiGlyph(
                  key: ValueKey('summary-emoji-motion-$motionId-$count'),
                  id: motionId!,
                  emoji: emoji,
                  fontSize: floating ? 12 : 13,
                  enabled:
                      !floating && !MediaQuery.disableAnimationsOf(context),
                ),
                const SizedBox(width: 3),
                Text('$count', style: textStyle),
              ],
            )
          : Text(emoji, style: textStyle),
    );
  }
}

class _AnimatedEmojiGlyph extends StatelessWidget {
  const _AnimatedEmojiGlyph({
    required this.id,
    required this.emoji,
    required this.fontSize,
    required this.enabled,
    super.key,
  });

  final String id;
  final String emoji;
  final double fontSize;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final glyph = Text(
      emoji,
      key: ValueKey('animated-emoji-glyph-$id'),
      style: TextStyle(fontSize: fontSize, height: 1),
    );
    if (!enabled) return glyph;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 880),
      builder: (context, progress, child) {
        final decay = 1 - progress;
        final wave = math.sin(progress * math.pi * 5);
        final pulse = wave.abs() * decay;
        return Transform.translate(
          key: ValueKey('animated-emoji-transform-$id'),
          offset: Offset(0, -3.2 * pulse),
          child: Transform.rotate(
            angle: wave * decay * 0.16,
            child: Transform.scale(scale: 1 + (pulse * 0.2), child: child),
          ),
        );
      },
      child: glyph,
    );
  }
}
