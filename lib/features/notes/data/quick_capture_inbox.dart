import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_handler/share_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class CapturedText {
  const CapturedText({required this.id, required this.text});
  final String id;
  final String text;
  Map<String, dynamic> toJson() => {'id': id, 'text': text};
}

/// Shares remain on this device until a note has actually been saved.
class QuickCaptureInbox extends ChangeNotifier {
  QuickCaptureInbox({SharedPreferences? preferences}) {
    _preferences = preferences;
  }
  static const _key = 'nocknock.pending_text_captures.v1';
  SharedPreferences? _preferences;
  List<CapturedText> _pending = [];
  List<CapturedText> get pending => List.unmodifiable(_pending);
  StreamSubscription<SharedMedia>? _subscription;
  Future<void> _serial = Future.value();
  bool _disposed = false;
  bool _started = false;
  String? _lastText;
  DateTime? _lastReceivedAt;

  Future<void>? _loading;
  Future<void> _load() => _loading ??= _loadStored();
  Future<void> _loadStored() async {
    _preferences ??= await SharedPreferences.getInstance();
    final raw = _preferences!.getString(_key);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as List;
      _pending = decoded
          .whereType<Map>()
          .where((item) => item['id'] is String && item['text'] is String)
          .map(
            (item) => CapturedText(
              id: item['id'] as String,
              text: item['text'] as String,
            ),
          )
          .toList();
      if (!_disposed) notifyListeners();
    } on FormatException {
      // A damaged cache must not prevent opening the app.
    } on TypeError {
      // Ignore caches from an incompatible schema.
    }
  }

  Future<void> start({bool listenToPlatform = true}) async {
    if (_started) return;
    _started = true;
    await _load();
    if (_disposed ||
        !listenToPlatform ||
        kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    try {
      final handler = ShareHandlerPlatform.instance;
      final initial = await handler.getInitialSharedMedia();
      if (_disposed) return;
      _subscription = handler.sharedMediaStream.listen((media) async {
        try {
          await _receive(media, handler);
        } catch (_) {
          /* Keep the native initial share available. */
        }
      }, onError: (Object _) {});
      if (initial != null) await _receive(initial, handler);
    } on MissingPluginException {
      // Desktop and widget tests have no native share receiver.
    } on PlatformException {
      // Opening the app remains possible if the OS has no pending share.
    }
  }

  Future<void> _receive(SharedMedia media, ShareHandlerPlatform handler) async {
    final text = media.content?.trim() ?? '';
    if (text.isEmpty || _disposed) return;
    final now = DateTime.now();
    if (_lastText == text &&
        _lastReceivedAt != null &&
        now.difference(_lastReceivedAt!) < const Duration(seconds: 1)) {
      return;
    }
    final previousText = _lastText;
    final previousReceivedAt = _lastReceivedAt;
    _lastText = text;
    _lastReceivedAt = now;
    try {
      await enqueue(text);
    } catch (_) {
      _lastText = previousText;
      _lastReceivedAt = previousReceivedAt;
      rethrow;
    }
    await handler.resetInitialSharedMedia();
  }

  Future<void> enqueue(String text) => _write(
    () => [
      ..._pending,
      if (text.trim().isNotEmpty)
        CapturedText(id: const Uuid().v4(), text: text.trim()),
    ],
  );

  Future<void> acknowledge(String id) =>
      _write(() => _pending.where((item) => item.id != id).toList());

  Future<void> _write(List<CapturedText> Function() update) {
    final operation = _serial.then((_) async {
      await _load();
      final next = update();
      final saved = await _preferences!.setString(
        _key,
        jsonEncode(next.map((item) => item.toJson()).toList()),
      );
      if (!saved) throw StateError('No se pudo guardar la captura');
      _pending = next;
      if (!_disposed) notifyListeners();
    });
    _serial = operation.catchError((Object _) {});
    return operation;
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}
