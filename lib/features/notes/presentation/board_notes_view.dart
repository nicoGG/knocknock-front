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
  static const _duration = Duration(milliseconds: 450);

  bool _isExiting = false;
  bool? _previewCompleted;

  @override
  void didUpdateWidget(covariant _NoteCompletionTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.isCompleted != widget.note.isCompleted) {
      _isExiting = false;
      _previewCompleted = null;
    }
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
  }

  @override
  Widget build(BuildContext context) {
    final displayedNote = _previewCompleted == null
        ? widget.note
        : widget.note.copyWith(isCompleted: _previewCompleted);
    final card = widget.builder(context, displayedNote, _toggle);
    return TweenAnimationBuilder<double>(
      key: ValueKey('note-exit-motion-${widget.note.id}'),
      tween: Tween(begin: 0, end: _isExiting ? 1 : 0),
      duration: _duration,
      curve: Curves.easeInOutCubic,
      onEnd: () {
        if (_isExiting) widget.onToggle();
      },
      child: RepaintBoundary(child: card),
      builder: (context, progress, child) => FractionalTranslation(
        key: ValueKey('note-exit-slide-${widget.note.id}'),
        translation: Offset(
          0,
          (widget.note.isCompleted ? -0.14 : 0.14) * progress,
        ),
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

// Known card heights make section extents independent of recycled children.
class _NoteMasonryDelegate extends SliverGridDelegate {
  _NoteMasonryDelegate(this.heights, this.columns, this.spacing, this.gap);
  final List<double> heights;
  final int columns;
  final double spacing;
  final double gap;
  _NoteMasonryLayout? _cachedLayout;
  double? _cachedWidth;
  AxisDirection? _cachedDirection;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    if (_cachedLayout != null &&
        _cachedWidth == constraints.crossAxisExtent &&
        _cachedDirection == constraints.crossAxisDirection) {
      return _cachedLayout!;
    }
    _cachedWidth = constraints.crossAxisExtent;
    _cachedDirection = constraints.crossAxisDirection;
    final width =
        (constraints.crossAxisExtent - spacing * (columns - 1)) / columns;
    final ends = List<double>.filled(columns, 0);
    final geometry = <SliverGridGeometry>[];
    for (final height in heights) {
      var column = 0;
      for (var i = 1; i < columns; i++) {
        if (ends[i] < ends[column]) column = i;
      }
      final visualColumn =
          axisDirectionIsReversed(constraints.crossAxisDirection)
          ? columns - column - 1
          : column;
      geometry.add(
        SliverGridGeometry(
          scrollOffset: ends[column],
          crossAxisOffset: visualColumn * (width + spacing),
          mainAxisExtent: height,
          crossAxisExtent: width,
        ),
      );
      ends[column] += height + gap;
    }
    return _cachedLayout = _NoteMasonryLayout(geometry);
  }

  @override
  bool shouldRelayout(covariant _NoteMasonryDelegate oldDelegate) =>
      columns != oldDelegate.columns ||
      spacing != oldDelegate.spacing ||
      gap != oldDelegate.gap ||
      !listEquals(heights, oldDelegate.heights);
}

class _NoteMasonryLayout extends SliverGridLayout {
  _NoteMasonryLayout(this.geometry) {
    var extent = 0.0;
    for (final child in geometry) {
      extent = math.max(extent, child.trailingScrollOffset);
      _maximumEnds.add(extent);
    }
  }
  final List<SliverGridGeometry> geometry;
  final List<double> _maximumEnds = [];

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) {
    // Prefix maxima preserve tall cards whose neighbours end earlier.
    var low = 0;
    var high = _maximumEnds.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_maximumEnds[middle] < scrollOffset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return math.min(low, math.max(0, geometry.length - 1));
  }

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) {
    var low = 0;
    var high = geometry.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (geometry[middle].scrollOffset < scrollOffset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return math.max(0, low - 1);
  }

  @override
  SliverGridGeometry getGeometryForChildIndex(int index) => geometry[index];

  @override
  double computeMaxScrollOffset(int childCount) => childCount == 0
      ? 0
      : _maximumEnds[math.min(childCount, geometry.length) - 1];
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
  bool _animateNoteReflow = false;
  final Set<String> _builtNoteIds = {};
  final Map<_GridNoteHeightCacheKey, double> _heightCache = {};
  String? _activeDragGroup;
  String? _activeDraggedNoteId;
  List<String>? _originalDragOrder;
  List<String>? _previewDragOrder;

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
    if (_notePlacementChanged(oldWidget.notes, notes)) {
      _animateNoteReflow = true;
    } else if (!listEquals(
      oldWidget.notes.map((note) => note.id).toList(),
      notes.map((note) => note.id).toList(),
    )) {
      _animateNoteReflow = false;
    }
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

  void _startGridDrag(
    String groupKey,
    List<Note> groupNotes,
    String draggedNoteId,
  ) {
    _animateNoteReflow = false;
    final order = groupNotes.map((note) => note.id).toList();
    setState(() {
      _activeDragGroup = groupKey;
      _activeDraggedNoteId = draggedNoteId;
      _originalDragOrder = order;
      _previewDragOrder = [...order];
    });
  }

  void _previewGridReorder(
    String groupKey,
    String draggedNoteId,
    String targetNoteId,
  ) {
    if (_activeDragGroup != groupKey || _activeDraggedNoteId != draggedNoteId) {
      return;
    }
    final currentOrder = _previewDragOrder;
    if (currentOrder == null) return;
    final oldIndex = currentOrder.indexOf(draggedNoteId);
    final targetIndex = currentOrder.indexOf(targetNoteId);
    if (oldIndex == -1 || targetIndex == -1 || oldIndex == targetIndex) return;

    final reordered = [...currentOrder];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(targetIndex, moved);
    setState(() => _previewDragOrder = reordered);
  }

  void _finishGridDrag(
    String groupKey,
    String draggedNoteId, {
    required bool accepted,
  }) {
    if (_activeDragGroup != groupKey || _activeDraggedNoteId != draggedNoteId) {
      return;
    }
    final originalOrder = _originalDragOrder;
    final previewOrder = _previewDragOrder;
    final orderChanged =
        originalOrder != null &&
        previewOrder != null &&
        !listEquals(originalOrder, previewOrder);
    setState(() {
      _activeDragGroup = null;
      _activeDraggedNoteId = null;
      _originalDragOrder = null;
      _previewDragOrder = null;
    });
    if (accepted && orderChanged) onReorder(previewOrder);
  }

  List<Note> _previewedGridNotes(String groupKey, List<Note> groupNotes) {
    final previewOrder = _previewDragOrder;
    if (_activeDragGroup != groupKey || previewOrder == null) {
      return groupNotes;
    }
    final notesById = {for (final note in groupNotes) note.id: note};
    if (previewOrder.length != groupNotes.length ||
        previewOrder.any((id) => !notesById.containsKey(id))) {
      return groupNotes;
    }
    return [for (final id in previewOrder) notesById[id]!];
  }

  @override
  Widget build(BuildContext context) {
    Object? cachedPresentation;
    Widget? cachedSliver;
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final presentation = (
          constraints.crossAxisExtent,
          Theme.of(context),
          MediaQuery.of(context),
          Directionality.of(context),
        );
        if (cachedPresentation == presentation && cachedSliver != null) {
          return cachedSliver!;
        }
        cachedPresentation = presentation;
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

        return cachedSliver = SliverMainAxisGroup(
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
    final arrangedNotes = _previewedGridNotes(keySuffix, notes);
    final layoutKey = 'masonry-grid-columns$keySuffix';
    final groupNoteIds = notes.map((note) => note.id).toSet();
    final noteIndexes = <Key, int>{
      for (var index = 0; index < arrangedNotes.length; index++)
        ValueKey('grid-note-size-${arrangedNotes[index].id}'): index,
    };
    final heights = [
      for (final note in arrangedNotes)
        _gridNoteHeight(
          context,
          note,
          columnWidth: columnWidth,
          isCompact: isCompact,
          completedChecklistExpanded: !_collapsedCompletedChecklistNoteIds
              .contains(note.id),
        ),
    ];
    final columnEnds = List<double>.filled(columnCount, 0);
    final positions = <String, Offset>{};
    for (var index = 0; index < arrangedNotes.length; index++) {
      var column = 0;
      for (var candidate = 1; candidate < columnCount; candidate++) {
        if (columnEnds[candidate] < columnEnds[column]) column = candidate;
      }
      final visualColumn = Directionality.of(context) == TextDirection.rtl
          ? columnCount - column - 1
          : column;
      positions[arrangedNotes[index].id] = Offset(
        visualColumn * (columnWidth + spacing),
        columnEnds[column],
      );
      columnEnds[column] += heights[index] + verticalSpacing;
    }
    return SliverGrid(
      key: ValueKey(layoutKey),
      gridDelegate: _NoteMasonryDelegate(
        heights,
        columnCount,
        spacing,
        verticalSpacing,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final note = arrangedNotes[index];
          final isFirstBuild = _builtNoteIds.add(note.id);
          final height = heights[index];
          return AnimatedContainer(
            key: ValueKey('grid-note-size-${note.id}'),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeInOutCubic,
            height: height,
            child: _NoteReflow(
              enabled: _animateNoteReflow && _activeDraggedNoteId == null,
              position: positions[note.id]!,
              motionId: note.id,
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: height,
                maxHeight: height,
                child: _NoteEntrance(
                  key: ValueKey('note-entrance-${note.id}'),
                  index: index,
                  motionId: note.id,
                  enabled: animateEntrances && isFirstBuild,
                  child: _DraggableGridNote(
                    key: ValueKey('reorder-grid-${note.id}'),
                    note: note,
                    canAccept: (draggedId) => groupNoteIds.contains(draggedId),
                    onHover: (draggedId) =>
                        _previewGridReorder(keySuffix, draggedId, note.id),
                    onDragStarted: () =>
                        _startGridDrag(keySuffix, notes, note.id),
                    onDragEnded: (accepted) =>
                        _finishGridDrag(keySuffix, note.id, accepted: accepted),
                    child: buildCard(
                      note,
                      PostItCardLayout.grid,
                      completedChecklistExpanded:
                          !_collapsedCompletedChecklistNoteIds.contains(
                            note.id,
                          ),
                      onCompletedChecklistExpansionChanged: (expanded) =>
                          _setCompletedChecklistExpanded(note.id, expanded),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        childCount: arrangedNotes.length,
        findChildIndexCallback: (key) => noteIndexes[key],
      ),
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
    // Keep a measurement for every loaded card so long boards do not remeasure
    // all text on each scroll frame after overflowing the fixed cache.
    final cacheLimit = math.max(_maximumCachedHeights, notes.length * 2);
    while (_heightCache.length > cacheLimit) {
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
    final titlePainter =
        TextPainter(
          text: TextSpan(
            text: note.title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          textDirection: textDirection,
          textScaler: textScaler,
          maxLines: 2,
        )..layout(
          maxWidth: (columnWidth - (note.isRecurring ? 32 : 80)).clamp(
            1,
            columnWidth,
          ),
        );
    final headerHeight =
        (titlePainter.height < 48 ? 48.0 : titlePainter.height) +
        (note.isRecurring ? 24 : 0);
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
    final reminderHeight =
        (hasBody || note.isRecurring) && note.reminderAt != null ? 32.0 : 0.0;
    final hasAssignee =
        note.assignedUserIds.isNotEmpty ||
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
        final titleHeight = 36.0 + titleOnlyPainter.height.ceilToDouble();
        final baseHeight = note.isRecurring
            ? titleHeight
            : titleHeight
                  .clamp(isCompact ? 84.0 : 96.0, isCompact ? 120.0 : 136.0)
                  .toDouble();
        return baseHeight +
            (note.isRecurring ? 24 : 0) +
            reminderHeight +
            photoHeight +
            (hasColorIndicator ? 36 : 0);
      }
      final desiredEmptyHeight = 36.0 + headerHeight + 28 + photoHeight;
      return desiredEmptyHeight
              .clamp(
                isCompact ? 136.0 : 142.0,
                (isCompact ? 150.0 : 166.0) + photoHeight,
              )
              .toDouble() +
          reminderHeight;
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
    required this.canAccept,
    required this.onHover,
    required this.onDragStarted,
    required this.onDragEnded,
    required this.child,
    super.key,
  });

  final Note note;
  final bool Function(String draggedNoteId) canAccept;
  final ValueChanged<String> onHover;
  final VoidCallback onDragStarted;
  final ValueChanged<bool> onDragEnded;
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
        final accepted = widget.canAccept(details.data);
        final targeted = accepted && details.data != widget.note.id;
        if (_isTargeted != targeted) setState(() => _isTargeted = targeted);
        // The preview moves the source into the hovered slot. Accept a drop
        // on that source too, without reordering it again on pointer updates.
        if (targeted) widget.onHover(details.data);
        return accepted;
      },
      onLeave: (_) {
        if (_isTargeted) setState(() => _isTargeted = false);
      },
      onAcceptWithDetails: (details) {
        if (_isTargeted) setState(() => _isTargeted = false);
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
              onDragStarted: () {
                HapticFeedback.mediumImpact();
                widget.onDragStarted();
              },
              onDragEnd: (details) => widget.onDragEnded(details.wasAccepted),
              feedback: Material(
                key: ValueKey('grid-drag-feedback-${widget.note.id}'),
                color: Colors.transparent,
                elevation: 10,
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: widget.child,
                ),
              ),
              // Keep the source card rendered while Flutter transfers the
              // drag avatar back to the sliver. A translucent replacement can
              // remain attached to a recycled masonry child after a drop,
              // which looks like the note disappeared until the view rebuilds.
              childWhenDragging: KeyedSubtree(
                key: ValueKey('grid-drag-source-${widget.note.id}'),
                child: widget.child,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _NotesList extends StatefulWidget {
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
  State<_NotesList> createState() => _NotesListState();
}

class _NotesListState extends State<_NotesList> {
  bool _animateNoteReflow = false;
  final Set<String> _builtNoteIds = {};

  List<Note> get notes => widget.notes;
  bool get groupCompleted => widget.groupCompleted;
  bool get completedSectionExpanded => widget.completedSectionExpanded;
  bool get animateEntrances => widget.animateEntrances;
  PostItCardLayout get layout => widget.layout;
  double get itemHeight => widget.itemHeight;
  double get maxWidth => widget.maxWidth;
  NoteCardBuilder get buildCard => widget.buildCard;
  NoteReorderCallback get onReorder => widget.onReorder;
  ValueChanged<bool> get onCompletedSectionExpansionChanged =>
      widget.onCompletedSectionExpansionChanged;

  @override
  void didUpdateWidget(covariant _NotesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_notePlacementChanged(oldWidget.notes, notes)) {
      _animateNoteReflow = true;
    } else if (!listEquals(
      oldWidget.notes.map((note) => note.id).toList(),
      notes.map((note) => note.id).toList(),
    )) {
      _animateNoteReflow = false;
    }
  }

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
    _animateNoteReflow = false;
    if (oldIndex == newIndex) return;
    final reordered = [...notes];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    onReorder(reordered.map((note) => note.id).toList());
  }

  Widget _buildItem(BuildContext context, List<Note> notes, int index) {
    final note = notes[index];
    final isFirstBuild = _builtNoteIds.add(note.id);
    return ReorderableDelayedDragStartListener(
      key: ValueKey('reorder-list-${note.id}'),
      index: index,
      child: _NoteReflow(
        enabled: _animateNoteReflow,
        position: Offset(
          0,
          index * (itemHeight + (layout == PostItCardLayout.compact ? 3 : 8)),
        ),
        motionId: note.id,
        child: Semantics(
          hint:
              'Toca para abrir; mantén presionada y arrastra para cambiar el orden',
          child: _NoteEntrance(
            index: index,
            motionId: note.id,
            enabled: animateEntrances && isFirstBuild,
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

/// Keeps surviving cards visually in their old slot while the sliver relayouts.
class _NoteReflow extends StatefulWidget {
  const _NoteReflow({
    required this.position,
    this.enabled = false,
    required this.motionId,
    required this.child,
  });
  final Offset position;
  final bool enabled;
  final String motionId;
  final Widget child;
  @override
  State<_NoteReflow> createState() => _NoteReflowState();
}

class _NoteReflowState extends State<_NoteReflow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
    value: 1,
  );
  Offset _from = Offset.zero;
  Offset get _offset => Offset.lerp(
    _from,
    Offset.zero,
    Curves.easeInOutCubic.transform(_motion.value),
  )!;

  @override
  void didUpdateWidget(covariant _NoteReflow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled &&
        oldWidget.position != widget.position &&
        !MediaQuery.disableAnimationsOf(context)) {
      _from = _offset + oldWidget.position - widget.position;
      _motion.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _motion,
    child: widget.child,
    builder: (context, child) => Transform.translate(
      key: ValueKey('note-reflow-${widget.motionId}'),
      offset: _offset,
      child: child,
    ),
  );
}

bool _notePlacementChanged(List<Note> previous, List<Note> next) {
  if (previous.length != next.length) return true;
  final previousNotes = {for (final note in previous) note.id: note};
  return next.any((note) {
    final oldNote = previousNotes[note.id];
    return oldNote == null ||
        oldNote.isCompleted != note.isCompleted ||
        oldNote.isPinned != note.isPinned;
  });
}

class _NoteFilterEntrance extends StatelessWidget {
  const _NoteFilterEntrance({
    required this.animation,
    required this.motionId,
    required this.child,
  });
  final Animation<double> animation;
  final String motionId;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final progress = MediaQuery.disableAnimationsOf(context)
          ? 1.0
          : animation.value;
      return Transform.translate(
        key: ValueKey('note-filter-motion-$motionId'),
        offset: Offset(0, 10 * (1 - progress)),
        child: Transform.scale(scale: .98 + .02 * progress, child: child),
      );
    },
  );
}
