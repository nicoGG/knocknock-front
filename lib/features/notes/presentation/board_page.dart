import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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
import 'package:nocknock/features/notes/presentation/note_hero.dart';
import 'package:nocknock/features/notes/presentation/widgets/board_loading_state.dart';
import 'package:nocknock/features/notes/presentation/widgets/collapsing_new_note_fab.dart';
import 'package:nocknock/features/notes/presentation/widgets/list_background.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_editor_sheet.dart';
import 'package:nocknock/features/notes/presentation/widgets/post_it_card.dart';
import 'package:nocknock/features/notifications/domain/app_notification.dart';
import 'package:nocknock/features/notifications/logic/notifications_controller.dart';
import 'package:nocknock/features/notifications/presentation/notifications_page.dart';
import 'package:package_info_plus/package_info_plus.dart';

enum NoteFilter { all, pending, completed }

enum _ListMenuAction { background, rename, delete }

enum _BoardScope { list, assignedToMe, pinned }

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
  _BoardScope _scope = _BoardScope.list;
  late BoardViewMode _viewMode = widget.viewModeController.viewMode;
  ListAppearance _assignedToMeAppearance = const ListAppearance();
  ListAppearance _pinnedAppearance = const ListAppearance();
  StreamSubscription<Map<String, String>>? _notificationTapSubscription;
  late final AnimationController _entranceController;
  late final Animation<double> _headerOpacity;
  late final Animation<Offset> _headerSlide;
  late final Animation<double> _fabScale;
  final ValueNotifier<double> _appBarScrollProgress = ValueNotifier(0);

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
    _appBarScrollProgress.dispose();
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
        final scopedNotes = _scope == _BoardScope.pinned
            ? state.pinnedNotes
            : state.notes;
        final scopeNotes = _scope == _BoardScope.assignedToMe
            ? _assignedToCurrentUser(scopedNotes)
            : scopedNotes;
        final notes = _filtered(scopeNotes);
        final isPinnedScope = _scope == _BoardScope.pinned;
        final isListScope = _scope == _BoardScope.list;
        final colorScheme = Theme.of(context).colorScheme;
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: _AppBar(
            isConnected: state.isRealtimeConnected,
            onOpenProfile: _openProfile,
            notificationsController: widget.notificationsController,
            onOpenNotifications: _openNotifications,
            scrollProgress: _appBarScrollProgress,
          ),
          drawer: _AppDrawer(
            lists: state.lists,
            selectedListId: state.selectedListId,
            assignedToMeSelected: _scope == _BoardScope.assignedToMe,
            pinnedSelected: isPinnedScope,
            isSavingList: state.isSavingList,
            onSelectList: _selectList,
            onShowAssignedToMe: _openAssignedToMe,
            onShowPinned: _openPinned,
            onCreateList: _createList,
            onOpenProfile: _openProfile,
            onOpenSettings: _openSettings,
          ),
          floatingActionButton: isCompact && !isPinnedScope
              ? ScaleTransition(
                  scale: _fabScale,
                  child: CollapsingNewNoteFab(
                    key: const ValueKey('new-note-fab'),
                    scrollProgress: _appBarScrollProgress,
                    onPressed: state.isSaving ? null : () => _openEditor(),
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                  ),
                )
              : null,
          body: ListBoardBackground(
            appearance: isListScope
                ? state.selectedList?.appearance ?? const ListAppearance()
                : _scope == _BoardScope.assignedToMe
                ? _assignedToMeAppearance
                : _pinnedAppearance,
            child: _BoardContentFade(
              topInset: MediaQuery.paddingOf(context).top,
              scrollProgress: _appBarScrollProgress,
              child: SafeArea(
                bottom: false,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _updateAppBarParallax,
                  child: NestedScrollView(
                    key: const ValueKey('board-scroll-view'),
                    headerSliverBuilder: (context, innerBoxIsScrolled) => [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          isCompact ? 18 : 40,
                          isCompact ? 12 : 40,
                          isCompact ? 18 : 40,
                          0,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: ValueListenableBuilder<double>(
                            valueListenable: _appBarScrollProgress,
                            builder: (context, progress, child) {
                              final motionProgress =
                                  MediaQuery.disableAnimationsOf(context)
                                  ? 0.0
                                  : Curves.easeOutCubic.transform(progress);
                              return Transform.translate(
                                key: const ValueKey('board-header-parallax'),
                                offset: Offset(0, 12 * motionProgress),
                                child: child,
                              );
                            },
                            child: FadeTransition(
                              opacity: _headerOpacity,
                              child: SlideTransition(
                                position: _headerSlide,
                                child: _BoardHeader(
                                  title: switch (_scope) {
                                    _BoardScope.list =>
                                      state.selectedList?.name ?? 'Mis notas',
                                    _BoardScope.assignedToMe => 'Asignado a mí',
                                    _BoardScope.pinned => 'Ancladas',
                                  },
                                  list: isListScope ? state.selectedList : null,
                                  noteCount: scopeNotes.length,
                                  filter: _filter,
                                  viewMode: _viewMode,
                                  onFilterChanged: (value) =>
                                      setState(() => _filter = value),
                                  onViewModeChanged: _changeViewMode,
                                  onAdd: state.isSaving || isPinnedScope
                                      ? null
                                      : () => _openEditor(),
                                  onShare: state.isInviting || isPinnedScope
                                      ? null
                                      : () => _openCollaborators(
                                          state.selectedList,
                                        ),
                                  onCustomizeBackground:
                                      state.isSavingAppearance
                                      ? null
                                      : _openBackgroundPicker,
                                  onRenameList:
                                      !isListScope ||
                                          state.isSavingList ||
                                          state.selectedList?.currentUserRole !=
                                              ListMemberRole.owner
                                      ? null
                                      : _renameList,
                                  onDeleteList:
                                      !isListScope ||
                                          state.isSavingList ||
                                          state.selectedList?.currentUserRole !=
                                              ListMemberRole.owner
                                      ? null
                                      : _deleteList,
                                  isSavingListOptions:
                                      state.isSavingAppearance ||
                                      state.isSavingList,
                                  showAddButton: !isCompact && !isPinnedScope,
                                  isCompact: isCompact,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 26)),
                    ],
                    body: Padding(
                      padding: EdgeInsets.fromLTRB(
                        isCompact ? 18 : 40,
                        0,
                        isCompact ? 18 : 40,
                        0,
                      ),
                      child: _content(state, notes),
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

  Widget _content(NotesState state, List<Note> notes) {
    if ((_scope == _BoardScope.pinned && state.isLoadingPinned) ||
        state.status == NotesStatus.loading ||
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
      final isUnfiltered = _filter == NoteFilter.all;
      return _MessageState(
        icon: _scope == _BoardScope.pinned
            ? Icons.push_pin_outlined
            : Icons.sticky_note_2_outlined,
        title: switch (_scope) {
          _BoardScope.assignedToMe =>
            isUnfiltered
                ? 'No tienes notas asignadas en esta lista'
                : 'No hay notas asignadas en este filtro',
          _BoardScope.pinned =>
            isUnfiltered
                ? 'Todavía no tienes notas ancladas'
                : 'No hay notas ancladas en este filtro',
          _BoardScope.list =>
            isUnfiltered
                ? 'Tu lista está lista'
                : 'No hay notas en este filtro',
        },
        detail: switch (_scope) {
          _BoardScope.assignedToMe =>
            'Cuando te asignen una nota, aparecerá aquí.',
          _BoardScope.pinned =>
            'Ancla una nota en cualquier lista y aparecerá aquí.',
          _BoardScope.list =>
            isUnfiltered
                ? 'Crea una nota y empieza a organizar lo que importa.'
                : 'Prueba otro filtro o crea una nota nueva.',
        },
        actionLabel: _scope == _BoardScope.list && isUnfiltered
            ? 'Crear primera nota'
            : null,
        onAction: _scope == _BoardScope.list && isUnfiltered
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
          groupCompleted: _filter == NoteFilter.all,
          showOriginList: _scope == _BoardScope.pinned,
          buildCard: _buildCard,
          onReorder: _reorderNotes,
        ),
        BoardViewMode.list => _NotesList(
          key: const ValueKey('notes-list'),
          notes: notes,
          groupCompleted: _filter == NoteFilter.all,
          layout: PostItCardLayout.compact,
          itemHeight: 55,
          maxWidth: 980,
          buildCard: _buildCard,
          onReorder: _reorderNotes,
        ),
      },
    );
  }

  bool _updateAppBarParallax(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final progress = (notification.metrics.pixels / 96).clamp(0.0, 1.0);
    if ((_appBarScrollProgress.value - progress).abs() > 0.001) {
      _appBarScrollProgress.value = progress;
    }
    return false;
  }

  Widget _buildCard(Note note, PostItCardLayout layout) {
    final state = context.read<NotesCubit>().state;
    final noteList = state.lists
        .where((list) => list.id == note.boardId)
        .firstOrNull;
    final collaborators = noteList?.collaborators ?? const [];
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
    return _NoteCompletionTransition(
      key: ValueKey('note-completion-transition-${note.id}'),
      note: note,
      removesFromCurrentFilter: switch (_filter) {
        NoteFilter.all => false,
        NoteFilter.pending => !note.isCompleted,
        NoteFilter.completed => note.isCompleted,
      },
      onToggle: () => context.read<NotesCubit>().toggleNote(note),
      builder: (context, displayedNote, onToggle) => PostItCard(
        note: displayedNote,
        layout: layout,
        originListName: _scope == _BoardScope.pinned
            ? noteList?.name ?? 'Lista desconocida'
            : null,
        assignee: assignee,
        authorPhotoUrl: currentUserPhoto?.isNotEmpty == true
            ? currentUserPhoto
            : collaboratorPhoto,
        onToggle: onToggle,
        onPin: () {
          HapticFeedback.lightImpact();
          context.read<NotesCubit>().togglePin(note);
        },
        onOpen: () => _openNote(note),
        onChecklistToggle: (item) {
          HapticFeedback.selectionClick();
          context.read<NotesCubit>().toggleChecklistItem(note, item);
        },
      ),
    );
  }

  List<Note> _filtered(List<Note> notes) {
    return switch (_filter) {
      NoteFilter.all => notes,
      NoteFilter.pending => notes.where((note) => !note.isCompleted).toList(),
      NoteFilter.completed => notes.where((note) => note.isCompleted).toList(),
    };
  }

  List<Note> _assignedToCurrentUser(List<Note> notes) {
    final userId = context.read<AuthRepository>().currentUser?.id;
    return notes
        .where((note) => userId != null && note.assigneeUid == userId)
        .toList();
  }

  Future<void> _selectList(String listId) async {
    if (_scope != _BoardScope.list) {
      setState(() => _scope = _BoardScope.list);
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
    setState(() => _scope = _BoardScope.assignedToMe);
  }

  Future<void> _openPinned() async {
    setState(() => _scope = _BoardScope.pinned);
    await context.read<NotesCubit>().loadPinnedNotes();
  }

  void _reorderNotes(List<String> orderedIds) {
    if (_scope == _BoardScope.pinned) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ordena estas notas dentro de su lista original.'),
        ),
      );
      return;
    }
    context.read<NotesCubit>().reorderVisibleNotes(orderedIds);
  }

  void _openNote(Note note) {
    final cubit = context.read<NotesCubit>();
    final currentUser = context.read<AuthRepository>().currentUser;
    final sourceList = cubit.state.lists
        .where((list) => list.id == note.boardId)
        .firstOrNull;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BlocProvider<NotesCubit>.value(
          value: cubit,
          child: NoteDetailPage(
            noteId: note.id,
            initialNote: note,
            listName:
                sourceList?.name ??
                cubit.state.selectedList?.name ??
                'Mis notas',
            defaultAuthorName: currentUser?.displayName ?? note.authorName,
            heroTag: noteHeroTag(
              note.id,
              variant: switch (_viewMode) {
                BoardViewMode.grid => PostItCardLayout.grid.name,
                BoardViewMode.list => PostItCardLayout.compact.name,
              },
            ),
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
      initialAppearance: switch (_scope) {
        _BoardScope.assignedToMe => _assignedToMeAppearance,
        _BoardScope.pinned => _pinnedAppearance,
        _BoardScope.list => list.appearance,
      },
    );
    if (appearance == null || !mounted) return;
    if (_scope == _BoardScope.assignedToMe) {
      setState(() => _assignedToMeAppearance = appearance);
      return;
    }
    if (_scope == _BoardScope.pinned) {
      setState(() => _pinnedAppearance = appearance);
      return;
    }
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
          onOpenProfile: _openProfile,
          onClearLocalData: notesCubit.clearLocalData,
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
    return AnimatedSlide(
      key: ValueKey('note-exit-slide-${widget.note.id}'),
      offset: _isExiting ? const Offset(0.08, -0.025) : Offset.zero,
      duration: _duration,
      curve: Curves.easeInCubic,
      child: AnimatedScale(
        key: ValueKey('note-exit-scale-${widget.note.id}'),
        scale: _isExiting ? 0.94 : 1,
        duration: _duration,
        curve: Curves.easeInCubic,
        alignment: Alignment.centerRight,
        child: AnimatedOpacity(
          key: ValueKey('note-exit-opacity-${widget.note.id}'),
          opacity: _isExiting ? 0 : 1,
          duration: _duration,
          curve: Curves.easeInCubic,
          child: widget.builder(context, displayedNote, _toggle),
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
  const _CompletedSectionHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Semantics(
      header: true,
      label: 'Completadas, $count ${count == 1 ? 'nota' : 'notas'}',
      child: Container(
        key: const ValueKey('completed-section-header'),
        margin: const EdgeInsets.only(top: 20),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.42),
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_rounded,
                size: 20,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Completadas',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Container(
              key: const ValueKey('completed-section-count'),
              constraints: const BoxConstraints(minWidth: 30),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
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
          ],
        ),
      ),
    );
  }
}

class _NotesGrid extends StatelessWidget {
  const _NotesGrid({
    required this.notes,
    required this.groupCompleted,
    required this.showOriginList,
    required this.buildCard,
    required this.onReorder,
    super.key,
  });

  final List<Note> notes;
  final bool groupCompleted;
  final bool showOriginList;
  final NoteCardBuilder buildCard;
  final NoteReorderCallback onReorder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 720;
        final spacing = isCompact ? 10.0 : 16.0;
        // Grid cards reserve 10 px above their surface for the pin. Removing
        // that amount here keeps the visible vertical and horizontal gaps
        // equal while allowing the pin to share the space between cards.
        final verticalSpacing = spacing - 10;
        final columnCount = isCompact
            ? 2
            : ((constraints.maxWidth + spacing) / (280 + spacing))
                  .floor()
                  .clamp(2, 4);
        final columnWidth =
            (constraints.maxWidth - (spacing * (columnCount - 1))) /
            columnCount;
        final pendingNotes = groupCompleted
            ? notes.where((note) => !note.isCompleted).toList()
            : notes;
        final completedNotes = groupCompleted
            ? notes.where((note) => note.isCompleted).toList()
            : const <Note>[];

        return SingleChildScrollView(
          padding: EdgeInsets.only(
            top: 6,
            bottom: _boardBottomScrollPadding(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (pendingNotes.isNotEmpty)
                _buildMasonryGroup(
                  context,
                  notes: pendingNotes,
                  columnCount: columnCount,
                  columnWidth: columnWidth,
                  spacing: spacing,
                  verticalSpacing: verticalSpacing,
                  isCompact: isCompact,
                  keySuffix: '',
                ),
              if (completedNotes.isNotEmpty) ...[
                _CompletedSectionHeader(count: completedNotes.length),
                const SizedBox(height: 12),
                _buildMasonryGroup(
                  context,
                  notes: completedNotes,
                  columnCount: columnCount,
                  columnWidth: columnWidth,
                  spacing: spacing,
                  verticalSpacing: verticalSpacing,
                  isCompact: isCompact,
                  keySuffix: '-completed',
                ),
              ],
            ],
          ),
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
    required String keySuffix,
  }) {
    final columns = List.generate(
      columnCount,
      (_) => <({int index, Note note, double height})>[],
    );
    final columnHeights = List.filled(columnCount, 0.0);

    for (var index = 0; index < notes.length; index++) {
      final note = notes[index];
      final height = _gridNoteHeight(
        context,
        note,
        columnWidth: columnWidth,
        isCompact: isCompact,
      );
      var targetColumn = 0;
      for (var column = 1; column < columnCount; column++) {
        if (columnHeights[column] < columnHeights[targetColumn]) {
          targetColumn = column;
        }
      }
      columns[targetColumn].add((index: index, note: note, height: height));
      columnHeights[targetColumn] += height + verticalSpacing;
    }

    return Row(
      key: ValueKey('masonry-grid-columns$keySuffix'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var column = 0; column < columnCount; column++) ...[
          if (column > 0) SizedBox(width: spacing),
          Expanded(
            child: Column(
              key: ValueKey('masonry-grid-column-$column$keySuffix'),
              children: [
                for (final item in columns[column]) ...[
                  SizedBox(
                    height: item.height,
                    child: _NoteEntrance(
                      key: ValueKey('note-entrance-${item.note.id}'),
                      index: item.index,
                      child: _DraggableGridNote(
                        key: ValueKey('reorder-grid-${item.note.id}'),
                        note: item.note,
                        onDrop: (draggedId) {
                          final reordered = [...notes];
                          final oldIndex = reordered.indexWhere(
                            (note) => note.id == draggedId,
                          );
                          if (oldIndex == -1 || oldIndex == item.index) return;
                          final moved = reordered.removeAt(oldIndex);
                          final targetIndex = reordered.indexWhere(
                            (note) => note.id == item.note.id,
                          );
                          reordered.insert(targetIndex, moved);
                          onReorder(reordered.map((note) => note.id).toList());
                        },
                        child: buildCard(item.note, PostItCardLayout.grid),
                      ),
                    ),
                  ),
                  SizedBox(height: verticalSpacing),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  double _gridNoteHeight(
    BuildContext context,
    Note note, {
    required double columnWidth,
    required bool isCompact,
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
      text: TextSpan(
        text: note.content,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 7,
    )..layout(maxWidth: (columnWidth - 32).clamp(1, columnWidth));
    final contentHeight = note.checklist.isNotEmpty
        ? (note.checklist.length.clamp(1, 10) * 30) +
              (note.checklist.length > 10 ? 22 : 0)
        : note.content.isEmpty
        ? 0.0
        : contentPainter.height;
    final hasBody = note.checklist.isNotEmpty || note.content.isNotEmpty;
    final originListHeight = showOriginList && hasBody ? 35.0 : 0.0;
    final categoryHeight = hasBody
        ? note.category == NoteCategory.general
              ? 6.0
              : 40.0
        : 0.0;
    final reminderHeight = hasBody && note.reminderAt != null ? 24.0 : 0.0;
    final footerHeight = note.assigneeUid != null
        ? 28.0
        : isCompact
        ? 0.0
        : 24.0;
    if (!hasBody) {
      final hasAssignee = note.assigneeUid != null;
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
        return (36.0 + titleOnlyPainter.height)
            .clamp(isCompact ? 84.0 : 96.0, isCompact ? 120.0 : 136.0)
            .toDouble();
      }
      final desiredEmptyHeight = 36.0 + headerHeight + 28;
      return desiredEmptyHeight
          .clamp(isCompact ? 136.0 : 142.0, isCompact ? 150.0 : 166.0)
          .toDouble();
    }
    final desiredHeight =
        36.0 +
        headerHeight +
        originListHeight +
        categoryHeight +
        contentHeight +
        reminderHeight +
        (note.assigneeUid != null ? 10 : 0) +
        footerHeight +
        (note.checklist.isNotEmpty ? 10 : 0);
    final minimumHeight = isCompact ? 184.0 : 205.0;
    if (note.checklist.isNotEmpty) {
      return desiredHeight < minimumHeight ? minimumHeight : desiredHeight;
    }
    final maximumHeight = (isCompact ? 320.0 : 330.0) + originListHeight;
    return desiredHeight.clamp(minimumHeight, maximumHeight).toDouble();
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
    required this.groupCompleted,
    required this.layout,
    required this.itemHeight,
    required this.maxWidth,
    required this.buildCard,
    required this.onReorder,
    super.key,
  });

  final List<Note> notes;
  final bool groupCompleted;
  final PostItCardLayout layout;
  final double itemHeight;
  final double maxWidth;
  final NoteCardBuilder buildCard;
  final NoteReorderCallback onReorder;

  @override
  Widget build(BuildContext context) {
    final pendingNotes = groupCompleted
        ? notes.where((note) => !note.isCompleted).toList()
        : notes;
    final completedNotes = groupCompleted
        ? notes.where((note) => note.isCompleted).toList()
        : const <Note>[];
    if (completedNotes.isEmpty) {
      return ReorderableListView.builder(
        padding: EdgeInsets.only(bottom: _boardBottomScrollPadding(context)),
        itemCount: pendingNotes.length,
        buildDefaultDragHandles: false,
        proxyDecorator: _proxyDecorator,
        onReorderStart: (_) => HapticFeedback.mediumImpact(),
        onReorderItem: (oldIndex, newIndex) =>
            _reorder(pendingNotes, oldIndex, newIndex),
        itemBuilder: (context, index) =>
            _buildItem(context, pendingNotes, index),
      );
    }
    return CustomScrollView(
      slivers: [
        if (pendingNotes.isNotEmpty) _buildSliver(pendingNotes),
        if (completedNotes.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _CompletedSectionHeader(count: completedNotes.length),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          _buildSliver(completedNotes),
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
        hint: 'Mantén presionada y arrastra para cambiar el orden',
        child: _NoteEntrance(
          index: index,
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
    required this.scrollProgress,
    this.notificationsController,
  });

  final bool isConnected;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenNotifications;
  final ValueListenable<double> scrollProgress;
  final NotificationsController? notificationsController;

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) {
    final repository = context.read<AuthRepository>();
    return ValueListenableBuilder<double>(
      valueListenable: scrollProgress,
      builder: (context, rawProgress, _) {
        final progress = Curves.easeOutCubic.transform(
          rawProgress.clamp(0.0, 1.0),
        );
        final colorScheme = Theme.of(context).colorScheme;
        final surfaceColor = colorScheme.surface.withValues(
          alpha: 0.03 + (0.63 * progress),
        );

        return AppBar(
          key: const ValueKey('parallax-app-bar'),
          toolbarHeight: 72,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: Builder(
            builder: (scaffoldContext) => IconButton(
              key: const ValueKey('appbar-menu-button'),
              tooltip: 'Abrir menú',
              onPressed: Scaffold.of(scaffoldContext).openDrawer,
              icon: const Icon(Icons.menu),
            ),
          ),
          flexibleSpace: ClipRect(
            child: ShaderMask(
              key: const ValueKey('appbar-bottom-fade'),
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.68, 1],
                colors: [Colors.white, Colors.white, Colors.transparent],
              ).createShader(bounds),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: 16 * progress,
                  sigmaY: 16 * progress,
                ),
                child: DecoratedBox(
                  key: const ValueKey('appbar-parallax-background'),
                  decoration: BoxDecoration(color: surfaceColor),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          actions: [
            Row(
              key: const ValueKey('appbar-actions'),
              mainAxisSize: MainAxisSize.min,
              children: [
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
                      padding: const EdgeInsets.all(4),
                      onPressed: onOpenProfile,
                      icon: AuthAvatar(user: snapshot.data),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _BoardContentFade extends StatelessWidget {
  const _BoardContentFade({
    required this.topInset,
    required this.scrollProgress,
    required this.child,
  });

  final double topInset;
  final ValueListenable<double> scrollProgress;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: scrollProgress,
    child: child,
    builder: (context, rawProgress, child) {
      final progress = Curves.easeOutCubic.transform(
        rawProgress.clamp(0.0, 1.0),
      );
      final concealedColor = Colors.white.withValues(alpha: 1 - progress);

      return ShaderMask(
        key: const ValueKey('appbar-content-fade'),
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) {
          final fadeStart = ((topInset + 88) / bounds.height).clamp(0.0, 1.0);
          final fadeEnd = ((topInset + 168) / bounds.height).clamp(0.0, 1.0);
          return LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0, fadeStart, fadeEnd, 1],
            colors: [
              concealedColor,
              concealedColor,
              Colors.white,
              Colors.white,
            ],
          ).createShader(bounds);
        },
        child: child,
      );
    },
  );
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
    required this.pinnedSelected,
    required this.isSavingList,
    required this.onSelectList,
    required this.onShowAssignedToMe,
    required this.onShowPinned,
    required this.onCreateList,
    required this.onOpenProfile,
    required this.onOpenSettings,
  });

  final List<NoteList> lists;
  final String selectedListId;
  final bool assignedToMeSelected;
  final bool pinnedSelected;
  final bool isSavingList;
  final ValueChanged<String> onSelectList;
  final VoidCallback onShowAssignedToMe;
  final VoidCallback onShowPinned;
  final VoidCallback onCreateList;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final drawerWidth = (MediaQuery.sizeOf(context).width * 0.88).clamp(
      280.0,
      360.0,
    );

    return Drawer(
      width: drawerWidth,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 18, 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(15),
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
                  IconButton(
                    tooltip: 'Cerrar menú',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 21),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _DrawerProfileSummary(
                onTap: () {
                  Navigator.pop(context);
                  onOpenProfile();
                },
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  _DrawerDestinationTile(
                    key: const ValueKey('assigned-to-me-menu-button'),
                    selected: assignedToMeSelected,
                    icon: assignedToMeSelected
                        ? Icons.assignment_ind_rounded
                        : Icons.assignment_ind_outlined,
                    label: 'Asignado a mí',
                    trailing: Icons.chevron_right_rounded,
                    onTap: () {
                      Navigator.pop(context);
                      onShowAssignedToMe();
                    },
                  ),
                  const SizedBox(height: 4),
                  _DrawerDestinationTile(
                    key: const ValueKey('pinned-menu-button'),
                    selected: pinnedSelected,
                    icon: pinnedSelected
                        ? Icons.push_pin_rounded
                        : Icons.push_pin_outlined,
                    label: 'Ancladas',
                    trailing: Icons.chevron_right_rounded,
                    onTap: () {
                      Navigator.pop(context);
                      onShowPinned();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 14, 4),
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
              child: Scrollbar(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 16),
                  itemCount: lists.length,
                  itemBuilder: (context, index) {
                    final list = lists[index];
                    final selected =
                        !assignedToMeSelected &&
                        !pinnedSelected &&
                        list.id == selectedListId;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _DrawerDestinationTile(
                        key: ValueKey('list-${list.id}'),
                        selected: selected,
                        icon: selected
                            ? Icons.folder_rounded
                            : Icons.folder_outlined,
                        label: list.name,
                        trailing: selected
                            ? Icons.check_rounded
                            : list.isShared
                            ? Icons.people_outline_rounded
                            : null,
                        trailingTooltip: list.isShared && !selected
                            ? 'Lista compartida'
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
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Column(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.55,
                        ),
                      ),
                    ),
                    child: _DrawerDestinationTile(
                      key: const ValueKey('settings-menu-button'),
                      icon: Icons.settings_outlined,
                      label: 'Configuración',
                      trailing: Icons.chevron_right_rounded,
                      onTap: () {
                        Navigator.pop(context);
                        onOpenSettings();
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  const _AppVersionLabel(),
                ],
              ),
            ),
          ],
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

    return StreamBuilder<AppUser?>(
      stream: repository.authStateChanges,
      initialData: repository.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        return Material(
          key: user == null
              ? const ValueKey('drawer-google-sign-in-suggestion')
              : null,
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('drawer-profile-button'),
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
                          user?.displayName ?? 'Inicia sesión con Google',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user?.email ?? 'Sincroniza y protege tus notas',
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
                      color: colorScheme.surface.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      user == null
                          ? Icons.login_rounded
                          : Icons.chevron_right_rounded,
                      size: 20,
                      color: user == null ? AppTheme.accent : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
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
      style: IconButton.styleFrom(
        backgroundColor: AppTheme.accent.withValues(alpha: 0.12),
        foregroundColor: AppTheme.accent,
      ),
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
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final IconData? trailing;
  final String? trailingTooltip;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = selected ? AppTheme.accent : colorScheme.onSurface;
    final trailingIcon = trailing == null
        ? null
        : Icon(trailing, size: 19, color: foreground.withValues(alpha: 0.78));

    return Material(
      color: selected
          ? AppTheme.accent.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 54,
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 3,
                height: selected ? 26 : 0,
                decoration: BoxDecoration(
                  color: AppTheme.accent,
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
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              if (trailingIcon != null)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: trailingTooltip == null
                      ? trailingIcon
                      : Tooltip(message: trailingTooltip!, child: trailingIcon),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({
    required this.authRepository,
    required this.themeController,
    required this.onOpenProfile,
    required this.onClearLocalData,
  });

  final AuthRepository authRepository;
  final AppThemeController themeController;
  final VoidCallback onOpenProfile;
  final Future<bool> Function() onClearLocalData;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
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

class _CollaboratorsDialog extends StatefulWidget {
  const _CollaboratorsDialog({required this.initialList});

  final NoteList initialList;

  @override
  State<_CollaboratorsDialog> createState() => _CollaboratorsDialogState();
}

class _CollaboratorsDialogState extends State<_CollaboratorsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  String? _removingCollaboratorUid;

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
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          key: const ValueKey('collaborators-dialog'),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          backgroundColor: Color.alphaBlend(
            AppTheme.accent.withValues(alpha: 0.1),
            colorScheme.surfaceContainerHigh,
          ),
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.black.withValues(alpha: 0.36),
          elevation: 18,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
            side: BorderSide(
              color: colorScheme.onSurface.withValues(alpha: 0.1),
            ),
          ),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.diversity_3_rounded,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      list.canInvite
                          ? 'Comparte esta lista'
                          : 'Personas de la lista',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      list.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: state.isInviting || state.isRemovingCollaborator
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
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colorScheme.primary.withValues(alpha: 0.14),
                          AppTheme.accent.withValues(alpha: 0.08),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          list.canInvite
                              ? Icons.auto_awesome_rounded
                              : Icons.info_outline_rounded,
                          size: 20,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            list.canInvite
                                ? 'Invita a otras personas. La lista aparecerá '
                                      'cuando ingresen con ese correo.'
                                : 'Aquí puedes ver quiénes participan. Solo la '
                                      'persona propietaria gestiona los accesos.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.45,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (list.canInvite) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surface.withValues(alpha: 0.48),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: colorScheme.onSurface.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Form(
                            key: _formKey,
                            child: TextFormField(
                              key: const ValueKey('collaborator-email-field'),
                              controller: _emailController,
                              enabled:
                                  !state.isInviting &&
                                  !state.isRemovingCollaborator,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.send,
                              autocorrect: false,
                              autovalidateMode:
                                  AutovalidateMode.onUserInteraction,
                              decoration: const InputDecoration(
                                labelText: 'Correo electrónico',
                                hintText: 'nombre@correo.com',
                                prefixIcon: Icon(Icons.alternate_email_rounded),
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
                              onPressed:
                                  state.isInviting ||
                                      state.isRemovingCollaborator ||
                                      !_hasValidEmail
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
                                  : const Icon(Icons.person_add_rounded),
                              label: Text(
                                state.isInviting
                                    ? 'Enviando invitación…'
                                    : 'Invitar a esta lista',
                              ),
                            ),
                          ),
                        ],
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
                    Text(
                      'Aún no hay personas con acceso a esta lista.',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    )
                  else
                    ...list.collaborators.map(
                      (person) => ListTile(
                        key: ValueKey('collaborator-${person.uid}'),
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
                        trailing: person.role == ListMemberRole.owner
                            ? Text(
                                'Propietario',
                                style: Theme.of(context).textTheme.labelSmall,
                              )
                            : list.canInvite
                            ? IconButton(
                                key: ValueKey(
                                  'remove-collaborator-${person.uid}',
                                ),
                                tooltip:
                                    'Quitar a ${person.displayName} de la lista',
                                onPressed:
                                    state.isRemovingCollaborator ||
                                        state.isInviting
                                    ? null
                                    : () => _confirmRemoveCollaborator(
                                        list,
                                        person,
                                      ),
                                icon:
                                    _removingCollaboratorUid == person.uid &&
                                        state.isRemovingCollaborator
                                    ? const SizedBox.square(
                                        dimension: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.person_remove_outlined),
                              )
                            : Text(
                                'Puede editar',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                      ),
                    ),
                  if (list.pendingInvitations.isNotEmpty) ...[
                    const Divider(height: 28),
                    const Text(
                      'INVITACIONES POR ACEPTAR',
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
                        subtitle: const Text(
                          'Tendrá acceso cuando inicie sesión',
                        ),
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

  Future<void> _confirmRemoveCollaborator(
    NoteList list,
    ListCollaborator person,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('remove-collaborator-dialog'),
        title: const Text('Quitar acceso'),
        content: Text(
          '${person.displayName} dejará de ver y editar “${list.name}”. '
          'Las notas de la lista no se eliminarán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            key: const ValueKey('confirm-remove-collaborator'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.person_remove_outlined),
            label: const Text('Quitar acceso'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _removingCollaboratorUid = person.uid);
    await context.read<NotesCubit>().removeCollaborator(person.uid);
    if (mounted) setState(() => _removingCollaboratorUid = null);
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
    final photoUrl = person.photoUrl?.trim();
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    return CircleAvatar(
      backgroundColor: AppTheme.accent.withValues(alpha: 0.13),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Text(
              initial,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          if (hasPhoto)
            ClipOval(
              child: Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
        ],
      ),
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
            if (isCompact && list != null)
              if (hasInvitedCollaborators)
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
                )
              else
                IconButton.filledTonal(
                  key: const ValueKey('share-list-button'),
                  tooltip: 'Compartir lista',
                  onPressed: onShare,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                ),
            if (showAddButton)
              Wrap(
                spacing: 10,
                children: [
                  if (list != null)
                    OutlinedButton.icon(
                      key: const ValueKey('share-list-button'),
                      onPressed: onShare,
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: Text(list!.isShared ? 'Personas' : 'Compartir'),
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
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (onCustomizeBackground != null)
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
      ],
    );
  }
}

class _CollaboratorAvatarStack extends StatelessWidget {
  const _CollaboratorAvatarStack({required this.collaborators});

  static const _avatarSize = 28.0;
  static const _visibleWidth = 18.0;
  static const _maxVisibleAvatars = 3;

  final List<ListCollaborator> collaborators;

  @override
  Widget build(BuildContext context) {
    final visibleCollaborators = collaborators
        .take(_maxVisibleAvatars)
        .toList(growable: false);
    final width =
        _avatarSize + (_visibleWidth * (visibleCollaborators.length - 1));
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      label: 'Personas involucradas: ${collaborators.length}',
      child: SizedBox(
        key: const ValueKey('collaborator-avatar-stack'),
        width: width,
        height: _avatarSize,
        child: Stack(
          children: [
            for (final indexed in visibleCollaborators.indexed)
              Positioned(
                left: indexed.$1 * _visibleWidth,
                child: Container(
                  width: _avatarSize,
                  height: _avatarSize,
                  padding: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    shape: BoxShape.circle,
                  ),
                  child: _CollaboratorAvatar(person: indexed.$2),
                ),
              ),
          ],
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
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
                label: 'Pend.',
                tooltip: 'Pendientes',
                icon: Icons.schedule_rounded,
              ),
              _BoardControlOption(
                value: NoteFilter.completed,
                label: 'Listas',
                tooltip: 'Completadas',
                icon: Icons.check_circle_outline_rounded,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
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
    return Container(
      height: 56,
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
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              option.icon,
                              size: 17,
                              color: isSelected
                                  ? selectedForeground
                                  : colorScheme.onSurface.withValues(
                                      alpha: 0.62,
                                    ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              option.label,
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: TextStyle(
                                color: isSelected
                                    ? selectedForeground
                                    : colorScheme.onSurface.withValues(
                                        alpha: 0.62,
                                      ),
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                height: 1,
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
        }).toList(),
      ),
    );
  }
}

class _BoardControlGroup<T> extends StatelessWidget {
  const _BoardControlGroup({
    required this.options,
    required this.selected,
    required this.selectedColor,
    required this.onChanged,
    required this.showIcons,
    super.key,
  });

  final List<_BoardControlOption<T>> options;
  final T selected;
  final Color selectedColor;
  final ValueChanged<T> onChanged;
  final bool showIcons;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
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
