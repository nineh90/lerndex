import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/domain/child_model.dart';
import '../features/tutor/domain/chat_message.dart';
import '../features/generated_tasks/data/generated_task_models.dart';
import '../features/generated_tasks/domain/generated_task_result.dart';
import '../features/quiz/domain/question_model.dart';
import '../features/quiz/data/curriculum_data.dart';

// ============================================================================
// ANTWORT-TYPEN
// ============================================================================

/// Antwort des KI-Tutors mit extrahiertem Schulfach und Korrektheitsstatus.
class TutorResponse {
  final String text;
  final String subject; // z.B. 'Mathematik' oder 'kein_schulfach'
  final bool
  isCorrect; // true wenn Schüler eine Aufgabe korrekt beantwortet hat

  const TutorResponse({
    required this.text,
    required this.subject,
    this.isCorrect = false,
  });

  bool get isSchoolSubject => subject != 'kein_schulfach';
}

// ============================================================================
// VERTEX AI SERVICE
//
// Einziger KI-Service der App. DSGVO-konform über Google Cloud Vertex AI.
// Kein google_generative_ai, kein googleAI() – ausschließlich vertexAI().
//
// Zuständigkeiten:
//   1. KI-Tutor für Kinder         → sendTutorMessage()
//   2. Aufgaben aus Foto generieren → generateTasksFromImage()
//   3. Quiz-Fragen generieren       → generateQuizQuestions()
// ============================================================================
class VertexAIService {
  GenerativeModel? _tutorModel;
  GenerativeModel? _taskGeneratorModel;
  GenerativeModel? _quizModel;

  bool _tutorInitialized = false;
  bool _taskInitialized = false;
  bool _quizInitialized = false;

  final FirebaseStorage _storage = FirebaseStorage.instance;
  final _random = Random();

  // --------------------------------------------------------------------------
  // INITIALISIERUNG
  // --------------------------------------------------------------------------

  /// Kompatibilitäts-Methode – wird von tutor_provider.dart aufgerufen.
  /// Die eigentliche Initialisierung erfolgt lazy beim ersten Aufruf.
  Future<void> initialize() async {
    await _ensureTutorInitialized();
    await _ensureTaskInitialized();
    await _ensureQuizInitialized();
  }

  Future<void> _ensureTutorInitialized() async {
    if (_tutorInitialized) return;
    debugPrint('🚀 Vertex AI Tutor-Modell wird initialisiert...');
    _tutorModel = FirebaseAI.vertexAI().generativeModel(
      model: 'gemini-2.0-flash',
      generationConfig: GenerationConfig(
        temperature: 0.7,
        maxOutputTokens: 2048,
        topP: 0.9,
        topK: 40,
      ),
      safetySettings: [
        SafetySetting(
          HarmCategory.harassment,
          HarmBlockThreshold.high,
          HarmBlockMethod.severity,
        ),
        SafetySetting(
          HarmCategory.hateSpeech,
          HarmBlockThreshold.high,
          HarmBlockMethod.severity,
        ),
        SafetySetting(
          HarmCategory.sexuallyExplicit,
          HarmBlockThreshold.medium,
          HarmBlockMethod.severity,
        ),
        SafetySetting(
          HarmCategory.dangerousContent,
          HarmBlockThreshold.high,
          HarmBlockMethod.severity,
        ),
      ],
    );
    _tutorInitialized = true;
    debugPrint('✅ Tutor-Modell initialisiert');
  }

  Future<void> _ensureTaskInitialized() async {
    if (_taskInitialized) return;
    debugPrint('🚀 Vertex AI Task-Modell wird initialisiert...');
    // Für Vision-Calls (Bild + Text): KEIN responseMimeType!
    _taskGeneratorModel = FirebaseAI.vertexAI().generativeModel(
      model: 'gemini-2.0-flash',
      generationConfig: GenerationConfig(
        temperature: 0.7,
        maxOutputTokens: 2048,
        topP: 0.95,
      ),
    );
    _taskInitialized = true;
    debugPrint('✅ Task-Modell initialisiert');
  }

  Future<void> _ensureQuizInitialized() async {
    if (_quizInitialized) return;
    debugPrint('🚀 Vertex AI Quiz-Modell wird initialisiert...');
    _quizModel = FirebaseAI.vertexAI().generativeModel(
      model: 'gemini-2.0-flash',
      generationConfig: GenerationConfig(
        temperature: 0.75,
        maxOutputTokens: 4096,
        topP: 0.92,
      ),
    );
    _quizInitialized = true;
    debugPrint('✅ Quiz-Modell initialisiert');
  }

  // --------------------------------------------------------------------------
  // 1. KI-TUTOR FÜR KINDER
  // --------------------------------------------------------------------------

