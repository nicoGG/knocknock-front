import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/data/resilient_web_socket.dart';
import 'package:web_socket/web_socket.dart' as ws;

void main() {
  test('treats closing an already closed transport as successful', () async {
    final socket = ResilientWebSocket(
      _FakeWebSocket(closeError: ws.WebSocketConnectionClosed()),
    );

    await expectLater(socket.close(), completes);
  });

  test('does not hide other close or send failures', () async {
    final closeSocket = ResilientWebSocket(
      _FakeWebSocket(closeError: StateError('transport failed')),
    );
    final sendSocket = ResilientWebSocket(
      _FakeWebSocket(sendError: ws.WebSocketConnectionClosed()),
    );

    await expectLater(closeSocket.close(), throwsStateError);
    expect(
      () => sendSocket.sendText('message'),
      throwsA(isA<ws.WebSocketConnectionClosed>()),
    );
  });
}

class _FakeWebSocket implements ws.WebSocket {
  _FakeWebSocket({this.closeError, this.sendError});

  final Object? closeError;
  final Object? sendError;

  @override
  Stream<ws.WebSocketEvent> get events => const Stream.empty();

  @override
  String get protocol => '';

  @override
  Future<void> close([int? code, String? reason]) async {
    if (closeError case final error?) throw error;
  }

  @override
  void sendBytes(Uint8List bytes) {
    if (sendError case final error?) throw error;
  }

  @override
  void sendText(String text) {
    if (sendError case final error?) throw error;
  }
}
