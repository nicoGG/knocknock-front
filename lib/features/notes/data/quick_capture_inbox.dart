import 'dart:async';

import 'package:nocknock/features/notes/data/shared_receipt_store.dart';
import 'package:nocknock/features/notes/presentation/note_attachment_picker.dart';

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_handler/share_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class CapturedText {
  const CapturedText({
    required this.id,
    required this.text,
    this.receipt = false,
    this.error,
  });
  final bool receipt;
  final String? error;
  final String id;
  final String text;
  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    if (receipt) 'receipt': true,
    if (error != null) 'error': error,
  };
}

/// Shares remain on this device until a note has actually been saved.
class QuickCaptureInbox extends ChangeNotifier {
  QuickCaptureInbox({
    SharedPreferences? preferences,
    SharedReceiptStore? receipts,
  }) : receipts = receipts ?? SharedReceiptStore() {
    _preferences = preferences;
  }
  final SharedReceiptStore receipts;
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
              receipt: item['receipt'] == true,
              error: item['error'] as String?,
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
      if (defaultTargetPlatform == TargetPlatform.android) {
        _android.setMethodCallHandler((call) async {
          if (call.method == 'available') await _drainAndroid();
        });
        await _drainAndroid();
      }
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
    final file = media.attachments?.whereType<SharedAttachment>().firstOrNull;
    if ((file == null && text.isEmpty) || _disposed) return;
    final signature = file == null ? text : 'file:${file.path}';
    final now = DateTime.now();
    if (_lastText == signature &&
        _lastReceivedAt != null &&
        now.difference(_lastReceivedAt!) < const Duration(seconds: 1)) {
      return;
    }
    final previousText = _lastText;
    final previousReceivedAt = _lastReceivedAt;
    _lastText = signature;
    _lastReceivedAt = now;
    try {
      if (file == null) {
        await enqueue(text);
      } else {
        await _stageReceipt(file.path);
      }
    } catch (_) {
      _lastText = previousText;
      _lastReceivedAt = previousReceivedAt;
      rethrow;
    }
    await handler.resetInitialSharedMedia();
  }

  Future<void> _stageReceipt(String? path, {String? error}) async {
    final id = const Uuid().v4();

    try {
      if (path != null) await receipts.stage(id, path);
    } catch (e) {
      error = e is NoteAttachmentPickFailure
          ? e.message
          : 'No se pudo leer la boleta. Vuelve a compartir la imagen o el PDF.';
      await receipts.remove(id).catchError((Object _) {});
    }
    try {
      await _write(
        () => [
          ..._pending,
          CapturedText(id: id, text: '', receipt: true, error: error),
        ],
      );
    } catch (_) {
      await receipts.remove(id);
      rethrow;
    }
  }

  static const _android = MethodChannel('cl.nocknock/incoming_receipts');
  bool _draining = false;
  bool _rescan = false;
  Future<void> _drainAndroid() async {
    if (_draining) {
      _rescan = true;
      return;
    }
    _draining = true;
    try {
      do {
        _rescan = false;
        while (!_disposed) {
          final item = await _android.invokeMapMethod<String, String>('next');
          if (item == null) break;
          try {
            await _stageReceipt(item['path'], error: item['error']);
          } finally {
            if (item['name'] != null) {
              await _android.invokeMethod<void>('release', item['name']);
            }
          }
        }
      } while (_rescan && !_disposed);
    } on MissingPluginException {
      // Tests without the Android engine.
    } finally {
      _draining = false;
    }
  }

  Future<void> enqueue(String text) => _write(
    () => [
      ..._pending,
      if (text.trim().isNotEmpty)
        CapturedText(id: const Uuid().v4(), text: text.trim()),
    ],
  );

  Future<void> acknowledge(String id) async {
    final receipt = _pending.any(
      (item) => item.id == id && item.receipt && item.error == null,
    );
    await _write(() => _pending.where((item) => item.id != id).toList());
    if (receipt) await receipts.remove(id);
  }

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
    if (_started &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      _android.setMethodCallHandler(null);
    }
    _subscription?.cancel();
    super.dispose();
  }
}
