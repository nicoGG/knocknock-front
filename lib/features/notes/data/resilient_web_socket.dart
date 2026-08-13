import 'dart:typed_data';

import 'package:web_socket/web_socket.dart' as ws;

import 'web_socket_connector_stub.dart'
    if (dart.library.js_interop) 'web_socket_connector_web.dart'
    if (dart.library.io) 'web_socket_connector_io.dart'
    as platform;

Future<ws.WebSocket> connectResilientWebSocket(
  Uri uri, {
  Iterable<String>? protocols,
  Map<String, String>? headers,
}) async => ResilientWebSocket(
  await platform.connectWebSocket(uri, protocols: protocols, headers: headers),
);

/// Makes transport teardown idempotent while leaving send failures untouched.
///
/// socket_io_client 3.1.6 does not await the Future returned by close(). When
/// the peer already closed the connection, package:web_socket reports a second
/// close as an asynchronous WebSocketConnectionClosed. Absorbing that exact
/// condition here prevents an otherwise benign teardown from becoming fatal.
class ResilientWebSocket implements ws.WebSocket {
  ResilientWebSocket(this._delegate);

  final ws.WebSocket _delegate;

  @override
  Stream<ws.WebSocketEvent> get events => _delegate.events;

  @override
  String get protocol => _delegate.protocol;

  @override
  void sendBytes(Uint8List bytes) => _delegate.sendBytes(bytes);

  @override
  void sendText(String text) => _delegate.sendText(text);

  @override
  Future<void> close([int? code, String? reason]) async {
    try {
      await _delegate.close(code, reason);
    } on ws.WebSocketConnectionClosed {
      // The desired closed state has already been reached.
    }
  }
}
