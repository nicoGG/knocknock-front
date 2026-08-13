import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

OfflineMutationStore createPersistentOfflineMutationStore(
  SharedPreferences preferences,
) {
  final fallback = SharedPreferencesOfflineMutationStore(preferences);
  if (kIsWeb) return fallback;
  return ResilientOfflineMutationStore(
    primary: SqfliteOfflineMutationStore(),
    fallback: fallback,
  );
}

enum StoredMutationKind { create, update, delete, reaction, reorder }

enum StoredMutationStatus { pending, conflict }

class StoredOfflineMutation {
  const StoredOfflineMutation({
    required this.id,
    required this.userId,
    required this.entityId,
    required this.boardId,
    required this.kind,
    required this.payload,
    required this.baseRevision,
    required this.createdAt,
    this.status = StoredMutationStatus.pending,
    this.localNoteJson,
    this.remoteNoteJson,
    this.errorMessage,
  });

  final String id;
  final String userId;
  final String entityId;
  final String boardId;
  final StoredMutationKind kind;

  /// Contains only the transport representation. In authenticated flows this
  /// store sits below E2EE, so user-authored fields are ciphertext.
  final String payload;
  final int baseRevision;
  final DateTime createdAt;
  final StoredMutationStatus status;
  final String? localNoteJson;
  final String? remoteNoteJson;
  final String? errorMessage;

  StoredOfflineMutation copyWith({
    String? payload,
    int? baseRevision,
    StoredMutationStatus? status,
    String? localNoteJson,
    String? remoteNoteJson,
    String? errorMessage,
    bool clearRemoteNote = false,
    bool clearError = false,
  }) => StoredOfflineMutation(
    id: id,
    userId: userId,
    entityId: entityId,
    boardId: boardId,
    kind: kind,
    payload: payload ?? this.payload,
    baseRevision: baseRevision ?? this.baseRevision,
    createdAt: createdAt,
    status: status ?? this.status,
    localNoteJson: localNoteJson ?? this.localNoteJson,
    remoteNoteJson: clearRemoteNote
        ? null
        : remoteNoteJson ?? this.remoteNoteJson,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'user_id': userId,
    'entity_id': entityId,
    'board_id': boardId,
    'kind': kind.name,
    'payload': payload,
    'base_revision': baseRevision,
    'created_at': createdAt.millisecondsSinceEpoch,
    'status': status.name,
    'local_note_json': localNoteJson,
    'remote_note_json': remoteNoteJson,
    'error_message': errorMessage,
  };

  factory StoredOfflineMutation.fromRow(Map<String, Object?> row) =>
      StoredOfflineMutation(
        id: row['id']! as String,
        userId: row['user_id']! as String,
        entityId: row['entity_id']! as String,
        boardId: row['board_id']! as String,
        kind: StoredMutationKind.values.byName(row['kind']! as String),
        payload: row['payload']! as String,
        baseRevision: row['base_revision']! as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row['created_at']! as int,
        ),
        status: StoredMutationStatus.values.byName(row['status']! as String),
        localNoteJson: row['local_note_json'] as String?,
        remoteNoteJson: row['remote_note_json'] as String?,
        errorMessage: row['error_message'] as String?,
      );
}

abstract interface class OfflineMutationStore {
  Future<List<StoredOfflineMutation>> listForUser(String userId);

  Future<void> put(StoredOfflineMutation mutation);

  Future<void> remove(String mutationId);

  Future<void> close();
}

/// Keeps the offline queue available when a newly added native plugin has not
/// been registered yet (for example, after hot restart instead of a cold run).
/// Once the primary store is available again, fallback rows are migrated into
/// it before they are returned.
class ResilientOfflineMutationStore implements OfflineMutationStore {
  factory ResilientOfflineMutationStore({
    required OfflineMutationStore primary,
    required OfflineMutationStore fallback,
  }) => ResilientOfflineMutationStore._(primary, fallback);

  ResilientOfflineMutationStore._(this._primary, this._fallback);

  final OfflineMutationStore _primary;
  final OfflineMutationStore _fallback;
  bool _useFallback = false;

  @override
  Future<List<StoredOfflineMutation>> listForUser(String userId) async {
    if (_useFallback) return _fallback.listForUser(userId);
    try {
      final primaryItems = await _primary.listForUser(userId);
      final fallbackItems = await _fallback.listForUser(userId);
      if (fallbackItems.isEmpty) return primaryItems;

      for (final mutation in fallbackItems) {
        await _primary.put(mutation);
      }
      for (final mutation in fallbackItems) {
        await _fallback.remove(mutation.id);
      }

      final merged = <String, StoredOfflineMutation>{
        for (final mutation in primaryItems) mutation.id: mutation,
        for (final mutation in fallbackItems) mutation.id: mutation,
      }.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return merged;
    } on MissingPluginException {
      _useFallback = true;
      return _fallback.listForUser(userId);
    }
  }

