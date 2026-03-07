import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// TTS PROVIDER – Zentraler Text-to-Speech Service für Lerndex
//
// Nutzung:
//   final tts = ref.read(ttsControllerProvider.notifier);
//   tts.speak("Hallo!");
//   tts.speakQuestion("Wie viele Äpfel siehst du?");
//   tts.speakFeedback("Richtig toll gemacht!");
//   tts.stop();
//
// Einstellungen pro Kind:
//   ref.read(ttsSettingsProvider(childId).notifier).toggle();
//   final isEnabled = ref.watch(ttsSettingsProvider(childId));
//
// Design-Entscheidungen:
// • Sprache: de-DE (deutsch für alle Inhalte)
// • Geschwindigkeit: 0.42 (langsam genug für 6-8 Jährige)
// • Pitch: 1.1 (leicht höher → freundlicher, kindgerechter)
// • Singleton-Instanz: FlutterTts wird einmal erstellt und wiederverwendet
// • Stop-before-speak: Jeder neue speak() stoppt laufende Ausgabe
// ============================================================================

// ── TTS State ─────────────────────────────────────────────────────────────────

/// Aktueller Zustand der Sprachausgabe
class TtsState {
  final bool isSpeaking;
  final bool isInitialized;

  const TtsState({this.isSpeaking = false, this.isInitialized = false});

