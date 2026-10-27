import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/platform_info.dart';
import 'speakable_text.dart';

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

  /// Kennung des gerade gesprochenen Textes (z.B. ID der Tutor-Nachricht),
  /// damit genau dort der Stopp-Knopf erscheint.
  final String? utteranceId;

  const TtsState({
    this.isSpeaking = false,
    this.isInitialized = false,
    this.utteranceId,
  });

  TtsState copyWith({
    bool? isSpeaking,
    bool? isInitialized,
    String? utteranceId,
    bool clearUtterance = false,
  }) {
    return TtsState(
      isSpeaking: isSpeaking ?? this.isSpeaking,
      isInitialized: isInitialized ?? this.isInitialized,
      utteranceId: clearUtterance ? null : (utteranceId ?? this.utteranceId),
    );
  }

  /// True, solange der Text mit dieser Kennung gesprochen wird.
  bool isSpeakingId(String id) => isSpeaking && utteranceId == id;
}

// ── TTS Controller ────────────────────────────────────────────────────────────

class TtsController extends StateNotifier<TtsState> {
  TtsController() : super(const TtsState()) {
    _init();
  }

  final FlutterTts _tts = FlutterTts();

  /// Kennung für die nächste Ausgabe, siehe [speakTutor].
  String? _pendingUtteranceId;

  // Im Browser nimmt das Plugin ein neues speak() erst an, wenn es das Ende
  // der vorigen Ausgabe gemeldet bekommen hat. Nach stop() kommt diese Meldung
  // aber verzögert – ohne Warten würde der neue Text still verworfen (z.B.
  // beim Tipp auf eine andere Nachricht, während Lexi noch spricht).
  bool _webSpeaking = false;
  Completer<void>? _webStopped;

  void _markWebStopped() {
    _webSpeaking = false;
    final stopped = _webStopped;
    _webStopped = null;
    if (stopped != null && !stopped.isCompleted) stopped.complete();
  }

  /// Laufende Ausgabe beenden, bevor etwas Neues gesprochen wird.
  Future<void> _stopBeforeSpeak() async {
    if (!kIsWeb || !_webSpeaking) {
      await _tts.stop();
      return;
    }
    final stopped = _webStopped ??= Completer<void>();
    await _tts.stop();
    await stopped.future.timeout(
      const Duration(milliseconds: 500),
      onTimeout: () {},
    );
  }