  @override
  Future<void> put(StoredOfflineMutation mutation) async {
    if (_useFallback) return _fallback.put(mutation);
    try {
      await _primary.put(mutation);
    } on MissingPluginException {
      _useFallback = true;
      await _fallback.put(mutation);
    }
  }

  @override
  Future<void> remove(String mutationId) async {
    if (_useFallback) return _fallback.remove(mutationId);
    try {
      await _primary.remove(mutationId);
      await _fallback.remove(mutationId);
    } on MissingPluginException {
      _useFallback = true;
      await _fallback.remove(mutationId);
    }
  }

  @override
  Future<void> close() async {
    await _primary.close();
    await _fallback.close();
  }
}

class InMemoryOfflineMutationStore implements OfflineMutationStore {
  final _mutations = <String, StoredOfflineMutation>{};

  @override
  Future<List<StoredOfflineMutation>> listForUser(String userId) async {
    final items =
        _mutations.values
            .where((mutation) => mutation.userId == userId)
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return items;
  }

  @override
  Future<void> put(StoredOfflineMutation mutation) async {
    _mutations[mutation.id] = mutation;
  }

  @override
  Future<void> remove(String mutationId) async {
    _mutations.remove(mutationId);
  }

  @override
  Future<void> close() async {}
}

class SharedPreferencesOfflineMutationStore implements OfflineMutationStore {
  SharedPreferencesOfflineMutationStore(this._preferences);

  static const _storageKey = 'nocknock.offline_mutations.web.v1';

  final SharedPreferences _preferences;
  final _mutations = <String, StoredOfflineMutation>{};
  Future<void>? _loadFuture;
  Future<void> _writeQueue = Future.value();

  Future<void> _ensureLoaded() => _loadFuture ??= Future<void>(() {
    final raw = _preferences.getString(_storageKey);
    if (raw == null) return;
    try {
      final rows = jsonDecode(raw) as List<dynamic>;
      for (final row in rows) {
        final mutation = StoredOfflineMutation.fromRow(
          Map<String, Object?>.from(row as Map),
        );
        _mutations[mutation.id] = mutation;
      }
    } on Object {
      _mutations.clear();
    }
  });

  @override
  Future<List<StoredOfflineMutation>> listForUser(String userId) async {
    await _writeQueue;
    await _ensureLoaded();
    final items =
        _mutations.values
            .where((mutation) => mutation.userId == userId)
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return items;
  }

  @override
  Future<void> put(StoredOfflineMutation mutation) => _enqueueWrite(() {
    _mutations[mutation.id] = mutation;
  });

  @override
  Future<void> remove(String mutationId) => _enqueueWrite(() {
    _mutations.remove(mutationId);
  });

  Future<void> _enqueueWrite(void Function() update) {
    final operation = _writeQueue.then((_) async {
      await _ensureLoaded();
      update();
      await _preferences.setString(
        _storageKey,
        jsonEncode(_mutations.values.map((item) => item.toRow()).toList()),
      );
    });
    _writeQueue = operation;
    return operation;
  }

  @override
  Future<void> close() => _writeQueue;
}

class SqfliteOfflineMutationStore implements OfflineMutationStore {
  SqfliteOfflineMutationStore() : _databaseOpener = _openDefaultDatabase;

  @visibleForTesting
  SqfliteOfflineMutationStore.testing(this._databaseOpener);

  static const _databaseName = 'nocknock_offline_v1.db';
  static const _table = 'offline_mutations';

  final Future<Database> Function() _databaseOpener;
  Future<Database>? _databaseFuture;

  static Future<Database> _openDefaultDatabase() => openDatabase(
    _databaseName,
    version: 1,
    onCreate: (database, _) => database.execute('''
      CREATE TABLE $_table (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        board_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        payload TEXT NOT NULL,
        base_revision INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        status TEXT NOT NULL,
        local_note_json TEXT,
        remote_note_json TEXT,
        error_message TEXT
      )
    '''),
  );

  Future<Database> get _db {
    final existing = _databaseFuture;
    if (existing != null) return existing;

    final opening = Future<Database>.sync(_databaseOpener);
    _databaseFuture = opening;
    unawaited(
      opening.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (identical(_databaseFuture, opening)) {
            _databaseFuture = null;
          }
        },
      ),
    );
    return opening;
  }

  @override
  Future<List<StoredOfflineMutation>> listForUser(String userId) async {
    final rows = await (await _db).query(
      _table,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at ASC',
    );
    return rows.map(StoredOfflineMutation.fromRow).toList();
  }

  @override
  Future<void> put(StoredOfflineMutation mutation) async {
    await (await _db).insert(
      _table,
      mutation.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> remove(String mutationId) async {
    await (await _db).delete(_table, where: 'id = ?', whereArgs: [mutationId]);
  }

  @override
  Future<void> close() async {
    final opening = _databaseFuture;
    _databaseFuture = null;
    if (opening == null) return;

    final Database database;
    try {
      database = await opening;
    } catch (_) {
      return;
    }
    await database.close();
  }
}
