import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

// ============================================================================
// STT PROVIDER – Speech-to-Text für Lerndex (Tap-Toggle)
//
// Bedienung:
//   • 1x tippen  → Aufnahme START
//   • 2x tippen  → Aufnahme STOP
//   • Erkannter Text läuft live ins TextField
//
// Robustheit:
//   Der native Android SpeechRecognizer beendet sich automatisch bei Stille
//   (~2-3s, nicht abschaltbar). Damit der User durchgehend sprechen kann,
//   restarten wir intern, solange `_userWantsListening` true ist — d.h.
//   bis der User explizit auf Stop tippt.
//
// Datenschutz:
//   Die Spracherkennung des Systems schickt die Aufnahme sonst an einen
//   Online-Dienst (Android: Google, im Browser: Chrome → Google, Safari →
//   Apple). Deshalb nur auf dem Gerät erkennen (`onDevice: true`):
//   • Android: nur wenn das System eine Erkennung auf dem Gerät hat
//     (SpeechRecognizer.isOnDeviceRecognitionAvailable, Android 12+). Sonst
//     fällt das Plugin still auf die Online-Erkennung zurück – darum ist das
//     Mikrofon dann ausgeblendet ([sttAvailableProvider]).
//   • iOS: requiresOnDeviceRecognition, scheitert ohne Gerät-Modell.
//   • Browser: Web Speech API erkennt immer online → keine Spracheingabe.
//   Lerndex selbst speichert keine Audio-Daten — nur den erkannten Text als
//   normale Chat-Nachricht (sofern abgeschickt).
// ============================================================================

/// Kanal zur App (MainActivity): fragt, ob Android Sprache auf dem Gerät
/// erkennen kann. Ohne Antwort (älterer App-Stand, anderes System) gilt:
/// nicht verfügbar.
const _speechChannel = MethodChannel('de.nilsdigital.lerndex/speech');

/// Spracheingabe nur, wenn sie ohne Online-Dienst läuft (siehe oben).
Future<bool> isOnDeviceSpeechAvailable() async {
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
      return true;
    case TargetPlatform.android:
      try {
        return await _speechChannel.invokeMethod<bool>(
              'isOnDeviceRecognitionAvailable',
            ) ??
            false;
      } catch (_) {
        // MissingPluginException / PlatformException
        return false;
      }
    default:
      return false;
  }
}

/// Ob der Mikrofon-Knopf erscheinen darf.
final sttAvailableProvider = FutureProvider<bool>(
  (ref) => isOnDeviceSpeechAvailable(),
);

class SttState {
  final bool isListening;
  final bool isAvailable;
  final String? error;
  final double soundLevel; // 0..1 für visuelles Feedback

  const SttState({
    this.isListening = false,
    this.isAvailable = false,
    this.error,
    this.soundLevel = 0.0,
  });

  SttState copyWith({
    bool? isListening,
    bool? isAvailable,
    String? error,
    bool clearError = false,
    double? soundLevel,
  }) {
    return SttState(
      isListening: isListening ?? this.isListening,
      isAvailable: isAvailable ?? this.isAvailable,
      error: clearError ? null : (error ?? this.error),
      soundLevel: soundLevel ?? this.soundLevel,
    );
  }
}

class SttController extends StateNotifier<SttState> {
  SttController() : super(const SttState());

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _initialized = false;

  /// True solange der User die Aufnahme aktiv haben will. Wird in start()
  /// auf true gesetzt, in stop()/cancel() auf false.
  /// Wenn der native Recognizer sich von selbst beendet (Stille-Timeout),
  /// prüfen wir dieses Flag und starten neu.
  bool _userWantsListening = false;

  /// Akkumulierter Text über mehrere Recognizer-Sessions hinweg.
  String _accumulatedText = '';

  /// Callback ans UI für Live-Update des TextFields.
  void Function(String text)? _onPartialResult;

  /// Verhindert dass mehrere parallel laufende Restart-Versuche aufeinander
  /// schießen (kann passieren wenn onStatus mehrfach hintereinander feuert).
  bool _restartInProgress = false;

  void _onError(SpeechRecognitionError err) {
    final msg = err.errorMsg;
    debugPrint('🎙️ STT Error: $msg (perm=${err.permanent})');
    // "no_match" / "no speech" / "speech_timeout" sind KEINE harten
    // Fehler — bedeutet nur "in dieser Session nichts erkannt".
    // Solange der User noch aufnimmt, wird die Session neugestartet
    // (siehe onStatus-Handler).
    if (_isSoftError(msg)) return;
    // Echter Fehler: stoppe alles
    _userWantsListening = false;
    if (mounted) {
      state = state.copyWith(isListening: false, error: _humanizeError(msg));
    }
  }

  void _onStatus(String status) {
    debugPrint('🎙️ STT Status: $status');
    if (!mounted) return;

    if (status == 'notListening' || status == 'done') {
      if (_userWantsListening) {
        _restartInternal();
      } else {
        state = state.copyWith(isListening: false, soundLevel: 0);
      }
    } else if (status == 'listening') {
      state = state.copyWith(isListening: true, clearError: true);
    }
  }

  Future<bool> _ensureInitialized() async {
    if (_initialized) return state.isAvailable;

    try {
      final available = await _speech.initialize(
        onError: _onError,
        onStatus: _onStatus,
        debugLogging: kDebugMode,
      );
      // SpeechToText ist ein Singleton und übernimmt die Listener nur beim
      // allerersten initialize(). Nach dem Schließen des Tutors gibt es aber
      // einen neuen Controller – ohne Umhängen meldete der Recognizer weiter
      // an den alten (entsorgten).
      _speech.errorListener = _onError;
      _speech.statusListener = _onStatus;
      _initialized = true;
      state = state.copyWith(isAvailable: available, clearError: true);
      return available;
    } catch (e) {
      debugPrint('🎙️ STT Init Fehler: $e');
      state = state.copyWith(
        isAvailable: false,
        error: 'Spracherkennung nicht verfügbar',
      );
      return false;
    }
  }