  Future<TutorResponse> sendTutorMessage({
    required ChildModel child,
    required String userMessage,
    required List<ChatMessage> conversationHistory,
  }) async {
    await _ensureTutorInitialized();

    // Sicherheitschecks
    if (!_isAppropriateQuestion(userMessage)) {
      return const TutorResponse(
        text:
            'Diese Frage kann ich leider nicht beantworten. Ich bin Lerndex und helfe dir nur beim Lernen! 📚 Hast du eine Frage zu Mathe, Deutsch, Englisch oder anderen Schulfächern? 🎓',
        subject: 'kein_schulfach',
      );
    }

    if (_isNonSchoolQuestion(userMessage)) {
      return TutorResponse(
        text:
            'Das ist eine interessante Frage, ${child.name}! Aber ich bin Lerndex, dein Lernbegleiter, und helfe dir nur bei Schulfächern. 📚 Hast du vielleicht eine Frage zu Mathe, Deutsch, Englisch oder einem anderen Schulfach? 🎓',
        subject: 'kein_schulfach',
      );
    }

    if (userMessage.length > 500) {
      return const TutorResponse(
        text:
            'Deine Frage ist etwas zu lang. Kannst du sie kürzer formulieren? 😊',
        subject: 'kein_schulfach',
      );
    }

    try {
      final systemPrompt = _buildTutorSystemPrompt(child);

      // Modell pro Anfrage mit systemInstruction erstellen –
      // das ist der einzige Weg systemInstruction in firebase_ai zu übergeben.
      final model = FirebaseAI.vertexAI().generativeModel(
        model: 'gemini-2.0-flash',
        generationConfig: GenerationConfig(
          temperature: 0.7,
          maxOutputTokens: 2048,
          topP: 0.9,
          topK: 40,
        ),
        systemInstruction: Content.system(systemPrompt),
        safetySettings: [
          SafetySetting(
            HarmCategory.harassment,
            HarmBlockThreshold.high,
            HarmBlockMethod.severity,
          ),
          SafetySetting(
            HarmCategory.hateSpeech,
            HarmBlockThreshold.high,
            HarmBlockMethod.severity,
          ),
          SafetySetting(
            HarmCategory.sexuallyExplicit,
            HarmBlockThreshold.medium,
            HarmBlockMethod.severity,
          ),
          SafetySetting(
            HarmCategory.dangerousContent,
            HarmBlockThreshold.high,
            HarmBlockMethod.severity,
          ),
        ],
      );

      final history = <Content>[];

      final recentMessages = conversationHistory.length > 10
          ? conversationHistory.sublist(conversationHistory.length - 10)
          : conversationHistory;

      for (final msg in recentMessages) {
        if (msg.isLoading) continue;
        history.add(
          Content(msg.isUser ? 'user' : 'model', [TextPart(msg.text)]),
        );
      }

      debugPrint('📜 History an KI (${history.length} Nachrichten):');
      for (final h in history) {
        final role = h.role;
        final txt = (h.parts.first as TextPart).text;
        debugPrint(
          '  [$role]: ${txt.length > 80 ? "${txt.substring(0, 80)}..." : txt}',
        );
      }
      debugPrint('  [user/neu]: $userMessage');

      final chat = model.startChat(history: history);
      final response = await chat.sendMessage(Content.text(userMessage));
      final text = response.text;

      if (text == null || text.isEmpty) {
        return const TutorResponse(
          text:
              'Hmm, ich bin mir bei dieser Frage nicht sicher. Kannst du sie anders formulieren? 🤔',
          subject: 'kein_schulfach',
        );
      }

      final subject = _extractSubjectTag(text);
      final isCorrect = _extractCorrectTag(text);
      final cleanText = _stripSubjectTag(text);
      debugPrint(
        '🏷️ KI-Fach erkannt: "$subject" | korrekt: $isCorrect | Tag vorhanden: ${text.contains('[FACH:')}',
      );
      return TutorResponse(
        text: cleanText,
        subject: subject,
        isCorrect: isCorrect,
      );
    } catch (e) {
      debugPrint('❌ Tutor-Fehler: $e');
      return const TutorResponse(
        text: 'Ups, da ist etwas schiefgelaufen. Versuch es nochmal! 😅',
        subject: 'kein_schulfach',
      );
    }
  }

  // --------------------------------------------------------------------------
  // 2. AUFGABEN AUS FOTO GENERIEREN (für Eltern)
  // --------------------------------------------------------------------------

  Future<GeneratedTaskResult> generateTasksFromImage({
    required File imageFile,
    required ChildModel child,
    required String userId,
    required Subject subject,
    int numberOfTasks = 5,
    String? earlyLearnerTopic,
  }) async {
    await _ensureTaskInitialized();

    try {
      debugPrint(
        '📸 Analysiere Schulaufgabe für ${child.name} '
        '(${child.schoolType}, Kl. ${child.grade}, Lv. ${child.level}, '
        '${subject.displayName})...',
      );

      // Bild hochladen
      String? imageUrl;
      try {
        imageUrl = await _uploadImage(imageFile, userId, child.id, subject);
      } catch (e) {
        debugPrint('⚠️ Bild-Upload fehlgeschlagen (wird ignoriert): $e');
      }

      final imageBytes = await imageFile.readAsBytes();
      final prompt = _buildTaskGeneratorPrompt(
        child: child,
        subject: subject,
        numberOfTasks: numberOfTasks,
        earlyLearnerTopic: earlyLearnerTopic,
      );

      final content = [
        Content.multi([
          TextPart(prompt),
          InlineDataPart('image/jpeg', imageBytes),
        ]),
      ];

      debugPrint('🤖 Sende Anfrage an Vertex AI...');
      final response = await _taskGeneratorModel!.generateContent(content);
      final text = response.text;

      if (text == null || text.isEmpty) {
        throw Exception('KI hat keine Antwort generiert');
      }

      debugPrint('📝 Antwort erhalten, parse JSON...');
      final questions = _parseGeneratedQuestions(text);

      if (questions.isEmpty) {
        throw Exception('Keine validen Aufgaben generiert');
      }

      debugPrint(
        '✅ ${questions.length} von $numberOfTasks Aufgaben generiert!',
      );
      return GeneratedTaskResult(
        success: true,
        questions: questions,
        imageUrl: imageUrl,
      );
    } catch (e) {
      debugPrint('❌ Fehler bei Aufgabengenerierung: $e');
      return GeneratedTaskResult(
        success: false,
        questions: [],
        errorMessage: e.toString(),
      );
    }
  }

  // --------------------------------------------------------------------------
  // 3. QUIZ-FRAGEN GENERIEREN (für Schüler-Dashboard)
  // --------------------------------------------------------------------------

  Future<List<Question>> generateQuizQuestions({
    required ChildModel child,
    required String subject,
    int count = 10,
    List<String> recentTopics = const [],
  }) async {
    await _ensureQuizInitialized();

    try {
      final prompt = _buildQuizPrompt(
        child: child,
        subject: subject,
        count: count,
        recentTopics: recentTopics,
      );

      debugPrint(
        '📚 Generiere $count Quiz-Fragen für ${child.name} '
        '(${child.schoolType}, Kl. ${child.grade}, Lv. ${child.level}) '
        'im Fach $subject',
      );

      final response = await _quizModel!.generateContent([
        Content.text(prompt),
      ]);
      final text = response.text ?? '';

      return _parseQuizResponse(text, child.grade, subject: subject);
    } catch (e) {
      debugPrint('❌ Quiz-Generierung fehlgeschlagen: $e');
      return [];
    }
  }

  // --------------------------------------------------------------------------
  // PROMPTS
  // --------------------------------------------------------------------------

  String _buildTutorSystemPrompt(ChildModel child) {
    return '''
Du bist Lerndex, der persönliche Lernbegleiter für ${child.name}.

🎯 DEINE IDENTITÄT:
- Name: Lerndex
- Rolle: Geduldiger, freundlicher KI-Lernbegleiter
- Ziel: ${child.name} beim Lernen unterstützen und motivieren

📚 SCHÜLER-INFORMATIONEN:
- Name: ${child.name}
- Alter: ${child.age} Jahre
- Schulform: ${child.schoolType}
- Klassenstufe: ${child.grade}
- Aktuelles Level: ${child.level}

✅ DEINE HAUPTAUFGABEN:
1. Beantworte NUR Fragen zu Schulfächern (${_subjectsForGrade(child.grade, child.schoolType)})
2. Erkläre Konzepte Schritt für Schritt und altersgerecht
3. Verwende Beispiele, die für Klasse ${child.grade} passen
4. Sei motivierend, ermutigend und geduldig
5. Leite ${child.name} sanft zurück zum Lernen bei Nicht-Schul-Themen

🚫 ABSOLUTE GRENZEN:
- Beantworte KEINE Fragen zu: Kochen, Rezepten, Videospielen, Filmen, Serien, Hobbys, Freizeit
- Bei JEDER Nicht-Schul-Frage: Lehne HÖFLICH ab und leite zurück zu Schulfächern
- Keine Gewalt, unangemessene Inhalte oder gefährliche Themen

🧠 SOKRATES-METHODE – NIEMALS DIREKTE LÖSUNGEN VERRATEN:
- Gib NIEMALS direkt das Ergebnis einer Aufgabe an, egal wie einfach sie ist.
- Statt "2 + 2 = 4" sagst du: "Was passiert, wenn du 2 Äpfel hast und 2 dazulegst? Zähl mal nach! 🍎🍎"
- Erkläre das PRINZIP oder den LÖSUNGSWEG, niemals das fertige Ergebnis.
- Benutze ein ANDERES, ähnliches Beispiel um das Konzept zu erklären.
  → Beispiel: Fragt ${child.name} "Was ist 15 × 4?", erkläre anhand von "10 × 4 = 40, und 5 × 4 = 20 – kannst du die beiden Teilergebnisse jetzt zusammenzählen?"
- Stelle Rückfragen, die ${child.name} selbst zum Nachdenken bringen: "Was weißt du schon darüber?", "Welchen Schritt könntest du als erstes machen?"
- Wenn ${child.name} die richtige Antwort selbst nennt → dann und nur dann bestätige sie freudig!
- Ausnahme: Vokabeln / Fremdwörter / Fakten (z.B. "Was bedeutet 'apple'?") dürfen direkt beantwortet werden, da es hier kein Lösungsdenken gibt.

💬 KOMMUNIKATIONSSTIL:
- Einfache, kindgerechte Sprache (passend für ${child.age} Jahre)
- Kurze, klare Antworten (max. 3-4 Sätze)
- Gelegentlich passende Emojis
- Lobe Fortschritte, ermutige zum Weiterlernen
- Mathematische Formeln IMMER in LaTeX: \$\\frac{1}{2}\$, \$\\sqrt{4}\$, \$x^2\$

PFLICHT BEI JEDER ANTWORT:
Füge als ALLERLETZTE Zeile exakt diese zwei Tags an (werden automatisch entfernt, für den Nutzer unsichtbar):
- Schulfach: [FACH:Mathematik] / [FACH:Deutsch] / [FACH:Englisch]${child.grade <= 4 || child.schoolType == 'Grundschule' ? ' / [FACH:Sachkunde]' : ''}${child.grade >= 5 ? ' / [FACH:Biologie] / [FACH:Chemie] / [FACH:Physik] / [FACH:Geschichte]' : ''}
- Kein Schulfach / unklar / Smalltalk / Ablehnung: [FACH:kein_schulfach]
- Nur wenn der Schüler eine Aufgabe FALSCH beantwortet hat: [KORREKT:nein]
- Nur wenn der Schüler eine Aufgabe RICHTIG beantwortet hat: [KORREKT:ja]
- Frage stellen / Erklärung bitten / kein Lösungsversuch: kein KORREKT-Tag
''';
  }

  // --------------------------------------------------------------------------
  // DYNAMISCHE BEGRÜSSUNG
  // --------------------------------------------------------------------------

  /// Baut eine dynamische Begrüßungsnachricht aus Tageszeit, Wochentag,
  /// Streak und Level. Jeder Baustein hat mehrere Varianten → viele
  /// mögliche Kombinationen, ohne extra KI-Aufruf.
  static String buildWelcomeMessage(ChildModel child) {
    final now = DateTime.now();
    final hour = now.hour;
    final weekday = now.weekday; // 1=Mo … 7=So
    final streak = child.streak ?? 0;
    final level = child.level;
    final name = child.name;

    // Seed wechselt jede Sekunde → andere Kombination bei jedem Öffnen
    final seed = now.second + now.minute * 60;
    String pick(List<String> options) => options[seed % options.length];

    // ── Tageszeit-Gruß ──────────────────────────────────────────────────
    final String greeting;
    if (hour < 10) {
      greeting = pick([
        'Guten Morgen, $name! 🌅',
        'Hey $name, früh auf heute! 🌄',
        'Morgen, $name! ☀️ Der Tag fängt gut an.',
        'Oh, schon wach, $name? Super! 🐦',
      ]);
    } else if (hour < 13) {
      greeting = pick([
        'Hallo $name! 👋',
        'Hi $name! 😊',
        'Hey $name, schön dass du da bist!',
        'Na $name, bereit zum Lernen? 💪',
      ]);
    } else if (hour < 17) {
      greeting = pick([
        'Schön, dass du vorbeischaust, $name! 🌤️',
        'Hey $name! 👋 Nachmittagsrunde?',
        'Hi $name! Nach der Schule direkt weitergemacht? 🎒',
        'Hallo $name! 😄 Hausaufgaben-Zeit?',
      ]);
    } else if (hour < 20) {
      greeting = pick([
        'Hallo $name! 🌇 Noch ein bisschen lernen?',
        'Hey $name! Abends ist auch eine gute Zeit. 🌆',
        'Hi $name! 👋 Den Tag noch gut nutzen?',
        'Schön, $name! Abends lernt es sich oft am besten. 🌙',
      ]);
    } else {
      greeting = pick([
        'Hallo $name! 🌙 Noch ein bisschen?',
        'Hey $name! Nicht zu lange, aber kurz lernen geht immer. ⭐',
        'Hi $name! 🌟 Ein kleines Lern-Abenteuer vor dem Schlafen?',
      ]);
    }

    // ── Kontext-Kommentar ────────────────────────────────────────────────
    final String context;
    if (streak >= 14) {
      context = pick([
        '🔥 **$streak Tage** am Stück – das ist wirklich beeindruckend! Du bist kaum aufzuhalten.',
        '🏆 **$streak-Tage-Streak**! So eine Ausdauer haben nur die Besten.',
        '⚡ Unfassbar – **$streak Tage** ohne Pause! Du bist eine echte Lernmaschine.',
      ]);
    } else if (streak >= 7) {
      context = pick([
        '🔥 Eine ganze Woche am Stück – **$streak Tage Streak**! Weiter so!',
        '⭐ **$streak Tage** in Folge! Das ist echte Ausdauer.',
        '💪 **$streak-Tage-Streak** – du bist richtig im Rhythmus!',
      ]);
    } else if (streak >= 3) {
      context = pick([
        '⚡ Schon **$streak Tage** hintereinander dabei – bleib dran!',
        '🌟 **$streak Tage Streak** – du kommst in Fahrt!',
        '👍 **$streak Tage** am Stück! Noch ein paar mehr und du knackst eine Woche.',
      ]);
    } else if (level >= 15) {
      context = pick([
        '🏆 Level **$level** – du weißt wirklich schon eine Menge!',
        '🌟 Level **$level**! Nicht viele kommen so weit.',
        '💎 Wow, Level **$level**. Richtig beeindruckend!',
      ]);
    } else if (level >= 8) {
      context = pick([
        '📈 Level **$level** – du machst tolle Fortschritte!',
        '🎯 Level **$level** erreicht! Du wirst immer besser.',
        '🚀 Level **$level** – weiter so, du bist auf einem guten Weg!',
      ]);
    } else if (weekday == 1) {
      context = pick([
        '🗓️ Montag – neuer Start, neue Chance! Was nimmst du dir diese Woche vor?',
        '💪 Die Woche fängt direkt gut an, wenn man lernt!',
        '🌱 Montags den Grundstein für die Woche legen – gute Idee!',
      ]);
    } else if (weekday == 5) {
      context = pick([
        '🎉 Freitag! Noch ein bisschen Lernen, dann kommt das Wochenende.',
        '⭐ Freitags noch dabei sein – das zeigt echten Einsatz!',
        '🏁 Zielgerade der Woche! Ein bisschen Lernen und dann Wochenende.',
      ]);
    } else if (weekday >= 6) {
      context = pick([
        '🛋️ Auch am Wochenende dabei – das zahlt sich aus!',
        '🌈 Wochenende und trotzdem lernen – du bist wirklich motiviert!',
        '⭐ Selbst am Wochenende? Respekt, $name!',
      ]);
    } else {
      context = pick([
        '💡 Ich bin gespannt, was du heute wissen möchtest!',
        '📖 Jede Frage ist eine gute Frage. Nur raus damit!',
        '🚀 Gemeinsam kriegen wir das hin. Was beschäftigt dich gerade?',
        '🧠 Dein Gehirn ist bereit – ich auch!',
        '✏️ Hausaufgaben, ein schwieriges Thema oder einfach Neugier? Ich bin da!',
        '🌟 Keine Frage ist zu klein oder zu groß für mich!',
        '🎯 Was lernst du gerade in der Schule? Ich helfe dir dabei.',
        '😊 Schön, dass du da bist! Womit soll ich dir helfen?',
      ]);
    }

    // ── Abschluss-Frage ──────────────────────────────────────────────────
    final subjects = _subjectsForGrade(child.grade, child.schoolType);
    final String closing = pick([
      'Ich helfe dir bei $subjects und allem anderen was in der Schule drankommt. **Was möchtest du heute lernen?** 📚',
      'Stell mir einfach deine Frage – ich erkläre alles Schritt für Schritt. **Womit fangen wir an?** 🎓',
      'Hausaufgaben, Erklärungen oder einfach üben – ich bin für alles bereit. **Was darf es sein?** ✨',
      '$subjects – alles kein Problem. **Was beschäftigt dich heute?** 📖',
    ]);

    return '$greeting\n\n$context\n\n$closing';
  }

  String _buildTaskGeneratorPrompt({
    required ChildModel child,
    required Subject subject,
    required int numberOfTasks,
    String? earlyLearnerTopic,
  }) {
    final curriculumContext = CurriculumData.buildCurriculumContext(
      schoolType: child.schoolType,
      grade: child.grade,
      subject: subject.value,
      level: child.level,
    );

    final profile = CurriculumData.getDifficultyProfile(
      schoolType: child.schoolType,
      level: child.level,
    );

    final subjectContext = _buildSubjectContext(subject, child);

    return '''
Du bist ein pädagogischer Experte, der personalisierte Multiple-Choice-Aufgaben für Schüler erstellt.

SCHÜLER:
- Name: ${child.name}
- Schulform: ${child.schoolType}
- Klasse: ${child.grade}
- Level: ${child.level}
- Fach: ${subject.displayName}

LEHRPLAN-KONTEXT:
$curriculumContext

SCHWIERIGKEITSPROFIL: $profile

FACH-KONTEXT:
$subjectContext

${child.schoolType == 'Hauptschule' || (child.schoolType == 'Gesamtschule' && child.level <= 4) ? '''
⚠️ HAUPTSCHULE/G-KURS-NIVEAU:
- Aufgaben mit Alltagsbezug, keine Abstraktion
- Einfache, klare Formulierungen
- Keine formalen Beweise oder komplexe Fachsprache
''' : ''}

${earlyLearnerTopic != null ? '''
FRUEHE LERNPHASE (Klasse 1-2) - PFLICHT:
- Thema: $earlyLearnerTopic
- Aufgaben NUR zu "$earlyLearnerTopic" - keine anderen Themen!
- Sprache: sehr einfach, kurze Saetze, kindgerecht (6-8 Jahre)
- Antworten: einzelne Woerter oder Zahlen, keine langen Saetze
''' : ''}
AUFGABE:
Schau auf das Foto und erstelle GENAU $numberOfTasks neue Multiple-Choice-Aufgaben zu ähnlichen Themen.

REGELN:
- Exakt 4 Antwortmöglichkeiten pro Aufgabe
- Genau 1 richtige Antwort
- Falsche Antworten müssen plausibel klingen (typische Schülerfehler!)
- Alle 4 Optionen ähnlich lang
- Passend für Klasse ${child.grade}

WICHTIG: Antworte NUR mit diesem JSON-Array, ohne Markdown oder Text davor/danach:
[
  {
    "question": "Klare Aufgabenstellung",
    "options": ["Option A", "Option B", "Option C", "Option D"],
    "correctAnswer": "Exakt wie eine der Optionen",
    "solution": "Kurze Erklärung in 1-2 Sätzen",
    "difficulty": "easy|medium|hard",
    "topic": "Spezifisches Thema"
  }
]
''';
  }

  String _buildQuizPrompt({
    required ChildModel child,
    required String subject,
    required int count,
    required List<String> recentTopics,
  }) {
    final subjectDisplay = _subjectDisplayName(subject);

    final curriculumContext = CurriculumData.buildCurriculumContext(
      schoolType: child.schoolType,
      grade: child.grade,
      subject: subject,
      level: child.level,
    );

    final profile = CurriculumData.getDifficultyProfile(
      schoolType: child.schoolType,
      level: child.level,
    );

    final topicFocus = _pickTopicFocus(
      schoolType: child.schoolType,
      grade: child.grade,
      subject: subject,
      level: child.level,
    );

    final topicAvoidance = recentTopics.isNotEmpty
        ? 'THEMEN-VARIATION:\n'
              'Das Kind hatte kürzlich viele Fragen zu: ${recentTopics.join(", ")}.\n'
              'Bevorzuge ANDERE Unterthemen innerhalb des Lehrplans.\n'
        : '';

    final gesamtschulNote = child.schoolType == 'Gesamtschule'
        ? '\nWICHTIG — GESAMTSCHULE:\n'
              'Basierend auf Level ${child.level}: '
              '${child.level <= 4
                  ? "G-Kurs (Grundkurs = Hauptschulniveau)"
                  : child.level <= 8
                  ? "E-Kurs (Erweiterungskurs = Realschulniveau)"
                  : "Oberer E-Kurs (= Gymnasialniveau)"}.\n'
        : '';

    final exampleQuestions = _getExampleQuestions(
      subject: subject,
      schoolType: child.schoolType,
      grade: child.grade,
      level: child.level,
    );

    return '''
Du bist ein hochspezialisierter Aufgabengenerator für das deutsche Schulsystem.
Deine Aufgaben basieren auf den offiziellen KMK-Bildungsstandards und Landeslehrplänen.

SCHÜLER-PROFIL:
- Name: ${child.name}
- Alter: ${child.age} Jahre
- Schulform: ${child.schoolType}
- Klasse: ${child.grade}
- App-Level: ${child.level}
- Fach: $subjectDisplay
$gesamtschulNote

LEHRPLAN-KONTEXT:
$curriculumContext

THEMEN-FOKUS FÜR DIESEN BATCH:
$topicFocus

$topicAvoidance

SCHWIERIGKEITSPROFIL: $profile

AUFGABE: Erstelle GENAU $count Multiple-Choice-Fragen.

REGELN:
- Exakt 4 Antwortmöglichkeiten
- Genau 1 richtige Antwort
- Abwechslungsreiche Alltagskontexte
- Falsche Antworten: plausibel, typische Schülerfehler

$exampleQuestions

⚠️ FACH-BINDUNG (KRITISCH):
Du generierst AUSSCHLIESSLICH Fragen zum Fach $subjectDisplay.
- KEINE Fragen aus anderen Fächern (nicht Mathe wenn Deutsch angefragt, etc.)
- KEINE fächerübergreifenden Fragen
- Jede Frage MUSS eindeutig dem Fach $subjectDisplay zuzuordnen sein
- Das Feld "topic" MUSS ein Unterthema von $subjectDisplay enthalten (z.B. "Bruchrechnung", "Groß- und Kleinschreibung", "Simple Past")

Antworte NUR mit einem JSON-Array, kein Text oder Markdown davor/danach:
[
  {
    "question": "Fragetext",
    "options": ["A", "B", "C", "D"],
    "answer": "Richtige Option exakt wie oben",
    "difficulty": "easy|medium|hard",
    "topic": "Spezifisches Unterthema von $subjectDisplay"
  }
]
''';
  }

