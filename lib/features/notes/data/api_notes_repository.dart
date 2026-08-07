// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/core/telemetry/app_telemetry.dart';
import 'package:nocknock/core/telemetry/telemetry_dio.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class ApiNotesRepository implements NotesRepository, GuestDataSyncTarget {
  ApiNotesRepository({
    required String apiBaseUrl,
    required String socketBaseUrl,
    required Future<String?> Function() accessTokenProvider,
    AppTelemetry? telemetry,
  }) : _accessTokenProvider = accessTokenProvider,
       _dio = createTelemetryDio(
         BaseOptions(baseUrl: apiBaseUrl),
         telemetry: telemetry,
       ),
       _socket = io.io(
         '$socketBaseUrl/notes',
         io.OptionBuilder()
             .setTransports(['websocket'])
             .disableAutoConnect()
             .build(),
       ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _accessTokenProvider();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
    _socket
      ..on('connection:ready', (_) {
        _events.add(const RealtimeConnectionChanged(true));
        if (_boardId case final boardId?) {
          _socket.emit('board:join', boardId);
        }
      })
      ..on(
        'connection:error',
        (_) => _events.add(const RealtimeConnectionChanged(false)),
      )
      ..onDisconnect((_) => _events.add(const RealtimeConnectionChanged(false)))
      ..on('note:created', _onNoteChanged)
      ..on('note:updated', _onNoteChanged)
      ..on('list:appearance-updated', _onListAppearanceChanged)
      ..on('list:access-removed', (data) {
        final listId = _asJson(data)?['listId'] as String?;
        if (listId != null) _events.add(ListAccessRemoved(listId));
      })
      ..on('notes:reordered', (data) {
        final json = _asJson(data);
        final boardId = json?['boardId'] as String?;
        final rawNotes = json?['notes'];
        if (boardId != null && rawNotes is List) {
          _events.add(
            NotesReordered(
              boardId,
              rawNotes
                  .map(
                    (item) =>
                        Note.fromJson(Map<String, dynamic>.from(item as Map)),
                  )
                  .toList(),
            ),
          );
        }
      })
      ..on('note:deleted', (data) {
        final json = _asJson(data);
        final id = json?['id'] as String?;
        final boardId = json?['boardId'] as String?;
        if (id != null && boardId != null) {
          _events.add(NoteRemoved(id, boardId));
        }
      });
  }

  final Dio _dio;
  final io.Socket _socket;
  final Future<String?> Function() _accessTokenProvider;
  final _events = StreamController<NotesRealtimeEvent>.broadcast();
  String? _boardId;

  @override
  Stream<NotesRealtimeEvent> get realtimeEvents => _events.stream;

  @override
  Future<void> connect(String boardId) async {
    final previousBoardId = _boardId;
    _boardId = boardId;
    if (_socket.connected) {
      if (previousBoardId != null && previousBoardId != boardId) {
        _socket.emit('board:leave', previousBoardId);
      }
      _socket.emit('board:join', boardId);
    } else {
      final token = await _accessTokenProvider();
      if (token == null || token.isEmpty) return;
      _socket.auth = {'token': token};
      _socket.connect();
    }
  }

  @override
  void disconnect() {
    _boardId = null;
    _socket.disconnect();
  }

  @override
  Future<List<NoteList>> fetchLists() async {
    final response = await _dio.get<List<dynamic>>('/lists');
    return (response.data ?? const [])
        .map(
          (item) => NoteList.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  @override
  Future<NoteList> createList(String name) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/lists',
      data: {'name': name},
    );
    return NoteList.fromJson(response.data!);
  }

  @override
  Future<NoteList> updateList(String listId, String name) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/lists/$listId',
      data: {'name': name},
    );
    return NoteList.fromJson(response.data!);
  }

  @override
  Future<void> deleteList(String listId) => _dio.delete<void>('/lists/$listId');

  @override
  Future<NoteList> inviteCollaborator(String listId, String email) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/lists/$listId/invitations',
      data: {'email': email},
    );
    return NoteList.fromJson(response.data!);
  }

  @override
  Future<NoteList> removeCollaborator(
    String listId,
    String collaboratorUid,
  ) async {
    final encodedUid = Uri.encodeComponent(collaboratorUid);
    final response = await _dio.delete<Map<String, dynamic>>(
      '/lists/$listId/collaborators/$encodedUid',
    );
    return NoteList.fromJson(response.data!);
  }

  @override
  Future<NoteList> updateListAppearance(
    String listId,
    ListAppearance appearance,
  ) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/lists/$listId/appearance',
      data: appearance.toJson(),
    );
    return NoteList.fromJson(response.data!);
  }

  @override
  Future<List<Note>> fetchNotes(String boardId) async {
    final response = await _dio.get<List<dynamic>>(
      '/notes',
      queryParameters: {'boardId': boardId},
    );
    return (response.data ?? const [])
        .map((item) => Note.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  @override
  Future<List<Note>> fetchPinnedNotes() async {
    final response = await _dio.get<List<dynamic>>('/notes/pinned');
    return (response.data ?? const [])
        .map((item) => Note.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  @override
  Future<Note> createNote(String boardId, NoteDraft draft) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/notes',
      queryParameters: {'boardId': boardId},
      data: draft.toJson(),
    );
    return Note.fromJson(response.data!);
  }

  @override
  Future<Note> updateNote(String id, Map<String, dynamic> changes) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/notes/$id',
      data: changes,
    );
    return Note.fromJson(response.data!);
  }

  @override
  Future<List<Note>> reorderNotes(
    String boardId,
    List<String> orderedIds,
  ) async {
    final response = await _dio.patch<List<dynamic>>(
      '/notes/reorder',
      queryParameters: {'boardId': boardId},
      data: {'orderedIds': orderedIds},
    );
    return (response.data ?? const [])
        .map((item) => Note.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  @override
  Future<void> deleteNote(String id) => _dio.delete<void>('/notes/$id');

  @override
  Future<GuestDataSyncResult> syncGuestData(LocalNotesSnapshot snapshot) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/sync/guest-data',
      data: {
        'lists': snapshot.lists
            .map(
              (list) => {
                'localId': list.id,
                'name': list.name,
                if (list.id != 'home' ||
                    list.appearance != const ListAppearance())
                  'appearance': list.appearance.toJson(),
                'createdAt': list.createdAt.toIso8601String(),
                'updatedAt': list.updatedAt.toIso8601String(),
              },
            )
            .toList(),
        'notes': snapshot.notes
            .map(
              (note) => {
                'localId': note.id,
                'localBoardId': note.boardId,
                'title': note.title,
                'content': note.content,
                if (note.contentDelta != null)
                  'contentDelta': note.contentDelta,
                'color': note.color.name,
                'category': note.category.name,
                'checklist': note.checklist
                    .map((item) => item.toJson())
                    .toList(),
                'authorName': note.authorName,
                if (note.assigneeUid != null) 'assigneeUid': note.assigneeUid,
                'isCompleted': note.isCompleted,
                'isPinned': note.isPinned,
                'sortOrder': note.sortOrder,
                'positionX': note.positionX,
                'positionY': note.positionY,
                if (note.reminderAt != null)
                  'reminderAt': note.reminderAt!.toIso8601String(),
                'createdAt': note.createdAt.toIso8601String(),
                'updatedAt': note.updatedAt.toIso8601String(),
              },
            )
            .toList(),
      },
    );
    final data = response.data;
    if (data == null) throw const NotesPersistenceFailure();
    final result = GuestDataSyncResult(
      listsImported: (data['listsImported'] as num?)?.toInt() ?? 0,
      notesImported: (data['notesImported'] as num?)?.toInt() ?? 0,
    );
    final expectedLists = snapshot.lists
        .where((list) => list.id != 'home')
        .length;
    if (result.listsImported != expectedLists ||
        result.notesImported != snapshot.notes.length) {
      throw const NotesPersistenceFailure();
    }
    return result;
  }

  void _onNoteChanged(dynamic data) {
    final json = _asJson(data);
    if (json != null) _events.add(NoteChanged(Note.fromJson(json)));
  }

  void _onListAppearanceChanged(dynamic data) {
    final json = _asJson(data);
    final listId = json?['listId'] as String?;
    final rawAppearance = json?['appearance'];
    if (listId != null && rawAppearance is Map) {
      _events.add(
        ListAppearanceChanged(
          listId,
          ListAppearance.fromJson(Map<String, dynamic>.from(rawAppearance)),
        ),
      );
    }
  }

  Map<String, dynamic>? _asJson(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  @override
  void dispose() {
    _socket.dispose();
    unawaited(_events.close());
  }
}
