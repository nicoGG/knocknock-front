import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nocknock/core/input_formatters/initial_uppercase_text_formatter.dart';
import 'package:nocknock/core/theme/app_theme.dart';
import 'package:nocknock/core/theme/app_theme_controller.dart';
import 'package:nocknock/features/auth/data/auth_repository.dart';
import 'package:nocknock/features/auth/domain/app_user.dart';
import 'package:nocknock/features/auth/presentation/profile_page.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:nocknock/features/notes/logic/notes_state.dart';
import 'package:nocknock/features/notes/presentation/board_view_mode_controller.dart';
import 'package:nocknock/features/notes/presentation/note_detail_page.dart';
import 'package:nocknock/features/notes/presentation/widgets/board_loading_state.dart';
import 'package:nocknock/features/notes/presentation/widgets/list_background.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_editor_sheet.dart';
import 'package:nocknock/features/notes/presentation/widgets/post_it_card.dart';
import 'package:nocknock/features/notifications/domain/app_notification.dart';
import 'package:nocknock/features/notifications/logic/notifications_controller.dart';
import 'package:nocknock/features/notifications/presentation/notifications_page.dart';

enum NoteFilter { all, pending, completed }

enum _ListMenuAction { background, rename, delete }

class BoardPage extends StatefulWidget {
  const BoardPage({
    required this.themeController,
    required this.viewModeController,
    this.notificationsController,
    super.key,
  });

