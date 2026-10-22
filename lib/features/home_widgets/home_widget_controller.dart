import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nocknock/features/auth/data/auth_repository.dart';
import 'package:nocknock/features/notes/data/list_protection_controller.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';

/// Only the five visible titles are shared with the native widget. No tokens,
/// attachments, note bodies or protected-list names leave the app repository.
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
            note.financialEntry!.status != 'pending') ||
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
    this.channel = const MethodChannel('cl.nocknock/home_widgets'),
  });
  final NotesRepository repository;
  final AuthRepository auth;
  final ListProtectionController protection;
  final MethodChannel channel;
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  String get owner => auth.currentUser?.id ?? 'guest';
  String? listId;
  String? captureListId;
  bool hideContent = false;
  String? error;
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
      await _publish(
        buildHomeWidgetSnapshot(
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
      );
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
        await repository.updateNote(action['id'] as String, {
          'isCompleted': true,
          'completedAt': DateTime.fromMillisecondsSinceEpoch(
            action['completedAt'] as int,
          ).toUtc().toIso8601String(),
          'expectedRevision': action['revision'],
          'clientMutationId': action['mutationId'],
        });
        await channel.invokeMethod<void>('acknowledge', action['mutationId']);
      } catch (_) {
        // The native queue is acknowledged only after the repository persists it.
        // Retry on the next foreground or repository event.
      }
    }
  }

  Future<void> _publish(Map<String, dynamic> snapshot) =>
      channel.invokeMethod<void>('publish', jsonEncode(snapshot));

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

  Future<bool> requestPin() async =>
      supported &&
      defaultTargetPlatform == TargetPlatform.android &&
      (await channel.invokeMethod<bool>('requestPin') ?? false);

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
    _generation++;
    _timer?.cancel();
    _events?.cancel();
    _authEvents?.cancel();
    protection.removeListener(_privacyChanged);
    WidgetsBinding.instance.removeObserver(this);
    if (supported) channel.setMethodCallHandler(null);
    super.dispose();
  }
}
