import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum DictationPhase { idle, preparing, listening, finishing }

/// A dictation session only owns the selected part of the current draft.
/// Partial and final results replace that same range, never the surrounding text.
class AssistantDictation extends ChangeNotifier {
  AssistantDictation(this._field);

  static const maxLength = 2000;
  final TextEditingController _field;
  final _speech = SpeechToText();
  DictationPhase phase = DictationPhase.idle;
  String? error;
  bool get active => phase != DictationPhase.idle;
  int _session = 0;
  Timer? _deadline;
  bool _started = false;
  bool _heardWords = false;
  String? get _emptyResultMessage => _heardWords
      ? null
      : 'No se entendió la frase. Toca el micrófono para intentarlo otra vez.';

  Future<void> start(Locale locale) async {
    if (active) return;
    final id = ++_session;
    final initial = _field.value;
    final selection = initial.selection.isValid
        ? initial.selection
        : TextSelection.collapsed(offset: initial.text.length);
    final before = initial.text.substring(0, selection.start);
    final after = initial.text.substring(selection.end);
    error = null;
    _heardWords = false;
    phase = DictationPhase.preparing;
    notifyListeners();
    try {
      final available = await _speech.initialize(
        options: [SpeechToText.androidNoBluetooth],
      );
      if (id != _session) return;
      if (!available) {
        final permitted = await _speech.hasPermission;
        if (id == _session) {
          _end(
            permitted
                ? 'El reconocimiento de voz no está disponible en este dispositivo.'
                : 'Permite el micrófono y el reconocimiento de voz en los ajustes para dictar.',
          );
        }
        return;
      }

      // Nock's interface is in Spanish. Prefer the speaker's regional variant.
      final spanish = locale.languageCode == 'es'
          ? locale.toLanguageTag()
          : 'es-CL';
      final locales = await _speech.locales();
      if (id != _session) return;
      final ids = locales.map((l) => l.localeId);
      String normalized(String id) => id.toLowerCase().replaceAll('_', '-');
      final language =
          ids.where((l) => normalized(l) == normalized(spanish)).firstOrNull ??
          ids
              .where((l) => normalized(l).split('-').first == 'es')
              .firstOrNull ??
          spanish;

      // The plugin is a singleton. initialize() retains its first callbacks, so
      // attach listeners to the current chat after permissions have resolved.
      _speech.errorListener = (e) {
        if (_session != id) return;
        cancel(
          message: switch (e.errorMsg) {
            'error_no_match' || 'error_speech_timeout' || 'no-speech' => 'No se entendió la frase. Toca el micrófono para intentarlo otra vez.',
            'error_permission' ||
            'error_insufficient_permissions' ||
            'not-allowed' => 'Permite el micrófono y el reconocimiento de voz en los ajustes para dictar.',
            'error_network' || 'error_network_timeout' || 'network' => 'El dictado perdió la conexión. Puedes reintentar o seguir escribiendo.',
            'error_language_not_supported' ||
            'error_language_unavailable' ||
            'language-not-supported' => 'El dictado en español no está disponible. Revisa los idiomas de reconocimiento de voz en los ajustes.',
            'error_unknown (300)' => 'El servicio de voz no pudo cargar el idioma. Reinicia el dispositivo o prueba el dictado en un teléfono físico si usas el simulador.',
            _ => 'No se pudo continuar el dictado. Puedes reintentar o seguir escribiendo.',
          },
        );
      };
      _speech.statusListener = (status) {
        if (_session != id) return;
        if (status == SpeechToText.listeningStatus &&
            phase == DictationPhase.preparing) {
          _deadline?.cancel();
          phase = DictationPhase.listening;
          notifyListeners();
        } else if (status == SpeechToText.notListeningStatus) {
          _awaitFinal(id);
        } else if (status == SpeechToText.doneStatus) {
          // iOS can deliver its native failure just after "done". Keep the
          // session alive briefly so that error and the final result arrive.
          if (_heardWords) {
            _end();
          } else {
            _awaitFinal(id);
          }
        }
      };
      _started = true;
      _deadline = Timer(const Duration(seconds: 8), () {
        if (_session == id && phase == DictationPhase.preparing) {
          cancel(message: 'El micrófono no respondió. Vuelve a intentarlo.');
        }
      });
      await _speech.listen(
        listenOptions: SpeechListenOptions(
          localeId: language,
          listenMode: ListenMode.dictation,
          autoPunctuation: true,
          listenFor: const Duration(seconds: 55),
          pauseFor: const Duration(seconds: 5),
        ),
        onResult: (result) {
          if (_session != id) return;
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) {
            _heardWords = true;
            final leftSpace =
                before.isNotEmpty && !RegExp(r'\s$').hasMatch(before)
                ? ' '
                : '';
            final rightSpace =
                after.isNotEmpty && !RegExp(r'^[\s.,;:!?)]').hasMatch(after)
                ? ' '
                : '';
            final room =
                maxLength -
                (before + after + rightSpace + leftSpace).characters.length;
            if (room > 0) {
              final insert = leftSpace + words.characters.take(room).toString();
              _field.value = TextEditingValue(
                text: before + insert + rightSpace + after,
                selection: TextSelection.collapsed(
                  offset: before.length + insert.length,
                ),
              );
            } else {
              cancel(message: 'Tu mensaje llegó al máximo de 2000 caracteres.');
              return;
            }
          }
          if (result.finalResult) _awaitFinal(id);
        },
      );
    } catch (failure) {
      if (id == _session) {
        // Keep native setup failures distinguishable from a silent microphone.
        // Do not log recognized speech or the draft.
        debugPrint('Nock dictation setup: ${failure.runtimeType}');
        cancel(
          message: switch (failure) {
            MissingPluginException() => 'El módulo de voz no está cargado. Cierra la app y vuelve a ejecutarla con una compilación completa.',
            ListenFailedException() => 'No se pudo abrir el micrófono. Si usas el simulador, revisa I/O → Audio Input y selecciona el micrófono del Mac.',
            PlatformException(code: final code)
                when code.contains('permission') || code.contains('denied') =>
              'Permite el micrófono y el reconocimiento de voz en los ajustes para dictar.',
            _ => 'No se pudo iniciar el dictado. Cierra la app y vuelve a intentarlo.',
          },
        );
      }
    }
  }

  void _awaitFinal(int id) {
    if (phase == DictationPhase.finishing) return;
    phase = DictationPhase.finishing;
    _deadline?.cancel();
    // Keep the last partial if the OS never delivers a final result.
    _deadline = Timer(const Duration(seconds: 3), () {
      if (_session == id) cancel(message: _emptyResultMessage);
    });
    notifyListeners();
  }

  Future<void> stop() async {
    if (!active || phase == DictationPhase.finishing) return;
    if (phase == DictationPhase.preparing) {
      cancel();
      return;
    }
    final id = _session;
    _awaitFinal(id);
    try {
      await _speech.stop();
    } catch (_) {
      if (_session == id) cancel();
    }
  }

  void cancel({String? message}) {
    if (!active) return;
    final wasStarted = _started;
    _end(message);
    if (wasStarted) unawaited(_speech.cancel().catchError((Object _) {}));
  }

  void _end([String? message]) {
    _session++;
    _deadline?.cancel();
    if (_started) {
      _speech.statusListener = null;
      _speech.errorListener = null;
    }
    _started = false;
    phase = DictationPhase.idle;
    error = message;
    notifyListeners();
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }
}
