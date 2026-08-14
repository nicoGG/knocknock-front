part of 'board_page.dart';

/// Board header, list actions, and facet filter controls.

class _BoardHeader extends StatelessWidget {
  const _BoardHeader({
    required this.title,
    required this.list,
    required this.filter,
    required this.categoryCounts,
    required this.selectedCategory,
    required this.assigneeFilters,
    required this.selectedAssigneeUid,
    required this.viewMode,
    required this.onFilterChanged,
    required this.onCategoryChanged,
    required this.onAssigneeChanged,
    required this.onClearFilters,
    required this.filterOrderController,
    required this.onViewModeChanged,
    required this.onAdd,
    required this.onShare,
    required this.onCustomizeBackground,
    required this.onRenameList,
    required this.onDeleteList,
    required this.onToggleListProtection,
    required this.isListProtected,
    required this.isSavingListOptions,
    required this.showAddButton,
    required this.isCompact,
  });

  final String title;
  final NoteList? list;
  final NoteFilter filter;
  final Map<NoteCategory, int> categoryCounts;
  final NoteCategory? selectedCategory;
  final List<_AssigneeFilterOption> assigneeFilters;
  final String? selectedAssigneeUid;
  final BoardViewMode viewMode;
  final ValueChanged<NoteFilter> onFilterChanged;
  final ValueChanged<NoteCategory?> onCategoryChanged;
  final ValueChanged<String?> onAssigneeChanged;
  final VoidCallback onClearFilters;
  final BoardFilterOrderController filterOrderController;
  final ValueChanged<BoardViewMode> onViewModeChanged;
  final VoidCallback? onAdd;
  final VoidCallback? onShare;
  final VoidCallback? onCustomizeBackground;
  final VoidCallback? onRenameList;
  final VoidCallback? onDeleteList;
  final VoidCallback? onToggleListProtection;
  final bool isListProtected;
  final bool isSavingListOptions;
  final bool showAddButton;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasInvitedCollaborators =
        list?.collaborators.any(
          (person) => person.role != ListMemberRole.owner,
        ) ==
        true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.bottomLeft,
                  children: [...previousChildren, ?currentChild],
                ),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.18),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: Text(
                  title,
                  key: ValueKey(title),
                  style: Theme.of(context).textTheme.displaySmall,
                ),
              ),
            ),
            if (showAddButton ||
                onShare != null ||
                onCustomizeBackground != null ||
                onRenameList != null ||
                onToggleListProtection != null ||
                onDeleteList != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isCompact && hasInvitedCollaborators)
                    Tooltip(
                      message: 'Personas de la lista',
                      child: InkWell(
                        key: const ValueKey('share-list-button'),
                        onTap: onShare,
                        customBorder: const StadiumBorder(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                          child: _CollaboratorAvatarStack(
                            collaborators: list!.collaborators,
                          ),
                        ),
                      ),
                    ),
                  if (showAddButton)
                    GlassNewNoteButton(
                      key: const ValueKey('new-note-button'),
                      onPressed: onAdd,
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                    ),
                  if (onShare != null ||
                      onCustomizeBackground != null ||
                      onRenameList != null ||
                      onToggleListProtection != null ||
                      onDeleteList != null) ...[
                    if ((isCompact && hasInvitedCollaborators) || showAddButton)
                      const SizedBox(width: 8),
                    _ListMenuButton(
                      onShare: onShare,
                      showShareInMenu:
                          onShare != null &&
                          !(isCompact && hasInvitedCollaborators),
                      hasInvitedCollaborators: hasInvitedCollaborators,
                      onCustomizeBackground: onCustomizeBackground,
                      onRenameList: onRenameList,
                      onToggleListProtection: onToggleListProtection,
                      isListProtected: isListProtected,
                      onDeleteList: onDeleteList,
                      isSaving: isSavingListOptions,
                    ),
                  ],
                ],
              ),
          ],
        ),
        if (isListProtected) ...[
          const SizedBox(height: 10),
          _BoardMetaChip(
            key: const ValueKey('protected-list-chip'),
            icon: Icons.lock_rounded,
            label: 'Protegida',
            color: colorScheme.primary,
          ),
        ],
        SizedBox(height: isCompact ? 16 : 24),
        if (isCompact)
          _CompactBoardControls(
            filter: filter,
            viewMode: viewMode,
            onFilterChanged: onFilterChanged,
            onViewModeChanged: onViewModeChanged,
          )
        else
          Wrap(
            spacing: 16,
            runSpacing: 18,
            children: [
              SizedBox(
                width: 480,
                child: _BoardControlGroup<NoteFilter>(
                  key: const ValueKey('note-filter-selector'),
                  keyPrefix: 'desktop-filter-mode',
                  selected: filter,
                  selectedColor: colorScheme.primary,
                  onChanged: onFilterChanged,
                  options: const [
                    _BoardControlOption(
                      value: NoteFilter.all,
                      label: 'Todas',
                      icon: Icons.dashboard_outlined,
                    ),
                    _BoardControlOption(
                      value: NoteFilter.pending,
                      label: 'Pendientes',
                      icon: Icons.schedule_rounded,
                    ),
                    _BoardControlOption(
                      value: NoteFilter.completed,
                      label: 'Completadas',
                      icon: Icons.check_circle_outline_rounded,
                    ),
                  ],
                  showIcons: true,
                ),
              ),
              SizedBox(
                width: 430,
                child: _BoardControlGroup<BoardViewMode>(
                  key: const ValueKey('view-mode-selector'),
                  keyPrefix: 'desktop-view-mode',
                  selected: viewMode,
                  selectedColor: colorScheme.primary,
                  onChanged: onViewModeChanged,
                  options: const [
                    _BoardControlOption(
                      value: BoardViewMode.grid,
                      label: 'Cuadrícula',
                      icon: Icons.grid_view_rounded,
                      tooltip: 'Vista en cuadrícula',
                    ),
                    _BoardControlOption(
                      value: BoardViewMode.list,
                      label: 'Lista',
                      icon: Icons.view_list_rounded,
                      tooltip: 'Vista de lista compacta',
                    ),
                  ],
                  showIcons: true,
                ),
              ),
            ],
          ),
        if (categoryCounts.isNotEmpty || assigneeFilters.isNotEmpty) ...[
          const SizedBox(height: 12),
          _CategoryFilterBar(
            counts: categoryCounts,
            selected: selectedCategory,
            onChanged: onCategoryChanged,
            assignees: assigneeFilters,
            selectedAssigneeUid: selectedAssigneeUid,
            onAssigneeChanged: onAssigneeChanged,
            onClear: onClearFilters,
            orderController: filterOrderController,
          ),
        ],
      ],
    );
  }
}

