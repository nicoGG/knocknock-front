// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:nocknock/features/notes/data/notes_repository.dart';
import 'package:nocknock/core/telemetry/app_telemetry.dart';
import 'package:nocknock/core/telemetry/telemetry_dio.dart';
import 'package:nocknock/features/notes/data/resilient_web_socket.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class ApiNotesRepository
    implements
        NotesRepository,
        GuestDataSyncTarget,
        E2eeNotesTransport,
        AggregateBoardAppearancesRepository,
        NoteAttachmentsRepository,
        PaginatedNotesRepository {
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
             .setWebSocketConnector(connectResilientWebSocket)
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
      ..onReconnectAttempt(
        (_) => _events.add(const RealtimeConnectionAttemptStarted()),
      )
      ..onConnectError(
        (_) => _events.add(const RealtimeConnectionChanged(false)),
      )
      ..onReconnectFailed(
        (_) => _events.add(const RealtimeConnectionChanged(false)),
      )
      ..onDisconnect((_) => _events.add(const RealtimeConnectionChanged(false)))
      ..on('note:created', _onNoteChanged)
      ..on('note:updated', _onNoteChanged)
      ..on('list:appearance-updated', _onListAppearanceChanged)
      ..on('list:name-updated', _onListNameChanged)
      ..on(
        'account:aggregate-board-appearance-updated',
        _onAggregateBoardAppearanceChanged,
      )
      ..on('list:access-removed', (data) {
        final listId = _asJson(data)?['listId'] as String?;
        if (listId != null) _events.add(ListAccessRemoved(listId));
      })
      ..on('encryption:key-share-requested', (data) {
        final listId = _asJson(data)?['listId'] as String?;
        if (listId != null) _events.add(ListKeyShareRequested(listId));
      })
      ..on('encryption:key-envelope-updated', (data) {
        final listId = _asJson(data)?['listId'] as String?;
        if (listId != null) _events.add(ListKeyEnvelopeUpdated(listId));
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
      _events.add(const RealtimeConnectionAttemptStarted());
      final String? token;
      try {
        token = await _accessTokenProvider();
      } on Object {
        _events.add(const RealtimeConnectionChanged(false));
        rethrow;
      }
      if (token == null || token.isEmpty) {
        _events.add(const RealtimeConnectionChanged(false));
        return;
      }
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
  Future<void> registerEncryptionDevice({
    required String deviceId,
    required String publicKey,
  }) async {
    await _dio.post<void>(
      '/encryption/devices',
      data: {'deviceId': deviceId, 'publicKey': publicKey},
    );
  }

  @override
  Future<NoteList> createEncryptedList({
    required String encryptedName,
    required ListKeyEnvelope keyEnvelope,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/lists',
      data: {
        'name': encryptedName,
        'encryptionVersion': 1,
        'keyEnvelope': keyEnvelope.toJson(),
      },
    );
    return NoteList.fromJson(response.data!);
  }

  @override
  Future<NoteList> enableListEncryption({
    required String listId,
    required String encryptedName,
    required String? encryptedCustomBackgroundImage,
    required ListKeyEnvelope keyEnvelope,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/lists/$listId/encryption',
      data: {
        'name': encryptedName,
        'customBackgroundImage': ?encryptedCustomBackgroundImage,
        'keyEnvelope': keyEnvelope.toJson(),
      },
    );
    return NoteList.fromJson(response.data!);
  }

  @override
  Future<List<EncryptionRecipient>> fetchEncryptionRecipients(
    String listId,
  ) async {
    final response = await _dio.get<List<dynamic>>(
      '/lists/$listId/encryption/recipients',
    );
    return (response.data ?? const [])
        .map(
          (item) => EncryptionRecipient.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  @override
  Future<void> storeListKeyEnvelope({
    required String listId,
    required String recipientUid,
    required String deviceId,
    required String envelope,
  }) => _dio.post<void>(
    '/lists/$listId/encryption/envelopes',
    data: {
      'recipientUid': recipientUid,
      'deviceId': deviceId,
      'envelope': envelope,
    },
  );

  @override
  Future<NoteList> updateList(String listId, String name) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/lists/$listId',
      data: {'name': name},
    );
    return NoteList.fromJson(response.data!);
  }

  @override
  Future<List<NoteList>> reorderLists(List<String> orderedIds) async {
    final response = await _dio.patch<List<dynamic>>(
      '/lists/reorder',
      data: {'orderedIds': orderedIds},
    );
    return (response.data ?? const [])
        .map(
          (item) => NoteList.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
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
  Future<AggregateBoardAppearances> fetchAggregateBoardAppearances() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/account/aggregate-board-appearances',
    );
    return AggregateBoardAppearances.fromJson(response.data);
  }

  @override
  Future<AggregateBoardAppearances> updateAggregateBoardAppearance(
    AggregateBoardScope scope,
    ListAppearance appearance,
  ) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/account/aggregate-board-appearances/${scope.name}',
      data: appearance.toJson(),
    );
    return AggregateBoardAppearances.fromJson(response.data);
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
  Future<NotesPage> fetchNotesPage(
    String boardId, {
    String? cursor,
    int limit = 40,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/notes/page',
      queryParameters: {'boardId': boardId, 'limit': limit, 'cursor': ?cursor},
    );
    final data = response.data ?? const <String, dynamic>{};
    return NotesPage(
      items: (data['items'] as List<dynamic>? ?? const [])
          .map((item) => Note.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
      nextCursor: data['nextCursor'] as String?,
    );
  }

  @override
  Future<List<Note>> fetchPinnedNotes() async {
    final response = await _dio.get<List<dynamic>>('/notes/pinned');
    return (response.data ?? const [])
        .map((item) => Note.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  @override
  Future<List<Note>> fetchReminderNotes() async {
    final response = await _dio.get<List<dynamic>>('/notes/reminders');
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
  Future<NoteAttachment> fetchAttachment(
    String noteId,
    String attachmentId,
  ) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/notes/$noteId/attachments/${Uri.encodeComponent(attachmentId)}',
    );
    return NoteAttachment.fromJson(response.data!);
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
  Future<Note> setNoteReaction(String id, String emoji, bool active) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/notes/$id/reactions',
      data: {'emoji': emoji, 'active': active},
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
  Future<void> deleteNote(
    String id, {
    int? expectedRevision,
    String? clientMutationId,
  }) => _dio.delete<void>(
    '/notes/$id',
    data: {
      'expectedRevision': ?expectedRevision,
      'clientMutationId': ?clientMutationId,
    },
  );

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
                'encryptionVersion': list.encryption.version,
                'keyEnvelope': list.encryption.keyEnvelopes.single.toJson(),
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
                if (note.customAssigneeName != null)
                  'customAssigneeName': note.customAssigneeName,
                'attachments': note.photoAttachments
                    .map((entry) => entry.toJson())
                    .toList(),
                'isCompleted': note.isCompleted,
                'isPinned': note.isPinned,
                'sortOrder': note.sortOrder,
                'positionX': note.positionX,
                'positionY': note.positionY,
                if (note.reminderAt != null)
                  'reminderAt': note.reminderAt!.toIso8601String(),
                'reactions': note.reactions
                    .where(
                      (reaction) =>
                          reaction.isSelectedBy(localNoteReactionUserId),
                    )
                    .map((reaction) => reaction.emoji)
                    .toList(),
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

  void _onListNameChanged(dynamic data) {
    final json = _asJson(data);
    final listId = json?['listId'] as String?;
    final name = json?['name'] as String?;
    final updatedAt = DateTime.tryParse(json?['updatedAt'] as String? ?? '');
    if (listId != null && name != null && updatedAt != null) {
      _events.add(ListNameChanged(listId, name, updatedAt));
    }
  }

  void _onAggregateBoardAppearanceChanged(dynamic data) {
    final json = _asJson(data);
    final scopeName = json?['scope'] as String?;
    final rawAppearance = json?['appearance'];
    final scope = AggregateBoardScope.values
        .where((candidate) => candidate.name == scopeName)
        .firstOrNull;
    if (scope != null && rawAppearance is Map) {
      _events.add(
        AggregateBoardAppearanceChanged(
          scope,
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
