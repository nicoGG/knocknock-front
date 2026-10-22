import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/finance/list_configuration.dart';
import 'package:nocknock/features/notes/data/api_notes_repository.dart';
import 'package:nocknock/features/notes/domain/note_list.dart';
import 'package:nocknock/features/notes/logic/notes_error_message.dart';

class _ListServer implements HttpClientAdapter {
  _ListServer({this.legacy = true});
  final bool legacy;
  final requests = <Map<String, dynamic>>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    final data = Map<String, dynamic>.from(options.data as Map);
    requests.add(data);
    final rejected =
        legacy &&
        (data.containsKey('listType') || data.containsKey('currency'));
    return ResponseBody.fromString(
      jsonEncode(
        rejected
            ? {
                'message': [
                  'property listType should not exist',
                  'property currency should not exist',
                ],
              }
            : {
                ...data,
                'id': 'list-qa',
                'createdAt': '2026-10-22T14:00:00Z',
                'updatedAt': '2026-10-22T14:00:00Z',
              },
      ),
      rejected ? 400 : 201,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ApiNotesRepository _repository(_ListServer server) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
    ..httpClientAdapter = server;
  final api = ApiNotesRepository(
    apiBaseUrl: 'https://example.test',
    socketBaseUrl: 'https://example.test',
    accessTokenProvider: () async => null,
    httpClient: dio,
  );
  addTearDown(api.dispose);
  return api;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final encrypted in [false, true]) {
    test(
      'normal list preserves the legacy request, encrypted=$encrypted',
      () async {
        final server = _ListServer();
        final api = _repository(server);
        const envelope = ListKeyEnvelope(
          deviceId: 'qa-device',
          envelope: 'opaque-key',
        );
        final result = encrypted
            ? await api.createTypedEncryptedList(
                encryptedName: 'opaque-name',
                keyEnvelope: envelope,
                configuration: const ListConfiguration(),
              )
            : await api.createTypedList(
                'Lista normal',
                const ListConfiguration(),
              );
        expect(result.configuration.type, NoteListType.normal);
        expect(server.requests.single, {
          'name': encrypted ? 'opaque-name' : 'Lista normal',
          if (encrypted) ...{
            'encryptionVersion': 1,
            'keyEnvelope': envelope.toJson(),
          },
        });
      },
    );
  }
  test(
    'financial creation preserves type and currency on a modern server',
    () async {
      final server = _ListServer(legacy: false);
      final api = _repository(server);
      final saved = await api.createTypedList(
        'Gastos',
        const ListConfiguration(type: NoteListType.expenses, currency: 'EUR'),
      );
      expect(saved.configuration.type, NoteListType.expenses);
      expect(saved.configuration.currency, 'EUR');
      expect(server.requests.single['listType'], 'expenses');
      expect(server.requests.single['currency'], 'EUR');
    },
  );
  test('legacy rejection explains availability and never silently creates a normal list', () async {
    final server = _ListServer();
    final api = _repository(server);
    try {
      await api.createTypedList(
        'Gastos',
        const ListConfiguration(type: NoteListType.expenses),
      );
      fail('A legacy server must not accept a financial list');
    } on DioException catch (error) {
      expect(
        notesErrorMessage(error),
        contains('Por ahora puedes crear una lista Normal'),
      );
      expect(notesErrorMessage(error), isNot(contains('should not exist')));
    }
    expect(server.requests, hasLength(1));
  });
}