  /// Tap-Toggle: wenn aktuell aktiv → stop, sonst → start.
  /// [initialText] ist der bereits im TextField stehende Inhalt.
  /// Beim Start wird daran angehängt — so geht nichts verloren wenn der
  /// User die Aufnahme stoppt, dann ergänzt, und wieder neu startet.
  Future<void> toggle({
    required void Function(String text) onResult,
    String initialText = '',
  }) async {
    if (_userWantsListening || state.isListening) {
      await stop();
    } else {
      await start(onResult: onResult, initialText: initialText);
    }
  }

  /// Explizit starten.
  /// [initialText] wird als Basis für die Akkumulation übernommen.
  Future<bool> start({
    required void Function(String text) onResult,
    String initialText = '',
  }) async {
    if (!await isOnDeviceSpeechAvailable()) {
      if (mounted) {
        state = state.copyWith(
          error: 'Spracheingabe gibt es auf diesem Gerät leider nicht',
        );
      }
      return false;
    }
    final ok = await _ensureInitialized();
    if (!ok || !mounted) return false;

    _userWantsListening = true;
    _onPartialResult = onResult;
    // Bestehenden Text als Basis nehmen, damit eine zweite Aufnahme
    // an den vorhandenen Text anhängt statt ihn zu überschreiben.
    _accumulatedText = initialText.trim();

    return _startNativeSession();
  }

  Future<bool> _startNativeSession() async {
    if (_speech.isListening) return true;

    try {
      await _speech.listen(
        onResult: (result) {
          if (_onPartialResult == null) return;
          final session = result.recognizedWords;
          final combined = _accumulatedText.isEmpty
              ? session
              : (session.isEmpty
                    ? _accumulatedText
                    : '$_accumulatedText $session');
          _onPartialResult!(combined);

          if (result.finalResult && session.isNotEmpty) {
            _accumulatedText = combined;
          }
        },
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: stt.ListenMode.dictation,
          listenFor: const Duration(minutes: 5),
          pauseFor: const Duration(seconds: 30),
          localeId: 'de_DE',
          // Nur auf dem Gerät erkennen – nichts an Google/Apple schicken.
          onDevice: true,
        ),
        onSoundLevelChange: (level) {
          final normalized = ((level + 2) / 12).clamp(0.0, 1.0);
          if (mounted) {
            state = state.copyWith(soundLevel: normalized);
          }
        },
      );
      if (mounted) {
        state = state.copyWith(
          isListening: true,
          clearError: true,
          soundLevel: 0,
        );
      }
      return true;
    } catch (e) {
      debugPrint('🎙️ STT Start Fehler: $e');
      _userWantsListening = false;
      if (mounted) {
        state = state.copyWith(
          isListening: false,
          error: 'Aufnahme konnte nicht gestartet werden',
        );
      }
      return false;
    }
  }

  /// Auto-Restart wenn der Recognizer von selbst aufgegeben hat und der
  /// User noch will. Kurzer Delay verhindert "busy"-Fehler.
  Future<void> _restartInternal() async {
    if (_restartInProgress) return;
    _restartInProgress = true;
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!_userWantsListening || !mounted) return;
      if (_speech.isListening) return;
      debugPrint('🎙️ STT Auto-Restart (User noch aktiv)');
      await _startNativeSession();
    } finally {
      _restartInProgress = false;
    }
  }

  Future<void> stop() async {
    _userWantsListening = false;
    try {
      if (_speech.isListening) {
        await _speech.stop();
      }
    } catch (e) {
      debugPrint('🎙️ STT Stop Fehler: $e');
    }
    _onPartialResult = null;
    _accumulatedText = '';
    if (mounted) {
      state = state.copyWith(isListening: false, soundLevel: 0);
    }
  }

  Future<void> cancel() async {
    _userWantsListening = false;
    try {
      if (_speech.isListening) {
        await _speech.cancel();
      }
    } catch (_) {}
    _onPartialResult = null;
    _accumulatedText = '';
    if (mounted) {
      state = state.copyWith(isListening: false, soundLevel: 0);
    }
  }

  bool _isSoftError(String raw) {
    final lc = raw.toLowerCase();
    return lc.contains('no_match') ||
        lc.contains('no match') ||
        lc.contains('speech_timeout') ||
        lc.contains('no speech');
  }

  String _humanizeError(String raw) {
    final lc = raw.toLowerCase();
    if (lc.contains('permission')) return 'Mikrofon-Berechtigung fehlt';
    if (lc.contains('network')) return 'Keine Internet-Verbindung';
    if (lc.contains('busy')) return 'Mikrofon ist gerade belegt';
    return 'Sprach-Eingabe nicht möglich';
  }

  @override
  void dispose() {
    // Mikrofon sofort aus – sonst startete onStatus die Aufnahme neu.
    _userWantsListening = false;
    _onPartialResult = null;
    unawaited(cancel());
    super.dispose();
  }
}

/// autoDispose: Verlässt das Kind den Tutor, wird der Controller entsorgt
/// und das Mikrofon ausgeschaltet.
final sttControllerProvider =
    StateNotifierProvider.autoDispose<SttController, SttState>((ref) {
      return SttController();
    });
