import 'package:nocknock/features/assistant/assistant_mascot.dart';

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:nocknock/core/widgets/ambient_page_background.dart';
import 'package:nocknock/core/widgets/liquid_alert_dialog.dart';
import 'package:nocknock/features/notes/presentation/widgets/completion_undo_countdown.dart';
import 'package:nocknock/features/notes/presentation/note_assignee.dart';
import 'package:nocknock/features/notes/presentation/note_category_style.dart';
import 'package:nocknock/features/notes/presentation/widgets/today_loading_state.dart';
import 'package:nocknock/features/notes/presentation/widgets/post_it_card.dart';
import 'package:nocknock/features/notes/presentation/widgets/scroll_edge_fade.dart';
import 'package:nocknock/features/notes/data/list_protection_controller.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/logic/notes_cubit.dart';
import 'package:nocknock/features/notes/logic/notes_error_message.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/presentation/widgets/liquid_bottom_sheet.dart';

bool canPostponeTodayReminder(Note note, DateTime now) {
  final reminder = note.reminderAt?.toLocal();
  final today = now.toLocal();
  return !note.isCompleted &&
      reminder != null &&
      reminder.year == today.year &&
      reminder.month == today.month &&
      reminder.day == today.day;
}

/// Disjoint sections: dated reminders take precedence over assignment.
Map<String, List<NoteSearchResult>> groupTodayNotes(
  Iterable<NoteSearchResult> notes, {
  required DateTime now,
  required String? userId,
}) {
  final local = now.toLocal();
  final start = DateTime(local.year, local.month, local.day);
  final end = DateTime(local.year, local.month, local.day + 1);
  final groups = <String, List<NoteSearchResult>>{
    'Atrasadas': [],
    'Para hoy': [],
    'Asignadas a mí': [],
    'Próximos recordatorios': [],
    'Completadas hoy': [],
  };
  final seen = <String>{};
  for (final result in notes) {
    final note = result.note;
    if (note.deletedAt != null || !seen.add('${note.boardId}/${note.id}')) {
      continue;
    }
    if (note.isCompleted) {
      final completed = note.completedAt?.toLocal();
      if (completed != null &&
          !completed.isBefore(start) &&
          completed.isBefore(end)) {
        groups['Completadas hoy']!.add(result);
      }
      continue;
    }
    final reminder = note.reminderAt?.toLocal();
    if (reminder != null && reminder.isBefore(start)) {
      groups['Atrasadas']!.add(result);
    } else if (reminder != null && reminder.isBefore(end)) {
      groups['Para hoy']!.add(result);
    } else if (reminder != null) {
      groups['Próximos recordatorios']!.add(result);
    } else if (userId != null && note.assignedUserIds.contains(userId)) {
      groups['Asignadas a mí']!.add(result);
    }
  }
  for (final group in groups.values) {
    group.sort((a, b) {
      final left = a.note.reminderAt;
      final right = b.note.reminderAt;
      final comparison = left == null
          ? (right == null ? 0 : 1)
          : right == null
          ? -1
          : left.compareTo(right);
      return comparison != 0
          ? comparison
          : a.note.title.compareTo(b.note.title);
    });
  }
  return groups;
}

/// Tomorrow and the rest of the local calendar week; distant reminders stay collapsed.
Map<String, List<NoteSearchResult>> groupUpcomingReminders(
  Iterable<NoteSearchResult> notes, {
  required DateTime now,
}) {
  final local = now.toLocal();
  final afterTomorrow = DateTime(local.year, local.month, local.day + 2);
  final nextWeek = DateTime(
    local.year,
    local.month,
    local.day + 8 - local.weekday,
  );
  final groups = <String, List<NoteSearchResult>>{
    'Mañana': [],
    'Esta semana': [],
    'Más adelante': [],
  };
  for (final result in notes) {
    final date = result.note.reminderAt!.toLocal();
    groups[date.isBefore(afterTomorrow)
            ? 'Mañana'
            : date.isBefore(nextWeek)
            ? 'Esta semana'
            : 'Más adelante']!
        .add(result);
  }
  return groups;
}

class TodayPage extends StatefulWidget {
  const TodayPage({
    required this.cubit,
    required this.protection,
    required this.userId,
    required this.onPreviewNote,
    required this.onCreateNote,
    this.onAssistant,
    super.key,
  });