class _CategoryFilterBar extends StatelessWidget {
  const _CategoryFilterBar({
    required this.counts,
    required this.selected,
    required this.onChanged,
    required this.assignees,
    required this.selectedAssigneeUid,
    required this.onAssigneeChanged,
    required this.onClear,
    required this.orderController,
  });

  final Map<NoteCategory, int> counts;
  final NoteCategory? selected;
  final ValueChanged<NoteCategory?> onChanged;
  final List<_AssigneeFilterOption> assignees;
  final String? selectedAssigneeUid;
  final ValueChanged<String?> onAssigneeChanged;
  final VoidCallback onClear;
  final BoardFilterOrderController orderController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: orderController,
      builder: (context, _) {
        final assigneesById = {
          for (final assignee in assignees) assignee.uid: assignee,
        };
        final orderedAssignees = orderController
            .orderAssignees(assigneesById.keys)
            .map(assigneesById.newValue)
            .nonNulls
            .toList(growable: false);
        final orderedCategories = orderController.orderCategories(counts.keys);
        return Semantics(
          container: true,
          label: 'Filtros por persona responsable y categoría',
          child: SingleChildScrollView(
            key: const ValueKey('category-filter-bar'),
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                for (final entry in orderedAssignees.indexed) ...[
                  if (entry.$1 > 0) const SizedBox(width: 8),
                  _DraggableFilterChip(
                    key: ValueKey('assignee-filter-${entry.$2.uid}'),
                    data: _FilterDragData.assignee(entry.$2.uid),
                    previewLabel: entry.$2.displayName,
                    onReorder: (dragged) {
                      if (dragged.assigneeUid case final draggedUid?) {
                        unawaited(
                          orderController.moveAssignee(
                            draggedId: draggedUid,
                            targetId: entry.$2.uid,
                            availableIds: assigneesById.keys,
                          ),
                        );
                      }
                    },
                    child: _AssigneeFilterChip(
                      assignee: entry.$2,
                      selected: selectedAssigneeUid == entry.$2.uid,
                      onTap: () => onAssigneeChanged(
                        selectedAssigneeUid == entry.$2.uid
                            ? null
                            : entry.$2.uid,
                      ),
                    ),
                  ),
                ],
                for (final category in orderedCategories) ...[
                  if (orderedAssignees.isNotEmpty ||
                      category != orderedCategories.first)
                    const SizedBox(width: 8),
                  _DraggableFilterChip(
                    key: ValueKey('category-filter-${category.name}'),
                    data: _FilterDragData.category(category),
                    previewLabel: NoteCategoryStyle.label(category),
                    onReorder: (dragged) {
                      if (dragged.category case final draggedCategory?) {
                        unawaited(
                          orderController.moveCategory(
                            draggedCategory: draggedCategory,
                            targetCategory: category,
                            availableCategories: counts.keys,
                          ),
                        );
                      }
                    },
                    child: _CategoryFilterChip(
                      category: category,
                      count: counts[category]!,
                      selected: selected == category,
                      onTap: () =>
                          onChanged(selected == category ? null : category),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                _ClearCategoryFilterButton(
                  enabled: selected != null || selectedAssigneeUid != null,
                  onTap: onClear,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

extension on Map<String, _AssigneeFilterOption> {
  _AssigneeFilterOption? newValue(String key) => this[key];
}

enum _FilterDragGroup { assignee, category }

class _FilterDragData {
  const _FilterDragData.assignee(String uid)
    : group = _FilterDragGroup.assignee,
      assigneeUid = uid,
      category = null;

  const _FilterDragData.category(NoteCategory value)
    : group = _FilterDragGroup.category,
      assigneeUid = null,
      category = value;

  final _FilterDragGroup group;
  final String? assigneeUid;
  final NoteCategory? category;
}

class _DraggableFilterChip extends StatelessWidget {
  const _DraggableFilterChip({
    required this.data,
    required this.previewLabel,
    required this.onReorder,
    required this.child,
    super.key,
  });

  final _FilterDragData data;
  final String previewLabel;
  final ValueChanged<_FilterDragData> onReorder;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _boardControlMotionDuration;
    return DragTarget<_FilterDragData>(
      onWillAcceptWithDetails: (details) =>
          details.data.group == data.group && details.data != data,
      onAcceptWithDetails: (details) => onReorder(details.data),
      builder: (context, candidates, rejected) {
        final highlighted = candidates.any(
          (candidate) => candidate?.group == data.group,
        );
        return AnimatedScale(
          duration: duration,
          curve: Curves.easeOutCubic,
          scale: highlighted ? 1.05 : 1,
          child: Semantics(
            hint: 'Mantén presionado y arrastra para cambiar su posición',
            child: LongPressDraggable<_FilterDragData>(
              data: data,
              hapticFeedbackOnStart: true,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              feedback: _FilterDragPreview(label: previewLabel),
              childWhenDragging: Opacity(opacity: 0.35, child: child),
              child: MouseRegion(cursor: SystemMouseCursors.grab, child: child),
            ),
          ),
        );
      },
    );
  }
}

class _FilterDragPreview extends StatelessWidget {
  const _FilterDragPreview({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.58),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 16,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.drag_indicator_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssigneeFilterOption {
  const _AssigneeFilterOption({
    required this.uid,
    required this.displayName,
    required this.photoUrl,
    required this.count,
  });

  final String uid;
  final String displayName;
  final String? photoUrl;
  final int count;
}

class _AssigneeFilterChip extends StatelessWidget {
  const _AssigneeFilterChip({
    required this.assignee,
    required this.selected,
    required this.onTap,
  });

  final _AssigneeFilterOption assignee;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedForeground =
        ThemeData.estimateBrightnessForColor(colorScheme.primary) ==
            Brightness.dark
        ? Colors.white
        : Colors.black87;
    final foreground = selected
        ? selectedForeground
        : colorScheme.onSurface.withValues(alpha: 0.78);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _boardControlMotionDuration;
    final displayName = assignee.displayName.trim();
    final nameParts = displayName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    final firstName = nameParts.isEmpty ? 'Usuario' : nameParts.first;
    final initials = nameParts.isEmpty
        ? '?'
        : [
            String.fromCharCode(nameParts.first.runes.first),
            if (nameParts.length > 1)
              String.fromCharCode(nameParts.last.runes.first),
          ].join().toUpperCase();
    final photoUrl = assignee.photoUrl?.trim();

    return Semantics(
      button: true,
      selected: selected,
      label:
          '${assignee.displayName}, ${assignee.count} ${assignee.count == 1 ? 'nota pendiente asignada' : 'notas pendientes asignadas'}',
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        height: 36,
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.88)
              : colorScheme.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: selected ? 0.9 : 0.4),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            enableFeedback: false,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    key: ValueKey('assignee-filter-avatar-${assignee.uid}'),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: selected
                          ? selectedForeground.withValues(alpha: 0.18)
                          : colorScheme.primary.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: photoUrl?.isNotEmpty == true
                        ? Image.network(
                            photoUrl!,
                            key: ValueKey(
                              'assignee-filter-photo-${assignee.uid}',
                            ),
                            cacheWidth: _avatarCacheSize(context, 24),
                            cacheHeight: _avatarCacheSize(context, 24),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Center(
                              child: Text(
                                initials,
                                style: TextStyle(
                                  color: foreground,
                                  fontSize: initials.length > 1 ? 9 : 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              initials,
                              style: TextStyle(
                                color: foreground,
                                fontSize: initials.length > 1 ? 9 : 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      firstName,
                      key: ValueKey('assignee-filter-name-${assignee.uid}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    key: ValueKey('assignee-filter-count-${assignee.uid}'),
                    constraints: const BoxConstraints(minWidth: 22),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? selectedForeground.withValues(alpha: 0.16)
                          : colorScheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '${assignee.count}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        height: 1,
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

class _ClearCategoryFilterButton extends StatelessWidget {
  const _ClearCategoryFilterButton({
    required this.enabled,
    required this.onTap,
  });

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _boardControlMotionDuration;
    return Tooltip(
      message: 'Limpiar filtros',
      child: Semantics(
        button: true,
        enabled: enabled,
        label: 'Limpiar filtros',
        child: AnimatedOpacity(
          duration: duration,
          opacity: enabled ? 1 : 0.42,
          child: Material(
            key: const ValueKey('category-filter-clear-button'),
            color: enabled
                ? colorScheme.primary.withValues(alpha: 0.15)
                : colorScheme.surface.withValues(alpha: 0.72),
            shape: CircleBorder(
              side: BorderSide(
                color: enabled
                    ? colorScheme.primary.withValues(alpha: 0.48)
                    : colorScheme.outline.withValues(alpha: 0.28),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              enableFeedback: false,
              onTap: enabled ? onTap : null,
              child: SizedBox.square(
                dimension: 36,
                child: Icon(
                  Icons.close_rounded,
                  size: 19,
                  color: enabled
                      ? colorScheme.primary
                      : colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryFilterChip extends StatelessWidget {
  const _CategoryFilterChip({
    required this.category,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final NoteCategory category;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final categoryColor = NoteCategoryStyle.baseColor(category);
    final selectedForeground = NoteCategoryStyle.foregroundColor(category);
    final foreground = selected
        ? selectedForeground
        : colorScheme.onSurface.withValues(alpha: 0.78);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _boardControlMotionDuration;
    final label = NoteCategoryStyle.label(category);

    return Semantics(
      button: true,
      selected: selected,
      label:
          '$label, $count ${count == 1 ? 'nota pendiente' : 'notas pendientes'}',
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        height: 36,
        decoration: BoxDecoration(
          color: selected
              ? categoryColor.withValues(alpha: 0.9)
              : colorScheme.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? categoryColor.withValues(alpha: 0.95)
                : categoryColor.withValues(alpha: 0.42),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: categoryColor.withValues(alpha: 0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            enableFeedback: false,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 7, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    NoteCategoryStyle.icon(category),
                    size: 16,
                    color: selected ? selectedForeground : categoryColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Container(
                    key: ValueKey('category-filter-count-${category.name}'),
                    constraints: const BoxConstraints(minWidth: 22),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? selectedForeground.withValues(alpha: 0.16)
                          : categoryColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '$count',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    Icons.drag_indicator_rounded,
                    size: 14,
                    color: foreground.withValues(alpha: 0.72),
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

class _CollaboratorAvatarStack extends StatefulWidget {
  const _CollaboratorAvatarStack({required this.collaborators});

  static const _avatarSize = 28.0;
  static const _visibleWidth = 18.0;
  static const _maxVisibleAvatars = 3;

  final List<ListCollaborator> collaborators;

  @override
  State<_CollaboratorAvatarStack> createState() =>
      _CollaboratorAvatarStackState();
}

class _CollaboratorAvatarStackState extends State<_CollaboratorAvatarStack>
    with SingleTickerProviderStateMixin {
  static const _floatDuration = Duration(milliseconds: 4200);
  static const _restDuration = Duration(milliseconds: 180);

  late final AnimationController _floatController = AnimationController(
    vsync: this,
    duration: _floatDuration,
  )..addStatusListener(_handleAnimationStatus);
  Timer? _restartTimer;
  bool? _reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    _restartTimer?.cancel();

    if (reduceMotion) {
      _floatController
        ..stop()
        ..value = 0;
    } else {
      _floatController.forward(from: 0);
    }
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _reduceMotion != false) return;
    _restartTimer?.cancel();
    _restartTimer = Timer(_restDuration, () {
      if (mounted && _reduceMotion == false) {
        _floatController.forward(from: 0);
      }
    });
  }

  @override
  void dispose() {
    _restartTimer?.cancel();
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleCollaborators = widget.collaborators
        .take(_CollaboratorAvatarStack._maxVisibleAvatars)
        .toList(growable: false);
    final width =
        _CollaboratorAvatarStack._avatarSize +
        (_CollaboratorAvatarStack._visibleWidth *
            (visibleCollaborators.length - 1));
    final colorScheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      label: 'Personas involucradas: ${widget.collaborators.length}',
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _floatController,
          builder: (context, _) {
            final easedProgress = Curves.easeInOutSine.transform(
              _floatController.value,
            );
            final orbit = easedProgress * math.pi * 2;
            return SizedBox(
              key: const ValueKey('collaborator-avatar-stack'),
              width: width,
              height: _CollaboratorAvatarStack._avatarSize,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final indexed in visibleCollaborators.indexed)
                    Positioned(
                      left: indexed.$1 * _CollaboratorAvatarStack._visibleWidth,
                      child: _FloatingCollaboratorAvatar(
                        index: indexed.$1,
                        orbit: orbit,
                        reduceMotion: reduceMotion,
                        colorScheme: colorScheme,
                        person: indexed.$2,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FloatingCollaboratorAvatar extends StatelessWidget {
  const _FloatingCollaboratorAvatar({
    required this.index,
    required this.orbit,
    required this.reduceMotion,
    required this.colorScheme,
    required this.person,
  });

  final int index;
  final double orbit;
  final bool reduceMotion;
  final ColorScheme colorScheme;
  final ListCollaborator person;

  @override
  Widget build(BuildContext context) {
    final phase = index * 2.05;
    final verticalTravel = 1.8 + ((index % 3) * 0.4);
    final horizontalTravel = 0.45 + ((index % 2) * 0.25);
    final floatOffset = reduceMotion
        ? Offset.zero
        : Offset(
            math.cos(orbit + phase) * horizontalTravel,
            math.sin(orbit + phase) * verticalTravel,
          );
    final rotation = reduceMotion
        ? 0.0
        : math.sin(orbit + phase + (math.pi / 3)) * 0.016;
    final scale = reduceMotion ? 1.0 : 1 + (math.cos(orbit + phase) * 0.012);

    return Transform.translate(
      key: ValueKey('collaborator-avatar-float-$index'),
      offset: floatOffset,
      child: Transform.rotate(
        angle: rotation,
        child: Transform.scale(
          scale: scale,
          child: Container(
            width: _CollaboratorAvatarStack._avatarSize,
            height: _CollaboratorAvatarStack._avatarSize,
            padding: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.18),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _CollaboratorAvatar(person: person),
          ),
        ),
      ),
    );
  }
}

class _BoardMetaChip extends StatelessWidget {
  const _BoardMetaChip({
    required this.icon,
    required this.label,
    required this.color,
    super.key,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color.withValues(alpha: 0.82)),
          const SizedBox(width: 6),
          Flexible(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween(begin: 0.92, end: 1.0).animate(animation),
                  child: child,
                ),
              ),
              child: Text(
                label,
                key: ValueKey(label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.68),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListMenuButton extends StatelessWidget {
  const _ListMenuButton({
    required this.onShare,
    required this.showShareInMenu,
    required this.hasInvitedCollaborators,
    required this.onCustomizeBackground,
    required this.onRenameList,
    required this.onToggleListProtection,
    required this.isListProtected,
    required this.onDeleteList,
    required this.isSaving,
  });

  final VoidCallback? onShare;
  final bool showShareInMenu;
  final bool hasInvitedCollaborators;
  final VoidCallback? onCustomizeBackground;
  final VoidCallback? onRenameList;
  final VoidCallback? onToggleListProtection;
  final bool isListProtected;
  final VoidCallback? onDeleteList;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopupMenuButton<_ListMenuAction>(
      key: const ValueKey('list-options-button'),
      tooltip: 'Opciones de la lista',
      enableFeedback: false,
      onOpened: _playBoardTapSound,
      padding: EdgeInsets.zero,
      enabled: !isSaving,
      elevation: 0,
      color: Colors.transparent,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      menuPadding: EdgeInsets.zero,
      clipBehavior: Clip.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 280),
      popUpAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: Duration(milliseconds: 180),
              reverseDuration: Duration(milliseconds: 140),
              curve: Curves.easeOutQuart,
              reverseCurve: Curves.easeInCubic,
            ),
      onSelected: (action) {
        switch (action) {
          case _ListMenuAction.share:
            onShare?.call();
          case _ListMenuAction.background:
            onCustomizeBackground?.call();
          case _ListMenuAction.rename:
            onRenameList?.call();
          case _ListMenuAction.protection:
            onToggleListProtection?.call();
          case _ListMenuAction.delete:
            onDeleteList?.call();
        }
      },
      itemBuilder: (context) => [
        _GlassListMenuEntry(
          showShare: showShareInMenu,
          hasInvitedCollaborators: hasInvitedCollaborators,
          backgroundEnabled: onCustomizeBackground != null,
          showRename: onRenameList != null,
          showProtection: onToggleListProtection != null,
          isListProtected: isListProtected,
          showDelete: onDeleteList != null,
        ),
      ],
      style: IconButton.styleFrom(
        minimumSize: const Size.square(36),
        fixedSize: const Size.square(36),
        backgroundColor: colorScheme.primary.withValues(alpha: 0.13),
        foregroundColor: colorScheme.primary,
      ),
      icon: isSaving
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.more_vert_rounded, size: 20),
    );
  }
}

class _GlassListMenuEntry extends PopupMenuEntry<_ListMenuAction> {
  const _GlassListMenuEntry({
    required this.showShare,
    required this.hasInvitedCollaborators,
    required this.backgroundEnabled,
    required this.showRename,
    required this.showProtection,
    required this.isListProtected,
    required this.showDelete,
  });

  final bool showShare;
  final bool hasInvitedCollaborators;
  final bool backgroundEnabled;
  final bool showRename;
  final bool showProtection;
  final bool isListProtected;
  final bool showDelete;

  int get itemCount =>
      1 +
      (showShare ? 1 : 0) +
      (showRename ? 1 : 0) +
      (showProtection ? 1 : 0) +
      (showDelete ? 1 : 0);

  @override
  double get height => 28 + (itemCount * 62);

  @override
  bool represents(_ListMenuAction? value) => false;

  @override
  State<_GlassListMenuEntry> createState() => _GlassListMenuEntryState();
}

class _GlassListMenuEntryState extends State<_GlassListMenuEntry> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final platform = Theme.of(context).platform;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(26);
    return SizedBox(
      width: 280,
      height: widget.height,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.28),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: RepaintBoundary(
            key: const ValueKey('list-options-glass-repaint-boundary'),
            child: ClipRRect(
              key: const ValueKey('list-options-glass-menu'),
              borderRadius: borderRadius,
              child: BackdropFilter(
                key: const ValueKey('list-options-glass-blur'),
                filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: DecoratedBox(
                  key: const ValueKey('list-options-glass-surface'),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: isDark ? 0.14 : 0.54),
                        colorScheme.surface.withValues(
                          alpha: isDark ? 0.58 : 0.62,
                        ),
                      ],
                    ),
                    borderRadius: borderRadius,
                    border: Border.all(
                      color: Colors.white.withValues(
                        alpha: isDark ? 0.2 : 0.62,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.showShare)
                          _GlassListMenuTile(
                            key: const ValueKey('invite-list-menu-item'),
                            icon: Icons.person_add_alt_1_rounded,
                            label: widget.hasInvitedCollaborators
                                ? 'Personas de la lista'
                                : 'Invitar personas',
                            onTap: () => Navigator.of(
                              context,
                            ).pop(_ListMenuAction.share),
                          ),
                        _GlassListMenuTile(
                          key: const ValueKey('customize-background-menu-item'),
                          icon: Icons.wallpaper_rounded,
                          label: 'Cambiar fondo',
                          enabled: widget.backgroundEnabled,
                          onTap: () => Navigator.of(
                            context,
                          ).pop(_ListMenuAction.background),
                        ),
                        if (widget.showRename)
                          _GlassListMenuTile(
                            key: const ValueKey('rename-list-menu-item'),
                            icon: Icons.edit_outlined,
                            label: 'Editar nombre',
                            onTap: () => Navigator.of(
                              context,
                            ).pop(_ListMenuAction.rename),
                          ),
                        if (widget.showProtection)
                          _GlassListMenuTile(
                            key: const ValueKey('protect-list-menu-item'),
                            icon: widget.isListProtected
                                ? Icons.lock_open_rounded
                                : listBiometricIcon(platform),
                            label: widget.isListProtected
                                ? 'Quitar protección biométrica'
                                : 'Proteger con ${listBiometricMethodLabel(platform)}',
                            onTap: () => Navigator.of(
                              context,
                            ).pop(_ListMenuAction.protection),
                          ),
                        if (widget.showDelete)
                          _GlassListMenuTile(
                            key: const ValueKey('delete-list-menu-item'),
                            icon: Icons.delete_outline_rounded,
                            label: 'Eliminar lista',
                            color: colorScheme.error,
                            onTap: () => Navigator.of(
                              context,
                            ).pop(_ListMenuAction.delete),
                          ),
                      ],
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

class _GlassListMenuTile extends StatelessWidget {
  const _GlassListMenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.color,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = enabled
        ? color ?? colorScheme.onSurface
        : colorScheme.onSurface.withValues(alpha: 0.34);
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            height: 62,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: foreground.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(icon, size: 21, color: foreground),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
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

class _BoardControlOption<T> {
  const _BoardControlOption({
    required this.value,
    required this.label,
    required this.icon,
    this.selectedIcon,
    this.tooltip,
  });

  final T value;
  final String label;
  final IconData icon;
  final IconData? selectedIcon;
  final String? tooltip;
}

class _GlassSelectorSurface extends StatelessWidget {
  const _GlassSelectorSurface({
    required this.borderRadius,
    required this.padding,
    required this.child,
    this.blurKey,
  });

  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final Widget child;
  final Key? blurKey;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final useBackdropBlur =
        Theme.of(context).platform != TargetPlatform.android;
    final surface = DecoratedBox(
      key: useBackdropBlur ? null : blurKey,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(
              alpha: isDark
                  ? 0.12
                  : useBackdropBlur
                  ? 0.42
                  : 0.72,
            ),
            colorScheme.surface.withValues(
              alpha: isDark
                  ? 0.64
                  : useBackdropBlur
                  ? 0.46
                  : 0.7,
            ),
          ],
        ),
        borderRadius: borderRadius,
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.16 : 0.5),
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.14),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: useBackdropBlur
                    ? BackdropFilter(
                        key: blurKey,
                        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: surface,
                      )
                    : surface,
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

class _SlidingSelectorHighlight extends StatelessWidget {
  const _SlidingSelectorHighlight({
    required this.keyPrefix,
    required this.selectedIndex,
    required this.itemCount,
    required this.size,
    required this.color,
    required this.borderRadius,
  });

  final String keyPrefix;
  final int selectedIndex;
  final int itemCount;
  final Size size;
  final Color color;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final alignment = itemCount <= 1
        ? Alignment.center
        : Alignment(-1 + (2 * selectedIndex / (itemCount - 1)), 0);
    return AnimatedAlign(
      key: ValueKey('$keyPrefix-selection-indicator'),
      duration: reduceMotion ? Duration.zero : _boardSelectorSlideDuration,
      curve: Curves.easeInOutCubic,
      alignment: alignment,
      child: SizedBox.fromSize(
        size: size,
        child: DecoratedBox(
          key: ValueKey('$keyPrefix-selection-pill'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: isDark ? 0.88 : 0.82),
                color.withValues(alpha: isDark ? 0.72 : 0.66),
              ],
            ),
            borderRadius: borderRadius,
            border: Border.all(
              color: Colors.white.withValues(alpha: isDark ? 0.26 : 0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.22),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactBoardControls extends StatelessWidget {
  const _CompactBoardControls({
    required this.filter,
    required this.viewMode,
    required this.onFilterChanged,
    required this.onViewModeChanged,
  });

  final NoteFilter filter;
  final BoardViewMode viewMode;
  final ValueChanged<NoteFilter> onFilterChanged;
  final ValueChanged<BoardViewMode> onViewModeChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _CompactIconSelector<NoteFilter>(
            key: const ValueKey('compact-filter-selector'),
            keyPrefix: 'filter-mode',
            selected: filter,
            selectedColor: colorScheme.primary,
            onChanged: onFilterChanged,
            options: const [
              _BoardControlOption(
                value: NoteFilter.all,
                label: 'Todas',
                icon: Icons.dashboard_outlined,
                selectedIcon: Icons.dashboard_rounded,
              ),
              _BoardControlOption(
                value: NoteFilter.pending,
                label: 'Pend.',
                tooltip: 'Pendientes',
                icon: Icons.schedule_rounded,
              ),
              _BoardControlOption(
                value: NoteFilter.completed,
                label: 'Hechas',
                tooltip: 'Completadas',
                icon: Icons.check_circle_outline_rounded,
                selectedIcon: Icons.check_circle_rounded,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _CompactIconSelector<BoardViewMode>(
            key: const ValueKey('compact-view-selector'),
            keyPrefix: 'view-mode',
            selected: viewMode,
            selectedColor: colorScheme.primary,
            onChanged: onViewModeChanged,
            options: const [
              _BoardControlOption(
                value: BoardViewMode.grid,
                label: 'Mosaico',
                tooltip: 'Vista en cuadrícula',
                icon: Icons.grid_view_rounded,
              ),
              _BoardControlOption(
                value: BoardViewMode.list,
                label: 'Lista',
                tooltip: 'Vista de lista compacta',
                icon: Icons.view_list_rounded,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CompactIconSelector<T extends Enum> extends StatelessWidget {
  const _CompactIconSelector({
    required this.keyPrefix,
    required this.options,
    required this.selected,
    required this.selectedColor,
    required this.onChanged,
    super.key,
  });

  final String keyPrefix;
  final List<_BoardControlOption<T>> options;
  final T selected;
  final Color selectedColor;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedIndex = options.indexWhere(
      (option) => option.value == selected,
    );
    final motionDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _boardControlMotionDuration;
    return SizedBox(
      height: 52,
      child: _GlassSelectorSurface(
        blurKey: ValueKey('$keyPrefix-glass-blur'),
        borderRadius: BorderRadius.circular(20),
        padding: const EdgeInsets.all(3),
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            fit: StackFit.expand,
            children: [
              _SlidingSelectorHighlight(
                keyPrefix: keyPrefix,
                selectedIndex: selectedIndex,
                itemCount: options.length,
                size: Size(
                  constraints.maxWidth / options.length,
                  constraints.maxHeight,
                ),
                color: selectedColor,
                borderRadius: BorderRadius.circular(17),
              ),
              Row(
                children: options.map((option) {
                  final isSelected = option.value == selected;
                  final selectedForeground =
                      ThemeData.estimateBrightnessForColor(selectedColor) ==
                          Brightness.dark
                      ? Colors.white
                      : Colors.black87;
                  final foreground = isSelected
                      ? selectedForeground
                      : colorScheme.onSurface.withValues(alpha: 0.7);
                  return Expanded(
                    child: Tooltip(
                      message: option.tooltip ?? option.label,
                      child: Semantics(
                        button: true,
                        selected: isSelected,
                        label: option.tooltip ?? option.label,
                        child: AnimatedContainer(
                          key: ValueKey('$keyPrefix-${option.value.name}'),
                          duration: motionDuration,
                          curve: Curves.easeOutCubic,
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(17),
                              enableFeedback: false,
                              onTap: isSelected
                                  ? null
                                  : () => onChanged(option.value),
                              child: AnimatedScale(
                                key: ValueKey(
                                  '$keyPrefix-${option.value.name}-motion',
                                ),
                                scale: isSelected ? 1 : 0.96,
                                duration: motionDuration,
                                curve: Curves.easeOutBack,
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TweenAnimationBuilder<Color?>(
                                        duration: motionDuration,
                                        tween: ColorTween(end: foreground),
                                        builder: (context, color, child) =>
                                            Icon(
                                              isSelected
                                                  ? option.selectedIcon ??
                                                        option.icon
                                                  : option.icon,
                                              size: 18,
                                              color: color ?? foreground,
                                            ),
                                      ),
                                      const SizedBox(height: 3),
                                      AnimatedDefaultTextStyle(
                                        duration: motionDuration,
                                        curve: Curves.easeOutCubic,
                                        style: TextStyle(
                                          color: foreground,
                                          fontSize: 10,
                                          fontWeight: isSelected
                                              ? FontWeight.w900
                                              : FontWeight.w700,
                                          height: 1,
                                        ),
                                        child: Text(
                                          option.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.fade,
                                          softWrap: false,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoardControlGroup<T> extends StatelessWidget {
  const _BoardControlGroup({
    required this.keyPrefix,
    required this.options,
    required this.selected,
    required this.selectedColor,
    required this.onChanged,
    required this.showIcons,
    super.key,
  });

  final String keyPrefix;
  final List<_BoardControlOption<T>> options;
  final T selected;
  final Color selectedColor;
  final ValueChanged<T> onChanged;
  final bool showIcons;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = options.indexWhere(
      (option) => option.value == selected,
    );
    return SizedBox(
      height: 48,
      child: _GlassSelectorSurface(
        borderRadius: BorderRadius.circular(19),
        padding: const EdgeInsets.all(4),
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            fit: StackFit.expand,
            children: [
              _SlidingSelectorHighlight(
                keyPrefix: keyPrefix,
                selectedIndex: selectedIndex,
                itemCount: options.length,
                size: Size(
                  constraints.maxWidth / options.length,
                  constraints.maxHeight,
                ),
                color: selectedColor,
                borderRadius: BorderRadius.circular(13),
              ),
              Row(
                children: options
                    .map(
                      (option) => Expanded(
                        child: _BoardControlItem<T>(
                          option: option,
                          selected: option.value == selected,
                          selectedColor: selectedColor,
                          showIcon: showIcons,
                          onTap: () => onChanged(option.value),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoardControlItem<T> extends StatelessWidget {
  const _BoardControlItem({
    required this.option,
    required this.selected,
    required this.selectedColor,
    required this.showIcon,
    required this.onTap,
  });

  final _BoardControlOption<T> option;
  final bool selected;
  final Color selectedColor;
  final bool showIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final motionDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _boardControlMotionDuration;
    final foreground = selected
        ? (ThemeData.estimateBrightnessForColor(selectedColor) ==
                  Brightness.dark
              ? Colors.white
              : Colors.black87)
        : colorScheme.onSurface.withValues(alpha: 0.7);
    final item = Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: motionDuration,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            enableFeedback: false,
            onTap: selected ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: AnimatedScale(
                scale: selected ? 1 : 0.96,
                duration: motionDuration,
                curve: Curves.easeOutBack,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (showIcon) ...[
                      Icon(option.icon, size: 16, color: foreground),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: AnimatedDefaultTextStyle(
                        duration: motionDuration,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                        child: Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return option.tooltip == null
        ? item
        : Tooltip(message: option.tooltip!, child: item);
  }
}