  final AppThemeController themeController;
  final BoardViewModeController viewModeController;
  final NotificationsController? notificationsController;

  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage>
    with SingleTickerProviderStateMixin {
  NoteFilter _filter = NoteFilter.all;
  bool _showAssignedToMe = false;
  late BoardViewMode _viewMode = widget.viewModeController.viewMode;
  StreamSubscription<Map<String, String>>? _notificationTapSubscription;
  late final AnimationController _entranceController;
  late final Animation<double> _headerOpacity;
  late final Animation<Offset> _headerSlide;
  late final Animation<double> _fabScale;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _headerOpacity = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0, 0.72, curve: Curves.easeOutCubic),
    );
    _headerSlide =
        Tween<Offset>(begin: const Offset(0, -0.055), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: const Interval(0, 0.78, curve: Curves.easeOutCubic),
          ),
        );
    _fabScale = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.42, 1, curve: Curves.easeOutBack),
    );
    _entranceController.forward();
    widget.viewModeController.addListener(_restoreViewMode);
    final notificationsController = widget.notificationsController;
    if (notificationsController != null) {
      _notificationTapSubscription = notificationsController.tapEvents.listen(
        (data) => _handleNotificationData(
          notificationsController.takePendingTap() ?? data,
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final pending = notificationsController.takePendingTap();
        if (pending != null) _handleNotificationData(pending);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _entranceController.value = 1;
    }
  }

  @override
  void dispose() {
    widget.viewModeController.removeListener(_restoreViewMode);
    unawaited(_notificationTapSubscription?.cancel());
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<NotesCubit, NotesState>(
      listenWhen: (previous, current) =>
          current.message != null && previous.message != current.message,
      listener: (context, state) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(state.message!)));
      },
      builder: (context, state) {
        final width = MediaQuery.sizeOf(context).width;
        final isCompact = width < 720;
        final notes = _filtered(state.notes);
        final colorScheme = Theme.of(context).colorScheme;
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: _AppBar(
            isConnected: state.isRealtimeConnected,
            onOpenProfile: _openProfile,
            notificationsController: widget.notificationsController,
            onOpenNotifications: _openNotifications,
          ),
          drawer: _AppDrawer(
            lists: state.lists,
            selectedListId: state.selectedListId,
            assignedToMeSelected: _showAssignedToMe,
            isSavingList: state.isSavingList,
            onSelectList: _selectList,
            onShowAssignedToMe: _openAssignedToMe,
            onCreateList: _createList,
            onOpenSettings: _openSettings,
          ),
          floatingActionButton: isCompact
              ? ScaleTransition(
                  scale: _fabScale,
                  child: FloatingActionButton.extended(
                    key: const ValueKey('new-note-fab'),
                    onPressed: state.isSaving ? null : () => _openEditor(),
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Nueva nota'),
                  ),
                )
              : null,
          body: ListBoardBackground(
            appearance:
                state.selectedList?.appearance ?? const ListAppearance(),
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isCompact ? 18 : 40,
                  isCompact ? 12 : 40,
                  isCompact ? 18 : 40,
                  12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FadeTransition(
                      opacity: _headerOpacity,
                      child: SlideTransition(
                        position: _headerSlide,
                        child: _BoardHeader(
                          title: _showAssignedToMe
                              ? 'Asignado a mí'
                              : state.selectedList?.name ?? 'Mis notas',
                          list: state.selectedList,
                          noteCount: state.notes.length,
                          filter: _filter,
                          viewMode: _viewMode,
                          onFilterChanged: (value) =>
                              setState(() => _filter = value),
                          onViewModeChanged: _changeViewMode,
                          onAdd: state.isSaving ? null : () => _openEditor(),
                          onShare: state.isInviting
                              ? null
                              : () => _openCollaborators(state.selectedList),
                          onCustomizeBackground: state.isSavingAppearance
                              ? null
                              : _openBackgroundPicker,
                          onRenameList:
                              state.isSavingList ||
                                  state.selectedList?.currentUserRole !=
                                      ListMemberRole.owner
                              ? null
                              : _renameList,
                          onDeleteList:
                              state.isSavingList ||
                                  state.selectedList?.currentUserRole !=
                                      ListMemberRole.owner
                              ? null
                              : _deleteList,
                          isSavingListOptions:
                              state.isSavingAppearance || state.isSavingList,
                          showAddButton: !isCompact,
                          isCompact: isCompact,
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Expanded(child: _content(state, notes)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _content(NotesState state, List<Note> notes) {
    if (state.status == NotesStatus.loading ||
        state.status == NotesStatus.initial) {
      return const BoardLoadingState();
    }
    if (state.status == NotesStatus.failure && state.notes.isEmpty) {
      return _MessageState(
        icon: Icons.cloud_off_rounded,
        title: 'No pudimos abrir el tablero',
        detail: 'Enciende el backend y vuelve a intentarlo.',
        actionLabel: 'Reintentar',
        onAction: context.read<NotesCubit>().load,
      );
    }
    if (notes.isEmpty) {
      return _MessageState(
        icon: Icons.sticky_note_2_outlined,
        title: _showAssignedToMe
            ? _filter == NoteFilter.all
                  ? 'No tienes notas asignadas en esta lista'
                  : 'No hay notas asignadas en este filtro'
            : _filter == NoteFilter.all
            ? 'Tu lista está lista'
            : 'No hay notas en este filtro',
        detail: _showAssignedToMe
            ? 'Cuando te asignen una nota, aparecerá aquí.'
            : _filter == NoteFilter.all
            ? 'Crea una nota y empieza a organizar lo que importa.'
            : 'Prueba otro filtro o crea una nota nueva.',
        actionLabel: !_showAssignedToMe && _filter == NoteFilter.all
            ? 'Crear primera nota'
            : null,
        onAction: !_showAssignedToMe && _filter == NoteFilter.all
            ? _openEditor
            : null,
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.025),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: switch (_viewMode) {
        BoardViewMode.grid => _NotesGrid(
          key: const ValueKey('notes-grid'),
          notes: notes,
          buildCard: _buildCard,
          onReorder: _reorderNotes,
        ),
        BoardViewMode.list => _NotesList(
          key: const ValueKey('notes-list'),
          notes: notes,
          layout: PostItCardLayout.compact,
          itemHeight: 112,
          maxWidth: 980,
          buildCard: _buildCard,
          onReorder: _reorderNotes,
        ),
        BoardViewMode.largeList => _NotesList(
          key: const ValueKey('notes-large-list'),
          notes: notes,
          layout: PostItCardLayout.large,
          itemHeight: 224,
          maxWidth: 1120,
          buildCard: _buildCard,
          onReorder: _reorderNotes,
        ),
      },
    );
  }

  Widget _buildCard(Note note, PostItCardLayout layout) {
    final selectedList = context.read<NotesCubit>().state.selectedList;
    final collaborators = selectedList?.collaborators ?? const [];
    final assignee = collaborators
        .where((person) => person.uid == note.assigneeUid)
        .firstOrNull;
    final normalizedAuthorName = note.authorName.trim().toLowerCase();
    final author = collaborators
        .where(
          (person) =>
              person.displayName.trim().toLowerCase() == normalizedAuthorName,
        )
        .firstOrNull;
    final currentUser = context.read<AuthRepository>().currentUser;
    final currentUserPhoto =
        currentUser?.displayName.trim().toLowerCase() == normalizedAuthorName
        ? currentUser?.photoUrl?.trim()
        : null;
    final collaboratorPhoto = author?.photoUrl?.trim();
    return PostItCard(
      note: note,
      layout: layout,
      assignee: assignee,
      authorPhotoUrl: currentUserPhoto?.isNotEmpty == true
          ? currentUserPhoto
          : collaboratorPhoto,
      onToggle: () {
        HapticFeedback.selectionClick();
        context.read<NotesCubit>().toggleNote(note);
      },
      onPin: () {
        HapticFeedback.lightImpact();
        context.read<NotesCubit>().togglePin(note);
      },
      onOpen: () => _openNote(note),
      onChecklistToggle: (item) {
        HapticFeedback.selectionClick();
        context.read<NotesCubit>().toggleChecklistItem(note, item);
      },
    );
  }

  List<Note> _filtered(List<Note> notes) {
    final statusFiltered = switch (_filter) {
      NoteFilter.all => notes,
      NoteFilter.pending => notes.where((note) => !note.isCompleted).toList(),
      NoteFilter.completed => notes.where((note) => note.isCompleted).toList(),
    };
    if (!_showAssignedToMe) return statusFiltered;
    final userId = context.read<AuthRepository>().currentUser?.id;
    return statusFiltered
        .where((note) => userId != null && note.assigneeUid == userId)
        .toList();
  }

  Future<void> _selectList(String listId) async {
    if (_showAssignedToMe) {
      setState(() => _showAssignedToMe = false);
    }
    await context.read<NotesCubit>().selectList(listId);
  }

  void _openAssignedToMe() {
    final authRepository = context.read<AuthRepository>();
    if (authRepository.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inicia sesión para ver las notas asignadas a ti.'),
        ),
      );
      _openProfile();
      return;
    }
    setState(() => _showAssignedToMe = true);
  }

  void _reorderNotes(List<String> orderedIds) {
    context.read<NotesCubit>().reorderVisibleNotes(orderedIds);
  }

  void _openNote(Note note) {
    final cubit = context.read<NotesCubit>();
    final currentUser = context.read<AuthRepository>().currentUser;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BlocProvider<NotesCubit>.value(
          value: cubit,
          child: NoteDetailPage(
            noteId: note.id,
            initialNote: note,
            listName: cubit.state.selectedList?.name ?? 'Mis notas',
            defaultAuthorName: currentUser?.displayName ?? note.authorName,
            currentUserId: currentUser?.id,
            currentUserPhotoUrl: currentUser?.photoUrl,
          ),
        ),
      ),
    );
  }

  Future<void> _openEditor([Note? note]) async {
    final assignees = context
        .read<NotesCubit>()
        .state
        .selectedList
        ?.collaborators;
    final draft = await showNoteEditor(
      context,
      note: note,
      defaultAuthorName:
          context.read<AuthRepository>().currentUser?.displayName ?? 'Invitado',
      assignees: assignees ?? const [],
    );
    if (draft == null || !mounted) return;
    final cubit = context.read<NotesCubit>();
    if (note == null) {
      await cubit.createNote(draft);
    } else {
      await cubit.editNote(note, draft);
    }
  }

  Future<void> _createList() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _CreateListDialog(),
    );
    if (name == null || !mounted) return;
    await context.read<NotesCubit>().createList(name);
  }

  Future<void> _openCollaborators(NoteList? list) async {
    if (list == null) return;
    final authRepository = context.read<AuthRepository>();
    if (authRepository.currentUser == null) {
      final openProfile = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Inicia sesión para compartir'),
          content: const Text(
            'Conecta tu cuenta de Google para invitar por correo y mantener '
            'la lista sincronizada entre todos los colaboradores.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Ahora no'),
            ),
            FilledButton.icon(
              key: const ValueKey('share-sign-in-button'),
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.login_rounded),
              label: const Text('Iniciar sesión'),
            ),
          ],
        ),
      );
      if (openProfile == true && mounted) _openProfile();
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (_) => BlocProvider<NotesCubit>.value(
        value: context.read<NotesCubit>(),
        child: _CollaboratorsDialog(initialList: list),
      ),
    );
  }

  Future<void> _openBackgroundPicker() async {
    final cubit = context.read<NotesCubit>();
    final list = cubit.state.selectedList;
    if (list == null) return;
    final appearance = await showListBackgroundPicker(
      context,
      initialAppearance: list.appearance,
    );
    if (appearance == null || !mounted) return;
    await cubit.updateListAppearance(appearance);
  }

  Future<void> _renameList() async {
    final cubit = context.read<NotesCubit>();
    final list = cubit.state.selectedList;
    if (list == null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _EditListNameDialog(initialName: list.name),
    );
    if (name == null || !mounted) return;
    await cubit.updateSelectedList(name);
  }

  Future<void> _deleteList() async {
    final cubit = context.read<NotesCubit>();
    final list = cubit.state.selectedList;
    if (list == null) return;
    final isOnlyList = cubit.state.lists.length == 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar lista'),
        content: Text(
          'Se eliminará “${list.name}” junto con todas sus notas. '
          'Esta acción no se puede deshacer.'
          '${isOnlyList ? ' Como es tu única lista, se creará una lista vacía para que puedas seguir usando NockNock.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-list-button'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar definitivamente'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await cubit.deleteSelectedList();
    }
  }

  void _openSettings() {
    final authRepository = context.read<AuthRepository>();
    final notesCubit = context.read<NotesCubit>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SettingsPage(
          authRepository: authRepository,
          themeController: widget.themeController,
          initialViewMode: _viewMode,
          onOpenProfile: _openProfile,
          onClearLocalData: notesCubit.clearLocalData,
          onViewModeChanged: _changeViewMode,
        ),
      ),
    );
  }

  void _restoreViewMode() {
    final restoredViewMode = widget.viewModeController.viewMode;
    if (mounted && _viewMode != restoredViewMode) {
      setState(() => _viewMode = restoredViewMode);
    }
  }

  void _changeViewMode(BoardViewMode value) {
    widget.viewModeController.setViewMode(value);
  }

  void _openProfile() {
    final authRepository = context.read<AuthRepository>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RepositoryProvider<AuthRepository>.value(
          value: authRepository,
          child: const ProfilePage(),
        ),
      ),
    );
  }

  Future<void> _openNotifications() async {
    final controller = widget.notificationsController;
    if (controller == null) return;
    final notification = await Navigator.of(context).push<AppNotification>(
      MaterialPageRoute<AppNotification>(
        builder: (_) => NotificationsPage(controller: controller),
      ),
    );
    if (notification != null && mounted) {
      await _handleNotificationData(notification.data);
    }
  }

  Future<void> _handleNotificationData(Map<String, String> data) async {
    if (!mounted) return;
    final boardId = data['boardId'];
    if (boardId == null || boardId.isEmpty) return;
    final cubit = context.read<NotesCubit>();
    if (cubit.state.lists.isEmpty &&
        (cubit.state.status == NotesStatus.initial ||
            cubit.state.status == NotesStatus.loading)) {
      await cubit.stream
          .firstWhere(
            (state) =>
                state.status == NotesStatus.ready ||
                state.status == NotesStatus.failure,
          )
          .timeout(const Duration(seconds: 10), onTimeout: () => cubit.state);
    }
    if (!mounted) return;
    await cubit.selectList(boardId);
    if (!mounted) return;
    final noteId = data['noteId'];
    if (noteId == null || noteId.isEmpty) return;
    for (final note in cubit.state.notes) {
      if (note.id == noteId) {
        _openNote(note);
        return;
      }
    }
  }
}