  final Future<void> Function(List<NoteSearchResult>, [MascotTip? tip])?
  onAssistant;
  final NotesCubit cubit;
  final ListProtectionController protection;
  final String? userId;
  final Future<bool> Function(BuildContext context, NoteSearchResult result)
  onPreviewNote;
  final Future<void> Function(BuildContext context, String listId) onCreateNote;

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> with WidgetsBindingObserver {
  List<NoteSearchResult> _notes = const [];
  bool _loading = true;
  bool _hasLoaded = false;
  bool _failed = false;
  int _generation = 0;
  Timer? _clock;
  bool _previewing = false;
  bool _creating = false;
  bool _confirmingCompletion = false;
  String? _filter;
  DateTime? _filterChangedAt;
  final Set<String> _busyIds = {};
  final _newNoteDock = GlobalKey();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.protection.addListener(_protectionChanged);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    unawaited(_load());
  }

  void _protectionChanged() {
    // Drop protected content immediately, including during an in-flight read.
    setState(
      () => _notes = _notes
          .where((result) => widget.protection.canAccess(result.list.id))
          .toList(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  @override
  void dispose() {
    _clock?.cancel();
    widget.protection.removeListener(_protectionChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final notes = await widget.cubit.fetchVisibleListNotes(
        canShowList: widget.protection.canAccess,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _notes = notes
            .where((r) => widget.protection.canAccess(r.list.id))
            .toList();
        _loading = false;
        _hasLoaded = true;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _failed = !_hasLoaded;
      });
      if (_hasLoaded) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(notesErrorMessage(error))),
        );
      }
    }
  }

  Future<void> _previewNote(NoteSearchResult result) async {
    if (_previewing || !widget.protection.canAccess(result.list.id)) return;
    _previewing = true;
    bool shouldOpen;
    try {
      shouldOpen = await widget.onPreviewNote(context, result);
    } finally {
      _previewing = false;
    }
    if (!mounted) return;
    if (shouldOpen && widget.protection.canAccess(result.list.id)) {
      Navigator.pop(context, result);
    } else {
      await _load();
    }
  }

  Future<void> _confirmComplete(NoteSearchResult result) async {
    if (_confirmingCompletion ||
        _busyIds.contains(result.note.id) ||
        !widget.protection.canAccess(result.list.id)) {
      return;
    }
    _confirmingCompletion = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => LiquidAlertDialog(
          scrollable: true,
          icon: const Icon(Icons.task_alt_rounded),
          title: const Text('¿Completar esta nota?'),
          content: Text(
            '“${result.note.title.trim().isEmpty ? 'Sin título' : result.note.title}” se marcará como completada.',
          ),
          actions: [
            TextButton(
              key: const ValueKey('cancel-today-complete-button'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const ValueKey('confirm-today-complete-button'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Completar'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      final saved = await _runAction(
        result,
        () => widget.cubit.completeTodayNote(result.note),
      );
      if (mounted && saved != null) {
        _showCompletionUndo(NoteSearchResult(note: saved, list: result.list));
      }
    } finally {
      _confirmingCompletion = false;
    }
  }

  void _showCompletionUndo(NoteSearchResult result) {
    final messenger = _messengerKey.currentState!;
    messenger.clearSnackBars();
    var undoAvailable = true;
    late ScaffoldFeatureController<SnackBar, SnackBarClosedReason> controller;
    controller = messenger.showSnackBar(
      SnackBar(
        key: const ValueKey('today-completion-undo-snackbar'),
        behavior: SnackBarBehavior.fixed,
        duration: const Duration(seconds: 8),
        dismissDirection: DismissDirection.none,
        content: CompletionUndoCountdown(
          seconds: 8,
          onExpired: () {
            undoAvailable = false;
            controller.close();
          },
        ),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () {
            if (!undoAvailable) return;
            undoAvailable = false;
            unawaited(
              _runAction(
                result,
                () => widget.cubit.undoTodayCompletion(result.note),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<Note?> _runAction(
    NoteSearchResult result,
    Future<Note> Function() action,
  ) async {
    if (_busyIds.contains(result.note.id) ||
        !widget.protection.canAccess(result.list.id)) {
      return null;
    }
    setState(() => _busyIds.add(result.note.id));
    try {
      final saved = await action();
      if (!mounted) return null;
      setState(() {
        _notes = [
          for (final item in _notes)
            if (item.note.id != saved.id)
              item
            else if (widget.protection.canAccess(item.list.id))
              NoteSearchResult(note: saved, list: item.list),
        ];
      });
      return saved;
    } catch (error) {
      if (!mounted) return null;
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(notesErrorMessage(error))),
      );
      return null;
    } finally {
      if (mounted) setState(() => _busyIds.remove(result.note.id));
    }
  }

  Future<void> _postpone(NoteSearchResult result) async {
    if (!canPostponeTodayReminder(result.note, DateTime.now())) return;
    final choice = await showLiquidBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Posponer recordatorio',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final entry in const {
                15: '15 minutos',
                60: '1 hora',
                -1: 'Mañana a la misma hora',
              }.entries)
                ListTile(
                  leading: const Icon(Icons.snooze_rounded),
                  title: Text(entry.value),
                  onTap: () => Navigator.pop(sheetContext, entry.key),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted ||
        choice == null ||
        !canPostponeTodayReminder(result.note, DateTime.now()) ||
        !widget.protection.canAccess(result.list.id)) {
      return;
    }
    final now = DateTime.now();
    final original = result.note.reminderAt!.toLocal();
    final next = choice == -1
        ? DateTime(
            now.year,
            now.month,
            now.day + 1,
            original.hour,
            original.minute,
          )
        : now.add(Duration(minutes: choice));
    await _runAction(
      result,
      () => widget.cubit.postponeTodayReminder(result.note, next),
    );
  }

  Future<void> _createNote() async {
    if (_creating || _previewing) return;
    final lists = widget.cubit.state.lists
        .where((list) => list.canEdit && widget.protection.canAccess(list.id))
        .toList();
    if (lists.isEmpty) {
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text(
            'Desbloquea una lista desde el tablero para crear una nota.',
          ),
        ),
      );
      return;
    }
    setState(() => _creating = true);
    try {
      final id = await showLiquidBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        builder: (sheetContext) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '¿En qué lista la guardamos?',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                for (final list in lists)
                  ListTile(
                    leading: const Icon(Icons.folder_rounded),
                    title: Text(list.name),
                    onTap: () => Navigator.pop(sheetContext, list.id),
                  ),
              ],
            ),
          ),
        ),
      );
      if (!mounted || id == null || !widget.protection.canAccess(id)) return;
      await widget.onCreateNote(context, id);
      if (mounted) await _load();
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final groups = groupTodayNotes(_notes, now: now, userId: widget.userId);
    final completed = groups['Completadas hoy']!.length;
    final pending =
        groups['Atrasadas']!.length +
        groups['Para hoy']!.length +
        groups['Asignadas a mí']!.length;
    final total = pending + completed;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final horizontal = MediaQuery.sizeOf(context).width > 720
        ? (MediaQuery.sizeOf(context).width - 680) / 2
        : 18.0;
    final visibleGroups = _filter == null
        ? groups.entries.where((entry) => entry.key != 'Completadas hoy')
        : groups.entries.where((entry) => entry.key == _filter);
    final entranceOrder = <String, int>{};
    for (final group in visibleGroups) {
      for (final result in group.value) {
        entranceOrder[result.note.id] = entranceOrder.length;
      }
    }
    final hasVisible = visibleGroups.any((entry) => entry.value.isNotEmpty);
    final today = ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          title: const Text('Hoy'),
          actions: [
            IconButton(
              tooltip: 'Actualizar',
              onPressed: _loading || _busyIds.isNotEmpty ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
            const SizedBox(width: 8),
          ],
        ),
        floatingActionButton: KeyedSubtree(
          key: _newNoteDock,
          child: FloatingActionButton.extended(
            key: const ValueKey('today-create-note-button'),
            onPressed: _creating || _loading ? null : _createNote,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Nueva nota'),
          ),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const AmbientPageBackground(),
            SafeArea(
              child: _loading && !_hasLoaded
                  ? TodayLoadingState(horizontalPadding: horizontal)
                  : RefreshIndicator(
                      onRefresh: () async {
                        if (_busyIds.isEmpty) await _load();
                      },
                      child: ScrollEdgeFade(
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                            horizontal,
                            12,
                            horizontal,
                            104,
                          ),
                          children: [
                            _TodayGlassSurface(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (MediaQuery.textScalerOf(context)
                                              .scale(1) <
                                          1.4) ...[
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: colors.primary.withValues(
                                              alpha: 0.12,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              18,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.wb_sunny_rounded,
                                            color: colors.primary,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                      ],
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              MaterialLocalizations.of(context)
                                                  .formatMediumDate(now),
                                              style: theme.textTheme.labelLarge
                                                  ?.copyWith(
                                                    color:
                                                        colors.onSurfaceVariant,
                                                  ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              _failed
                                                  ? 'Tus pendientes'
                                                  : pending == 0
                                                  ? 'Un día por delante'
                                                  : pending == 1
                                                  ? '1 pendiente para hoy'
                                                  : '$pending pendientes para hoy',
                                              style: theme.textTheme.titleLarge
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: -0.4,
                                                  ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              'Recordatorios y tareas asignadas',
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                    color:
                                                        colors.onSurfaceVariant,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (!_failed && total > 0) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      '$completed de $total pendientes completados hoy',
                                      key: const ValueKey(
                                        'today-progress-label',
                                      ),
                                      style: theme.textTheme.labelLarge,
                                    ),
                                    const SizedBox(height: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(99),
                                      child: LinearProgressIndicator(
                                        value: completed / total,
                                        minHeight: 5,
                                        semanticsLabel:
                                            'Progreso de hoy, $completed de $total pendientes',
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (!_failed &&
                                (_filter != null ||
                                    [
                                      'Atrasadas',
                                      'Para hoy',
                                      'Asignadas a mí',
                                      'Próximos recordatorios',
                                      'Completadas hoy',
                                    ].any(
                                      (key) => groups[key]!.isNotEmpty,
                                    ))) ...[
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  for (final key in [
                                    'Atrasadas',
                                    'Para hoy',
                                    'Asignadas a mí',
                                    'Próximos recordatorios',
                                    'Completadas hoy',
                                  ])
                                    if (groups[key]!.isNotEmpty ||
                                        _filter == key)
                                      _TodayFilterChip(
                                        key: ValueKey('today-filter-$key'),
                                        label: key == 'Próximos recordatorios'
                                            ? 'Próximos'
                                            : key == 'Asignadas a mí'
                                            ? 'Asignadas'
                                            : key,
                                        count: groups[key]!.length,
                                        icon: switch (key) {
                                          'Atrasadas' => Icons.history_rounded,
                                          'Para hoy' => Icons.today_rounded,
                                          'Asignadas a mí' =>
                                            Icons.person_outline_rounded,
                                          'Completadas hoy' =>
                                            Icons.task_alt_rounded,
                                          _ => Icons.event_outlined,
                                        },
                                        selected: _filter == key,
                                        onTap: () => setState(() {
                                          _filter = _filter == key ? null : key;
                                          _filterChangedAt = DateTime.now();
                                        }),
                                      ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 16),
                            if (_failed)
                              _TodayMessage(
                                icon: Icons.cloud_off_rounded,
                                title: 'No pudimos cargar tus pendientes',
                                detail: 'Tus notas siguen guardadas. Intenta nuevamente.',
                                action: TextButton.icon(
                                  onPressed: _load,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Reintentar'),
                                ),
                              )
                            else if (!hasVisible)
                              _TodayMessage(
                                icon: Icons.task_alt_rounded,
                                title: _filter == null
                                    ? 'Todo al día'
                                    : 'Sin notas en este filtro',
                                detail: _filter == null
                                    ? 'No tienes recordatorios ni notas asignadas pendientes.'
                                    : 'Aquí aparecerán las notas que correspondan a este estado.',
                              )
                            else
                              for (final entry in visibleGroups)
                                if (entry.value.isNotEmpty)
                                  if (entry.key ==
                                      'Próximos recordatorios') ...[
                                    _sectionHeading(
                                      context,
                                      entry.key,
                                      entry.value.length,
                                    ),
                                    for (final upcoming
                                        in groupUpcomingReminders(
                                          entry.value,
                                          now: now,
                                        ).entries)
                                      if (upcoming.value.isNotEmpty)
                                        if (upcoming.key == 'Más adelante')
                                          ExpansionTile(
                                            key: const PageStorageKey(
                                              'today-later-reminders',
                                            ),
                                            tilePadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 4,
                                                ),
                                            title: Text(
                                              'Más adelante · ${upcoming.value.length}',
                                            ),
                                            children: [
                                              for (final result
                                                  in upcoming.value)
                                                _noteCard(
                                                  context,
                                                  result,
                                                  entranceOrder[result
                                                          .note
                                                          .id] ??
                                                      0,
                                                ),
                                            ],
                                          )
                                        else ...[
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              4,
                                              8,
                                              4,
                                              10,
                                            ),
                                            child: Text(
                                              upcoming.key,
                                              style: theme.textTheme.labelLarge
                                                  ?.copyWith(
                                                    color:
                                                        colors.onSurfaceVariant,
                                                  ),
                                            ),
                                          ),
                                          for (final result in upcoming.value)
                                            _noteCard(
                                              context,
                                              result,
                                              entranceOrder[result.note.id] ??
                                                  0,
                                            ),
                                        ],
                                  ] else ...[
                                    _sectionHeading(
                                      context,
                                      entry.key,
                                      entry.value.length,
                                    ),
                                    for (final result in entry.value)
                                      _noteCard(
                                        context,
                                        result,
                                        entranceOrder[result.note.id] ?? 0,
                                      ),
                                  ],
                            if (widget.cubit.state.lists.any(
                              (list) => !widget.protection.canAccess(list.id),
                            ))
                              const _TodayHint(
                                icon: Icons.lock_rounded,
                                text: 'Las listas bloqueadas están ocultas. Desbloquéalas desde el tablero para incluirlas.',
                              ),
                            if (widget.userId == null)
                              const _TodayHint(
                                icon: Icons.person_rounded,
                                text: 'Inicia sesión para incluir las notas asignadas a ti.',
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
    return AssistantSurface(
      label: 'Hoy',
      dock: _newNoteDock,
      topic: MascotTopic.today,
      hint: 'Planificar mi día con Nocky',
      onOpen: widget.onAssistant == null || _loading || _failed
          ? null
          : ([tip]) async {
              await widget.onAssistant!([
                for (final group in groups.entries)
                  if (_filter == null || _filter == group.key) ...group.value,
              ], tip);
              if (mounted) await _load();
            },
      child: today,
    );
  }

  Widget _sectionHeading(BuildContext context, String title, int count) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Row(
        children: [
          Icon(
            switch (title) {
              'Atrasadas' => Icons.history_rounded,
              'Para hoy' => Icons.today_rounded,
              'Próximos recordatorios' => Icons.notifications_active_rounded,
              'Completadas hoy' => Icons.task_alt_rounded,
              _ => Icons.person_rounded,
            },
            size: 20,
            color: title == 'Atrasadas' ? colors.error : colors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$title · $count',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: title == 'Atrasadas' ? colors.error : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noteCard(
    BuildContext context,
    NoteSearchResult result,
    int entranceIndex,
  ) {
    final note = result.note;
    final busy = _busyIds.contains(note.id);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final card = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        key: ValueKey('today-note-${note.id}'),
        height: 100 + 100 * (scale - 1).clamp(0.0, 1.0),
        child: PostItCard(
          note: note,
          layout: PostItCardLayout.compact,
          compactSubtitle: _subtitle(context, result),
          compactLeading:
              result.list.canEdit && !note.isCompleted && !note.isRecurring
              ? IconButton(
                  key: ValueKey('today-complete-${note.id}'),
                  tooltip: 'Completar nota',
                  onPressed: busy ? null : () => _confirmComplete(result),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  icon: Opacity(
                    opacity: busy ? 0.35 : 1,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: NoteCategoryStyle.foregroundColor(note.category)
                            .withValues(alpha: 0.06),
                        border: Border.all(
                          color: NoteCategoryStyle.foregroundColor(
                            note.category,
                          ).withValues(alpha: 0.25),
                        ),
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: NoteCategoryStyle.foregroundColor(note.category)
                            .withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                )
              : null,
          compactTrailing:
              result.list.canEdit &&
                  canPostponeTodayReminder(note, DateTime.now())
              ? IconButton(
                  key: ValueKey('today-postpone-${note.id}'),
                  tooltip: 'Posponer recordatorio',
                  onPressed: busy ? null : () => _postpone(result),
                  iconSize: 20,
                  style: IconButton.styleFrom(
                    foregroundColor: NoteCategoryStyle.foregroundColor(
                      note.category,
                    ).withValues(alpha: 0.72),
                    disabledForegroundColor: NoteCategoryStyle.foregroundColor(
                      note.category,
                    ).withValues(alpha: 0.3),
                  ),
                  icon: const Icon(Icons.snooze_rounded),
                )
              : null,
          assignee: resolveNoteAssignee(note, result.list.collaborators),
          assignees: resolveNoteAssignees(note, result.list.collaborators),
          compactTitleMaxLines: 2,
          compactShowCategory: false,
          compactReadOnly: true,
          compactOpenIndicator: true,
          showPin: false,
          enableHero: false,
          onToggle: () {},
          onPin: () {},
          onChecklistToggle: (_) {},
          onOpen: busy ? () {} : () => _previewNote(result),
        ),
      ),
    );
    final animateFilterChange =
        _filterChangedAt != null &&
        DateTime.now().difference(_filterChangedAt!).inMilliseconds < 500;
    final reducedMotion =
        MediaQuery.disableAnimationsOf(context) || !animateFilterChange;
    final delay = entranceIndex.clamp(0, 5) * 35;
    final duration = 300 + delay;
    return TweenAnimationBuilder<double>(
      key: ValueKey('today-card-entrance-${_filter ?? 'all'}-${note.id}'),
      tween: Tween(begin: reducedMotion ? 1 : 0, end: 1),
      duration: reducedMotion
          ? Duration.zero
          : Duration(milliseconds: duration),
      curve: Interval(delay / duration, 1, curve: Curves.easeOutCubic),
      child: RepaintBoundary(child: card),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 22 * (1 - value)),
          child: child,
        ),
      ),
    );
  }

  String _subtitle(BuildContext context, NoteSearchResult result) {
    final reminder = result.note.reminderAt?.toLocal();
    final category = NoteCategoryStyle.label(result.note.category);
    if (reminder == null) return '${result.list.name} · $category';
    final localizations = MaterialLocalizations.of(context);
    return '${result.list.name} · $category\n${localizations.formatShortDate(reminder)} · '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(reminder), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
  }
}

class _TodayGlassSurface extends StatelessWidget {
  const _TodayGlassSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(26);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: Colors.white.withValues(alpha: isDark ? 0.14 : 0.5),
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.surface.withValues(alpha: isDark ? 0.65 : 0.78),
                colors.surfaceContainerHigh.withValues(
                  alpha: isDark ? 0.45 : 0.6,
                ),
              ],
            ),
          ),
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );
  }
}

class _TodayMessage extends StatelessWidget {
  const _TodayMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _TodayGlassSurface(
      child: Column(
        children: [
          const SizedBox(height: 12),
          Icon(icon, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _TodayHint extends StatelessWidget {
  const _TodayHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: colors.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayFilterChip extends StatelessWidget {
  const _TodayFilterChip({
    super.key,
    required this.label,
    required this.count,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int count;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected
        ? colors.onPrimaryContainer
        : colors.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $count',
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: selected
                  ? [
                      colors.primaryContainer,
                      colors.primaryContainer.withValues(alpha: .65),
                    ]
                  : [
                      colors.surfaceContainerHigh.withValues(alpha: .7),
                      colors.surface.withValues(alpha: .4),
                    ],
            ),
            border: Border.all(
              color: colors.primary.withValues(alpha: selected ? .5 : .18),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: .12),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Stack(
                children: [
                  Positioned(
                    right: 22,
                    bottom: -9,
                    child: Transform.rotate(
                      angle: -.14,
                      child: Icon(
                        icon,
                        size: 52,
                        color: foreground.withValues(alpha: .07),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 18, color: foreground),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: foreground,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: foreground.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$count',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: foreground,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ],
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
