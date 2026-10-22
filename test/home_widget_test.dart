import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/auth/data/auth_repository.dart';
import 'package:nocknock/features/auth/domain/app_user.dart';
import 'package:nocknock/features/home_widgets/home_widget_controller.dart';
import 'package:nocknock/features/notes/data/list_protection_controller.dart';
import 'package:nocknock/features/notes/data/local_notes_repository.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

final now = DateTime(2026, 10, 22, 12);
NoteList list(String id, {bool keyPending = false}) => NoteList(
  id: id,
  name: 'Lista $id',
  createdAt: now,
  updatedAt: now,
  isEncryptionKeyPending: keyPending,
);
Note note(
  String id, {
  String board = 'public',
  DateTime? reminder,
  bool done = false,
  List<String>? assigned,
  DateTime? deleted,
  bool recurring = false,
}) => Note(
  id: id,
  boardId: board,
  title: 'Título $id',
  content: 'CUERPO SECRETO',
  color: NoteColor.yellow,
  authorName: 'Autor secreto',
  isCompleted: done,
  positionX: 0,
  positionY: 0,
  createdAt: now,
  updatedAt: now,
  revision: 7,
  reminderAt: reminder,
  assigneeUids: assigned,
  deletedAt: deleted,
  reminderRecurrence: recurring
      ? const ReminderRecurrence(
          frequency: ReminderRecurrenceFrequency.daily,
          interval: 1,
          timeZoneOffsetMinutes: 0,
        )
      : null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('Today includes overdue, today and undated assigned notes only', () {
    final snapshot = buildHomeWidgetSnapshot(
      owner: 'u',
      lists: [list('public')],
      notes: [
        note('old', reminder: now.subtract(const Duration(days: 1))),
        note('today', reminder: now),
        note('tomorrow', reminder: DateTime(2026, 10, 23), assigned: ['u']),
        note('mine', assigned: ['u']),
        note('other', assigned: ['someone']),
        note('done', done: true, reminder: now),
        note('deleted', deleted: now, reminder: now),
      ],
      isProtected: (_) => false,
      now: now,
      userId: 'u',
    );
    expect((snapshot['rows'] as List).map((row) => row['id']), [
      'old',
      'today',
      'mine',
    ]);
    expect(snapshot['total'], 3);
  });

  test('protected, removed and key-pending lists never expose titles', () {
    final snapshot = buildHomeWidgetSnapshot(
      owner: 'u',
      lists: [
        list('public'),
        list('private'),
        list('locked', keyPending: true),
      ],
      notes: [
        note('ok', reminder: now),
        note('SECRET', board: 'private', reminder: now),
        note('KEY', board: 'locked', reminder: now),
        note('REMOVED', board: 'gone', reminder: now),
      ],
      isProtected: (id) => id == 'private',
      now: now,
    );
    final serialized = jsonEncode(snapshot);
    expect(snapshot['total'], 1);
    for (final secret in [
      'SECRET',
      'KEY',
      'REMOVED',
      'CUERPO SECRETO',
      'Autor secreto',
    ]) {
      expect(serialized, isNot(contains(secret)));
    }
  });

  test('selected list includes undated tasks, counts all and sends only five titles', () {
    final snapshot = buildHomeWidgetSnapshot(
      owner: 'guest',
      lists: [list('public')],
      notes: [...List.generate(8, (i) => note('$i')), note('0')],
      isProtected: (_) => false,
      now: now,
      listId: 'public',
      captureListId: 'public',
    );
    expect(snapshot['total'], 8);
    expect(snapshot['rows'], hasLength(5));
    expect(snapshot['captureListId'], 'public');
    expect(snapshot['listId'], 'public');
  });

  test('privacy mode hides names, counts and rows; protected capture destination is removed', () {
    final snapshot = buildHomeWidgetSnapshot(
      owner: 'u',
      lists: [list('private')],
      notes: [note('secret', board: 'private')],
      isProtected: (_) => true,
      now: now,
      listId: 'private',
      captureListId: 'private',
      hideContent: true,
    );
    expect(snapshot['rows'], isEmpty);
    expect(snapshot['total'], 0);
    expect(snapshot['listId'], isNull);
    expect(snapshot['captureListId'], isNull);
    expect(jsonEncode(snapshot), isNot(contains('private')));
  });

  test('recurring reminders open in app instead of permanently completing the series', () {
    final snapshot = buildHomeWidgetSnapshot(
      owner: 'u',
      lists: [list('public')],
      notes: [note('repeat', reminder: now, recurring: true)],
      isProtected: (_) => false,
      now: now,
    );
    expect((snapshot['rows'] as List).single['canComplete'], false);
  });

  group('durable widget actions', () {
    const channel = MethodChannel('cl.nocknock/home_widgets');
    late _Repository repository;
    late _Auth auth;
    late ListProtectionController protection;
    late HomeWidgetController controller;
    late List<Map<String, dynamic>> queue;
    late List<Map<String, dynamic>> published;
    Map<String, String>? launch;

    setUp(() async {
      repository = _Repository();
      auth = _Auth();
      protection = ListProtectionController(
        preferences: await SharedPreferences.getInstance(),
      );
      queue = [];
      published = [];
      launch = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'publish':
                published.add(
                  Map<String, dynamic>.from(
                    jsonDecode(call.arguments as String) as Map,
                  ),
                );
                return null;
              case 'readQueue':
                return jsonEncode(queue);
              case 'acknowledge':
                queue.removeWhere(
                  (action) => action['mutationId'] == call.arguments,
                );
                return null;
              case 'takeAction':
                final action = launch;
                launch = null;
                return action;
            }
            return null;
          });
      controller = HomeWidgetController(
        repository: repository,
        auth: auth,
        protection: protection,
      );
    });
    tearDown(() async {
      controller.dispose();
      protection.dispose();
      repository.dispose();
      await auth.events.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    Future<Note> enqueue({String owner = 'guest'}) async {
      final saved = await repository.createNote(
        'home',
        const NoteDraft(
          title: 'Pendiente',
          content: '',
          color: NoteColor.none,
          authorName: 'Invitado',
        ),
      );
      queue.add({
        'id': saved.id,
        'boardId': 'home',
        'owner': owner,
        'revision': saved.revision,
        'mutationId': 'widget-mutation',
        'completedAt': now.millisecondsSinceEpoch,
      });
      return saved;
    }

    test(
      'completion is acknowledged only after repository persistence',
      () async {
        final saved = await enqueue();
        await controller.start();
        await controller.refreshNow();
        expect((await repository.fetchNotes('home')).single.isCompleted, true);
        expect(queue, isEmpty);
        expect(
          repository.changes.single['clientMutationId'],
          'widget-mutation',
        );
        expect(repository.changes.single['expectedRevision'], saved.revision);
      },
    );

    test(
      'failed writes remain queued and retry with the same mutation ID',
      () async {
        await enqueue();
        repository.fail = true;
        await controller.start();
        await controller.refreshNow();
        expect(queue, hasLength(1));
        expect((await repository.fetchNotes('home')).single.isCompleted, false);
        repository.fail = false;
        await controller.refreshNow();
        expect(queue, isEmpty);
        expect(
          repository.changes
              .map((change) => change['clientMutationId'])
              .toSet(),
          {'widget-mutation'},
        );
      },
    );

    test('a different account cannot replay old completions', () async {
      await enqueue(owner: 'another-account');
      await controller.start();
      await controller.refreshNow();
      expect(repository.changes, isEmpty);
      expect((await repository.fetchNotes('home')).single.isCompleted, false);
      expect(queue, isEmpty);
    });

    test(
      'cold start capture is delivered once and rejected after account change',
      () async {
        launch = {'action': 'capture', 'owner': 'guest', 'boardId': 'home'};
        await controller.start();
        expect(controller.takeAction()?['action'], 'capture');
        expect(controller.takeAction(), isNull);
        launch = {'action': 'capture', 'owner': 'guest'};
        controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await Future<void>.delayed(Duration.zero);
        auth.user = const AppUser(
          id: 'other',
          displayName: 'Other',
          email: 'other@example.com',
        );
        expect(controller.takeAction(), isNull);
      },
    );

    test('settings survive restart and startup clears stale titles before fetching', () async {
      await controller.start();
      await controller.configure(source: 'home', capture: 'home', hidden: true);
      await controller.refreshNow();
      expect(controller.listId, 'home');
      expect(controller.captureListId, 'home');
      expect(controller.hideContent, true);
      expect(published.first['hidden'], true);
      expect(published.last['rows'], isEmpty);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'home_widget.guest.hidden',
        ),
        true,
      );
    });
  });
}

class _Repository extends LocalNotesRepository {
  bool fail = false;
  final changes = <Map<String, dynamic>>[];
  @override
  Future<Note> updateNote(String id, Map<String, dynamic> value) {
    changes.add(Map.of(value));
    if (fail) throw const FormatException('write failed');
    return super.updateNote(id, value);
  }
}

class _Auth implements AuthRepository {
  AppUser? user;
  final events = StreamController<AppUser?>.broadcast();
  @override
  AppUser? get currentUser => user;
  @override
  Stream<AppUser?> get authStateChanges => events.stream;
  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => null;
  @override
  Future<void> signInWithGoogle() async {}
  @override
  Future<void> signOut() async {
    user = null;
    events.add(null);
  }

  @override
  Future<void> deleteAccount() => signOut();
}
