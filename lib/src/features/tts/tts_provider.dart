import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter/scheduler.dart';
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
  // Weniger Pitch-Tweaking = weniger Roboter-Klang
  static const double _speechRate = 0.48; // Etwas schneller → natürlicher
  static const double _pitch = 1.0; // Natürliches Pitch – kein Tweak!
  static const double _volume = 1.0;
  static const String _language = 'de-DE';

  // Feedback: minimal höher, aber kaum Unterschied
  static const double _feedbackRate = 0.50;
  static const double _feedbackPitch = 1.0; // Pitch NICHT verändern

  Future<void> _init() async {
    try {
      await _tts.setLanguage(_language);
      await _tts.setSpeechRate(_speechRate);
      await _tts.setPitch(_pitch);
      await _tts.setVolume(_volume);

      // iOS: playback-Kategorie für bessere Audio-Qualität
      // (ambient schneidet Frequenzen ab → klingt dumpfer/roboterhafter)
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ],
        IosTextToSpeechAudioMode.defaultMode,
      );

      // Beste verfügbare deutsche Stimme wählen
      // iOS: Siri/Neural-Stimmen klingen deutlich natürlicher
      await _selectBestVoice();

      _tts.setStartHandler(() {
        // Scheduling über SchedulerBinding verhindert setState auf defunct Elementen
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) state = state.copyWith(isSpeaking: true);
        });
      });

      _tts.setCompletionHandler(() {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) state = state.copyWith(isSpeaking: false);
        });
      });

      _tts.setCancelHandler(() {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) state = state.copyWith(isSpeaking: false);
        });
      });

      _tts.setErrorHandler((msg) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) state = state.copyWith(isSpeaking: false);
        });
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

  /// Wählt die best verfügbare deutsche Stimme.
  /// iOS: Siri/Neural-Stimmen bevorzugen (klingen deutlich natürlicher)
  /// Android: Google-Stimme bevorzugen
  Future<void> _selectBestVoice() async {
    try {
      final voices = await _tts.getVoices as List?;
      if (voices == null || voices.isEmpty) return;

      // Preferred voice IDs (iOS Neural/Siri Stimmen für de-DE)
      const iosPreferred = [
        'com.apple.ttsbundle.siri_female_de-DE_premium',
        'com.apple.ttsbundle.siri_male_de-DE_premium',
        'com.apple.voice.premium.de-DE.Anna',
        'com.apple.ttsbundle.Anna-premium',
        'com.apple.ttsbundle.siri_female_de-DE_compact',
        'com.apple.ttsbundle.Anna-compact',
      ];

      // Alle de-DE Stimmen sammeln
      final deVoices = voices.cast<Map>().where((v) {
        final locale = (v['locale'] ?? v['language'] ?? '').toString();
        return locale.startsWith('de');
      }).toList();

      if (deVoices.isEmpty) return;

      // iOS: Bevorzugte Stimme nach Priorität suchen
      for (final preferred in iosPreferred) {
        final match = deVoices.firstWhere(
          (v) => v['name']?.toString() == preferred,
          orElse: () => {},
        );
        if (match.isNotEmpty) {
          await _tts.setVoice({
            'name': match['name'].toString(),
            'locale': match['locale']?.toString() ?? 'de-DE',
          });
          debugPrint('🎙️ TTS: Stimme gewählt: ${match['name']}');
          return;
        }
      }

      // Android: Google de-DE bevorzugen
      final googleVoice = deVoices.firstWhere(
        (v) => v['name']?.toString().contains('Google') == true,
        orElse: () => {},
      );
      if (googleVoice.isNotEmpty) {
        await _tts.setVoice({
          'name': googleVoice['name'].toString(),
          'locale': googleVoice['locale']?.toString() ?? 'de-DE',
        });
        debugPrint('🎙️ TTS: Google-Stimme gewählt: ${googleVoice['name']}');
        return;
      }

      // Fallback: erste verfügbare de-Stimme
      final first = deVoices.first;
      await _tts.setVoice({
        'name': first['name'].toString(),
        'locale': first['locale']?.toString() ?? 'de-DE',
      });
      debugPrint('🎙️ TTS: Fallback-Stimme: ${first['name']}');
    } catch (e) {
      debugPrint('⚠️ TTS: Stimme konnte nicht gesetzt werden: $e');
    }
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
