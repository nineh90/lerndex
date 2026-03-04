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

/// Antwort des KI-Tutors mit extrahiertem Schulfach.
class TutorResponse {
  final String text;
  final String subject; // z.B. 'Mathematik' oder 'kein_schulfach'

  const TutorResponse({required this.text, required this.subject});

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
    print('🚀 Vertex AI Tutor-Modell wird initialisiert...');
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
    print('✅ Tutor-Modell initialisiert');
  }

  Future<void> _ensureTaskInitialized() async {
    if (_taskInitialized) return;
    print('🚀 Vertex AI Task-Modell wird initialisiert...');
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
    print('✅ Task-Modell initialisiert');
  }

  Future<void> _ensureQuizInitialized() async {
    if (_quizInitialized) return;
    print('🚀 Vertex AI Quiz-Modell wird initialisiert...');
    _quizModel = FirebaseAI.vertexAI().generativeModel(
      model: 'gemini-2.0-flash',
      generationConfig: GenerationConfig(
        temperature: 0.75,
        maxOutputTokens: 4096,
        topP: 0.92,
      ),
    );
    _quizInitialized = true;
    print('✅ Quiz-Modell initialisiert');
  }

  // --------------------------------------------------------------------------
  // 1. KI-TUTOR FÜR KINDER
  // --------------------------------------------------------------------------

  Future<TutorResponse> sendTutorMessage({
    required ChildModel child,
    required String userMessage,
    required List<ChatMessage> conversationHistory,
    bool subjectAlreadyDetermined = false,
  }) async {
    await _ensureTutorInitialized();

    // Sicherheitschecks
    if (!_isAppropriateQuestion(userMessage)) {
      return TutorResponse(
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
      return TutorResponse(
        text:
            'Deine Frage ist etwas zu lang. Kannst du sie kürzer formulieren? 😊',
        subject: 'kein_schulfach',
      );
    }

    try {
      final systemPrompt = _buildTutorSystemPrompt(
        child,
        subjectAlreadyDetermined: subjectAlreadyDetermined,
      );

      final history = <Content>[Content.text(systemPrompt)];

      final recentMessages = conversationHistory.length > 10
          ? conversationHistory.sublist(conversationHistory.length - 10)
          : conversationHistory;

      for (final msg in recentMessages) {
        if (msg.isLoading) continue;
        history.add(
          Content(msg.isUser ? 'user' : 'model', [TextPart(msg.text)]),
        );
      }

      final chat = _tutorModel!.startChat(history: history);
      final response = await chat.sendMessage(Content.text(userMessage));
      final text = response.text;

      if (text == null || text.isEmpty) {
        return TutorResponse(
          text:
              'Hmm, ich bin mir bei dieser Frage nicht sicher. Kannst du sie anders formulieren? 🤔',
          subject: 'kein_schulfach',
        );
      }

      final subject = _extractSubjectTag(text);
      final cleanText = _stripSubjectTag(text);
      return TutorResponse(text: cleanText, subject: subject);
    } catch (e) {
      print('❌ Tutor-Fehler: $e');
      return TutorResponse(
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
  }) async {
    await _ensureTaskInitialized();

    try {
      print(
        '📸 Analysiere Schulaufgabe für ${child.name} '
        '(${child.schoolType}, Kl. ${child.grade}, Lv. ${child.level}, '
        '${subject.displayName})...',
      );

      // Bild hochladen
      String? imageUrl;
      try {
        imageUrl = await _uploadImage(imageFile, userId, child.id, subject);
      } catch (e) {
        print('⚠️ Bild-Upload fehlgeschlagen (wird ignoriert): $e');
      }

      final imageBytes = await imageFile.readAsBytes();
      final prompt = _buildTaskGeneratorPrompt(
        child: child,
        subject: subject,
        numberOfTasks: numberOfTasks,
      );

      final content = [
        Content.multi([
          TextPart(prompt),
          InlineDataPart('image/jpeg', imageBytes),
        ]),
      ];

      print('🤖 Sende Anfrage an Vertex AI...');
      final response = await _taskGeneratorModel!.generateContent(content);
      final text = response.text;

      if (text == null || text.isEmpty) {
        throw Exception('KI hat keine Antwort generiert');
      }

      print('📝 Antwort erhalten, parse JSON...');
      final questions = _parseGeneratedQuestions(text);

      if (questions.isEmpty) {
        throw Exception('Keine validen Aufgaben generiert');
      }

      print('✅ ${questions.length} von $numberOfTasks Aufgaben generiert!');
      return GeneratedTaskResult(
        success: true,
        questions: questions,
        imageUrl: imageUrl,
      );
    } catch (e) {
      print('❌ Fehler bei Aufgabengenerierung: $e');
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

      print(
        '📚 Generiere $count Quiz-Fragen für ${child.name} '
        '(${child.schoolType}, Kl. ${child.grade}, Lv. ${child.level}) '
        'im Fach $subject',
      );

      final response = await _quizModel!.generateContent([
        Content.text(prompt),
      ]);
      final text = response.text ?? '';

      return _parseQuizResponse(text, child.grade);
    } catch (e) {
      print('❌ Quiz-Generierung fehlgeschlagen: $e');
      return [];
    }
  }

  // --------------------------------------------------------------------------
  // PROMPTS
  // --------------------------------------------------------------------------

  String _buildTutorSystemPrompt(
    ChildModel child, {
    bool subjectAlreadyDetermined = false,
  }) {
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
1. Beantworte NUR Fragen zu Schulfächern (Mathe, Deutsch, Englisch, Sachkunde, Naturwissenschaften usw.)
2. Erkläre Konzepte Schritt für Schritt und altersgerecht
3. Verwende Beispiele, die für Klasse ${child.grade} passen
4. Sei motivierend, ermutigend und geduldig
5. Leite ${child.name} sanft zurück zum Lernen bei Nicht-Schul-Themen

🚫 ABSOLUTE GRENZEN:
- Beantworte KEINE Fragen zu: Kochen, Rezepten, Videospielen, Filmen, Serien, Hobbys, Freizeit
- Bei JEDER Nicht-Schul-Frage: Lehne HÖFLICH ab und leite zurück zu Schulfächern
- Keine Gewalt, unangemessene Inhalte oder gefährliche Themen
- Bei Hausaufgaben: Hilf beim Verstehen, gib nicht einfach die fertige Lösung

💬 KOMMUNIKATIONSSTIL:
- Einfache, kindgerechte Sprache (passend für ${child.age} Jahre)
- Kurze, klare Antworten (max. 3-4 Sätze)
- Gelegentlich passende Emojis
- Lobe Fortschritte, ermutige zum Weiterlernen
- Mathematische Formeln IMMER in LaTeX: \$\\frac{1}{2}\$, \$\\sqrt{4}\$, \$x^2\$

${subjectAlreadyDetermined ? '' : '''
PFLICHT NUR BEI DIESER ERSTEN ANTWORT:
Füge als ALLERLETZTE Zeile exakt dieses Tag an (wird automatisch entfernt):
- Erkanntes Schulfach: [FACH:Mathematik] / [FACH:Deutsch] / [FACH:Englisch] / [FACH:Biologie] / [FACH:Chemie] / [FACH:Physik] / [FACH:Geschichte] / [FACH:Geographie] / [FACH:Sachkunde] / [FACH:Informatik] / [FACH:Latein] / [FACH:Französisch] / [FACH:Spanisch] / [FACH:Ethik] / [FACH:Philosophie] / [FACH:Musik] / [FACH:Kunst] / [FACH:Sport] / [FACH:Politik]
- Kein Schulfach / unklar / Smalltalk: [FACH:kein_schulfach]
'''}
''';
  }

  String _buildTaskGeneratorPrompt({
    required ChildModel child,
    required Subject subject,
    required int numberOfTasks,
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

Antworte NUR mit einem JSON-Array, kein Text oder Markdown davor/danach:
[
  {
    "question": "Fragetext",
    "options": ["A", "B", "C", "D"],
    "answer": "Richtige Option exakt wie oben",
    "difficulty": "easy|medium|hard",
    "topic": "Thema"
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
            print('✅ ${questions.length} Aufgaben aus JSON-Array geparst');
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

      print('✅ ${questions.length} Aufgaben aus Einzel-Objekten geparst');
    } catch (e) {
      print('❌ JSON Parse Fehler (generateTasks): $e');
      print('Text war: ${text.substring(0, text.length.clamp(0, 200))}...');
    }

    return questions;
  }

  GeneratedQuestion? _parseGeneratedQuestionFromMap(Map<String, dynamic> json) {
    try {
      final questionText = json['question']?.toString() ?? '';
      if (questionText.isEmpty) return null;

      final rawOptions = json['options'];
      if (rawOptions == null || rawOptions is! List || rawOptions.length != 4)
        return null;

      final options = List<String>.from(rawOptions);
      final correctAnswer = json['correctAnswer']?.toString() ?? '';
      if (correctAnswer.isEmpty || !options.contains(correctAnswer)) {
        print('⚠️ Richtige Antwort nicht in Optionen: "$correctAnswer"');
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
      print('⚠️ Fehler beim Parsen einer Aufgabe: $e');
      return null;
    }
  }

  /// Parst Quiz-Fragen (Question-Format für Schüler-Dashboard)
  List<Question> _parseQuizResponse(String rawText, int grade) {
    try {
      String cleaned = _cleanJson(rawText);

      final startIndex = cleaned.indexOf('[');
      final endIndex = cleaned.lastIndexOf(']');
      if (startIndex == -1 || endIndex == -1) {
        print('⚠️ Kein JSON-Array in Quiz-Antwort gefunden');
        return [];
      }

      final jsonStr = cleaned.substring(startIndex, endIndex + 1);
      final List<dynamic> jsonList = jsonDecode(jsonStr);

      final questions = <Question>[];
      final seenQuestions = <String>{};

      for (final item in jsonList) {
        try {
          final q = _parseQuizQuestionFromMap(
            item as Map<String, dynamic>,
            grade,
          );
          if (q == null) continue;

          final normalized = q.question.toLowerCase().trim();
          if (seenQuestions.contains(normalized)) continue;
          seenQuestions.add(normalized);
          questions.add(q);
        } catch (e) {
          print('⚠️ Quiz-Frage übersprungen: $e');
        }
      }

      print('✅ ${questions.length} Quiz-Fragen geparst');
      return questions;
    } catch (e) {
      print('❌ JSON-Parsing (Quiz) fehlgeschlagen: $e');
      return [];
    }
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
    if (cleaned.startsWith('```json'))
      cleaned = cleaned.substring(7);
    else if (cleaned.startsWith('```'))
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
    print('✅ Bild hochgeladen: $path');
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

  static String _stripSubjectTag(String response) {
    // Entfernt z.B. "- Erkanntes Schulfach: [FACH:Mathematik]" komplett
    return response
        .replaceAll(
          RegExp(r'[-–]?\s*Erkanntes Schulfach:\s*\[FACH:[^\]]+\]'),
          '',
        )
        .replaceAll(RegExp(r'\s*\[FACH:[^\]]+\]'), '')
        .trim();
  }
}

// ============================================================================
// RIVERPOD PROVIDER
// ============================================================================

/// Singleton VertexAIService — wird von Tutor, Task-Generator und Quiz genutzt
final vertexAIServiceProvider = Provider<VertexAIService>((ref) {
  return VertexAIService();
});
