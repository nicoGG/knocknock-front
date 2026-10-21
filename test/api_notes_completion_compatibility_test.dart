import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/data/api_notes_repository.dart';
import 'package:nocknock/features/notes/data/cached_notes_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final ResponseBody Function(RequestOptions) respond;
  final List<Map<String, dynamic>> patches = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'PATCH') {
      patches.add(Map<String, dynamic>.from(options.data as Map));
    }
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object data, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(data),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, dynamic> _note({bool completed = false}) => {
  'id': 'note-1',
  'boardId': 'home',
  'title': 'Tarea',
  'content': '',
  'authorName': 'Nico',
  'isCompleted': completed,
  'color': 'blue',
  'createdAt': '2026-10-20T10:00:00Z',
  'updatedAt': '2026-10-20T12:00:00Z',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy server completes with the same mutation and retains its observed date on reload', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    var completed = false;
    final adapter = _Adapter((options) {
      if (options.method == 'GET') return _json([_note(completed: completed)]);
      final body = options.data as Map;
      if (body.containsKey('completedAt')) {
        return _json({
          'message': ['property completedAt should not exist'],
        }, 400);
      }
      completed = body['isCompleted'] == true;
      return _json(_note(completed: completed));
    });
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;
    final api = ApiNotesRepository(
      apiBaseUrl: 'https://example.test',
      socketBaseUrl: 'https://example.test',
      accessTokenProvider: () async => null,
      httpClient: dio,
    );
    final cached = CachedNotesRepository(
      repository: api,
      preferences: preferences,
      userIdProvider: () => 'user-1',
    );
    addTearDown(() {
      cached.dispose();
      api.dispose();
    });
    await cached.fetchNotes('home');
    final changes = {
      'isCompleted': true,
      'completedAt': '2026-10-20T12:00:00Z',
      'expectedRevision': 0,
      'clientMutationId': 'mutation-1',
    };
    final saved = await cached.updateNote('note-1', changes);
    expect(saved.isCompleted, isTrue);
    expect(saved.completedAt!.toUtc(), DateTime.utc(2026, 10, 20, 12));
    expect(adapter.patches, hasLength(2));
    expect(adapter.patches[1], {
      'isCompleted': true,
      'expectedRevision': 0,
      'clientMutationId': 'mutation-1',
    });
    expect(changes, contains('completedAt'));
    final reloaded = (await cached.fetchNotes('home')).single;
    expect(reloaded.completedAt!.toUtc(), saved.completedAt!.toUtc());
    final reopened = await cached.updateNote('note-1', {
      'isCompleted': false,
      'completedAt': null,
    });
    expect(adapter.patches, hasLength(3));
    expect(adapter.patches.last, isNot(contains('completedAt')));
    expect(reopened.isCompleted, isFalse);
    expect(reopened.completedAt, isNull);
  });

  test('modern server receives and returns authoritative completion dates without retry', () async {
    final adapter = _Adapter(
      (_) => _json({
        ..._note(completed: true),
        'completedAt': '2026-10-19T10:00:00Z',
      }),
    );
    final api = ApiNotesRepository(
      apiBaseUrl: 'https://example.test',
      socketBaseUrl: 'https://example.test',
      accessTokenProvider: () async => null,
      httpClient: Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = adapter,
    );
    addTearDown(api.dispose);
    final saved = await api.updateNote('note-1', {
      'isCompleted': true,
      'completedAt': '2026-10-20T12:00:00Z',
    });
    expect(adapter.patches, hasLength(1));
    expect(adapter.patches.single, contains('completedAt'));
    expect(saved.completedAt!.toUtc(), DateTime.utc(2026, 10, 19, 10));
  });

  for (final status in [400, 403, 409, 500]) {
    test('does not hide or retry unrelated $status errors', () async {
      final adapter = _Adapter((_) => _json({'message': 'Otro error'}, status));
      final api = ApiNotesRepository(
        apiBaseUrl: 'https://example.test',
        socketBaseUrl: 'https://example.test',
        accessTokenProvider: () async => null,
        httpClient: Dio(BaseOptions(baseUrl: 'https://example.test'))
          ..httpClientAdapter = adapter,
      );
      addTearDown(api.dispose);
      await expectLater(
        api.updateNote('note-1', {
          'isCompleted': true,
          'completedAt': '2026-10-20T12:00:00Z',
        }),
        throwsA(isA<DioException>()),
      );
      expect(adapter.patches, hasLength(1));
    });
  }
}