typedef NoteCardBuilder = Widget Function(Note note, PostItCardLayout layout);
typedef NoteReorderCallback = void Function(List<String> orderedIds);

class _NotesGrid extends StatelessWidget {
  const _NotesGrid({
    required this.notes,
    required this.buildCard,
    required this.onReorder,
    super.key,
  });

  final List<Note> notes;
  final NoteCardBuilder buildCard;
  final NoteReorderCallback onReorder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 720;
        return GridView.builder(
          padding: const EdgeInsets.only(bottom: 96),
          gridDelegate: isCompact
              ? const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.86,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                )
              : const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 330,
                  mainAxisExtent: 270,
                  crossAxisSpacing: 22,
                  mainAxisSpacing: 22,
                ),
          itemCount: notes.length,
          itemBuilder: (context, index) {
            final note = notes[index];
            return _NoteEntrance(
              key: ValueKey('note-entrance-${note.id}'),
              index: index,
              child: _DraggableGridNote(
                key: ValueKey('reorder-grid-${note.id}'),
                note: note,
                onDrop: (draggedId) {
                  final reordered = [...notes];
                  final oldIndex = reordered.indexWhere(
                    (item) => item.id == draggedId,
                  );
                  if (oldIndex == -1 || oldIndex == index) return;
                  final moved = reordered.removeAt(oldIndex);
                  final targetIndex = reordered.indexWhere(
                    (item) => item.id == note.id,
                  );
                  reordered.insert(targetIndex, moved);
                  onReorder(reordered.map((item) => item.id).toList());
                },
                child: buildCard(note, PostItCardLayout.grid),
              ),
            );
          },
        );
      },
    );
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
            hint: 'Mantén presionada y arrastra para cambiar el orden',
            child: LongPressDraggable<String>(
              data: widget.note.id,
              delay: const Duration(milliseconds: 350),
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
    required this.layout,
    required this.itemHeight,
    required this.maxWidth,
    required this.buildCard,
    required this.onReorder,
    super.key,
  });

  final List<Note> notes;
  final PostItCardLayout layout;
  final double itemHeight;
  final double maxWidth;
  final NoteCardBuilder buildCard;
  final NoteReorderCallback onReorder;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: notes.length,
      buildDefaultDragHandles: false,
      proxyDecorator: (child, index, animation) => AnimatedBuilder(
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
      ),
      onReorderStart: (_) => HapticFeedback.mediumImpact(),
      onReorderItem: (oldIndex, newIndex) {
        if (oldIndex == newIndex) return;
        final reordered = [...notes];
        final moved = reordered.removeAt(oldIndex);
        reordered.insert(newIndex, moved);
        onReorder(reordered.map((note) => note.id).toList());
      },
      itemBuilder: (context, index) {
        final note = notes[index];
        return ReorderableDelayedDragStartListener(
          key: ValueKey('reorder-list-${note.id}'),
          index: index,
          child: Semantics(
            hint: 'Mantén presionada y arrastra para cambiar el orden',
            child: _NoteEntrance(
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
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
      },
    );
  }
}

