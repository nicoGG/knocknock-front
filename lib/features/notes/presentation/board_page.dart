import 'package:nocknock/features/finance/financial_budget_dialog.dart';
import 'package:nocknock/features/finance/list_templates.dart';
import 'package:nocknock/features/finance/financial_style.dart';
import 'package:nocknock/features/finance/list_configuration.dart';
import 'package:nocknock/features/finance/financial_entry_editor.dart';
import 'package:nocknock/features/finance/financial_list_board.dart';
import 'package:nocknock/features/home_widgets/home_widget_controller.dart';
import 'package:nocknock/features/home_widgets/home_widget_settings_page.dart';
import 'package:nocknock/features/notes/presentation/sync_activity_sheet.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_history_sheet.dart';
import 'package:nocknock/features/notes/data/quick_capture_inbox.dart';
import 'package:nocknock/features/notes/presentation/widgets/quick_capture_sheet.dart';
import 'package:nocknock/features/notes/domain/note_drawing.dart';
import 'package:nocknock/core/widgets/liquid_alert_dialog.dart';
import 'package:nocknock/features/notes/presentation/widgets/scroll_edge_fade.dart';

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:nocknock/features/notes/presentation/widgets/editable_list_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nocknock/core/input_formatters/initial_uppercase_text_formatter.dart';
import 'package:nocknock/core/theme/app_theme_controller.dart';
import 'package:nocknock/features/auth/data/auth_repository.dart';
import 'package:nocknock/features/auth/domain/app_user.dart';
import 'package:nocknock/features/auth/presentation/profile_page.dart';
import 'package:nocknock/features/notes/data/list_protection_controller.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:nocknock/features/notes/logic/notes_state.dart';
import 'package:nocknock/features/notes/presentation/board_filter_order_controller.dart';
import 'package:nocknock/features/notes/presentation/board_view_mode_controller.dart';
import 'package:nocknock/features/notes/presentation/global_note_search.dart';
import 'package:nocknock/features/notes/presentation/today_page.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart'
    show NoteSearchResult, NotesPersistenceFailure;
import 'package:nocknock/features/notes/presentation/list_biometric_copy.dart';
import 'package:nocknock/features/notes/presentation/list_shortcuts_controller.dart';
import 'package:nocknock/features/notes/presentation/note_category_style.dart';
import 'package:nocknock/features/notes/presentation/note_assignee.dart';
import 'package:nocknock/features/notes/presentation/note_detail_page.dart';
import 'package:nocknock/features/notes/presentation/note_hero.dart';
import 'package:nocknock/features/notes/presentation/list_protection_guard.dart';
import 'package:nocknock/features/notes/presentation/sync_conflicts_sheet.dart';
import 'package:nocknock/features/notes/presentation/trash_page.dart';
import 'package:nocknock/features/notes/presentation/widgets/board_loading_state.dart';
import 'package:nocknock/features/notes/presentation/widgets/collapsing_new_note_fab.dart';
import 'package:nocknock/features/notes/presentation/widgets/list_background.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_editor_sheet.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_preview_dialog.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_rich_text.dart';
import 'package:nocknock/features/notes/presentation/widgets/post_it_card.dart';
import 'package:nocknock/features/notifications/domain/app_notification.dart';
import 'package:nocknock/features/notifications/logic/notifications_controller.dart';
import 'package:nocknock/features/notifications/presentation/notifications_page.dart';
import 'package:nocknock/features/notifications/presentation/widgets/notification_bell_button.dart';
import 'package:nocknock/features/settings/presentation/settings_page.dart';
import 'package:package_info_plus/package_info_plus.dart';

part 'board_chrome.dart';
part 'board_dialogs.dart';
part 'board_drawer.dart';
part 'board_empty_state.dart';
part 'board_filters.dart';
part 'board_notes_view.dart';
part 'board_page_content.dart';

enum _ListMenuAction { share, background, rename, protection, delete }

enum _BoardScope { list, assignedToMe, pinned, withReminder }

const _boardContentSwitchDuration = Duration(milliseconds: 220);
const _boardControlMotionDuration = Duration(milliseconds: 200);
const _boardSelectorSlideDuration = Duration(milliseconds: 260);
const _maxAnimatedNoteEntrances = 6;

