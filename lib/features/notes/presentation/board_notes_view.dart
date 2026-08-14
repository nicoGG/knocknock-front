part of 'board_page.dart';

/// Board note layouts, completion transitions, and reordering gestures.

typedef NoteCardBuilder =
    Widget Function(
      Note note,
      PostItCardLayout layout, {
      bool? completedChecklistExpanded,
      ValueChanged<bool>? onCompletedChecklistExpansionChanged,
    });
typedef NoteReorderCallback = void Function(List<String> orderedIds);
typedef NoteCompletionBuilder =
    Widget Function(BuildContext context, Note note, VoidCallback onToggle);

class _NoteCompletionTransition extends StatefulWidget {
  const _NoteCompletionTransition({
    required this.note,
    required this.removesFromCurrentFilter,
    required this.onToggle,
    required this.builder,
    super.key,
  });

  final Note note;
  final bool removesFromCurrentFilter;
  final VoidCallback onToggle;
  final NoteCompletionBuilder builder;

  @override
  State<_NoteCompletionTransition> createState() =>
      _NoteCompletionTransitionState();
}

class _NoteCompletionTransitionState extends State<_NoteCompletionTransition> {
  static const _duration = Duration(milliseconds: 300);

  Timer? _toggleTimer;
  bool _isExiting = false;
  bool? _previewCompleted;

  @override
  void didUpdateWidget(covariant _NoteCompletionTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.isCompleted != widget.note.isCompleted) {
      _toggleTimer?.cancel();
      _isExiting = false;
      _previewCompleted = null;
    }
  }

  @override
  void dispose() {
    _toggleTimer?.cancel();
    super.dispose();
  }

  void _toggle() {
    if (_isExiting) return;
    HapticFeedback.selectionClick();
    if (!widget.removesFromCurrentFilter ||
        MediaQuery.disableAnimationsOf(context)) {
      widget.onToggle();
      return;
    }

    setState(() {
      _previewCompleted = !widget.note.isCompleted;
      _isExiting = true;
    });
    _toggleTimer = Timer(_duration, widget.onToggle);
  }

  @override
  Widget build(BuildContext context) {
    final displayedNote = _previewCompleted == null
        ? widget.note
        : widget.note.copyWith(isCompleted: _previewCompleted);
    final card = widget.builder(context, displayedNote, _toggle);
    if (!_isExiting) return card;
    return TweenAnimationBuilder<double>(
      key: ValueKey('note-exit-motion-${widget.note.id}'),
      tween: Tween(begin: 0, end: 1),
      duration: _duration,
      curve: Curves.easeInCubic,
      child: card,
      builder: (context, progress, child) => FractionalTranslation(
        key: ValueKey('note-exit-slide-${widget.note.id}'),
        translation: Offset(0.08 * progress, -0.025 * progress),
        transformHitTests: false,
        child: Transform.scale(
          key: ValueKey('note-exit-scale-${widget.note.id}'),
          scale: 1 - (0.06 * progress),
          alignment: Alignment.centerRight,
          transformHitTests: false,
          child: Opacity(
            key: ValueKey('note-exit-opacity-${widget.note.id}'),
            opacity: 1 - progress,
            child: child,
          ),
        ),
      ),
    );
  }
}

double _boardBottomScrollPadding(BuildContext context) {
  final isCompact = MediaQuery.sizeOf(context).width < 720;
  return MediaQuery.paddingOf(context).bottom + (isCompact ? 124 : 96);
}

class _CompletedSectionHeader extends StatelessWidget {
  const _CompletedSectionHeader({
    required this.count,
    required this.isExpanded,
    required this.onExpansionChanged,
  });