class _NoteEntrance extends StatelessWidget {
  const _NoteEntrance({required this.index, required this.child, super.key});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final staggerIndex = index.clamp(0, 7);
    final delay = staggerIndex * 42;
    final totalDuration = 390 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: totalDuration),
      curve: Interval(delay / totalDuration, 1, curve: Curves.easeOutCubic),
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
      child: child,
    );
  }
}

class _AppBar extends StatelessWidget implements PreferredSizeWidget {
  const _AppBar({
    required this.isConnected,
    required this.onOpenProfile,
    required this.onOpenNotifications,
    this.notificationsController,
  });

  final bool isConnected;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenNotifications;
  final NotificationsController? notificationsController;

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) {
    final repository = context.read<AuthRepository>();
    return AppBar(
      toolbarHeight: 72,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      actions: [
        _AnimatedConnectionIndicator(isConnected: isConnected),
        const SizedBox(width: 4),
        if (notificationsController case final controller?)
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => IconButton(
              key: const ValueKey('notifications-button'),
              tooltip: controller.unreadCount == 0
                  ? 'Notificaciones'
                  : '${controller.unreadCount} notificaciones sin leer',
              onPressed: onOpenNotifications,
              icon: Badge(
                isLabelVisible: controller.unreadCount > 0,
                label: Text(
                  controller.unreadCount > 99
                      ? '99+'
                      : '${controller.unreadCount}',
                ),
                child: const Icon(Icons.notifications_none_rounded),
              ),
            ),
          ),
        if (notificationsController != null) const SizedBox(width: 2),
        StreamBuilder<AppUser?>(
          stream: repository.authStateChanges,
          initialData: repository.currentUser,
          builder: (context, snapshot) => Padding(
            padding: const EdgeInsets.only(right: 16),
            child: IconButton(
              key: const ValueKey('profile-avatar-button'),
              tooltip: 'Abrir perfil',
              onPressed: onOpenProfile,
              icon: AuthAvatar(user: snapshot.data),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnimatedConnectionIndicator extends StatelessWidget {
  const _AnimatedConnectionIndicator({required this.isConnected});

  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    final color = isConnected
        ? const Color(0xFF2C9B4A)
        : const Color(0xFFD34242);
    final label = isConnected ? 'Conectado' : 'Sin conexión';

    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: TweenAnimationBuilder<double>(
          key: ValueKey(isConnected),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            final progress = value.clamp(0.0, 1.0);
            return Transform.scale(
              scale: 0.72 + (progress * 0.28),
              child: Opacity(opacity: 0.45 + (progress * 0.55), child: child),
            );
          },
          child: Container(
            key: ValueKey(
              isConnected
                  ? 'connected-status-indicator'
                  : 'disconnected-status-indicator',
            ),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isConnected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              color: color,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({
    required this.lists,
    required this.selectedListId,
    required this.assignedToMeSelected,
    required this.isSavingList,
    required this.onSelectList,
    required this.onShowAssignedToMe,
    required this.onCreateList,
    required this.onOpenSettings,
  });

  final List<NoteList> lists;
  final String selectedListId;
  final bool assignedToMeSelected;
  final bool isSavingList;
  final ValueChanged<String> onSelectList;
  final VoidCallback onShowAssignedToMe;
  final VoidCallback onCreateList;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: Image.asset(
                      'assets/branding/nocknock-logo.png',
                      width: 44,
                      height: 44,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'NockNock',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: ProfileCard(),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ListTile(
                key: const ValueKey('assigned-to-me-menu-button'),
                selected: assignedToMeSelected,
                selectedTileColor: AppTheme.accent.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: Icon(
                  assignedToMeSelected
                      ? Icons.assignment_ind_rounded
                      : Icons.assignment_ind_outlined,
                  color: assignedToMeSelected ? AppTheme.accent : null,
                ),
                title: Text(
                  'Asignado a mí',
                  style: TextStyle(
                    fontWeight: assignedToMeSelected
                        ? FontWeight.w800
                        : FontWeight.w700,
                  ),
                ),
                trailing: assignedToMeSelected
                    ? const Icon(Icons.check_rounded, size: 19)
                    : const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(context);
                  onShowAssignedToMe();
                },
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'LISTAS',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.52),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    key: const ValueKey('add-list-button'),
                    tooltip: 'Agregar lista',
                    onPressed: isSavingList
                        ? null
                        : () {
                            Navigator.pop(context);
                            onCreateList();
                          },
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 18),
                itemCount: lists.length,
                itemBuilder: (context, index) {
                  final list = lists[index];
                  final selected =
                      !assignedToMeSelected && list.id == selectedListId;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      key: ValueKey('list-${list.id}'),
                      selected: selected,
                      selectedTileColor: AppTheme.accent.withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      leading: Icon(
                        selected ? Icons.folder_rounded : Icons.folder_outlined,
                        color: selected
                            ? AppTheme.accent
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                      title: Text(
                        list.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                      trailing: selected
                          ? const Icon(Icons.check_rounded, size: 19)
                          : list.isShared
                          ? const Tooltip(
                              message: 'Lista compartida',
                              child: Icon(
                                Icons.people_outline_rounded,
                                size: 19,
                              ),
                            )
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        onSelectList(list.id);
                      },
                    ),
                  );
                },
              ),
            ),
            Divider(
              height: 1,
              indent: 20,
              endIndent: 20,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.1),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: ListTile(
                key: const ValueKey('settings-menu-button'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: const Icon(Icons.settings_outlined),
                title: const Text(
                  'Configuración',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(context);
                  onOpenSettings();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({
    required this.authRepository,
    required this.themeController,
    required this.initialViewMode,
    required this.onViewModeChanged,
    required this.onOpenProfile,
    required this.onClearLocalData,
  });

  final AuthRepository authRepository;
  final AppThemeController themeController;
  final BoardViewMode initialViewMode;
  final ValueChanged<BoardViewMode> onViewModeChanged;
  final VoidCallback onOpenProfile;
  final Future<bool> Function() onClearLocalData;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  late BoardViewMode _viewMode = widget.initialViewMode;
  late ThemeMode _themeMode = widget.themeController.themeMode;
  bool _isClearingData = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Configuración',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SettingsSectionTitle('APARIENCIA'),
                    const SizedBox(height: 10),
                    _SettingsCard(
                      child: RadioGroup<ThemeMode>(
                        groupValue: _themeMode,
                        onChanged: (value) {
                          if (value != null) _changeThemeMode(value);
                        },
                        child: Column(
                          children: [
                            _ThemeModeSetting(
                              key: const ValueKey('theme-mode-system'),
                              icon: Icons.brightness_auto_outlined,
                              title: 'Usar configuración del sistema',
                              value: ThemeMode.system,
                              groupValue: _themeMode,
                              onChanged: _changeThemeMode,
                            ),
                            const Divider(height: 1, indent: 56),
                            _ThemeModeSetting(
                              key: const ValueKey('theme-mode-light'),
                              icon: Icons.light_mode_outlined,
                              title: 'Modo claro',
                              value: ThemeMode.light,
                              groupValue: _themeMode,
                              onChanged: _changeThemeMode,
                            ),
                            const Divider(height: 1, indent: 56),
                            _ThemeModeSetting(
                              key: const ValueKey('theme-mode-dark'),
                              icon: Icons.dark_mode_outlined,
                              title: 'Modo oscuro',
                              value: ThemeMode.dark,
                              groupValue: _themeMode,
                              onChanged: _changeThemeMode,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    const _SettingsSectionTitle('CUENTA'),
                    const SizedBox(height: 10),
                    _SettingsCard(
                      child: StreamBuilder<AppUser?>(
                        stream: widget.authRepository.authStateChanges,
                        initialData: widget.authRepository.currentUser,
                        builder: (context, snapshot) {
                          final user = snapshot.data;
                          return ListTile(
                            key: const ValueKey('settings-profile-button'),
                            leading: AuthAvatar(user: user),
                            title: const Text(
                              'Perfil y cuenta',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              user == null
                                  ? 'Estás usando NockNock como invitado'
                                  : 'Conectado como ${user.email}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: widget.onOpenProfile,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 26),
                    const _SettingsSectionTitle('VISTA DEL TABLERO'),
                    const SizedBox(height: 10),
                    _SettingsCard(
                      child: RadioGroup<BoardViewMode>(
                        groupValue: _viewMode,
                        onChanged: (value) {
                          if (value != null) _changeViewMode(value);
                        },
                        child: Column(
                          children: [
                            _ViewModeSetting(
                              key: const ValueKey('settings-view-grid'),
                              icon: Icons.grid_view_rounded,
                              title: 'Cuadrícula',
                              value: BoardViewMode.grid,
                              groupValue: _viewMode,
                              onChanged: _changeViewMode,
                            ),
                            const Divider(height: 1, indent: 56),
                            _ViewModeSetting(
                              key: const ValueKey('settings-view-list'),
                              icon: Icons.view_agenda_outlined,
                              title: 'Lista compacta',
                              value: BoardViewMode.list,
                              groupValue: _viewMode,
                              onChanged: _changeViewMode,
                            ),
                            const Divider(height: 1, indent: 56),
                            _ViewModeSetting(
                              key: const ValueKey('settings-view-large-list'),
                              icon: Icons.view_stream_outlined,
                              title: 'Lista grande',
                              value: BoardViewMode.largeList,
                              groupValue: _viewMode,
                              onChanged: _changeViewMode,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'La vista elegida se aplica de inmediato al tablero.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 26),
                    const _SettingsSectionTitle('DATOS EN ESTE DISPOSITIVO'),
                    const SizedBox(height: 10),
                    _SettingsCard(
                      child: Column(
                        children: [
                          const ListTile(
                            leading: Icon(Icons.storage_outlined),
                            title: Text(
                              'Almacenamiento local',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              'Aquí se guardan las listas y notas que creas '
                              'como invitado.',
                            ),
                          ),
                          const Divider(height: 1, indent: 56),
                          ListTile(
                            key: const ValueKey('clear-local-data-button'),
                            enabled: !_isClearingData,
                            leading: _isClearingData
                                ? const SizedBox.square(
                                    dimension: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.delete_sweep_outlined),
                            iconColor: AppTheme.accent,
                            textColor: AppTheme.accent,
                            title: const Text(
                              'Limpiar datos locales',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: const Text(
                              'No elimina las notas guardadas en tu cuenta.',
                            ),
                            onTap: _confirmClearLocalData,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                    const _SettingsSectionTitle('ACERCA DE'),
                    const SizedBox(height: 10),
                    const _SettingsCard(
                      child: Column(
                        children: [
                          ListTile(
                            leading: Icon(Icons.sticky_note_2_outlined),
                            title: Text(
                              'NockNock',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              'Notas y recordatorios colaborativos. Versión 1.0.0',
                            ),
                          ),
                          Divider(height: 1, indent: 56),
                          ListTile(
                            leading: Icon(Icons.privacy_tip_outlined),
                            title: Text(
                              'Tus datos de invitado',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              'Permanecen en este dispositivo hasta que los '
                              'elimines desde esta pantalla.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _changeViewMode(BoardViewMode value) {
    setState(() => _viewMode = value);
    widget.onViewModeChanged(value);
  }

  void _changeThemeMode(ThemeMode value) {
    setState(() => _themeMode = value);
    widget.themeController.setThemeMode(value);
  }

  Future<void> _confirmClearLocalData() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Limpiar los datos locales?'),
        content: const Text(
          'Se eliminarán definitivamente todas las listas y notas creadas '
          'como invitado en este dispositivo. Los datos de tu cuenta no se '
          'verán afectados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('confirm-clear-local-data-button'),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Limpiar datos'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;

    setState(() => _isClearingData = true);
    final didClear = await widget.onClearLocalData();
    if (!mounted) return;
    setState(() => _isClearingData = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          didClear
              ? 'Los datos locales fueron eliminados.'
              : 'No pudimos limpiar los datos locales. Inténtalo nuevamente.',
        ),
      ),
    );
  }
}

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.52),
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colorScheme.onSurface.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _ThemeModeSetting extends StatelessWidget {
  const _ThemeModeSetting({
    required this.icon,
    required this.title,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    super.key,
  });

  final IconData icon;
  final String title;
  final ThemeMode value;
  final ThemeMode groupValue;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        icon,
        color: selected ? AppTheme.accent : colorScheme.onSurface,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      trailing: Radio<ThemeMode>(value: value),
      onTap: () => onChanged(value),
    );
  }
}

class _ViewModeSetting extends StatelessWidget {
  const _ViewModeSetting({
    required this.icon,
    required this.title,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    super.key,
  });

  final IconData icon;
  final String title;
  final BoardViewMode value;
  final BoardViewMode groupValue;
  final ValueChanged<BoardViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        icon,
        color: selected ? AppTheme.accent : colorScheme.onSurface,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      trailing: Radio<BoardViewMode>(value: value),
      onTap: () => onChanged(value),
    );
  }
}

class _CollaboratorsDialog extends StatefulWidget {
  const _CollaboratorsDialog({required this.initialList});

  final NoteList initialList;

  @override
  State<_CollaboratorsDialog> createState() => _CollaboratorsDialogState();
}

class _CollaboratorsDialogState extends State<_CollaboratorsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotesCubit, NotesState>(
      builder: (context, state) {
        final list = state.lists.firstWhere(
          (item) => item.id == widget.initialList.id,
          orElse: () => widget.initialList,
        );
        return AlertDialog(
          key: const ValueKey('collaborators-dialog'),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          title: Row(
            children: [
              const Expanded(child: Text('Compartir lista')),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: state.isInviting
                    ? null
                    : () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '“${list.name}”',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    list.canInvite
                        ? 'Invita a otra persona. Cuando inicie sesión con ese '
                              'correo, la lista aparecerá automáticamente.'
                        : 'Puedes editar esta lista junto a estas personas. '
                              'Solo su propietario puede enviar invitaciones.',
                  ),
                  if (list.canInvite) ...[
                    const SizedBox(height: 22),
                    Form(
                      key: _formKey,
                      child: TextFormField(
                        key: const ValueKey('collaborator-email-field'),
                        controller: _emailController,
                        enabled: !state.isInviting,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.send,
                        autocorrect: false,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        decoration: const InputDecoration(
                          labelText: 'Correo del colaborador',
                          hintText: 'persona@correo.com',
                          prefixIcon: Icon(Icons.mail_outline_rounded),
                        ),
                        validator: _validateEmail,
                        onChanged: (_) => setState(() {}),
                        onFieldSubmitted: (_) => _sendInvitation(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const ValueKey('send-invitation-button'),
                        onPressed: state.isInviting || !_hasValidEmail
                            ? null
                            : _sendInvitation,
                        icon: state.isInviting
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                        label: Text(
                          state.isInviting ? 'Enviando…' : 'Enviar invitación',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'PERSONAS CON ACCESO',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.55),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (list.collaborators.isEmpty)
                    const Text('La lista todavía no tiene colaboradores.')
                  else
                    ...list.collaborators.map(
                      (person) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _CollaboratorAvatar(person: person),
                        title: Text(
                          person.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          person.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          person.role == ListMemberRole.owner
                              ? 'Propietario'
                              : 'Puede editar',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ),
                  if (list.pendingInvitations.isNotEmpty) ...[
                    const Divider(height: 28),
                    const Text(
                      'INVITACIONES PENDIENTES',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...list.pendingInvitations.map(
                      (invitation) => ListTile(
                        key: ValueKey('pending-${invitation.email}'),
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                          child: Icon(Icons.schedule_send_outlined),
                        ),
                        title: Text(
                          invitation.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: const Text('Esperando que inicie sesión'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Escribe el correo de la persona';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return 'Escribe un correo válido';
    }
    return null;
  }

  bool get _hasValidEmail => _validateEmail(_emailController.text) == null;

  Future<void> _sendInvitation() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final sent = await context.read<NotesCubit>().inviteCollaborator(
      _emailController.text,
    );
    if (sent && mounted) {
      _emailController.clear();
      FocusScope.of(context).unfocus();
    }
  }
}

class _CollaboratorAvatar extends StatelessWidget {
  const _CollaboratorAvatar({required this.person});

  final ListCollaborator person;

  @override
  Widget build(BuildContext context) {
    final initial = person.displayName.trim().isEmpty
        ? '?'
        : person.displayName.trim()[0].toUpperCase();
    return CircleAvatar(
      backgroundColor: AppTheme.accent.withValues(alpha: 0.13),
      foregroundImage: person.photoUrl == null
          ? null
          : NetworkImage(person.photoUrl!),
      child: Text(initial, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}

class _CreateListDialog extends StatefulWidget {
  const _CreateListDialog();

  @override
  State<_CreateListDialog> createState() => _CreateListDialogState();
}

class _CreateListDialogState extends State<_CreateListDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva lista'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const ValueKey('list-name-field'),
          controller: _controller,
          autofocus: true,
          maxLength: 50,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: const [InitialUppercaseTextFormatter()],
          decoration: const InputDecoration(
            labelText: 'Nombre de la lista',
            hintText: 'Ej. Trabajo, Viaje o Casa',
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Escribe un nombre para la lista'
              : null,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('create-list-confirm-button'),
          onPressed: _submit,
          child: const Text('Crear lista'),
        ),
      ],
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, capitalizeInitialLetter(_controller.text.trim()));
    }
  }
}

class _EditListNameDialog extends StatefulWidget {
  const _EditListNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_EditListNameDialog> createState() => _EditListNameDialogState();
}

class _EditListNameDialogState extends State<_EditListNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar nombre de la lista'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const ValueKey('edit-list-name-field'),
          controller: _controller,
          autofocus: true,
          maxLength: 50,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: const [InitialUppercaseTextFormatter()],
          decoration: const InputDecoration(labelText: 'Nombre de la lista'),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Escribe un nombre para la lista'
              : null,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('save-list-name-button'),
          onPressed: _submit,
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, capitalizeInitialLetter(_controller.text.trim()));
    }
  }
}

class _BoardHeader extends StatelessWidget {
  const _BoardHeader({
    required this.title,
    required this.list,
    required this.noteCount,
    required this.filter,
    required this.viewMode,
    required this.onFilterChanged,
    required this.onViewModeChanged,
    required this.onAdd,
    required this.onShare,
    required this.onCustomizeBackground,
    required this.onRenameList,
    required this.onDeleteList,
    required this.isSavingListOptions,
    required this.showAddButton,
    required this.isCompact,
  });

  final String title;
  final NoteList? list;
  final int noteCount;
  final NoteFilter filter;
  final BoardViewMode viewMode;
  final ValueChanged<NoteFilter> onFilterChanged;
  final ValueChanged<BoardViewMode> onViewModeChanged;
  final VoidCallback? onAdd;
  final VoidCallback? onShare;
  final VoidCallback? onCustomizeBackground;
  final VoidCallback? onRenameList;
  final VoidCallback? onDeleteList;
  final bool isSavingListOptions;
  final bool showAddButton;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
            if (isCompact)
              IconButton.filledTonal(
                key: const ValueKey('share-list-button'),
                tooltip: 'Compartir lista',
                onPressed: onShare,
                icon: Icon(
                  list?.isShared == true
                      ? Icons.group_rounded
                      : Icons.person_add_alt_1_rounded,
                ),
              ),
            if (showAddButton)
              Wrap(
                spacing: 10,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('share-list-button'),
                    onPressed: onShare,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: Text(
                      list?.isShared == true ? 'Personas' : 'Compartir',
                    ),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('new-note-button'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                    ),
                    onPressed: onAdd,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Nueva nota'),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _BoardMetaChip(
                    icon: Icons.sticky_note_2_outlined,
                    label: '$noteCount ${noteCount == 1 ? 'nota' : 'notas'}',
                    color: AppTheme.accent,
                  ),
                  _BoardMetaChip(
                    icon: Icons.groups_2_outlined,
                    label: isCompact
                        ? 'Tiempo real'
                        : 'Compartido en tiempo real',
                    color: colorScheme.onSurface,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _ListMenuButton(
              onCustomizeBackground: onCustomizeBackground,
              onRenameList: onRenameList,
              onDeleteList: onDeleteList,
              isSaving: isSavingListOptions,
            ),
          ],
        ),
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
                  label: 'FILTRAR',
                  selected: filter,
                  selectedColor: AppTheme.accent,
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
                  label: 'VISTA',
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
                    _BoardControlOption(
                      value: BoardViewMode.largeList,
                      label: 'Lista grande',
                      icon: Icons.view_agenda_outlined,
                      tooltip: 'Vista de lista grande',
                    ),
                  ],
                  showIcons: true,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _BoardMetaChip extends StatelessWidget {
  const _BoardMetaChip({
    required this.icon,
    required this.label,
    required this.color,
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
          AnimatedSwitcher(
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
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.68),
                fontSize: 12,
                fontWeight: FontWeight.w700,
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
    required this.onCustomizeBackground,
    required this.onRenameList,
    required this.onDeleteList,
    required this.isSaving,
  });

  final VoidCallback? onCustomizeBackground;
  final VoidCallback? onRenameList;
  final VoidCallback? onDeleteList;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopupMenuButton<_ListMenuAction>(
      key: const ValueKey('list-options-button'),
      tooltip: 'Opciones de la lista',
      padding: EdgeInsets.zero,
      enabled: !isSaving,
      onSelected: (action) {
        switch (action) {
          case _ListMenuAction.background:
            onCustomizeBackground?.call();
          case _ListMenuAction.rename:
            onRenameList?.call();
          case _ListMenuAction.delete:
            onDeleteList?.call();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          key: const ValueKey('customize-background-menu-item'),
          value: _ListMenuAction.background,
          enabled: onCustomizeBackground != null,
          child: const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.wallpaper_rounded),
            title: Text('Cambiar fondo'),
          ),
        ),
        if (onRenameList != null)
          const PopupMenuItem(
            key: ValueKey('rename-list-menu-item'),
            value: _ListMenuAction.rename,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.edit_outlined),
              title: Text('Editar nombre'),
            ),
          ),
        if (onDeleteList != null)
          PopupMenuItem(
            key: const ValueKey('delete-list-menu-item'),
            value: _ListMenuAction.delete,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.delete_outline_rounded,
                color: colorScheme.error,
              ),
              title: Text(
                'Eliminar lista',
                style: TextStyle(color: colorScheme.error),
              ),
            ),
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

class _BoardControlOption<T> {
  const _BoardControlOption({
    required this.value,
    required this.label,
    required this.icon,
    this.tooltip,
  });

  final T value;
  final String label;
  final IconData icon;
  final String? tooltip;
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
      children: [
        SizedBox(
          width: 136,
          child: _CompactIconSelector<NoteFilter>(
            key: const ValueKey('compact-filter-selector'),
            keyPrefix: 'filter-mode',
            selected: filter,
            selectedColor: AppTheme.accent,
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
          ),
        ),
        const Spacer(),
        SizedBox(
          width: 136,
          child: _CompactIconSelector<BoardViewMode>(
            key: const ValueKey('compact-view-selector'),
            keyPrefix: 'view-mode',
            selected: viewMode,
            selectedColor: colorScheme.primary,
            onChanged: onViewModeChanged,
            options: const [
              _BoardControlOption(
                value: BoardViewMode.grid,
                label: 'Vista en cuadrícula',
                icon: Icons.grid_view_rounded,
              ),
              _BoardControlOption(
                value: BoardViewMode.list,
                label: 'Vista de lista compacta',
                icon: Icons.view_list_rounded,
              ),
              _BoardControlOption(
                value: BoardViewMode.largeList,
                label: 'Vista de lista grande',
                icon: Icons.view_agenda_outlined,
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
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: colorScheme.onSurface.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: options.map((option) {
          final isSelected = option.value == selected;
          final selectedForeground =
              ThemeData.estimateBrightnessForColor(selectedColor) ==
                  Brightness.dark
              ? Colors.white
              : Colors.black87;
          return Expanded(
            child: Tooltip(
              message: option.tooltip ?? option.label,
              child: Semantics(
                button: true,
                selected: isSelected,
                label: option.tooltip ?? option.label,
                child: AnimatedContainer(
                  key: ValueKey('$keyPrefix-${option.value.name}'),
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: isSelected ? selectedColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: isSelected ? null : () => onChanged(option.value),
                      child: Center(
                        child: Icon(
                          option.icon,
                          size: 18,
                          color: isSelected
                              ? selectedForeground
                              : colorScheme.onSurface.withValues(alpha: 0.62),
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
    );
  }
}

class _BoardControlGroup<T> extends StatelessWidget {
  const _BoardControlGroup({
    required this.label,
    required this.options,
    required this.selected,
    required this.selectedColor,
    required this.onChanged,
    required this.showIcons,
    super.key,
  });

  final String label;
  final List<_BoardControlOption<T>> options;
  final T selected;
  final Color selectedColor;
  final ValueChanged<T> onChanged;
  final bool showIcons;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 5, bottom: 7),
          child: Text(
            label,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.48),
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.25,
            ),
          ),
        ),
        Container(
          height: 48,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: colorScheme.onSurface.withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
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
        ),
      ],
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
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? selectedColor : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: selectedColor.withValues(alpha: 0.2),
                    blurRadius: 9,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: selected ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (showIcon) ...[
                    Icon(option.icon, size: 16, color: foreground),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 180),
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
    );

    return option.tooltip == null
        ? item
        : Tooltip(message: option.tooltip!, child: item);
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 58,
                color: colorScheme.onSurface.withValues(alpha: 0.35),
              ),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 7),
              Text(detail, textAlign: TextAlign.center),
              if (actionLabel != null) ...[
                const SizedBox(height: 20),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
