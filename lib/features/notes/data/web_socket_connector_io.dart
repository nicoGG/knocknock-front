import 'dart:io' as io;

import 'package:web_socket/io_web_socket.dart';
import 'package:web_socket/web_socket.dart' as ws;

Future<ws.WebSocket> connectWebSocket(
  Uri uri, {
  Iterable<String>? protocols,
  Map<String, String>? headers,
}) async {
  // Ownership passes to IOWebSocket and the Socket.IO transport.
  // ignore: close_sinks
  final io.WebSocket socket;
  try {
    socket = await io.WebSocket.connect(
      uri.toString(),
      protocols: protocols,
      headers: headers,
    );
  } on io.WebSocketException catch (error) {
    throw ws.WebSocketException(error.message);
  }
  return IOWebSocket.fromWebSocket(socket);
}
