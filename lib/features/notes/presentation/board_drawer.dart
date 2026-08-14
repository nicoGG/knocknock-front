part of 'board_page.dart';

/// Navigation drawer, list shortcuts, and list reordering.

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({
    required this.lists,
    required this.selectedListId,
    required this.assignedToMeSelected,
    required this.pinnedSelected,
    required this.withReminderSelected,
    required this.isListProtected,
    required this.isSavingList,
    required this.onSelectList,
    required this.onShowAssignedToMe,
    required this.onShowPinned,
    required this.onShowWithReminder,
    required this.onReorderLists,
    required this.onCreateList,
    required this.onOpenProfile,
    required this.onOpenSettings,
    required this.favoriteListIds,
    required this.recentListIds,
    required this.onToggleFavorite,
    required this.assignedCount,
    required this.pinnedCount,
    required this.reminderCount,
  });

  final List<NoteList> lists;
  final String selectedListId;
  final bool assignedToMeSelected;
  final bool pinnedSelected;
  final bool withReminderSelected;
  final bool Function(String listId) isListProtected;
  final bool isSavingList;
  final ValueChanged<String> onSelectList;
  final VoidCallback onShowAssignedToMe;
  final VoidCallback onShowPinned;
  final VoidCallback onShowWithReminder;
  final VoidCallback onReorderLists;
  final VoidCallback onCreateList;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenSettings;
  final Set<String> favoriteListIds;
  final List<String> recentListIds;
  final Future<bool> Function(String) onToggleFavorite;
  final int assignedCount;
  final int pinnedCount;
  final int reminderCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final drawerWidth = (MediaQuery.sizeOf(context).width * 0.82).clamp(
      272.0,
      336.0,
    );
    final drawerRadius = BorderRadius.horizontal(right: Radius.circular(30));

    return Drawer(
      width: drawerWidth,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: drawerRadius),
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        key: const ValueKey('app-drawer-glass-blur'),
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          key: const ValueKey('app-drawer-glass-surface'),
          decoration: BoxDecoration(
            borderRadius: drawerRadius,
            border: Border(
              right: BorderSide(
                color: Colors.white.withValues(alpha: isDark ? 0.16 : 0.48),
              ),
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: isDark ? 0.08 : 0.38),
                colorScheme.surface.withValues(alpha: isDark ? 0.76 : 0.7),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.3),
                blurRadius: 34,
                offset: const Offset(12, 0),
              ),
            ],
          ),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 14, 16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withValues(
                                alpha: isDark ? 0.14 : 0.48,
                              ),
                              colorScheme.primary.withValues(alpha: 0.18),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(
                              alpha: isDark ? 0.16 : 0.42,
                            ),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: Image.asset(
                            'assets/branding/nocknock-logo.png',
                            width: 42,
                            height: 42,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'NockNock',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: _DrawerProfileSummary(
                    onTap: () {
                      Navigator.pop(context);
                      onOpenProfile();
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: _DrawerScopeShortcutButton(
                          key: const ValueKey('assigned-to-me-menu-button'),
                          selected: assignedToMeSelected,
                          icon: assignedToMeSelected
                              ? Icons.assignment_ind_rounded
                              : Icons.assignment_ind_outlined,
                          label: 'Asignado a mí',
                          count: assignedCount,
                          onTap: () {
                            Navigator.pop(context);
                            onShowAssignedToMe();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DrawerScopeShortcutButton(
                          key: const ValueKey('pinned-menu-button'),
                          selected: pinnedSelected,
                          icon: pinnedSelected
                              ? Icons.push_pin_rounded
                              : Icons.push_pin_outlined,
                          label: 'Ancladas',
                          count: pinnedCount,
                          onTap: () {
                            Navigator.pop(context);
                            onShowPinned();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DrawerScopeShortcutButton(
                          key: const ValueKey('with-reminder-menu-button'),
                          selected: withReminderSelected,
                          icon: withReminderSelected
                              ? Icons.alarm_rounded
                              : Icons.alarm_outlined,
                          label: 'Con recordatorio',
                          count: reminderCount,
                          onTap: () {
                            Navigator.pop(context);
                            onShowWithReminder();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _DrawerListShortcuts(
                  lists: lists,
                  favoriteIds: favoriteListIds,
                  recentIds: recentListIds,
                  onSelect: (id) {
                    Navigator.pop(context);
                    onSelectList(id);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
                  child: Row(
                    children: [
                      Text(
                        'LISTAS',
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.35,
                        ),
                      ),
                      const Spacer(),
                      _DrawerReorderListsButton(
                        enabled: !isSavingList && lists.length > 1,
                        onPressed: () {
                          Navigator.pop(context);
                          onReorderLists();
                        },
                      ),
                      const SizedBox(width: 4),
                      _DrawerAddListButton(
                        isSaving: isSavingList,
                        onPressed: () {
                          Navigator.pop(context);
                          onCreateList();
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Scrollbar(
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(10, 2, 10, 112),
                            itemCount: lists.length,
                            itemBuilder: (context, index) {
                              final list = lists[index];
                              final selected =
                                  !assignedToMeSelected &&
                                  !pinnedSelected &&
                                  !withReminderSelected &&
                                  list.id == selectedListId;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: _DrawerDestinationTile(
                                  key: ValueKey('list-${list.id}'),
                                  selected: selected,
                                  icon: selected
                                      ? Icons.folder_rounded
                                      : Icons.folder_outlined,
                                  label: list.name,
                                  trailing: selected
                                      ? isListProtected(list.id)
                                            ? Icons.lock_rounded
                                            : Icons.check_rounded
                                      : isListProtected(list.id)
                                      ? Icons.lock_outline_rounded
                                      : list.isShared
                                      ? Icons.people_outline_rounded
                                      : null,
                                  trailingTooltip: isListProtected(list.id)
                                      ? 'Lista protegida'
                                      : list.isShared && !selected
                                      ? 'Lista compartida'
                                      : null,
                                  trailingAction: IconButton(
                                    tooltip: favoriteListIds.contains(list.id)
                                        ? 'Quitar de favoritas'
                                        : 'Agregar a favoritas',
                                    onPressed: () async {
                                      final updated = await onToggleFavorite(
                                        list.id,
                                      );
                                      if (!updated && context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Puedes tener hasta 3 favoritas.',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    icon: Icon(
                                      favoriteListIds.contains(list.id)
                                          ? Icons.star_rounded
                                          : Icons.star_outline_rounded,
                                      color: favoriteListIds.contains(list.id)
                                          ? const Color(0xFFE4A528)
                                          : null,
                                    ),
                                  ),
                                  onTap: () {
                                    Navigator.pop(context);
                                    onSelectList(list.id);
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      _DrawerFloatingSettingsButton(
                        onTap: () {
                          Navigator.pop(context);
                          onOpenSettings();
                        },
                      ),
                    ],
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

class _DrawerFloatingSettingsButton extends StatelessWidget {
  const _DrawerFloatingSettingsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        key: const ValueKey('drawer-floating-settings-footer'),
        padding: const EdgeInsets.fromLTRB(10, 18, 10, 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.surface.withValues(alpha: 0),
              colorScheme.surface.withValues(alpha: isDark ? 0.94 : 0.97),
              colorScheme.surface.withValues(alpha: isDark ? 0.98 : 1),
            ],
            stops: const [0, 0.34, 1],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(
                  alpha: isDark ? 0.3 : 0.18,
                ),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DrawerDestinationTile(
                key: const ValueKey('settings-menu-button'),
                icon: Icons.settings_outlined,
                label: 'Configuración',
                trailing: Icons.chevron_right_rounded,
                onTap: onTap,
              ),
              const SizedBox(height: 10),
              const _AppVersionLabel(),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerListShortcuts extends StatefulWidget {
  const _DrawerListShortcuts({
    required this.lists,
    required this.favoriteIds,
    required this.recentIds,
    required this.onSelect,
  });
  final List<NoteList> lists;
  final Set<String> favoriteIds;
  final List<String> recentIds;
  final ValueChanged<String> onSelect;
  @override
  State<_DrawerListShortcuts> createState() => _DrawerListShortcutsState();
}

class _DrawerListShortcutsState extends State<_DrawerListShortcuts> {
  bool _favoritesExpanded = false;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final list in widget.lists) list.id: list};
    final favorites = widget.favoriteIds
        .where(byId.containsKey)
        .take(3)
        .toList();
    if (favorites.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (favorites.isNotEmpty) ...[
            InkWell(
              key: const ValueKey('favorite-lists-collapse-button'),
              onTap: () =>
                  setState(() => _favoritesExpanded = !_favoritesExpanded),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Expanded(
                      child: _ShortcutLabel(
                        label: 'FAVORITAS · HASTA 3',
                        icon: Icons.star_rounded,
                      ),
                    ),
                    Icon(
                      _favoritesExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            if (_favoritesExpanded)
              for (final id in favorites)
                _ShortcutListCard(
                  list: byId[id]!,
                  icon: Icons.star_rounded,
                  color: const Color(0xFFE4A528),
                  onTap: () => widget.onSelect(id),
                ),
          ],
        ],
      ),
    );
  }
}

class _ShortcutLabel extends StatelessWidget {
  const _ShortcutLabel({required this.label, required this.icon});
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 6),
      Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .52),
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.1,
        ),
      ),
    ],
  );
}

class _ShortcutListCard extends StatelessWidget {
  const _ShortcutListCard({
    required this.list,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final NoteList list;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: color),
    title: Text(list.name),
    onTap: onTap,
  );
}

class _ReorderListsSheet extends StatefulWidget {
  const _ReorderListsSheet({required this.lists, required this.selectedListId});

  final List<NoteList> lists;
  final String selectedListId;

  @override
  State<_ReorderListsSheet> createState() => _ReorderListsSheetState();
}

class _ReorderListsSheetState extends State<_ReorderListsSheet> {
  late final List<NoteList> _lists = List.of(widget.lists);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxHeight = math.min(MediaQuery.sizeOf(context).height * 0.72, 620.0);
    const borderRadius = BorderRadius.vertical(top: Radius.circular(32));
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: isDark ? 0.5 : 0.3),
            blurRadius: 40,
            offset: const Offset(0, -8),
          ),
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.1),
            blurRadius: 32,
          ),
        ],
      ),
      child: ClipRRect(
        key: const ValueKey('reorder-lists-sheet'),
        borderRadius: borderRadius,
        child: BackdropFilter(
          key: const ValueKey('reorder-lists-glass-blur'),
          filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: DecoratedBox(
            key: const ValueKey('reorder-lists-glass-surface'),
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              border: Border.all(
                color: Colors.white.withValues(alpha: isDark ? 0.2 : 0.58),
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: isDark ? 0.13 : 0.52),
                  colorScheme.surface.withValues(alpha: isDark ? 0.66 : 0.62),
                ],
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: SizedBox(
                height: maxHeight,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.onSurface.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 18, 14, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ordenar listas',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Mantén presionado el control y arrastra.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colorScheme.onSurface.withValues(
                                          alpha: 0.6,
                                        ),
                                      ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white.withValues(
                                alpha: isDark ? 0.08 : 0.38,
                              ),
                              side: BorderSide(
                                color: Colors.white.withValues(
                                  alpha: isDark ? 0.12 : 0.5,
                                ),
                              ),
                            ),
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ReorderableListView.builder(
                        key: const ValueKey('reorder-lists-view'),
                        buildDefaultDragHandles: false,
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                        itemCount: _lists.length,
                        proxyDecorator: (child, index, animation) => Material(
                          color: Colors.transparent,
                          elevation: 10,
                          shadowColor: colorScheme.shadow.withValues(
                            alpha: 0.28,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          child: child,
                        ),
                        onReorderItem: (oldIndex, newIndex) {
                          if (newIndex == oldIndex) return;
                          HapticFeedback.selectionClick();
                          setState(() {
                            final list = _lists.removeAt(oldIndex);
                            _lists.insert(newIndex, list);
                          });
                        },
                        itemBuilder: (context, index) {
                          final list = _lists[index];
                          final selected = list.id == widget.selectedListId;
                          return Padding(
                            key: ValueKey('reorder-list-item-${list.id}'),
                            padding: const EdgeInsets.only(bottom: 8),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: selected
                                      ? [
                                          colorScheme.primary.withValues(
                                            alpha: 0.2,
                                          ),
                                          colorScheme.primary.withValues(
                                            alpha: 0.08,
                                          ),
                                        ]
                                      : [
                                          Colors.white.withValues(
                                            alpha: isDark ? 0.08 : 0.44,
                                          ),
                                          colorScheme.surfaceContainerHigh
                                              .withValues(
                                                alpha: isDark ? 0.26 : 0.3,
                                              ),
                                        ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: selected
                                      ? colorScheme.primary.withValues(
                                          alpha: 0.3,
                                        )
                                      : colorScheme.outlineVariant.withValues(
                                          alpha: 0.55,
                                        ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  8,
                                  12,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      selected
                                          ? Icons.folder_rounded
                                          : Icons.folder_outlined,
                                      color: selected
                                          ? colorScheme.primary
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        list.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: selected
                                              ? FontWeight.w800
                                              : FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    if (list.isShared)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 4,
                                        ),
                                        child: Icon(
                                          Icons.people_outline_rounded,
                                          size: 19,
                                          color: colorScheme.onSurface
                                              .withValues(alpha: 0.55),
                                        ),
                                      ),
                                    ReorderableDragStartListener(
                                      key: ValueKey(
                                        'reorder-list-handle-${list.id}',
                                      ),
                                      index: index,
                                      child: Semantics(
                                        label: 'Mover ${list.name}',
                                        button: true,
                                        child: Padding(
                                          padding: const EdgeInsets.all(10),
                                          child: Icon(
                                            Icons.drag_handle_rounded,
                                            color: colorScheme.onSurface
                                                .withValues(alpha: 0.62),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            colorScheme.surface.withValues(alpha: 0),
                            colorScheme.surface.withValues(
                              alpha: isDark ? 0.22 : 0.18,
                            ),
                          ],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(54),
                                  foregroundColor: colorScheme.onSurface,
                                  side: BorderSide(
                                    color: Colors.white.withValues(
                                      alpha: isDark ? 0.34 : 0.72,
                                    ),
                                  ),
                                  shape: const StadiumBorder(),
                                ),
                                onPressed: () => Navigator.pop(context),
                                child: const Text(
                                  'Cancelar',
                                  maxLines: 1,
                                  softWrap: false,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 6,
                              child: FilledButton.icon(
                                key: const ValueKey('save-list-order-button'),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(54),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                  ),
                                  shape: const StadiumBorder(),
                                ),
                                onPressed: () => Navigator.pop(
                                  context,
                                  _lists.map((list) => list.id).toList(),
                                ),
                                icon: const Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 20,
                                ),
                                label: const Text(
                                  'Guardar orden',
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.fade,
                                ),
                              ),
                            ),
                          ],
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
  }
}

class _AppVersionLabel extends StatefulWidget {
  const _AppVersionLabel();

  @override
  State<_AppVersionLabel> createState() => _AppVersionLabelState();
}

class _AppVersionLabelState extends State<_AppVersionLabel> {
  late final Future<String> _version = _loadVersion();

  Future<String> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final buildSuffix = info.buildNumber.isEmpty
          ? ''
          : ' (${info.buildNumber})';
      return 'Versión ${info.version}$buildSuffix';
    } catch (_) {
      return 'Versión 1.0.0 (1)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FutureBuilder<String>(
      future: _version,
      builder: (context, snapshot) => Text(
        snapshot.data ?? 'Versión 1.0.0',
        key: const ValueKey('app-version-label'),
        style: TextStyle(
          color: colorScheme.onSurface.withValues(alpha: 0.38),
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.35,
        ),
      ),
    );
  }
}

class _DrawerProfileSummary extends StatelessWidget {
  const _DrawerProfileSummary({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<AuthRepository>();
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(22);

    return StreamBuilder<AppUser?>(
      stream: repository.authStateChanges,
      initialData: repository.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        return DecoratedBox(
          key: user == null
              ? const ValueKey('drawer-google-sign-in-suggestion')
              : null,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.16),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: BackdropFilter(
              key: const ValueKey('drawer-profile-glass-blur'),
              filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Material(
                color: Colors.transparent,
                child: Ink(
                  key: const ValueKey('drawer-profile-glass-surface'),
                  decoration: BoxDecoration(
                    borderRadius: borderRadius,
                    border: Border.all(
                      color: Colors.white.withValues(
                        alpha: isDark ? 0.14 : 0.42,
                      ),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: isDark ? 0.1 : 0.34),
                        colorScheme.surfaceContainerHigh.withValues(
                          alpha: isDark ? 0.5 : 0.42,
                        ),
                      ],
                    ),
                  ),
                  child: InkWell(
                    key: const ValueKey('drawer-profile-button'),
                    borderRadius: borderRadius,
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
                      child: Row(
                        children: [
                          AuthAvatar(user: user, size: 46),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user?.displayName ??
                                      'Inicia sesión con Google',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  user?.email ??
                                      'Sincroniza y protege tus notas',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.62,
                                    ),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: colorScheme.surface.withValues(
                                alpha: isDark ? 0.26 : 0.42,
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(
                                  alpha: isDark ? 0.1 : 0.3,
                                ),
                              ),
                            ),
                            child: Icon(
                              user == null
                                  ? Icons.login_rounded
                                  : Icons.chevron_right_rounded,
                              size: 20,
                              color: user == null ? colorScheme.primary : null,
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
        );
      },
    );
  }
}

class _DrawerReorderListsButton extends StatelessWidget {
  const _DrawerReorderListsButton({
    required this.enabled,
    required this.onPressed,
  });

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      key: const ValueKey('reorder-lists-button'),
      tooltip: 'Reordenar listas',
      visualDensity: VisualDensity.compact,
      style: _drawerListActionButtonStyle(context),
      onPressed: enabled ? onPressed : null,
      icon: const Icon(Icons.swap_vert_rounded, size: 20),
    );
  }
}

ButtonStyle _drawerListActionButtonStyle(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;
  return IconButton.styleFrom(
    backgroundColor: colorScheme.primary.withValues(alpha: 0.16),
    foregroundColor: colorScheme.primary,
    side: BorderSide(
      color: Colors.white.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.14 : 0.4,
      ),
    ),
  );
}

class _DrawerAddListButton extends StatelessWidget {
  const _DrawerAddListButton({required this.isSaving, required this.onPressed});

  final bool isSaving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton.filledTonal(
      key: const ValueKey('add-list-button'),
      tooltip: 'Agregar lista',
      visualDensity: VisualDensity.compact,
      style: _drawerListActionButtonStyle(context),
      onPressed: isSaving ? null : onPressed,
      icon: isSaving
          ? SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            )
          : const Icon(Icons.add_rounded, size: 20),
    );
  }
}

class _DrawerDestinationTile extends StatelessWidget {
  const _DrawerDestinationTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.trailing,
    this.trailingTooltip,
    this.trailingAction,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final IconData? trailing;
  final String? trailingTooltip;
  final Widget? trailingAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = selected ? colorScheme.primary : colorScheme.onSurface;
    final trailingIcon = trailing == null
        ? null
        : Icon(trailing, size: 19, color: foreground.withValues(alpha: 0.78));

    final borderRadius = BorderRadius.circular(18);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: selected
            ? [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Material(
          color: Colors.transparent,
          child: Ink(
            key: selected ? const ValueKey('drawer-selected-tile-glass') : null,
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              border: Border.all(
                color: Colors.white.withValues(
                  alpha: selected
                      ? (isDark ? 0.18 : 0.46)
                      : (isDark ? 0.07 : 0.24),
                ),
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: selected
                    ? [
                        colorScheme.primary.withValues(
                          alpha: isDark ? 0.24 : 0.2,
                        ),
                        colorScheme.surface.withValues(
                          alpha: isDark ? 0.3 : 0.38,
                        ),
                      ]
                    : [
                        Colors.white.withValues(alpha: isDark ? 0.035 : 0.16),
                        colorScheme.surface.withValues(
                          alpha: isDark ? 0.12 : 0.18,
                        ),
                      ],
              ),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: borderRadius,
              child: SizedBox(
                height: 54,
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      width: 3,
                      height: selected ? 26 : 0,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Icon(icon, size: 22, color: foreground),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 15,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                    if (trailingAction != null)
                      trailingAction!
                    else if (trailingIcon != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: trailingTooltip == null
                            ? trailingIcon
                            : Tooltip(
                                message: trailingTooltip!,
                                child: trailingIcon,
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
  }
}

class _DrawerScopeShortcutButton extends StatelessWidget {
  const _DrawerScopeShortcutButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.selected,
    this.count = 0,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = selected ? colorScheme.primary : colorScheme.onSurface;
    final borderRadius = BorderRadius.circular(17);
    final animationDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);

    return Semantics(
      label: label,
      button: true,
      selected: selected,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: AnimatedContainer(
          duration: animationDuration,
          height: 54,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: Material(
              color: Colors.transparent,
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  border: Border.all(
                    color: selected
                        ? colorScheme.primary.withValues(
                            alpha: isDark ? 0.34 : 0.28,
                          )
                        : Colors.white.withValues(alpha: isDark ? 0.07 : 0.24),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: selected
                        ? [
                            colorScheme.primary.withValues(
                              alpha: isDark ? 0.24 : 0.2,
                            ),
                            colorScheme.surface.withValues(
                              alpha: isDark ? 0.3 : 0.38,
                            ),
                          ]
                        : [
                            Colors.white.withValues(
                              alpha: isDark ? 0.035 : 0.16,
                            ),
                            colorScheme.surface.withValues(
                              alpha: isDark ? 0.12 : 0.18,
                            ),
                          ],
                  ),
                ),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: borderRadius,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(icon, size: 24, color: foreground),
                      Positioned(
                        right: 7,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: count == 0
                                ? colorScheme.onSurface.withValues(alpha: 0.18)
                                : colorScheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              color: count == 0
                                  ? colorScheme.onSurface.withValues(
                                      alpha: 0.72,
                                    )
                                  : colorScheme.onPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 6,
                        child: AnimatedContainer(
                          duration: animationDuration,
                          width: selected ? 18 : 0,
                          height: 3,
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(99),
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
      ),
    );
  }
}
