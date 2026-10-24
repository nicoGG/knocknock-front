import 'package:nocknock/features/home_widgets/home_widget_kind.dart';
import 'package:nocknock/core/theme/app_theme.dart';
import 'package:nocknock/core/theme/app_theme_controller.dart';

import 'dart:async';
import 'dart:convert';

import 'package:nocknock/features/finance/financial_entry.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nocknock/features/auth/data/auth_repository.dart';
import 'package:nocknock/features/notes/data/list_protection_controller.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';

/// Device-only widget data excludes protected lists, credentials and attachments.
Map<String, dynamic> buildHomeWidgetSnapshot({
  required String owner,
  required List<NoteList> lists,
  required Iterable<Note> notes,
  required bool Function(String) isProtected,
  required DateTime now,
  String? userId,
  String? listId,
  String? captureListId,
  bool hideContent = false,
}) {
  final visibleLists = {
    for (final list in lists)
      if (!isProtected(list.id) && !list.isEncryptionKeyPending) list.id: list,
  };
  final selected = visibleLists[listId];
  final end = DateTime(now.year, now.month, now.day + 1);
  final unique = <String, Note>{};
  for (final note in notes) {
    if (!visibleLists.containsKey(note.boardId) ||
        (note.financialEntry != null &&
            (note.financialEntry!.isBudget ||
                note.financialEntry!.status != 'pending')) ||
        note.isCompleted ||
        note.deletedAt != null) {
      continue;
    }
    if (listId != null) {
      if (selected == null || note.boardId != listId) continue;
    } else {
      final reminder = note.reminderAt?.toLocal();
      if (!(reminder != null && reminder.isBefore(end)) &&
          !(reminder == null &&
              userId != null &&
              note.assignedUserIds.contains(userId))) {
        continue;
      }
    }
    unique[note.id] = note;
  }
  final pending = unique.values.toList()
    ..sort((a, b) {
      final left = a.reminderAt;
      final right = b.reminderAt;
      if (left != null && right != null) return left.compareTo(right);
      if (left != null) return -1;
      if (right != null) return 1;
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return a.sortOrder.compareTo(b.sortOrder);
    });
  return {
    'owner': owner,
    'title': hideContent
        ? 'Mis pendientes'
        : (selected?.name ?? (listId == null ? 'Hoy' : 'Lista no disponible')),
    'listId': hideContent ? null : selected?.id,
    'total': hideContent ? 0 : pending.length,
    'hidden': hideContent,
    'updatedAt': now.millisecondsSinceEpoch,
    'captureListId': visibleLists.containsKey(captureListId)
        ? captureListId
        : null,
    'rows': hideContent
        ? <Object>[]
        : pending
              .take(5)
              .map(
                (note) => {
                  'id': note.id,
                  'boardId': note.boardId,
                  'title': note.title.characters.take(120).toString(),
                  'revision': note.revision,
                  // Recurring notes are opened in the app, matching the board behavior.
                  'canComplete':
                      !note.isRecurring && note.financialEntry == null,
                },
              )
              .toList(),
  };
}

class HomeWidgetController extends ChangeNotifier with WidgetsBindingObserver {
  HomeWidgetController({
    required this.repository,
    required this.auth,
    required this.protection,
    this.themeController,
    this.channel = const MethodChannel('cl.nocknock/home_widgets'),
  });
  final NotesRepository repository;
  final AuthRepository auth;
  final ListProtectionController protection;
  final MethodChannel channel;
  final AppThemeController? themeController;
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  String get owner => auth.currentUser?.id ?? 'guest';
  String? listId;
  String? captureListId;
  bool hideContent = false;
  String? error;
  final _completedNotes = StreamController<Note>.broadcast();
  Stream<Note> get completedNotes => _completedNotes.stream;
  Map<String, String>? _pendingAction;
  Map<String, String>? get pendingAction => _pendingAction;
  StreamSubscription<NotesRealtimeEvent>? _events;
  StreamSubscription<Object?>? _authEvents;
  SharedPreferences? _preferences;
  Timer? _timer;
  Future<void> _serial = Future.value();
  bool _disposed = false;
  int _generation = 0;