  // --------------------------------------------------------------------------
  // PARSING
  // --------------------------------------------------------------------------

  /// Parst Aufgaben aus dem Task-Generator (GeneratedQuestion-Format)
  List<GeneratedQuestion> _parseGeneratedQuestions(String text) {
    final questions = <GeneratedQuestion>[];

    try {
      String cleaned = _cleanJson(text);

      // Versuche JSON-Array direkt zu parsen
      try {
        final startArr = cleaned.indexOf('[');
        final endArr = cleaned.lastIndexOf(']');
        if (startArr != -1 && endArr != -1 && endArr > startArr) {
          final jsonStr = cleaned.substring(startArr, endArr + 1);
          final List<dynamic> jsonList = jsonDecode(jsonStr);
          for (final item in jsonList) {
            final q = _parseGeneratedQuestionFromMap(
              item as Map<String, dynamic>,
            );
            if (q != null) questions.add(q);
          }
          if (questions.isNotEmpty) {
            debugPrint('✅ ${questions.length} Aufgaben aus JSON-Array geparst');
            return questions;
          }
        }
      } catch (_) {}

      // Fallback: Einzelne JSON-Objekte per Regex extrahieren
      final objectRegex = RegExp(r'\{[^{}]*"question"[^{}]*\}', dotAll: true);
      for (final match in objectRegex.allMatches(cleaned)) {
        try {
          final obj = jsonDecode(match.group(0)!) as Map<String, dynamic>;
          final q = _parseGeneratedQuestionFromMap(obj);
          if (q != null) questions.add(q);
        } catch (_) {}
      }

      debugPrint('✅ ${questions.length} Aufgaben aus Einzel-Objekten geparst');
    } catch (e) {
      debugPrint('❌ JSON Parse Fehler (generateTasks): $e');
      debugPrint(
        'Text war: ${text.substring(0, text.length.clamp(0, 200))}...',
      );
    }

    return questions;
  }