  final int count;
  final bool isExpanded;
  final ValueChanged<bool> onExpansionChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Semantics(
      header: true,
      button: true,
      toggled: isExpanded,
      label:
          'Completadas, $count ${count == 1 ? 'nota' : 'notas'}, '
          '${isExpanded ? 'expandido' : 'contraído'}',
      child: GestureDetector(
        key: const ValueKey('completed-section-header'),
        behavior: HitTestBehavior.opaque,
        onTap: () => onExpansionChanged(!isExpanded),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 22, 6, 4),
          child: Row(
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                size: 22,
                color: colorScheme.onSurface.withValues(alpha: 0.72),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Completadas',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.86),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                key: const ValueKey('completed-section-count'),
                constraints: const BoxConstraints(minWidth: 30),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: isExpanded ? 0.5 : 0,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: colorScheme.onSurface.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotesGrid extends StatefulWidget {
  const _NotesGrid({
    required this.notes,
    required this.groupCompleted,
    required this.completedSectionExpanded,
    required this.animateEntrances,
    required this.showOriginList,
    required this.buildCard,
    required this.onReorder,
    required this.onCompletedSectionExpansionChanged,
    super.key,
  });

  final List<Note> notes;
  final bool groupCompleted;
  final bool completedSectionExpanded;
  final bool animateEntrances;
  final bool showOriginList;
  final NoteCardBuilder buildCard;
  final NoteReorderCallback onReorder;
  final ValueChanged<bool> onCompletedSectionExpansionChanged;

  @override
  State<_NotesGrid> createState() => _NotesGridState();
}

class _GridNoteHeightCacheKey {
  const _GridNoteHeightCacheKey({
    required this.note,
    required this.columnWidth,
    required this.textScale,
    required this.textDirection,
    required this.titleStyle,
    required this.descriptionStyle,
    required this.isCompact,
    required this.completedChecklistExpanded,
    required this.showOriginList,
  });

  final Note note;
  final double columnWidth;
  final double textScale;
  final TextDirection textDirection;
  final TextStyle? titleStyle;
  final TextStyle descriptionStyle;
  final bool isCompact;
  final bool completedChecklistExpanded;
  final bool showOriginList;

  @override
  bool operator ==(Object other) =>
      other is _GridNoteHeightCacheKey &&
      identical(note, other.note) &&
      columnWidth == other.columnWidth &&
      textScale == other.textScale &&
      textDirection == other.textDirection &&
      titleStyle == other.titleStyle &&
      descriptionStyle == other.descriptionStyle &&
      isCompact == other.isCompact &&
      completedChecklistExpanded == other.completedChecklistExpanded &&
      showOriginList == other.showOriginList;

  @override
  int get hashCode => Object.hash(
    identityHashCode(note),
    columnWidth,
    textScale,
    textDirection,
    titleStyle,
    descriptionStyle,
    isCompact,
    completedChecklistExpanded,
    showOriginList,
  );
}

class _NotesGridState extends State<_NotesGrid> {
  static const _maximumCachedHeights = 256;

  final Set<String> _collapsedCompletedChecklistNoteIds = {};
  final Map<_GridNoteHeightCacheKey, double> _heightCache = {};

  List<Note> get notes => widget.notes;
  bool get groupCompleted => widget.groupCompleted;
  bool get completedSectionExpanded => widget.completedSectionExpanded;
  bool get animateEntrances => widget.animateEntrances;
  bool get showOriginList => widget.showOriginList;
  NoteCardBuilder get buildCard => widget.buildCard;
  NoteReorderCallback get onReorder => widget.onReorder;
  ValueChanged<bool> get onCompletedSectionExpansionChanged =>
      widget.onCompletedSectionExpansionChanged;

  @override
  void didUpdateWidget(covariant _NotesGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    final collapsibleNoteIds = notes
        .where((note) => note.checklist.any((item) => item.isCompleted))
        .map((note) => note.id)
        .toSet();
    _collapsedCompletedChecklistNoteIds.retainAll(collapsibleNoteIds);
  }

  void _setCompletedChecklistExpanded(String noteId, bool expanded) {
    setState(() {
      if (expanded) {
        _collapsedCompletedChecklistNoteIds.remove(noteId);
      } else {
        _collapsedCompletedChecklistNoteIds.add(noteId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.crossAxisExtent;
        final isCompact = availableWidth < 720;
        final spacing = isCompact ? 10.0 : 16.0;
        // Grid cards reserve 10 px above their surface for the pin. Removing
        // that amount here keeps the visible vertical and horizontal gaps
        // equal while allowing the pin to share the space between cards.
        final verticalSpacing = spacing - 10;
        final columnCount = isCompact
            ? 2
            : ((availableWidth + spacing) / (280 + spacing)).floor().clamp(
                2,
                4,
              );
        final columnWidth =
            (availableWidth - (spacing * (columnCount - 1))) / columnCount;
        final pendingNotes = groupCompleted
            ? notes.where((note) => !note.isCompleted).toList()
            : notes;
        final completedNotes = groupCompleted
            ? notes.where((note) => note.isCompleted).toList()
            : const <Note>[];

        return SliverMainAxisGroup(
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 6)),
            if (pendingNotes.isNotEmpty)
              _buildMasonryGroup(
                context,
                notes: pendingNotes,
                columnCount: columnCount,
                columnWidth: columnWidth,
                spacing: spacing,
                verticalSpacing: verticalSpacing,
                isCompact: isCompact,
                animateEntrances: animateEntrances,
                keySuffix: '',
              ),
            if (completedNotes.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _CompletedSectionHeader(
                  count: completedNotes.length,
                  isExpanded: completedSectionExpanded,
                  onExpansionChanged: onCompletedSectionExpansionChanged,
                ),
              ),
              if (completedSectionExpanded) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                _buildMasonryGroup(
                  context,
                  notes: completedNotes,
                  columnCount: columnCount,
                  columnWidth: columnWidth,
                  spacing: spacing,
                  verticalSpacing: verticalSpacing,
                  isCompact: isCompact,
                  animateEntrances: animateEntrances,
                  keySuffix: '-completed',
                ),
              ],
            ],
            SliverToBoxAdapter(
              child: SizedBox(height: _boardBottomScrollPadding(context)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMasonryGroup(
    BuildContext context, {
    required List<Note> notes,
    required int columnCount,
    required double columnWidth,
    required double spacing,
    required double verticalSpacing,
    required bool isCompact,
    required bool animateEntrances,
    required String keySuffix,
  }) {
    return SliverMasonryGrid.count(
      key: ValueKey('masonry-grid-columns$keySuffix'),
      crossAxisCount: columnCount,
      mainAxisSpacing: verticalSpacing,
      crossAxisSpacing: spacing,
      childCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        final completedChecklistExpanded = !_collapsedCompletedChecklistNoteIds
            .contains(note.id);
        final height = _gridNoteHeight(
          context,
          note,
          columnWidth: columnWidth,
          isCompact: isCompact,
          completedChecklistExpanded: completedChecklistExpanded,
        );
        return AnimatedContainer(
          key: ValueKey('grid-note-size-${note.id}'),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeInOutCubic,
          height: height,
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: height,
            maxHeight: height,
            child: _NoteEntrance(
              key: ValueKey('note-entrance-${note.id}'),
              index: index,
              motionId: note.id,
              enabled: animateEntrances,
              child: _DraggableGridNote(
                key: ValueKey('reorder-grid-${note.id}'),
                note: note,
                onDrop: (draggedId) {
                  final reordered = [...notes];
                  final oldIndex = reordered.indexWhere(
                    (note) => note.id == draggedId,
                  );
                  final targetIndex = reordered.indexWhere(
                    (entry) => entry.id == note.id,
                  );
                  if (oldIndex == -1 ||
                      targetIndex == -1 ||
                      oldIndex == targetIndex) {
                    return;
                  }
                  final moved = reordered.removeAt(oldIndex);
                  reordered.insert(targetIndex, moved);
                  onReorder(reordered.map((note) => note.id).toList());
                },
                child: buildCard(
                  note,
                  PostItCardLayout.grid,
                  completedChecklistExpanded:
                      !_collapsedCompletedChecklistNoteIds.contains(note.id),
                  onCompletedChecklistExpansionChanged: (expanded) =>
                      _setCompletedChecklistExpanded(note.id, expanded),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  double _gridNoteHeight(
    BuildContext context,
    Note note, {
    required double columnWidth,
    required bool isCompact,
    required bool completedChecklistExpanded,
  }) {
    final theme = Theme.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    final key = _GridNoteHeightCacheKey(
      note: note,
      columnWidth: columnWidth,
      textScale: textScaler.scale(14),
      textDirection: textDirection,
      titleStyle: theme.textTheme.titleLarge,
      descriptionStyle: gridNoteDescriptionTextStyle(context),
      isCompact: isCompact,
      completedChecklistExpanded: completedChecklistExpanded,
      showOriginList: showOriginList,
    );
    final cached = _heightCache.remove(key);
    if (cached != null) {
      _heightCache[key] = cached;
      return cached;
    }
    final measured = _measureGridNoteHeight(
      context,
      note,
      columnWidth: columnWidth,
      isCompact: isCompact,
      completedChecklistExpanded: completedChecklistExpanded,
    );
    _heightCache[key] = measured;
    while (_heightCache.length > _maximumCachedHeights) {
      _heightCache.remove(_heightCache.keys.first);
    }
    return measured;
  }

  double _measureGridNoteHeight(
    BuildContext context,
    Note note, {
    required double columnWidth,
    required bool isCompact,
    required bool completedChecklistExpanded,
  }) {
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    final titlePainter = TextPainter(
      text: TextSpan(
        text: note.title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 2,
    )..layout(maxWidth: (columnWidth - 80).clamp(1, columnWidth));
    final headerHeight = titlePainter.height < 48 ? 48.0 : titlePainter.height;
    final contentPainter = TextPainter(
      text: noteLinkifiedTextSpan(
        plainText: note.content,
        deltaJson: note.contentDelta,
        style: gridNoteDescriptionTextStyle(context),
      ),
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout(maxWidth: (columnWidth - 32).clamp(1, columnWidth));
    final pendingChecklistCount = note.checklist
        .where((item) => !item.isCompleted)
        .length;
    final completedChecklistCount =
        note.checklist.length - pendingChecklistCount;
    var visiblePendingChecklistCount = pendingChecklistCount
        .clamp(0, 10)
        .toInt();
    var visibleCompletedChecklistCount = 0;
    if (completedChecklistExpanded && completedChecklistCount > 0) {
      final remainingCapacity = 10 - visiblePendingChecklistCount;
      if (remainingCapacity > 0) {
        visibleCompletedChecklistCount = completedChecklistCount
            .clamp(0, remainingCapacity)
            .toInt();
      } else if (visiblePendingChecklistCount > 0) {
        visiblePendingChecklistCount -= 1;
        visibleCompletedChecklistCount = 1;
      }
    }
    final hiddenPendingChecklistCount =
        pendingChecklistCount - visiblePendingChecklistCount;
    // TextPainter can report a fractional height that RenderParagraph rounds
    // up during the card layout. Keep one logical pixel of breathing room so
    // multi-line descriptions do not overflow at narrow widths or high DPRs.
    final descriptionHeight = note.content.isEmpty
        ? 0.0
        : contentPainter.height.ceilToDouble() + 1;
    final checklistHeight = note.checklist.isEmpty
        ? 0.0
        : ((visiblePendingChecklistCount + visibleCompletedChecklistCount) *
                  30) +
              (hiddenPendingChecklistCount > 0 ? 22 : 0) +
              (completedChecklistCount > 0 ? 44 : 0);
    final contentHeight =
        descriptionHeight +
        checklistHeight +
        (note.content.isNotEmpty && note.checklist.isNotEmpty ? 10 : 0);
    final hasBody = note.checklist.isNotEmpty || note.content.isNotEmpty;
    final originListHeight = showOriginList && hasBody ? 35.0 : 0.0;
    final categoryHeight = hasBody
        ? note.category == NoteCategory.general
              ? 6.0
              : 40.0
        : 0.0;
    final reminderHeight = hasBody && note.reminderAt != null ? 32.0 : 0.0;
    final hasAssignee =
        note.assigneeUid != null ||
        (note.customAssigneeName?.trim().isNotEmpty ?? false);
    final hasColorIndicator =
        NoteCategoryStyle.assetPath(note.category) != null;
    final footerHeight = hasAssignee || hasColorIndicator
        ? 28.0
        : isCompact
        ? 0.0
        : 24.0;
    final photoHeight =
        note.photoAttachments.any((attachment) => attachment.isImage)
        ? gridNotePhotoHeight(columnWidth)
        : 0.0;
    if (!hasBody) {
      if (!hasAssignee) {
        final titleOnlyPainter = TextPainter(
          text: TextSpan(
            text: note.title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          textDirection: textDirection,
          textScaler: textScaler,
          maxLines: 2,
        )..layout(maxWidth: (columnWidth - 32).clamp(1, columnWidth));
        final baseHeight = (36.0 + titleOnlyPainter.height)
            .clamp(isCompact ? 84.0 : 96.0, isCompact ? 120.0 : 136.0)
            .toDouble();
        return baseHeight + photoHeight + (hasColorIndicator ? 36 : 0);
      }
      final desiredEmptyHeight = 36.0 + headerHeight + 28 + photoHeight;
      return desiredEmptyHeight
          .clamp(
            isCompact ? 136.0 : 142.0,
            (isCompact ? 150.0 : 166.0) + photoHeight,
          )
          .toDouble();
    }
    final desiredHeight =
        36.0 +
        headerHeight +
        originListHeight +
        categoryHeight +
        contentHeight +
        reminderHeight +
        photoHeight +
        (hasAssignee ? 10 : 0) +
        footerHeight +
        (note.checklist.isNotEmpty ? 10 : 0);
    final minimumHeight = isCompact ? 184.0 : 205.0;
    return (desiredHeight < minimumHeight ? minimumHeight : desiredHeight)
        .ceilToDouble();
  }
}

class _DraggableGridNote extends StatefulWidget {
  const _DraggableGridNote({
    required this.note,
    required this.onDrop,
    required this.child,
    super.key,
  });

  final Note note;
  final ValueChanged<String> onDrop;
  final Widget child;

  @override
  State<_DraggableGridNote> createState() => _DraggableGridNoteState();
}

class _DraggableGridNoteState extends State<_DraggableGridNote> {
  bool _isTargeted = false;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        final accepted = details.data != widget.note.id;
        if (_isTargeted != accepted) setState(() => _isTargeted = accepted);
        return accepted;
      },
      onLeave: (_) {
        if (_isTargeted) setState(() => _isTargeted = false);
      },
      onAcceptWithDetails: (details) {
        setState(() => _isTargeted = false);
        widget.onDrop(details.data);
      },
      builder: (context, candidateData, rejectedData) => AnimatedScale(
        scale: _isTargeted ? 1.025 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: LayoutBuilder(
          builder: (context, constraints) => Semantics(
            hint:
                'Toca para abrir; mantén presionada y arrastra para cambiar el orden',
            child: LongPressDraggable<String>(
              data: widget.note.id,
              delay: const Duration(milliseconds: 500),
              onDragStarted: HapticFeedback.mediumImpact,
              feedback: Material(
                color: Colors.transparent,
                elevation: 10,
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: widget.child,
                ),
              ),
              childWhenDragging: Opacity(opacity: 0.2, child: widget.child),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _NotesList extends StatelessWidget {
  const _NotesList({
    required this.notes,
    required this.groupCompleted,
    required this.completedSectionExpanded,
    required this.animateEntrances,
    required this.layout,
    required this.itemHeight,
    required this.maxWidth,
    required this.buildCard,
    required this.onReorder,
    required this.onCompletedSectionExpansionChanged,
    super.key,
  });

  final List<Note> notes;
  final bool groupCompleted;
  final bool completedSectionExpanded;
  final bool animateEntrances;
  final PostItCardLayout layout;
  final double itemHeight;
  final double maxWidth;
  final NoteCardBuilder buildCard;
  final NoteReorderCallback onReorder;
  final ValueChanged<bool> onCompletedSectionExpansionChanged;

  @override
  Widget build(BuildContext context) {
    final pendingNotes = groupCompleted
        ? notes.where((note) => !note.isCompleted).toList()
        : notes;
    final completedNotes = groupCompleted
        ? notes.where((note) => note.isCompleted).toList()
        : const <Note>[];
    return SliverMainAxisGroup(
      slivers: [
        if (pendingNotes.isNotEmpty) _buildSliver(pendingNotes),
        if (completedNotes.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _CompletedSectionHeader(
              count: completedNotes.length,
              isExpanded: completedSectionExpanded,
              onExpansionChanged: onCompletedSectionExpansionChanged,
            ),
          ),
          if (completedSectionExpanded) ...[
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            _buildSliver(completedNotes),
          ],
        ],
        SliverToBoxAdapter(
          child: SizedBox(height: _boardBottomScrollPadding(context)),
        ),
      ],
    );
  }

  Widget _buildSliver(List<Note> notes) {
    return SliverReorderableList(
      itemCount: notes.length,
      proxyDecorator: _proxyDecorator,
      onReorderStart: (_) => HapticFeedback.mediumImpact(),
      onReorderItem: (oldIndex, newIndex) =>
          _reorder(notes, oldIndex, newIndex),
      itemBuilder: (context, index) => _buildItem(context, notes, index),
    );
  }

  Widget _proxyDecorator(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => Transform.scale(
        scale: 1 + (animation.value * 0.015),
        child: Material(
          color: Colors.transparent,
          elevation: animation.value * 10,
          borderRadius: BorderRadius.circular(18),
          child: child,
        ),
      ),
    );
  }

  void _reorder(List<Note> notes, int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final reordered = [...notes];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    onReorder(reordered.map((note) => note.id).toList());
  }

  Widget _buildItem(BuildContext context, List<Note> notes, int index) {
    final note = notes[index];
    return ReorderableDelayedDragStartListener(
      key: ValueKey('reorder-list-${note.id}'),
      index: index,
      child: Semantics(
        hint:
            'Toca para abrir; mantén presionada y arrastra para cambiar el orden',
        child: _NoteEntrance(
          index: index,
          motionId: note.id,
          enabled: animateEntrances,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: layout == PostItCardLayout.compact ? 3 : 8,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: SizedBox(
                  height: itemHeight,
                  child: buildCard(note, layout),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoteEntrance extends StatefulWidget {
  const _NoteEntrance({
    required this.index,
    required this.motionId,
    required this.enabled,
    required this.child,
    super.key,
  });

  final int index;
  final String motionId;
  final bool enabled;
  final Widget child;

  @override
  State<_NoteEntrance> createState() => _NoteEntranceState();
}

class _NoteEntranceState extends State<_NoteEntrance> {
  late bool _finished;

  @override
  void initState() {
    super.initState();
    _finished = !widget.enabled;
  }

  @override
  void didUpdateWidget(covariant _NoteEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _finished = true;
  }

  @override
  Widget build(BuildContext context) {
    if (_finished ||
        !widget.enabled ||
        widget.index >= _maxAnimatedNoteEntrances ||
        MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    final delay = widget.index * 42;
    final totalDuration = 390 + delay;
    return TweenAnimationBuilder<double>(
      key: ValueKey('note-entrance-motion-${widget.motionId}'),
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: totalDuration),
      curve: Interval(delay / totalDuration, 1, curve: Curves.easeOutCubic),
      onEnd: () {
        if (mounted) setState(() => _finished = true);
      },
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - value)),
          child: Transform.scale(
            scale: 0.965 + (0.035 * value),
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        ),
      ),
      child: widget.child,
    );
  }
}