  TtsState copyWith({bool? isSpeaking, bool? isInitialized}) {
    return TtsState(
      isSpeaking: isSpeaking ?? this.isSpeaking,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

// ── TTS Controller ────────────────────────────────────────────────────────────

class TtsController extends StateNotifier<TtsState> {
  TtsController() : super(const TtsState()) {
    _init();
  }

  final FlutterTts _tts = FlutterTts();

  // TTS-Konfiguration für Kinder (Klasse 1–2)
  static const double _speechRate = 0.42; // Langsam & deutlich
  static const double _pitch = 1.1; // Leicht höher → freundlicher
  static const double _volume = 1.0;
  static const String _language = 'de-DE';

  // Feedback-spezifische Einstellungen
  static const double _feedbackRate = 0.48; // Lob etwas schneller
  static const double _feedbackPitch = 1.2; // Enthusiastischer

  Future<void> _init() async {
    try {
      await _tts.setLanguage(_language);
      await _tts.setSpeechRate(_speechRate);
      await _tts.setPitch(_pitch);
      await _tts.setVolume(_volume);

      // iOS-spezifisch: Audio-Session konfigurieren
      await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.ambient, [
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
        IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
      ]);

      _tts.setStartHandler(() {
        if (mounted) state = state.copyWith(isSpeaking: true);
      });

      _tts.setCompletionHandler(() {
        if (mounted) state = state.copyWith(isSpeaking: false);
      });

      _tts.setCancelHandler(() {
        if (mounted) state = state.copyWith(isSpeaking: false);
      });

      _tts.setErrorHandler((msg) {
        if (mounted) state = state.copyWith(isSpeaking: false);
      });

      if (mounted) state = state.copyWith(isInitialized: true);
    } catch (e) {
      // TTS nicht verfügbar – kein Crash, Feature degradiert still
      if (mounted) state = state.copyWith(isInitialized: false);
    }
  }

  // ── Öffentliche API ───────────────────────────────────────────────────────

  /// Spricht beliebigen Text vor. Stoppt vorherige Ausgabe.
  Future<void> speak(String text) async {
    if (!state.isInitialized || text.isEmpty) return;

    await _tts.stop();
    await _tts.setSpeechRate(_speechRate);
    await _tts.setPitch(_pitch);
    await _tts.speak(text);
  }

  /// Liest eine Quiz-Frage vor.
  /// Entfernt Emojis aus dem Text für natürlichere Sprachausgabe.
  Future<void> speakQuestion(String questionText) async {
    if (!state.isInitialized || questionText.isEmpty) return;

    final cleanText = _stripEmojis(questionText);
    await _tts.stop();
    await _tts.setSpeechRate(_speechRate);
    await _tts.setPitch(_pitch);
    await _tts.speak(cleanText);
  }

  /// Spricht Feedback (Lob / Ermutigung) mit enthusiastischerer Stimme.
  Future<void> speakFeedback(String feedbackText) async {
    if (!state.isInitialized || feedbackText.isEmpty) return;

    final cleanText = _stripEmojis(feedbackText);
    await _tts.stop();
    await _tts.setSpeechRate(_feedbackRate);
    await _tts.setPitch(_feedbackPitch);
    await _tts.speak(cleanText);
  }

  /// Spricht eine Begrüßung für das Dashboard.
  Future<void> speakGreeting(String childName) async {
    if (!state.isInitialized) return;

    await _tts.stop();
    await _tts.setSpeechRate(_speechRate);
    await _tts.setPitch(_pitch);
    await _tts.speak('Hallo $childName! Was wollen wir heute lernen?');
  }

  /// Spricht den Fachnamen beim Carousel-Wischen.
  Future<void> speakSubject(String subjectLabel) async {
    if (!state.isInitialized) return;

    await _tts.stop();
    await _tts.setSpeechRate(0.5); // Kurze Wörter etwas schneller
    await _tts.setPitch(_pitch);
    await _tts.speak(subjectLabel);
  }

  /// Spricht das Ergebnis am Ende eines Quiz.
  Future<void> speakResult({required int correct, required int total}) async {
    if (!state.isInitialized) return;

    String text;
    if (correct == total) {
      text =
          'Wow, perfekt! Du bist ein Superstar! '
          'Alle $total richtig!';
    } else if (correct >= total - 1) {
      text =
          'Super gemacht! $correct von $total richtig! '
          'Fast perfekt!';
    } else {
      text =
          'Gut gemacht! $correct von $total richtig! '
          'Beim nächsten Mal schaffst du noch mehr!';
    }

    await _tts.stop();
    await _tts.setSpeechRate(_feedbackRate);
    await _tts.setPitch(_feedbackPitch);
    await _tts.speak(text);
  }

  /// Stoppt die aktuelle Sprachausgabe sofort.
  Future<void> stop() async {
    await _tts.stop();
    if (mounted) state = state.copyWith(isSpeaking: false);
  }

  // ── Hilfsmethoden ─────────────────────────────────────────────────────────

  /// Entfernt Emojis aus Text für natürlichere TTS-Ausgabe.
  /// "🌟 Ja, 3 Äpfel!" → "Ja, 3 Äpfel!"
  String _stripEmojis(String text) {
    // Entferne Unicode-Emoji-Ranges
    return text
        .replaceAll(
          RegExp(
            r'[\u{1F300}-\u{1FAFF}]|[\u{2600}-\u{27BF}]|[\u{FE00}-\u{FE0F}]|'
            r'[\u{1F900}-\u{1F9FF}]|[\u{1FA00}-\u{1FA6F}]|[\u{2700}-\u{27BF}]|'
            r'[\u{E000}-\u{F8FF}]|[\u{200D}]|[\u{20E3}]|[\u{FE0F}]|'
            r'[\u{D83C}-\u{DBFF}][\u{DC00}-\u{DFFF}]|[\u{2B50}]|[\u{2B05}-\u{2B07}]|'
            r'[\u{2934}-\u{2935}]|[\u{3030}]|[\u{303D}]|[\u{25A0}-\u{25FF}]|'
            r'[\u{2300}-\u{23FF}]',
            unicode: true,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s{2,}'), ' ') // Doppelte Leerzeichen entfernen
        .trim();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// Haupt-Provider für TTS-Steuerung.
///
/// Nutzung:
/// ```dart
/// // State lesen (z.B. für Lautsprecher-Icon)
/// final ttsState = ref.watch(ttsControllerProvider);
///
/// // Controller nutzen
/// ref.read(ttsControllerProvider.notifier).speak("Hallo!");
/// ```
final ttsControllerProvider = StateNotifierProvider<TtsController, TtsState>((
  ref,
) {
  return TtsController();
});

// ── TTS Settings (pro Kind) ───────────────────────────────────────────────────

/// Speichert ob TTS für ein bestimmtes Kind aktiviert ist.
/// Default: true (standardmäßig an).
///
/// Nutzung:
/// ```dart
/// final isEnabled = ref.watch(ttsSettingsProvider(childId));
/// ref.read(ttsSettingsProvider(childId).notifier).toggle();
/// ```
class TtsSettingsNotifier extends StateNotifier<bool> {
  final String childId;

  TtsSettingsNotifier(this.childId) : super(true) {
    _load();
  }

  static const _prefix = 'tts_enabled_';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getBool('$_prefix$childId');
      if (mounted) state = value ?? true; // Default: an
    } catch (_) {
      // SharedPreferences nicht verfügbar → Default beibehalten
    }
  }

  /// Schaltet TTS für dieses Kind an/aus.
  Future<void> toggle() async {
    final newValue = !state;
    state = newValue;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_prefix$childId', newValue);
    } catch (_) {}
  }

  /// Setzt TTS explizit an oder aus.
  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_prefix$childId', enabled);
    } catch (_) {}
  }
}

/// Family-Provider: TTS-Einstellung pro Kind.
/// Wird mit der childId parametrisiert.
final ttsSettingsProvider =
    StateNotifierProvider.family<TtsSettingsNotifier, bool, String>((
      ref,
      childId,
    ) {
      return TtsSettingsNotifier(childId);
    });

// ── Convenience Extension ─────────────────────────────────────────────────────

/// Extension auf WidgetRef für bequemen TTS-Zugriff in Widgets.
///
/// ```dart
/// // In einem ConsumerWidget:
/// ref.tts.speak("Hallo!");
/// ref.ttsEnabled(childId); // true/false
/// ```
extension TtsRefExtension on WidgetRef {
  /// Direkter Zugriff auf den TTS-Controller.
  TtsController get tts => read(ttsControllerProvider.notifier);

  /// Prüft ob TTS für ein Kind aktiviert ist.
  bool ttsEnabled(String childId) => watch(ttsSettingsProvider(childId));

  /// Spricht Text nur wenn TTS für das Kind aktiviert ist.
  Future<void> speakIfEnabled(String childId, String text) async {
    if (watch(ttsSettingsProvider(childId))) {
      await read(ttsControllerProvider.notifier).speak(text);
    }
  }

  /// Spricht Frage nur wenn TTS aktiviert ist.
  Future<void> speakQuestionIfEnabled(
    String childId,
    String questionText,
  ) async {
    if (watch(ttsSettingsProvider(childId))) {
      await read(ttsControllerProvider.notifier).speakQuestion(questionText);
    }
  }

  /// Spricht Feedback nur wenn TTS aktiviert ist.
  Future<void> speakFeedbackIfEnabled(
    String childId,
    String feedbackText,
  ) async {
    if (watch(ttsSettingsProvider(childId))) {
      await read(ttsControllerProvider.notifier).speakFeedback(feedbackText);
    }
  }
}
