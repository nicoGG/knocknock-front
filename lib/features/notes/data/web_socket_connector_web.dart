import 'package:web_socket/web_socket.dart' as ws;

Future<ws.WebSocket> connectWebSocket(
  Uri uri, {
  Iterable<String>? protocols,
  Map<String, String>? headers,
}) => ws.WebSocket.connect(uri, protocols: protocols);