  /// Zustand erst nach dem nächsten Frame ändern (verhindert setState auf
  /// defunct Elementen) und diesen Frame auch anstoßen – sonst bliebe z.B. der
  /// Stopp-Knopf stehen, bis das Kind den Bildschirm berührt.
  void _afterFrame(VoidCallback fn) {
    SchedulerBinding.instance.addPostFrameCallback((_) => fn());
    SchedulerBinding.instance.scheduleFrame();
  }

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
      // (ambient schneidet Frequenzen ab → klingt dumpfer/roboterhafter).
      // Nur in der iOS-App: das Plugin fragt intern Platform.isIOS ab, was im
      // Browser einen Fehler wirft und TTS dort komplett abschalten würde.
      if (isIOSApp) {
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          ],
          IosTextToSpeechAudioMode.defaultMode,
        );
      }

      // Beste verfügbare deutsche Stimme wählen
      // iOS: Siri/Neural-Stimmen klingen deutlich natürlicher
      await _selectBestVoice();

      _tts.setStartHandler(() {
        // Kennung jetzt übernehmen: der Abbruch der vorigen Ausgabe (Cancel-
        // Handler) hat sie davor schon wieder gelöscht.
        final id = _pendingUtteranceId;
        _pendingUtteranceId = null;
        _webSpeaking = true;
        // Scheduling über SchedulerBinding verhindert setState auf defunct Elementen
        _afterFrame(() {
          if (mounted) {
            state = state.copyWith(
              isSpeaking: true,
              utteranceId: id,
              clearUtterance: id == null,
            );
          }
        });
      });

      _tts.setCompletionHandler(() {
        _markWebStopped();
        _afterFrame(() {
          if (mounted) {
            state = state.copyWith(isSpeaking: false, clearUtterance: true);
          }
        });
      });

      _tts.setCancelHandler(() {
        _markWebStopped();
        _afterFrame(() {
          if (mounted) {
            state = state.copyWith(isSpeaking: false, clearUtterance: true);
          }
        });
      });

      _tts.setErrorHandler((msg) {
        _markWebStopped();
        _afterFrame(() {
          if (mounted) {
            state = state.copyWith(isSpeaking: false, clearUtterance: true);
          }
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

    await _stopBeforeSpeak();
    await _tts.setSpeechRate(_speechRate);
    await _tts.setPitch(_pitch);
    await _tts.speak(text);
  }

  /// Liest eine Antwort von Lexi vor (Formeln, Markdown und Emojis werden
  /// in sprechbaren Text übersetzt). [id] ist die ID der Nachricht.
  Future<void> speakTutor(String text, {required String id}) async {
    if (!state.isInitialized) return;
    final clean = speakableText(text);
    if (clean.isEmpty) return;

    _pendingUtteranceId = id;
    await _stopBeforeSpeak();
    await _tts.setSpeechRate(_speechRate);
    await _tts.setPitch(_pitch);
    await _tts.speak(clean);
  }

  /// Safari (iPhone/iPad) spricht erst, nachdem einmal innerhalb eines Tipps
  /// gesprochen wurde. Antworten von Lexi kommen aber erst Sekunden später.
  /// Deshalb beim Tippen auf „Senden“ einmal leer sprechen.
  bool _webAudioUnlocked = false;
  Future<void> unlockWebAudio() async {
    // Läuft gerade eine Ausgabe, ist der Ton ohnehin schon freigeschaltet.
    if (!kIsWeb || _webAudioUnlocked || _webSpeaking || !state.isInitialized) {
      return;
    }
    _webAudioUnlocked = true;
    await _tts.speak(' ');
  }

  /// Liest eine Quiz-Frage vor.
  /// Entfernt Emojis aus dem Text für natürlichere Sprachausgabe.
  Future<void> speakQuestion(String questionText) async {
    if (!state.isInitialized || questionText.isEmpty) return;

    final cleanText = stripEmojis(questionText);
    await _stopBeforeSpeak();
    await _tts.setSpeechRate(_speechRate);
    await _tts.setPitch(_pitch);
    await _tts.speak(cleanText);
  }

  /// Spricht Feedback (Lob / Ermutigung) mit enthusiastischerer Stimme.
  Future<void> speakFeedback(String feedbackText) async {
    if (!state.isInitialized || feedbackText.isEmpty) return;

    final cleanText = stripEmojis(feedbackText);
    await _stopBeforeSpeak();
    await _tts.setSpeechRate(_feedbackRate);
    await _tts.setPitch(_feedbackPitch);
    await _tts.speak(cleanText);
  }

  /// Spricht eine Begrüßung für das Dashboard.
  Future<void> speakGreeting(String childName) async {
    if (!state.isInitialized) return;

    await _stopBeforeSpeak();
    await _tts.setSpeechRate(_speechRate);
    await _tts.setPitch(_pitch);
    await _tts.speak('Hallo $childName! Was wollen wir heute lernen?');
  }

  /// Spricht den Fachnamen beim Carousel-Wischen.
  Future<void> speakSubject(String subjectLabel) async {
    if (!state.isInitialized) return;

    await _stopBeforeSpeak();
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

    await _stopBeforeSpeak();
    await _tts.setSpeechRate(_feedbackRate);
    await _tts.setPitch(_feedbackPitch);
    await _tts.speak(text);
  }

  /// Stoppt die aktuelle Sprachausgabe sofort.
  Future<void> stop() async {
    await _tts.stop();
    if (mounted) {
      state = state.copyWith(isSpeaking: false, clearUtterance: true);
    }
  }

  // ── Hilfsmethoden ─────────────────────────────────────────────────────────

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

  /// Schlüssel-Präfix in SharedPreferences und Startwert – so dient die
  /// Klasse auch für „Lexi automatisch vorlesen“ (tutorAutoReadProvider).
  final String prefix;
  final bool defaultValue;

  TtsSettingsNotifier(
    this.childId, {
    this.prefix = 'tts_enabled_',
    this.defaultValue = true,
  }) : super(defaultValue) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getBool('$prefix$childId');
      if (mounted) state = value ?? defaultValue;
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
      await prefs.setBool('$prefix$childId', newValue);
    } catch (_) {}
  }

  /// Setzt TTS explizit an oder aus.
  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$prefix$childId', enabled);
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

/// Lexi liest ihre Antworten automatisch vor (pro Kind, Standard: aus).
/// Der Lautsprecher-Knopf an jeder Nachricht geht unabhängig davon immer.
final tutorAutoReadProvider =
    StateNotifierProvider.family<TtsSettingsNotifier, bool, String>((
      ref,
      childId,
    ) {
      return TtsSettingsNotifier(
        childId,
        prefix: 'tutor_auto_read_',
        defaultValue: false,
      );
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