  GeneratedQuestion? _parseGeneratedQuestionFromMap(Map<String, dynamic> json) {
    try {
      final questionText = json['question']?.toString() ?? '';
      if (questionText.isEmpty) return null;

      final rawOptions = json['options'];
      if (rawOptions == null || rawOptions is! List || rawOptions.length != 4) {
        return null;
      }

      final options = List<String>.from(rawOptions);
      final correctAnswer = json['correctAnswer']?.toString() ?? '';
      if (correctAnswer.isEmpty || !options.contains(correctAnswer)) {
        debugPrint('⚠️ Richtige Antwort nicht in Optionen: "$correctAnswer"');
        return null;
      }

      return GeneratedQuestion(
        id: '',
        question: questionText,
        options: options,
        correctAnswer: correctAnswer,
        solution: json['solution']?.toString(),
        difficulty: json['difficulty']?.toString() ?? 'medium',
        topic: json['topic']?.toString() ?? '',
        status: TaskApprovalStatus.pending,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('⚠️ Fehler beim Parsen einer Aufgabe: $e');
      return null;
    }
  }

  /// Parst Quiz-Fragen (Question-Format für Schüler-Dashboard).
  /// Führt nach dem Parsen eine Fach-Validierung durch:
  /// Fragen die eindeutig zum falschen Fach gehören werden herausgefiltert.
  List<Question> _parseQuizResponse(
    String rawText,
    int grade, {
    String subject = '',
  }) {
    try {
      String cleaned = _cleanJson(rawText);

      final startIndex = cleaned.indexOf('[');
      final endIndex = cleaned.lastIndexOf(']');
      if (startIndex == -1 || endIndex == -1) {
        debugPrint('⚠️ Kein JSON-Array in Quiz-Antwort gefunden');
        return [];
      }

      final jsonStr = cleaned.substring(startIndex, endIndex + 1);
      final List<dynamic> jsonList = jsonDecode(jsonStr);

      final questions = <Question>[];
      final seenQuestions = <String>{};
      int filteredOut = 0;

      for (final item in jsonList) {
        try {
          final q = _parseQuizQuestionFromMap(
            item as Map<String, dynamic>,
            grade,
          );
          if (q == null) continue;

          // Fach-Validierung: Frage muss zum angeforderten Fach passen
          if (subject.isNotEmpty && !_questionMatchesSubject(q, subject)) {
            filteredOut++;
            debugPrint(
              '🚫 Fach-Mismatch gefiltert: "${q.question.length > 60 ? q.question.substring(0, 60) : q.question}..." (topic: ${q.topic})',
            );
            continue;
          }

          final normalized = q.question.toLowerCase().trim();
          if (seenQuestions.contains(normalized)) continue;
          seenQuestions.add(normalized);
          questions.add(q);
        } catch (e) {
          debugPrint('⚠️ Quiz-Frage übersprungen: $e');
        }
      }

      if (filteredOut > 0) {
        debugPrint('🚫 $filteredOut Fragen wegen Fach-Mismatch gefiltert');
      }
      debugPrint('✅ ${questions.length} Quiz-Fragen geparst (Fach: $subject)');
      return questions;
    } catch (e) {
      debugPrint('❌ JSON-Parsing (Quiz) fehlgeschlagen: $e');
      return [];
    }
  }

  /// Prüft ob eine Frage wirklich zum angeforderten Fach gehört.
  /// Erkennt offensichtliche Fach-Mismatches anhand von Schlüsselwörtern
  /// im Fragetext und im topic-Feld.
  bool _questionMatchesSubject(Question q, String subject) {
    final subjectLower = subject.toLowerCase();
    final questionLower = q.question.toLowerCase();
    final topicLower = q.topic.toLowerCase();
    final combined = '$questionLower $topicLower';

    // Schlüsselwörter die auf ein bestimmtes Fach hindeuten
    const subjectKeywords = <String, List<String>>{
      'mathe': [
        'rechne',
        'berechne',
        'zahl',
        'summe',
        'differenz',
        'produkt',
        'quotient',
        'gleichung',
        'prozent',
        'bruch',
        'fläche',
        'volumen',
        'winkel',
        'dreieck',
        'viereck',
        'kreis',
        'addition',
        'subtraktion',
        'multiplikation',
        'division',
        'dezimal',
        'komma',
        'meter',
        'kilometer',
        'kilogramm',
        'liter',
        'euro',
        'cent',
        'primzahl',
        'teiler',
        'algebra',
        'geometrie',
        'statistik',
        'wahrscheinlichkeit',
      ],
      'deutsch': [
        'satz',
        'wort',
        'artikel',
        'nomen',
        'verb',
        'adjektiv',
        'adverb',
        'grammatik',
        'rechtschreibung',
        'komma',
        'gedicht',
        'text',
        'präteritum',
        'perfekt',
        'nominativ',
        'akkusativ',
        'dativ',
        'genitiv',
        'konjunktion',
        'pronomen',
        'silbe',
        'umlaut',
        'substantiv',
        'präposition',
        'synonym',
        'antonym',
        'leseverstehen',
      ],
      'englisch': [
        'english',
        'translate',
        'übersetz',
        'present',
        'past',
        'future',
        'tense',
        'verb',
        'noun',
        'adjective',
        'article',
        'plural',
        'singular',
        'sentence',
        'vocabulary',
        'grammar',
        'spelling',
        'simple past',
        'present perfect',
        'will',
        'going to',
        'modal',
        'irregular',
        'listening',
        'reading',
      ],
      'biologie': [
        'zelle',
        'organ',
        'tier',
        'pflanze',
        'fotosynthese',
        'evolution',
        'genetik',
        'dna',
        'chromosom',
        'protein',
        'ökosystem',
        'nahrungskette',
        'bakterie',
        'virus',
        'säugetier',
        'wirbeltier',
        'blüte',
        'wurzel',
        'blatt',
        'stamm',
        'atmung',
        'verdauung',
        'blutkreislauf',
        'nervensystem',
        'hormon',
        'mitose',
        'meiose',
      ],
      'chemie': [
        'atom',
        'molekül',
        'element',
        'verbindung',
        'reaktion',
        'säure',
        'base',
        'salz',
        'oxidation',
        'reduktion',
        'bindung',
        'elektron',
        'proton',
        'neutron',
        'periodensystem',
        'formel',
        'mol',
        'masse',
        'konzentration',
        'lösung',
        'titration',
        'elektrolyse',
        'verbrennung',
        'katalysator',
      ],
      'physik': [
        'kraft',
        'energie',
        'arbeit',
        'leistung',
        'geschwindigkeit',
        'beschleunigung',
        'masse',
        'gewicht',
        'dichte',
        'druck',
        'welle',
        'frequenz',
        'wellenlänge',
        'spannung',
        'strom',
        'widerstand',
        'magnet',
        'licht',
        'optik',
        'linse',
        'spiegel',
        'wärme',
        'temperatur',
        'newton',
        'joule',
        'watt',
      ],
      'sachkunde': [
        'tier',
        'pflanze',
        'jahreszeit',
        'wetter',
        'körper',
        'sinne',
        'familie',
        'berufe',
        'verkehr',
        'umwelt',
        'natur',
        'wald',
        'wasser',
        'luft',
        'boden',
        'heimat',
        'gemeinde',
        'gesundheit',
      ],
      'geschichte': [
        'jahr',
        'jahrhundert',
        'jahrtausend',
        'krieg',
        'frieden',
        'kaiser',
        'könig',
        'revolution',
        'republik',
        'demokratie',
        'antike',
        'mittelalter',
        'neuzeit',
        'römisch',
        'griechisch',
        'ägypten',
        'weltkrieg',
        'nazi',
        'weimar',
        'ddr',
        'brd',
        'reformation',
        'aufklärung',
        'industrialisierung',
      ],
    };

    // Schlüsselwörter anderer Fächer (nicht das angeforderte)
    final otherSubjects = subjectKeywords.entries
        .where((e) => e.key != subjectLower)
        .toList();

    // Prüfe ob das topic eines ANDEREN Fachs eindeutig zutrifft
    // und KEIN einziges Keyword des richtigen Fachs vorkommt
    final ownKeywords = subjectKeywords[subjectLower] ?? [];
    final hasOwnKeyword = ownKeywords.any((kw) => combined.contains(kw));

    for (final entry in otherSubjects) {
      final foreignKeywords = entry.value;
      // Mind. 2 fremde Keywords + kein eigenes Keyword → Mismatch
      final foreignMatches = foreignKeywords
          .where((kw) => combined.contains(kw))
          .length;
      if (foreignMatches >= 2 && !hasOwnKeyword) {
        return false;
      }
    }

    return true;
  }

  Question? _parseQuizQuestionFromMap(Map<String, dynamic> item, int grade) {
    final question = item['question'] as String? ?? '';
    final options = (item['options'] as List?)?.cast<String>() ?? [];
    final answer = item['answer'] as String? ?? '';
    final difficulty = item['difficulty'] as String? ?? 'medium';
    final topic = item['topic'] as String? ?? '';

    if (question.isEmpty || options.length != 4 || answer.isEmpty) return null;
    if (!options.contains(answer)) return null;

    return Question(
      grade: grade,
      question: question,
      options: options,
      answer: answer,
      difficulty: difficulty,
      topic: topic,
    );
  }

  // --------------------------------------------------------------------------
  // JSON HELPER
  // --------------------------------------------------------------------------

  /// Bereinigt KI-Output: entfernt Markdown-Fences und fixt Newlines in Strings
  String _cleanJson(String text) {
    String cleaned = text.trim();
    if (cleaned.startsWith('```json')) {
      cleaned = cleaned.substring(7);
    } else if (cleaned.startsWith('```'))
      cleaned = cleaned.substring(3);
    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }
    cleaned = cleaned.trim();
    return _fixJsonNewlines(cleaned);
  }