int _avatarCacheSize(BuildContext context, double logicalDiameter) =>
    (logicalDiameter * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(
      1,
      256,
    );

void _playBoardTapSound() {
  unawaited(_playSystemClick());
}

Future<void> _playSystemClick() async {
  try {
    await SystemSound.play(SystemSoundType.click);
  } catch (_) {
    // Sound feedback is best-effort and must never block an interaction.
  }
}

class BoardPage extends StatefulWidget {
  const BoardPage({
    required this.themeController,
    required this.viewModeController,
    required this.listProtectionController,
    this.notificationsController,
    this.captureInbox,
    this.homeWidgets,
    super.key,
  });

  final AppThemeController themeController;
  final BoardViewModeController viewModeController;
  final ListProtectionController listProtectionController;
  final NotificationsController? notificationsController;
  final QuickCaptureInbox? captureInbox;
  final HomeWidgetController? homeWidgets;

  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage> with TickerProviderStateMixin {
  bool _captureOpen = false;
  final Set<String> _offeredCaptures = {};
  NoteFilter _filter = NoteFilter.all;
  NoteCategory? _categoryFilter;
  String? _assigneeFilterUid;
  _BoardScope _scope = _BoardScope.list;
  BoardViewMode _viewMode = BoardViewMode.grid;
  bool _completedSectionExpanded = true;
  bool _isEditingListTitle = false;
  late String _activePreferenceListId;
  int? _trashCount;
  int _trashCountGeneration = 0;
  StreamSubscription<Map<String, String>>? _notificationTapSubscription;
  late final AnimationController _entranceController;
  late final Animation<double> _headerOpacity;
  late final Animation<Offset> _headerSlide;
  late final Animation<double> _fabScale;
  late final AnimationController _contentTransitionController;
  late final Animation<double> _contentOpacity;
  final ScrollController _boardScrollController = ScrollController();
  Object? _lastAutomaticPaginationRequest;
  final ValueNotifier<double> _appBarScrollProgress = ValueNotifier(0);
  late final BoardFilterOrderController _filterOrderController =
      BoardFilterOrderController();
  bool _animateNoteEntrances = true;
  int _noteEntranceSuppressionEpoch = 0;
  final Set<String> _automaticUnlockAttemptedListIds = {};
  final ListShortcutsController _listShortcutsController =
      ListShortcutsController();
  Timer? _drawerScopeRefreshTimer;
  String? _precachedDrawerPhotoUrl;
  bool _didPrecacheDrawerLogo = false;

  @override
  void initState() {
    super.initState();
    widget.captureInbox?.addListener(_scheduleCapture);
    widget.homeWidgets?.addListener(_scheduleWidgetAction);
    final selectedListId = context.read<NotesCubit>().state.selectedListId;
    _activePreferenceListId = selectedListId;
    _filter = widget.viewModeController.filterFor(selectedListId);
    _viewMode = widget.viewModeController.viewModeFor(selectedListId);
    _completedSectionExpanded = widget.viewModeController
        .completedSectionExpandedFor(selectedListId);
    unawaited(_filterOrderController.load());
    unawaited(_listShortcutsController.load());
    _listShortcutsController.addListener(_refreshShortcuts);
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
    _contentTransitionController = AnimationController(
      vsync: this,
      duration: _boardContentSwitchDuration,
      value: 1,
    );
    _contentOpacity = CurvedAnimation(
      parent: _contentTransitionController,
      curve: Curves.easeInOutCubic,
    );
    _entranceController.forward();
    widget.viewModeController.addListener(_restoreBoardPreferences);
    widget.listProtectionController.addListener(_restoreListProtectionState);
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
    _precacheDrawerImages();
    if (MediaQuery.disableAnimationsOf(context)) {
      _entranceController.value = 1;
      _contentTransitionController.value = 1;
    }
  }

  @override
  void dispose() {
    widget.captureInbox?.removeListener(_scheduleCapture);
    widget.homeWidgets?.removeListener(_scheduleWidgetAction);
    widget.viewModeController.removeListener(_restoreBoardPreferences);
    widget.listProtectionController.removeListener(_restoreListProtectionState);
    unawaited(_notificationTapSubscription?.cancel());
    _entranceController.dispose();
    _contentTransitionController.dispose();
    _filterOrderController.dispose();
    _drawerScopeRefreshTimer?.cancel();
    _listShortcutsController
      ..removeListener(_refreshShortcuts)
      ..dispose();
    _boardScrollController.dispose();
    _appBarScrollProgress.dispose();
    super.dispose();
  }

  bool _widgetActionOpen = false;
  void _scheduleWidgetAction() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          _widgetActionOpen ||
          _captureOpen ||
          ModalRoute.of(context)?.isCurrent != true ||
          context.read<NotesCubit>().state.status != NotesStatus.ready) {
        return;
      }
      final action = widget.homeWidgets?.takeAction();
      if (action == null) return;
      _widgetActionOpen = true;
      try {
        switch (action['action']) {
          case 'capture':
            final target = action['boardId'];
            await _openQuickCapture(
              preferredListId: target == null || target.isEmpty ? null : target,
            );
          case 'note':
            await _handleNotificationData({
              'boardId': action['boardId'] ?? '',
              'noteId': action['noteId'] ?? '',
            });
          default:
            final board = action['boardId'];
            if (board != null && board.isNotEmpty) {
              await _handleNotificationData({'boardId': board});
            } else {
              await _openToday();
            }
        }
      } finally {
        _widgetActionOpen = false;
        if (mounted) _scheduleWidgetAction();
      }
    });
  }

  void _scheduleCapture() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _captureOpen ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      final pending = widget.captureInbox?.pending
          .where((item) => !_offeredCaptures.contains(item.id))
          .firstOrNull;
      if (pending != null &&
          context.read<NotesCubit>().state.lists.isNotEmpty) {
        unawaited(_openQuickCapture(capture: pending));
      }
    });
  }

  Future<void> _openQuickCapture({
    CapturedText? capture,
    String? preferredListId,
  }) async {
    if (_captureOpen) return;
    final cubit = context.read<NotesCubit>();
    final target = cubit.state.lists
        .where(
          (list) => list.id == (preferredListId ?? cubit.state.selectedListId),
        )
        .firstOrNull;
    if (capture == null &&
        target?.isFinancial == true &&
        widget.captureInbox?.pending.isNotEmpty != true) {
      if (await _selectList(target!.id) && mounted) {
        await _openFinancialEditor();
      }
      return;
    }
    final lists = cubit.state.lists
        .where(
          (list) =>
              !list.isEncryptionKeyPending &&
              widget.listProtectionController.canAccess(list.id),
        )
        .toList();
    if (lists.isEmpty) return;
    capture ??= widget.captureInbox?.pending.firstOrNull;
    if (capture != null) _offeredCaptures.add(capture.id);
    _captureOpen = true;
    final user = context.read<AuthRepository>().currentUser;
    final author = user?.displayName ?? 'Invitado';
    try {
      final saved = await showQuickCaptureSheet(
        context: context,
        lists: lists,
        selectedListId: preferredListId ?? cubit.state.selectedListId,
        authorName: author,
        initialText: capture?.text ?? '',
        onSave: (listId, draft) async {
          if (!await _selectList(listId)) {
            throw StateError('Desbloquea la lista para guardar.');
          }
          await cubit.createCapturedNote(listId, draft);
        },
        onMoreOptions: (listId, draft) async {
          if (!await _selectList(listId) || !mounted) return false;
          final now = DateTime.now();
          final expanded = await showCreateNoteDialog(
            context: context,
            defaultAuthorName: author,
            showAuthorField: user == null,
            assignees: cubit.state.selectedList?.collaborators ?? const [],
            initialNote: Note(
              id: 'capture',
              boardId: listId,
              title: draft.title,
              content: draft.content,
              color: draft.color,
              authorName: author,
              isCompleted: false,
              positionX: 0,
              positionY: 0,
              createdAt: now,
              updatedAt: now,
            ),
          );
          if (expanded == null) return false;
          await cubit.createCapturedNote(listId, expanded);
          return true;
        },
      );
      if (saved == true && capture != null) {
        await widget.captureInbox?.acknowledge(capture.id);
      } else if (capture != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Captura pendiente. Mantén pulsado Nueva nota para retomarla.',
            ),
            action: SnackBarAction(
              label: 'Continuar',
              onPressed: () => _openQuickCapture(capture: capture),
            ),
          ),
        );
      }
    } finally {
      _captureOpen = false;
      if (mounted) _scheduleCapture();
    }
  }

  void _refreshShortcuts() {
    if (mounted) setState(() {});
  }

  void _update(VoidCallback update) {
    if (mounted) setState(update);
  }

  void _handleDrawerChanged(bool isOpened) {
    _drawerScopeRefreshTimer?.cancel();
    if (!isOpened) return;
    _drawerScopeRefreshTimer = Timer(const Duration(milliseconds: 360), () {
      if (!mounted) return;
      unawaited(context.read<NotesCubit>().refreshScopeNotesIfStale());
      unawaited(_refreshTrashCount());
    });
  }

  void _precacheDrawerImages() {
    if (!_didPrecacheDrawerLogo) {
      _didPrecacheDrawerLogo = true;
      unawaited(
        precacheImage(
          const AssetImage('assets/branding/nocknock-logo.png'),
          context,
        ).catchError((_) {}),
      );
    }

    final photoUrl = context
        .read<AuthRepository>()
        .currentUser
        ?.photoUrl
        ?.trim();
    if (photoUrl == null ||
        photoUrl.isEmpty ||
        photoUrl == _precachedDrawerPhotoUrl) {
      return;
    }
    _precachedDrawerPhotoUrl = photoUrl;
    unawaited(
      precacheImage(
        NetworkImage(photoUrl),
        context,
        onError: (_, _) {
          if (_precachedDrawerPhotoUrl == photoUrl) {
            _precachedDrawerPhotoUrl = null;
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ModalRoute.isCurrentOf(context);
    return BlocConsumer<NotesCubit, NotesState>(
      listenWhen: (previous, current) =>
          (current.message != null && previous.message != current.message) ||
          previous.selectedListId != current.selectedListId ||
          previous.lists != current.lists,
      listener: (context, state) {
        if (state.selectedListId != _activePreferenceListId) {
          _isEditingListTitle = false;
          _restoreBoardPreferences(state.selectedListId);
        }
        _scheduleActiveListProtectionSync(state);
        if (state.message != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(state.message!)));
        }
      },
      builder: (context, state) {
        _scheduleBoardPagination(state);
        _scheduleCapture();
        _scheduleWidgetAction();
        final width = MediaQuery.sizeOf(context).width;
        final isCompact = width < 720;
        final rawScopedNotes = switch (_scope) {
          _BoardScope.pinned => state.pinnedNotes,
          _BoardScope.withReminder => state.reminderNotes,
          _BoardScope.assignedToMe => state.assignedNotes,
          _BoardScope.list => state.notes,
        };
        final scopedNotes =
            _scope == _BoardScope.assignedToMe ||
                _scope == _BoardScope.pinned ||
                _scope == _BoardScope.withReminder
            ? rawScopedNotes
                  .where(
                    (note) =>
                        widget.listProtectionController.canAccess(note.boardId),
                  )
                  .toList()
            : rawScopedNotes;
        final scopeNotes = _scope == _BoardScope.assignedToMe
            ? _assignedToCurrentUser(scopedNotes)
            : scopedNotes;
        final statusFilteredNotes = _filtered(scopeNotes);
        final facetNotes = _filter == NoteFilter.completed
            ? statusFilteredNotes
            : statusFilteredNotes.where((note) => !note.isCompleted).toList();
        final categoryCounts = _categoryCounts(facetNotes);
        final selectedCategory = categoryCounts.containsKey(_categoryFilter)
            ? _categoryFilter
            : null;
        final categoryFilteredNotes = selectedCategory == null
            ? statusFilteredNotes
            : statusFilteredNotes
                  .where((note) => note.category == selectedCategory)
                  .toList();
        final assigneeFilters = _assigneeFilters(
          selectedCategory == null
              ? facetNotes
              : facetNotes
                    .where((note) => note.category == selectedCategory)
                    .toList(),
          state.lists,
        );
        final selectedAssigneeUid =
            assigneeFilters.any(
              (assignee) => assignee.uid == _assigneeFilterUid,
            )
            ? _assigneeFilterUid
            : null;
        final notes = selectedAssigneeUid == null
            ? categoryFilteredNotes
            : categoryFilteredNotes
                  .where(
                    (note) =>
                        noteAssigneeFilterKeys(note)
                            .contains(selectedAssigneeUid),
                  )
                  .toList();
        final isPinnedScope = _scope == _BoardScope.pinned;
        final isWithReminderScope = _scope == _BoardScope.withReminder;
        final isAssignedScope = _scope == _BoardScope.assignedToMe;
        final isAggregateScope =
            isAssignedScope || isPinnedScope || isWithReminderScope;
        final isListScope = _scope == _BoardScope.list;
        final selectedList = state.selectedList;
        final selectedListKeyPending =
            isListScope && (selectedList?.isEncryptionKeyPending ?? false);
        final selectedListRequiresUnlock =
            _scope == _BoardScope.list &&
            selectedList != null &&
            !widget.listProtectionController.canAccess(selectedList.id);
        if (selectedListRequiresUnlock) {
          _scheduleAutomaticUnlock(selectedList);
        }
        final colorScheme = Theme.of(context).colorScheme;
        final showsEmptyListAction =
            isListScope &&
            state.status == NotesStatus.ready &&
            notes.isEmpty &&
            _filter == NoteFilter.all &&
            selectedCategory == null &&
            selectedAssigneeUid == null;
        return Scaffold(
          extendBodyBehindAppBar: true,
          onDrawerChanged: _handleDrawerChanged,
          appBar: _AppBar(
            isConnected: state.isRealtimeConnected,
            isConnecting: state.isRealtimeConnecting,
            isEncrypted: (state.selectedList?.encryption.version ?? 0) > 0,
            pendingSyncCount: state.pendingSyncCount,
            syncConflictCount: state.syncConflictCount,
            isSyncingOfflineChanges: state.isSyncingOfflineChanges,
            onSearch: _openGlobalSearch,
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
            withReminderSelected: isWithReminderScope,
            isListProtected: widget.listProtectionController.isProtected,
            isSavingList: state.isSavingList,
            onSelectList: _selectList,
            onShowAssignedToMe: _openAssignedToMe,
            onShowPinned: _openPinned,
            onShowWithReminder: _openWithReminder,
            onReorderLists: _openListReorder,
            onCreateList: _createList,
            onOpenProfile: _openProfile,
            onOpenSettings: _openSettings,
            onOpenTrash: _openTrash,
            onOpenToday: _openToday,
            favoriteListIds: _listShortcutsController.favorites,
            recentListIds: _listShortcutsController.recents,
            onToggleFavorite: _listShortcutsController.toggleFavorite,
            assignedCount: _pendingScopeCount(
              _assignedToCurrentUser(state.assignedNotes),
            ),
            pinnedCount: _pendingScopeCount(state.pinnedNotes),
            reminderCount: _pendingScopeCount(state.reminderNotes),
            trashCount: _trashCount,
          ),
          floatingActionButton:
              isCompact &&
                  !showsEmptyListAction &&
                  !isAggregateScope &&
                  !selectedListRequiresUnlock &&
                  !selectedListKeyPending
              ? AnimatedBuilder(
                  animation: _entranceController,
                  child: CollapsingNewNoteFab(
                    key: const ValueKey('new-note-fab'),
                    scrollProgress: _appBarScrollProgress,
                    onPressed: state.isSaving ? null : _openNewNoteEditor,
                    onLongPress: () => _openQuickCapture(),
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                  ),
                  builder: (context, child) {
                    final scale = _fabScale.value;
                    if (_entranceController.isCompleted && scale >= 1) {
                      return child!;
                    }
                    return Transform.scale(scale: scale, child: child);
                  },
                )
              : null,
          body:
              selectedListRequiresUnlock &&
                  !widget.listProtectionController.privacyShieldRequired
              ? ListProtectionLockedView(
                  controller: widget.listProtectionController,
                )
              : ListBoardBackground(
                  // Note refreshes must not replace a known list background.
                  useThemeBackground:
                      state.lists.isEmpty &&
                      (state.status == NotesStatus.loading ||
                          state.status == NotesStatus.initial),
                  appearance: isListScope
                      ? state.selectedList?.appearance ?? const ListAppearance()
                      : _scope == _BoardScope.assignedToMe
                      ? state.aggregateBoardAppearances.assignedToMe
                      : _scope == _BoardScope.pinned
                      ? state.aggregateBoardAppearances.pinned
                      : state.aggregateBoardAppearances.withReminder,
                  topFadeInset: MediaQuery.paddingOf(context).top,
                  topFadeScrollProgress: _appBarScrollProgress,
                  child: SafeArea(
                    bottom: false,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _handleBoardScroll,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: KeyedSubtree(
                              key: const ValueKey('board-scroll-view'),
                              child: CustomScrollView(
                                key: const ValueKey('masonry-grid-scroll-view'),
                                controller: _boardScrollController,
                                scrollCacheExtent: ScrollCacheExtent.pixels(
                                  _viewMode == BoardViewMode.grid
                                      ? (MediaQuery.sizeOf(context).height *
                                                0.45)
                                            .clamp(280.0, 420.0)
                                            .toDouble()
                                      : 250,
                                ),
                                slivers: [
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
                                              MediaQuery.disableAnimationsOf(
                                                context,
                                              )
                                              ? 0.0
                                              : Curves.easeOutCubic.transform(
                                                  progress,
                                                );
                                          return Transform.translate(
                                            key: const ValueKey(
                                              'board-header-parallax',
                                            ),
                                            offset: Offset(
                                              0,
                                              12 * motionProgress,
                                            ),
                                            child: child,
                                          );
                                        },
                                        child: AnimatedBuilder(
                                          animation: _entranceController,
                                          child: RepaintBoundary(
                                            key: const ValueKey(
                                              'board-header-repaint-boundary',
                                            ),
                                            child: _BoardHeader(
                                              onQuickCapture: () =>
                                                  _openQuickCapture(),
                                              isEditingTitle:
                                                  _isEditingListTitle,
                                              onEditingTitleChanged:
                                                  (editing) => setState(
                                                    () => _isEditingListTitle =
                                                        editing,
                                                  ),
                                              title: switch (_scope) {
                                                _BoardScope.list =>
                                                  state.selectedList?.name ??
                                                      'Mis notas',
                                                _BoardScope.assignedToMe =>
                                                  'Asignado a mí',
                                                _BoardScope.pinned =>
                                                  'Ancladas',
                                                _BoardScope.withReminder =>
                                                  'Con recordatorio',
                                              },
                                              list: isListScope
                                                  ? state.selectedList
                                                  : null,
                                              filter: _filter,
                                              categoryCounts: categoryCounts,
                                              selectedCategory:
                                                  selectedCategory,
                                              assigneeFilters: assigneeFilters,
                                              selectedAssigneeUid:
                                                  selectedAssigneeUid,
                                              viewMode: _viewMode,
                                              onFilterChanged: _changeFilter,
                                              onCategoryChanged:
                                                  _changeCategoryFilter,
                                              onAssigneeChanged:
                                                  _changeAssigneeFilter,
                                              onClearFilters:
                                                  _clearFacetFilters,
                                              filterOrderController:
                                                  _filterOrderController,
                                              onViewModeChanged:
                                                  _changeViewMode,
                                              onAdd:
                                                  state.isSaving ||
                                                      isAggregateScope ||
                                                      selectedListKeyPending
                                                  ? null
                                                  : _openNewNoteEditor,
                                              onShare:
                                                  state.isInviting ||
                                                      isAggregateScope
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
                                                      state
                                                              .selectedList
                                                              ?.currentUserRole !=
                                                          ListMemberRole.owner
                                                  ? null
                                                  : _renameList,
                                              onDeleteList:
                                                  !isListScope ||
                                                      state.isSavingList ||
                                                      state
                                                              .selectedList
                                                              ?.currentUserRole !=
                                                          ListMemberRole.owner
                                                  ? null
                                                  : _deleteList,
                                              onToggleListProtection:
                                                  !isListScope
                                                  ? null
                                                  : _toggleListProtection,
                                              isListProtected:
                                                  isListScope &&
                                                      selectedList != null
                                                  ? widget
                                                        .listProtectionController
                                                        .isProtected(
                                                          selectedList.id,
                                                        )
                                                  : false,
                                              isSavingListOptions:
                                                  state.isSavingAppearance ||
                                                  state.isSavingList ||
                                                  widget
                                                      .listProtectionController
                                                      .isAuthenticating,
                                              showAddButton:
                                                  !isCompact &&
                                                  !isAggregateScope,
                                              isCompact: isCompact,
                                            ),
                                          ),
                                          builder: (context, child) {
                                            final opacity =
                                                _headerOpacity.value;
                                            final position = _headerSlide.value;
                                            if (_entranceController
                                                    .isCompleted &&
                                                opacity >= 1 &&
                                                position == Offset.zero) {
                                              return child!;
                                            }
                                            return Opacity(
                                              opacity: opacity,
                                              child: FractionalTranslation(
                                                translation: position,
                                                child: child,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SliverToBoxAdapter(
                                    child: SizedBox(height: 26),
                                  ),
                                  SliverPadding(
                                    padding: EdgeInsets.fromLTRB(
                                      isCompact ? 18 : 40,
                                      0,
                                      isCompact ? 18 : 40,
                                      0,
                                    ),
                                    sliver: _contentSliver(
                                      state,
                                      notes,
                                      selectedCategory,
                                      selectedAssigneeUid,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (state.isLoadingMoreNotes && isListScope)
                            Positioned(
                              left: 24,
                              right: 24,
                              bottom: MediaQuery.paddingOf(context).bottom + 12,
                              child: const LinearProgressIndicator(
                                key: ValueKey('notes-load-more-progress'),
                                minHeight: 3,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