  Future<void> start() async {
    if (!supported) return;
    WidgetsBinding.instance.addObserver(this);
    channel.setMethodCallHandler((call) async {
      if (call.method == 'actionAvailable') await _takeAction();
      if (call.method == 'queueChanged') refresh();
    });
    protection.addListener(_privacyChanged);
    themeController?.addListener(refresh);
    _events = repository.realtimeEvents.listen((event) {
      if (event is NotesSourceChanged || event is ListAccessRemoved) {
        _privacyChanged();
      } else {
        refresh();
      }
    });
    _authEvents = auth.authStateChanges.listen((_) => _privacyChanged());
    _preferences = await SharedPreferences.getInstance();
    _loadSettings();
    await _takeAction();
    _privacyChanged();
  }

  void _loadSettings() {
    listId = _preferences?.getString('home_widget.$owner.list');
    captureListId = _preferences?.getString('home_widget.$owner.capture');
    hideContent = _preferences?.getBool('home_widget.$owner.hidden') ?? false;
  }

  Future<void> configure({
    String? source,
    String? capture,
    required bool hidden,
  }) async {
    final preferences = _preferences ??= await SharedPreferences.getInstance();
    for (final entry in {'list': source, 'capture': capture}.entries) {
      final key = 'home_widget.$owner.${entry.key}';
      if (entry.value == null) {
        await preferences.remove(key);
      } else {
        await preferences.setString(key, entry.value!);
      }
    }
    await preferences.setBool('home_widget.$owner.hidden', hidden);
    _loadSettings();
    _privacyChanged();
  }

  void _privacyChanged() {
    _generation++;
    _loadSettings();
    // Purge titles immediately, before asynchronous reads, even when unlocked.
    _enqueue(
      () => _publish(
        buildHomeWidgetSnapshot(
          owner: owner,
          lists: const [],
          notes: const [],
          isProtected: (_) => true,
          now: DateTime.now(),
          hideContent: true,
        ),
      ),
    );
    refresh();
  }

