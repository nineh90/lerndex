import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
//   Native STT (iOS Speech Framework / Android SpeechRecognizer).
//   Lerndex speichert keine Audio-Daten — nur den erkannten Text als
//   normale Chat-Nachricht (sofern abgeschickt).
// ============================================================================

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

  Future<bool> _ensureInitialized() async {
    if (_initialized) return state.isAvailable;

    try {
      final available = await _speech.initialize(
        onError: (err) {
          debugPrint('🎙️ STT Error: ${err.errorMsg} (perm=${err.permanent})');
          // "no_match" / "no speech" / "speech_timeout" sind KEINE harten
          // Fehler — bedeutet nur "in dieser Session nichts erkannt".
          // Solange der User noch aufnimmt, wird die Session neugestartet
          // (siehe onStatus-Handler).
          if (_isSoftError(err.errorMsg)) {
            return;
          }
          // Echter Fehler: stoppe alles
          _userWantsListening = false;
          if (mounted) {
            state = state.copyWith(
              isListening: false,
              error: _humanizeError(err.errorMsg),
            );
          }
        },
        onStatus: (status) {
          debugPrint('🎙️ STT Status: $status');

          if (status == 'notListening' || status == 'done') {
            if (_userWantsListening) {
              _restartInternal();
            } else {
              if (mounted) {
                state = state.copyWith(isListening: false, soundLevel: 0);
              }
            }
          } else if (status == 'listening') {
            if (mounted) {
              state = state.copyWith(isListening: true, clearError: true);
            }
          }
        },
        debugLogging: kDebugMode,
      );
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
    final ok = await _ensureInitialized();
    if (!ok) return false;

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
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(seconds: 30),
        localeId: 'de_DE',
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: stt.ListenMode.dictation,
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
      if (!_userWantsListening) return;
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
    cancel();
    super.dispose();
  }
}

final sttControllerProvider = StateNotifierProvider<SttController, SttState>((
  ref,
) {
  return SttController();
});
