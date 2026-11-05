import 'package:nocknock/features/personal_expenses/personal_expenses_page.dart';
import 'package:nocknock/features/personal_expenses/personal_expenses_client.dart';
import 'package:nocknock/features/notes/presentation/widgets/reminders_board.dart';
import 'package:nocknock/features/assistant/assistant_client.dart';
import 'package:nocknock/features/assistant/assistant_mascot.dart';
import 'package:nocknock/features/assistant/assistant_view.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_version_preview.dart';
import 'package:nocknock/features/notes/presentation/widgets/note_pdf_viewer.dart';
import 'package:nocknock/features/notes/presentation/note_attachment_download.dart';
import 'package:nocknock/features/finance/monthly_finance_page.dart';
import 'package:nocknock/features/assistant/assistant_page.dart';
import 'package:nocknock/features/finance/financial_agenda_page.dart';
import 'package:nocknock/core/widgets/liquid_dropdown.dart';
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
    this.createAssistantClient,
    super.key,
  });

  final AppThemeController themeController;
  final BoardViewModeController viewModeController;
  final ListProtectionController listProtectionController;
  final NotificationsController? notificationsController;
  final QuickCaptureInbox? captureInbox;
  final HomeWidgetController? homeWidgets;
  final AssistantClient Function()? createAssistantClient;

  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage> with TickerProviderStateMixin {
  final _newNoteDock = GlobalKey();
  final _assistantMemory = AssistantChatMemory();
  FinancialBoardSelection? _financialView;
  StreamSubscription<AppUser?>? _assistantAuth;
  bool _drawerOpen = false;
  bool _captureOpen = false;
  final Set<String> _offeredCaptures = {};
  NoteFilter _filter = NoteFilter.all;
  ReminderDateFilter _reminderDateFilter = ReminderDateFilter.all;
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
  StreamSubscription<Note>? _widgetCompletionSubscription;
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
    final auth = context.read<AuthRepository>();
    var lastUid = auth.currentUser?.id;
    _assistantAuth = auth.authStateChanges.listen((user) {
      if (user?.id != lastUid) {
        _assistantMemory.clear();
        lastUid = user?.id;
      }
    });
    widget.captureInbox?.addListener(_scheduleCapture);
    widget.homeWidgets?.addListener(_scheduleWidgetAction);
    _widgetCompletionSubscription = widget.homeWidgets?.completedNotes.listen((
      note,
    ) {
      if (mounted) context.read<NotesCubit>().applyWidgetCompletion(note);
    });
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
    unawaited(_assistantAuth?.cancel());
    unawaited(_widgetCompletionSubscription?.cancel());
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
    if (widget.homeWidgets?.pendingAction == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          _widgetActionOpen ||
          _captureOpen ||
          context.read<NotesCubit>().state.status != NotesStatus.ready) {
        return;
      }
      final route = ModalRoute.of(context);
      final pending = widget.homeWidgets?.pendingAction;
      if (pending == null) return;
      if (pending['owner'] != null &&
          pending['owner'] != widget.homeWidgets?.owner) {
        widget.homeWidgets?.takeAction();
        return;
      }
      if (route != null && !route.isCurrent) {
        Navigator.of(context).popUntil((candidate) => candidate == route);
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
    // A native widget tap can arrive after the foreground frame has finished.
    // Request a frame so the action never waits for another touch or rebuild.
    WidgetsBinding.instance.scheduleFrame();
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
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _openSharedReceipt(CapturedText capture) async {
    final cubit = context.read<NotesCubit>();
    final inbox = widget.captureInbox!;
    final error = capture.error;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      await inbox.acknowledge(capture.id);
      return;
    }
    final destinations = cubit.state.lists.where(
      (list) =>
          list.configuration.type == NoteListType.expenses &&
          list.canEdit &&
          !list.isEncryptionKeyPending,
    );
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => ListView(
        shrinkWrap: true,
        children: [
          const ListTile(
            title: Text('Crear gasto con esta boleta'),
            subtitle: Text('Elige dónde guardar el gasto.'),
          ),
          for (final list in destinations)
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(list.name),
              subtitle: Text(list.configuration.currency),
              onTap: () => Navigator.pop(sheet, list.id),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Crear lista «Mis gastos» (CLP)'),
            onTap: () => Navigator.pop(sheet, '@create'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Descartar esta captura'),
            onTap: () => Navigator.pop(sheet, '@discard'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == '@discard') {
      await inbox.acknowledge(capture.id);
      return;
    }
    if (choice != null) {
      var id = choice;
      if (choice == '@create') {
        final before = cubit.state.lists.map((l) => l.id).toSet();
        await cubit.createList(
          'Mis gastos',
          configuration: const ListConfiguration(type: NoteListType.expenses),
        );
        final created = cubit.state.selectedList;
        if (created == null ||
            before.contains(created.id) ||
            created.configuration.type != NoteListType.expenses ||
            !mounted) {
          return;
        }
        id = created.id;
      }
      if (!await _selectList(id) || !mounted) return;
      final attachment = await inbox.receipts.read(capture.id);
      if (!mounted || cubit.state.selectedListId != id) return;
      if (await _openFinancialEditor(initialReceipt: attachment) == true) {
        await inbox.acknowledge(capture.id);
        return;
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Boleta pendiente de guardar.'),
          action: SnackBarAction(
            label: 'Continuar',
            onPressed: () => _openQuickCapture(capture: capture),
          ),
        ),
      );
    }
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
        target?.canEdit == true &&
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
              list.canEdit &&
              !list.isEncryptionKeyPending &&
              widget.listProtectionController.canAccess(list.id),
        )
        .toList();
    capture ??= widget.captureInbox?.pending.firstOrNull;
    if (lists.isEmpty && capture?.receipt != true) return;
    if (capture != null) _offeredCaptures.add(capture.id);
    _captureOpen = true;
    final user = context.read<AuthRepository>().currentUser;
    final author = user?.displayName ?? 'Invitado';
    try {
      if (capture != null && capture.receipt) {
        try {
          await _openSharedReceipt(capture);
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('No se pudo abrir la boleta pendiente.'),
                action: SnackBarAction(
                  label: 'Reintentar',
                  onPressed: () => _openQuickCapture(capture: capture),
                ),
              ),
            );
          }
        }
        return;
      }
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
    setState(() => _drawerOpen = isOpened);
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
          previous.notes != current.notes ||
          previous.lists != current.lists,
      listener: (context, state) {
        widget.homeWidgets?.refresh();
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
        final facetNotes =
            _scope == _BoardScope.withReminder ||
                _filter == NoteFilter.completed
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
        final protected =
            selectedList != null &&
            widget.listProtectionController.isProtected(selectedList.id);
        final title = isListScope && !protected
            ? selectedList?.name ?? 'Tablero'
            : switch (_scope) {
                _BoardScope.assignedToMe => 'Asignado a mí',
                _BoardScope.pinned => 'Ancladas',
                _BoardScope.withReminder => 'Con recordatorio',
                _ => 'Tablero',
              };
        void openBoardChat([MascotTip? tip]) {
          if (isListScope) {
            final visible = notes.map((n) => n.id).toSet();
            _openAssistant(
              tip: tip,
              visibleIds: selectedList?.isFinancial == true ? null : visible,
            );
          } else {
            final byId = {for (final list in state.lists) list.id: list};
            final entries = [
              for (final n in notes)
                if (byId[n.boardId] case final list?)
                  NoteSearchResult(list: list, note: n),
            ];
            _openAssistant(scopedNotes: entries, section: title, tip: tip);
          }
        }

        final board = Scaffold(
          extendBodyBehindAppBar: true,
          onDrawerChanged: _handleDrawerChanged,
          appBar: _AppBar(
            pendingReceiptAction: widget.captureInbox == null
                ? null
                : ListenableBuilder(
                    listenable: widget.captureInbox!,
                    builder: (context, _) {
                      final item = widget.captureInbox!.pending
                          .where((c) => c.receipt && c.error == null)
                          .firstOrNull;
                      return item == null
                          ? const SizedBox.shrink()
                          : IconButton(
                              tooltip: 'Retomar boleta pendiente',
                              icon: const Icon(Icons.receipt_long_outlined),
                              onPressed: () => _openQuickCapture(capture: item),
                            );
                    },
                  ),
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
            onOpenAgenda: _openFinancialAgenda,
            onOpenPersonalExpenses: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => PersonalExpensesPage(
                client: PersonalExpensesClient(tokenProvider: () => context.read<AuthRepository>().getIdToken()),
              )),
            ),
            onOpenAssistant: openBoardChat,
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
                  selectedList?.canEdit != false &&
                  !showsEmptyListAction &&
                  !isAggregateScope &&
                  !selectedListRequiresUnlock &&
                  !selectedListKeyPending
              ? AnimatedBuilder(
                  animation: _entranceController,
                  child: KeyedSubtree(
                    key: _newNoteDock,
                    child: CollapsingNewNoteFab(
                      key: const ValueKey('new-note-fab'),
                      label: state.selectedList?.isFinancial == true
                          ? state.selectedList!.configuration.entryLabel
                          : 'Nueva nota',
                      scrollProgress: state.selectedList?.isFinancial == true
                          ? const AlwaysStoppedAnimation<double>(1)
                          : _appBarScrollProgress,
                      onPressed: state.isSaving ? null : _openNewNoteEditor,
                      onLongPress: () => _openQuickCapture(),
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                    ),
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
                                              newNoteDock: _newNoteDock,
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
                                                _BoardScope.list
                                                    when selectedList
                                                            ?.canEdit ==
                                                        false =>
                                                  '${selectedList!.name} · Solo lectura',
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
                                              reminderFilter:
                                                  isWithReminderScope
                                                  ? _reminderDateFilter
                                                  : null,
                                              onReminderFilterChanged:
                                                  (value) => _update(() {
                                                    _reminderDateFilter = value;
                                                    _categoryFilter = null;
                                                    _assigneeFilterUid = null;
                                                  }),
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
                                                      selectedList?.canEdit ==
                                                          false ||
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
                                                  state.isSavingAppearance ||
                                                      (isListScope &&
                                                          selectedList
                                                                  ?.canEdit ==
                                                              false)
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
                                  if (state.selectedList?.isFinancial == true)
                                    const SliverToBoxAdapter(
                                      child: SizedBox(height: 100),
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
        return AssistantSurface(
          label: title,
          scope: isListScope ? selectedList?.id : title,
          dock: _newNoteDock,
          topic: protected
              ? MascotTopic.general
              : selectedList?.isFinancial == true && isListScope
              ? MascotTopic.finance
              : notes.isEmpty
              ? MascotTopic.emptyList
              : MascotTopic.list,
          hint: protected
              ? 'Hablar con Nocky'
              : '$title · ${selectedList?.isFinancial == true && isListScope ? "Analizar movimientos" : "Organizar pendientes"}',
          onOpen:
              _drawerOpen ||
                  selectedListRequiresUnlock ||
                  selectedListKeyPending
              ? null
              : openBoardChat,
          child: board,
        );
      },
    );
  }
}