  String _fixJsonNewlines(String json) {
    final buffer = StringBuffer();
    bool inString = false;
    bool escaped = false;

    for (int i = 0; i < json.length; i++) {
      final char = json[i];
      if (escaped) {
        buffer.write(char);
        escaped = false;
        continue;
      }
      if (char == '\\' && inString) {
        buffer.write(char);
        escaped = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        buffer.write(char);
        continue;
      }
      if (inString && char == '\n') {
        buffer.write('\\n');
        continue;
      }
      if (inString && char == '\r') {
        continue;
      }
      buffer.write(char);
    }
    return buffer.toString();
  }

  // --------------------------------------------------------------------------
  // UPLOAD
  // --------------------------------------------------------------------------

  Future<String> _uploadImage(
    File imageFile,
    String userId,
    String childId,
    Subject subject,
  ) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = 'task_images/$userId/$childId/${subject.value}/$timestamp.jpg';
    final ref = _storage.ref().child(path);
    await ref.putFile(imageFile);
    final url = await ref.getDownloadURL();
    debugPrint('✅ Bild hochgeladen: $path');
    return url;
  }

  // --------------------------------------------------------------------------
  // CURRICULUM HELPERS
  // --------------------------------------------------------------------------

  String _buildSubjectContext(Subject subject, ChildModel child) {
    final topics = CurriculumData.getTopics(
      schoolType: child.schoolType,
      grade: child.grade,
      subject: subject.value,
      level: child.level,
    );

    if (topics.isEmpty) {
      switch (subject) {
        case Subject.mathe:
          return 'FACH: MATHEMATIK — Mathematische Korrektheit und eindeutige Lösungswege.';
        case Subject.deutsch:
          return 'FACH: DEUTSCH — Sprachliche Korrektheit und altersgerechte Formulierungen.';
        case Subject.englisch:
          return 'FACH: ENGLISCH — Grammatikalische Korrektheit, konsistent British English.';
        case Subject.sachkunde:
          return 'FACH: SACHKUNDE — Wissenschaftliche Korrektheit und altersgerechte Erklärungen.';
        case Subject.biologie:
          return 'FACH: BIOLOGIE — Biologische Fachbegriffe und wissenschaftliche Korrektheit.';
        case Subject.chemie:
          return 'FACH: CHEMIE — Chemische Fachbegriffe und korrekte Formeln.';
        case Subject.physik:
          return 'FACH: PHYSIK — Physikalische Einheiten und Formeln.';
        case Subject.geschichte:
          return 'FACH: GESCHICHTE — Historische Fakten und zeitliche Einordnung.';
        case Subject.farbenFormen:
          return 'FACH: FARBEN & FORMEN — Grundfarben, geometrische Formen, kindgerechte Aufgaben für Klasse 1–2.';
      }
    }

    final buffer = StringBuffer();
    buffer.writeln('LEHRPLAN-THEMEN für ${subject.displayName}:');
    for (final topic in topics) {
      buffer.writeln('  📌 ${topic.competencyArea}: ${topic.topic}');
      for (final goal in topic.learningGoals) {
        buffer.writeln('     - $goal');
      }
      if (topic.notExpected.isNotEmpty) {
        buffer.writeln(
          '     ⚠️ ZU SCHWER / NICHT VERWENDEN: ${topic.notExpected.join(", ")}',
        );
      }
    }
    return buffer.toString();
  }

  String _pickTopicFocus({
    required String schoolType,
    required int grade,
    required String subject,
    required int level,
  }) {
    final topics = CurriculumData.getTopics(
      schoolType: schoolType,
      grade: grade,
      subject: subject,
      level: level,
    );

    if (topics.isEmpty) {
      return 'Generiere abwechslungsreiche Fragen zum Fach $subject für Klasse $grade.';
    }

    final shuffled = List.from(topics)..shuffle(_random);
    final focusTopics = shuffled.take(min(2, shuffled.length));

    final buffer = StringBuffer();
    buffer.writeln('Fokussiere diesen Batch auf:');
    for (final topic in focusTopics) {
      buffer.writeln('  * ${topic.topic}');
      final goals = List<String>.from(topic.learningGoals)..shuffle(_random);
      for (final goal in goals.take(min(3, goals.length))) {
        buffer.writeln('    -> $goal');
      }
    }
    return buffer.toString();
  }

  String _getExampleQuestions({
    required String subject,
    required String schoolType,
    required int grade,
    required int level,
  }) {
    if (subject.toLowerCase() != 'mathe') return '';

    String example;
    if (schoolType == 'Grundschule') {
      example =
          '{"question":"Anna hat 24 Äpfel. Sie gibt 9 davon ab. Wie viele hat sie noch?","options":["13","15","16","14"],"answer":"15","difficulty":"easy","topic":"Subtraktion"}';
    } else if (schoolType == 'Hauptschule' ||
        (schoolType == 'Gesamtschule' && level <= 4)) {
      example =
          '{"question":"Im Sale gibt es 15% Rabatt. Wie viel spart man bei einem Preis von 280 Euro?","options":["28 Euro","42 Euro","56 Euro","35 Euro"],"answer":"42 Euro","difficulty":"medium","topic":"Prozentrechnung im Alltag"}';
    } else if (schoolType == 'Gymnasium' ||
        (schoolType == 'Gesamtschule' && level > 8)) {
      example =
          '{"question":"Für welchen Wert von x gilt: 2(x - 3) + 4 = 3x - 5?","options":["x = 3","x = -3","x = 1","x = 5"],"answer":"x = 3","difficulty":"medium","topic":"Lineare Gleichungen"}';
    } else {
      example =
          '{"question":"Welche Zuordnung ist antiproportional?","options":["Mehr Arbeiter → weniger Tage","Mehr Äpfel → höherer Preis","Mehr Strecke → mehr Benzin","Mehr Monate → mehr Gehalt"],"answer":"Mehr Arbeiter → weniger Tage","difficulty":"medium","topic":"Zuordnungen"}';
    }
    return 'BEISPIEL:\n[$example]';
  }

  String _subjectDisplayName(String subject) {
    switch (subject.toLowerCase()) {
      case 'mathe':
        return 'Mathematik';
      case 'deutsch':
        return 'Deutsch';
      case 'englisch':
        return 'Englisch';
      case 'sachkunde':
        return 'Sachkunde / Heimat- und Sachunterricht';
      case 'biologie':
        return 'Biologie';
      case 'chemie':
        return 'Chemie';
      case 'physik':
        return 'Physik';
      case 'geschichte':
        return 'Geschichte';
      default:
        return subject;
    }
  }

  /// Gibt eine kommaseparierte Liste der tatsächlich verfügbaren Fächer zurück.
  /// Spiegelt exakt die Fächer aus subject_config.dart – nie mehr, nie weniger.
  static String _subjectsForGrade(int grade, String schoolType) {
    if (schoolType == 'Grundschule' || grade <= 4) {
      return 'Mathe, Deutsch, Englisch, Sachkunde';
    } else if (grade <= 10) {
      return 'Mathe, Deutsch, Englisch, Biologie, Chemie, Physik, Geschichte';
    } else {
      // Oberstufe Klasse 11–13
      return 'Mathe, Deutsch, Englisch, Chemie, Physik, Geschichte';
    }
  }

  // --------------------------------------------------------------------------
  // SICHERHEITS-FILTER (Tutor)
  // --------------------------------------------------------------------------

  bool _isAppropriateQuestion(String userMessage) {
    final lower = userMessage.toLowerCase();
    const inappropriate = [
      'gewalt',
      'waffe',
      'sex',
      'drogen',
      'schlagen',
      'töten',
      'selbstmord',
      'blut',
    ];
    return !inappropriate.any((word) => lower.contains(word));
  }

  bool _isNonSchoolQuestion(String userMessage) {
    final lower = userMessage.toLowerCase();
    const nonSchoolKeywords = [
      'rezept',
      'kochen',
      'backen',
      'nudeln',
      'pizza',
      'kuchen',
      'zubereiten',
      'essen machen',
      'gericht',
      'nudelsalat',
      'videospiel',
      'spiel spielen',
      'gaming',
      'zocken',
      'film',
      'serie',
      'netflix',
      'youtube',
      'tiktok',
      'instagram',
      'fernsehen',
      'streaming',
      'handy kaufen',
      'smartphone',
      'computer kaufen',
      'laptop',
      'spiel herunterladen',
      'app installieren',
      'fußball spielen',
      'freunde treffen',
      'party',
      'urlaub',
      'reise',
      'ausflug',
      'wie mache ich',
      'wie koche',
      'wie spiele',
      'wie baue ich',
      'wie bastle',
    ];

    if (nonSchoolKeywords.any((kw) => lower.contains(kw))) return true;

    if (lower.contains('wie') &&
        (lower.contains('mache') ||
            lower.contains('koche') ||
            lower.contains('baue') ||
            lower.contains('bastle'))) {
      const schoolRelated = [
        'hausaufgabe',
        'aufgabe',
        'rechnen',
        'lösen',
        'berechnen',
        'schreiben',
        'lernen',
        'verstehen',
        'erklären',
        'mathe',
        'deutsch',
        'englisch',
      ];
      if (!schoolRelated.any((word) => lower.contains(word))) return true;
    }

    return false;
  }

  static String _extractSubjectTag(String response) {
    final match = RegExp(r'\[FACH:([^\]]+)\]').firstMatch(response);
    if (match == null) return 'kein_schulfach';
    return match.group(1)?.trim() ?? 'kein_schulfach';
  }

  static bool _extractCorrectTag(String response) {
    // 1. Expliziter KI-Tag hat höchste Priorität
    final match = RegExp(
      r'\[KORREKT:(ja|nein)\]',
      caseSensitive: false,
    ).firstMatch(response);
    if (match != null) {
      return match.group(1)?.toLowerCase() != 'nein';
    }

    // 2. Lokale Textanalyse der KI-Antwort
    final lower = response.toLowerCase();

    // Eindeutig falsch
    final wrongPhrases = [
      'leider falsch',
      'leider nicht richtig',
      'leider nicht korrekt',
      'das ist falsch',
      'das ist leider',
      'nicht ganz richtig',
      'fast richtig',
      'nicht ganz',
      'nicht korrekt',
      'leider nicht',
      'das stimmt leider',
      'das ist nicht richtig',
      'das ist nicht korrekt',
      'das war nicht',
      'falsche antwort',
      'noch nicht ganz',
      'nicht die richtige',
      'nicht die richtige antwort',
      'not quite',
      'not correct',
      'that\'s not',
      'almost',
      'unfortunately',
      'wrong',
      'incorrect',
    ];
    if (wrongPhrases.any((p) => lower.contains(p))) return false;

    // Eindeutig richtig
    final correctPhrases = [
      'richtig',
      'korrekt',
      'genau',
      'super',
      'toll',
      'prima',
      'klasse',
      'bravo',
      'perfekt',
      'wunderbar',
      'sehr gut',
      'gut gemacht',
      'das stimmt',
      'das ist richtig',
      'correct',
      'exactly',
      'well done',
      'great',
      'perfect',
      'excellent',
      'that\'s right',
    ];
    if (correctPhrases.any((p) => lower.contains(p))) return true;

    // Kein klares Signal → kein XP (sicher ist sicher)
    return false;
  }

  static String _stripSubjectTag(String response) {
    // Entfernt FACH- und KORREKT-Tags sowie alle möglichen Label-Varianten.
    // Das Modell schreibt die Tags in verschiedenen Formaten, z.B.:
    //   [FACH:Mathematik]
    //   [KORREKT:ja]
    //   KORREKT: [ja]           <- mit Leerzeichen
    //   - Schulfach: [FACH:..] <- mit Praefix
    //   Erkanntes Schulfach: [FACH:..]
    return response
        // FACH mit optionalem Label-Praefix
        .replaceAll(
          RegExp(
            r'[-–]?\s*(?:Erkanntes\s+)?Schulfach:\s*\[FACH:[^\]]*\]',
            caseSensitive: false,
          ),
          '',
        )
        // Nackter FACH-Tag
        .replaceAll(RegExp(r'\s*\[FACH:[^\]]*\]', caseSensitive: false), '')
        // "KORREKT: [ja]" oder "KORREKT: [nein]" (mit Leerzeichen vor Klammer)
        .replaceAll(
          RegExp(r'\s*KORREKT:\s*\[[^\]]*\]', caseSensitive: false),
          '',
        )
        // Nackter [KORREKT:ja/nein]-Tag (ohne Leerzeichen)
        .replaceAll(RegExp(r'\s*\[KORREKT:[^\]]*\]', caseSensitive: false), '')
        // Leerzeilen aufraaeumen
        .replaceAll(RegExp(r'\n\s*\n\s*\n'), '\n\n')
        .trim();
  }
}

final vertexAIServiceProvider = Provider<VertexAIService>((ref) {
  return VertexAIService();
});