  void refresh() {
    if (!supported || _disposed) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 350), () => _enqueue(_refresh));
  }

  Future<void> refreshNow() async {
    if (!supported || _disposed) return;
    _timer?.cancel();
    _enqueue(_refresh);
    await _serial;
  }

  void _enqueue(Future<void> Function() operation) {
    _serial = _serial
        .then((_) async {
          if (!_disposed) await operation();
        })
        .catchError((Object _) {
          // Keep the previous snapshot and durable action queue on native failures.
        });
  }

  Future<void> _refresh() async {
    final generation = _generation;
    final account = owner;
    bool current() =>
        !_disposed && generation == _generation && account == owner;
    try {
      final lists = await repository.fetchLists();
      if (!current()) return;
      await _flushCompletions(lists, account);
      if (!current()) return;
      final visible = lists
          .where(
            (list) =>
                !protection.isProtected(list.id) &&
                !list.isEncryptionKeyPending,
          )
          .toList();
      final notes = <Note>[];
      if (listId != null) {
        if (visible.any((list) => list.id == listId)) {
          notes.addAll(await repository.fetchNotes(listId!));
        }
      } else {
        notes.addAll(await repository.fetchReminderNotes());
        if (repository is AssignedNotesRepository) {
          notes.addAll(
            await (repository as AssignedNotesRepository).fetchAssignedNotes(),
          );
        }
      }
      if (!current()) return;
      final catalog = <Map<String, dynamic>>[];
      if (defaultTargetPlatform == TargetPlatform.android && !hideContent) {
        for (final list in visible) {
          final entries = await repository.fetchNotes(list.id);
          if (!current()) return;
          final active = entries.where((n) => n.deletedAt == null).toList()
            ..sort(compareNotes);
          final summary = <String, int>{};
          for (final note in active) {
            final entry = note.financialEntry;
            if (entry == null ||
                entry.isBudget ||
                entry.isSettlement ||
                entry.status == 'rejected') {
              continue;
            }
            summary.update(
              entry.currency,
              (v) => v + entry.amountMinor,
              ifAbsent: () => entry.amountMinor,
            );
          }
          catalog.add({
            'listId': list.id,
            'title': list.name,
            'financial': list.isFinancial,
            'expenses': list.configuration.type.name == 'expenses',
            'currency': list.configuration.currency,
            'summary': summary.entries
                .map((e) => FinancialEntry.formatAmount(e.value, e.key))
                .join(' · '),
            'rows': active
                .map(
                  (note) => {
                    'id': note.id,
                    'boardId': list.id,
                    'title': note.title.characters.take(120).toString(),
                    'revision': note.revision,
                    'completed': note.isCompleted,
                    'canComplete':
                        !note.isRecurring && note.financialEntry == null,
                    'checklist': note.checklist
                        .map((item) => item.toJson())
                        .toList(),
                  },
                )
                .toList(),
          });
        }
      }
      await _publish({
        ...buildHomeWidgetSnapshot(
          owner: account,
          lists: lists,
          notes: notes,
          isProtected: protection.isProtected,
          now: DateTime.now(),
          userId: auth.currentUser?.id,
          listId: listId,
          captureListId: captureListId,
          hideContent: hideContent,
        ),
        'catalog': catalog,
      });
      error = null;
    } catch (_) {
      error =
          'No se pudo actualizar. Abre la app con conexión para reintentar.';
    }
    if (current()) notifyListeners();
  }

  Future<void> _flushCompletions(List<NoteList> lists, String account) async {
    final raw = await channel.invokeMethod<String>('readQueue');
    if (raw == null) return;
    final queue = (jsonDecode(raw) as List).whereType<Map>();
    for (final action in queue) {
      if (owner != account || _disposed) return;
      final board = action['boardId'];
      final allowed =
          action['owner'] == account &&
          lists.any(
            (list) => list.id == board && !list.isEncryptionKeyPending,
          ) &&
          !protection.isProtected(board as String);
      if (!allowed) {
        await channel.invokeMethod<void>('acknowledge', action['mutationId']);
        continue;
      }
      try {
        if (action['type'] == 'expense') {
          final list = lists.firstWhere((l) => l.id == board);
          final amount = FinancialEntry.parseAmount(
            action['amount'] as String,
            list.configuration.currency,
          );
          final title = (action['title'] as String).trim();
          if (list.configuration.type.name != 'expenses' ||
              amount == null ||
              title.isEmpty) {
            await channel.invokeMethod<void>(
              'acknowledge',
              action['mutationId'],
            );
            continue;
          }
          final created = await repository.createNote(
            board,
            NoteDraft(
              title: title,
              content: '',
              color: NoteColor.green,
              authorName: auth.currentUser?.displayName ?? 'Yo',
              category: NoteCategory.finance,
              clientNoteId: action['id'] as String,
              clientMutationId: action['mutationId'] as String,
              financialData: FinancialEntry(
                amountMinor: amount,
                currency: list.configuration.currency,
                counterparty: '',
                date: DateTime.fromMillisecondsSinceEpoch(
                  action['completedAt'] as int,
                ),
              ).encoded,
            ),
          );
          if (!_disposed && owner == account) _completedNotes.add(created);
          await channel.invokeMethod<void>('acknowledge', action['mutationId']);
          continue;
        }
        if (action['subtaskId'] != null) {
          final notes = await repository.fetchNotes(board);
          final note = notes
              .where((n) => n.id == action['id'] && n.deletedAt == null)
              .firstOrNull;
          if (note == null ||
              !note.checklist.any((item) => item.id == action['subtaskId'])) {
            await channel.invokeMethod<void>(
              'acknowledge',
              action['mutationId'],
            );
            continue;
          }
          final updated = await repository.updateNote(note.id, {
            'checklist': note.checklist
                .map(
                  (item) =>
                      (item.id == action['subtaskId']
                              ? item.copyWith(isCompleted: true)
                              : item)
                          .toJson(),
                )
                .toList(),
            'expectedRevision': note.revision,
            'clientMutationId': action['mutationId'],
          });
          if (!_disposed && owner == account) _completedNotes.add(updated);
          await channel.invokeMethod<void>('acknowledge', action['mutationId']);
          continue;
        }
        final completed = await repository.updateNote(action['id'] as String, {
          'isCompleted': true,
          'completedAt': DateTime.fromMillisecondsSinceEpoch(
            action['completedAt'] as int,
          ).toUtc().toIso8601String(),
          'expectedRevision': action['revision'],
          'clientMutationId': action['mutationId'],
        });
        if (!_disposed && owner == account) _completedNotes.add(completed);
        await channel.invokeMethod<void>('acknowledge', action['mutationId']);
      } catch (_) {
        // The native queue is acknowledged only after the repository persists it.
        // Retry on the next foreground or repository event.
      }
    }
  }

  Future<void> _publish(Map<String, dynamic> snapshot) {
    final colorTheme = themeController?.colorTheme ?? AppColorTheme.sunset;
    Map<String, int> palette(bool dark) {
      final scheme =
          (dark ? AppTheme.darkFor(colorTheme) : AppTheme.lightFor(colorTheme))
              .colorScheme;
      return {
        'ink': scheme.onSurface.toARGB32(),
        'muted': Color.alphaBlend(
          scheme.onSurface.withValues(alpha: .65),
          scheme.surface,
        ).toARGB32(),
        'accent': scheme.primary.toARGB32(),
        'start': Color.alphaBlend(
          scheme.primary.withValues(alpha: dark ? .24 : .12),
          scheme.surface,
        ).toARGB32(),
        'end': Color.alphaBlend(
          scheme.secondary.withValues(alpha: dark ? .14 : .07),
          scheme.surface,
        ).toARGB32(),
      };
    }

    return channel.invokeMethod<void>(
      'publish',
      jsonEncode({
        ...snapshot,
        'theme': {
          'mode': themeController?.themeMode.name ?? 'system',
          'light': palette(false),
          'dark': palette(true),
        },
      }),
    );
  }

  @override
  void didChangePlatformBrightness() => refresh();

  Future<void> _takeAction() async {
    try {
      final raw = await channel.invokeMapMethod<String, String>('takeAction');
      if (raw != null && (raw['owner'] == null || raw['owner'] == owner)) {
        _pendingAction = Map.of(raw);
        if (!_disposed) notifyListeners();
      }
    } on MissingPluginException {
      /* No widget host on desktop/tests. */
    }
  }

  Map<String, String>? takeAction() {
    final action = _pendingAction;
    _pendingAction = null;
    return action != null && action['owner'] != null && action['owner'] != owner
        ? null
        : action;
  }

  Future<bool> requestPin({HomeWidgetKind kind = HomeWidgetKind.list}) async =>
      supported &&
      defaultTargetPlatform == TargetPlatform.android &&
      (await channel.invokeMethod<bool>('requestPin', {'kind': kind.name}) ??
          false);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_takeAction());
      refresh();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_completedNotes.close());
    _generation++;
    _timer?.cancel();
    _events?.cancel();
    _authEvents?.cancel();
    protection.removeListener(_privacyChanged);
    themeController?.removeListener(refresh);
    WidgetsBinding.instance.removeObserver(this);
    if (supported) channel.setMethodCallHandler(null);
    super.dispose();
  }
}
