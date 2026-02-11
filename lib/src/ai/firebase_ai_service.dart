import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:firebase_vertexai/firebase_vertexai.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../features/auth/domain/child_model.dart';
import '../features/tutor/domain/chat_message.dart';

/// 🤖 FIREBASE AI SERVICE
/// Verwendet Vertex AI über Firebase
/// - KI-Tutor für Kinder
/// - Aufgabengenerator aus Fotos für Eltern

class FirebaseAIService {
  GenerativeModel? _tutorModel;
  GenerativeModel? _taskGeneratorModel;
  bool _isInitialized = false;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Initialisiert beide AI-Modelle
  Future<void> initialize() async {
    // ✅ Verhindere mehrfache Initialisierung
    if (_isInitialized) {
      print('ℹ️ Firebase AI ist bereits initialisiert');
      return;
    }

    print('🚀 Firebase AI wird initialisiert...');

    try {
      // Tutor-Modell (für Kinder)
      _tutorModel = FirebaseVertexAI.instance.generativeModel(
        model: 'gemini-2.5-flash',
        generationConfig: GenerationConfig(
          temperature: 0.7,
          maxOutputTokens: 2048,
          topP: 0.9,
          topK: 40,
        ),
        safetySettings: [
          SafetySetting(HarmCategory.harassment, HarmBlockThreshold.high, HarmBlockMethod.severity),
          SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.high, HarmBlockMethod.severity),
          SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.high, HarmBlockMethod.severity),
          SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.high, HarmBlockMethod.severity),
        ],
      );

      // Task-Generator-Modell (für Eltern - Vision API)
      _taskGeneratorModel = FirebaseVertexAI.instance.generativeModel(
        model: 'gemini-2.5-flash',
        generationConfig: GenerationConfig(
          temperature: 0.8,
          maxOutputTokens: 2000,
          topP: 0.95,
        ),
      );

      _isInitialized = true;
      print('✅ Firebase AI initialisiert!');
    } catch (e) {
      print('❌ Fehler bei AI-Initialisierung: $e');
      rethrow;
    }
  }

  // ========================================================================
  // KI-TUTOR FÜR KINDER
  // ========================================================================

  /// Sendet Nachricht an KI-Tutor und bekommt Antwort
  Future<String> sendTutorMessage({
    required ChildModel child,
    required String userMessage,
    required List<ChatMessage> conversationHistory,
  }) async {
    try {
      // Sicherheitscheck
      if (!_isAppropriateQuestion(userMessage)) {
        return _getInappropriateQuestionMessage();
      }

      // ✅ NEUER CHECK: Nicht-Schul-Themen erkennen und SOFORT ablehnen
      if (_isNonSchoolQuestion(userMessage)) {
        return _getNonSchoolQuestionMessage(child.name);
      }

      // Längencheck
      if (userMessage.length > 500) {
        return 'Deine Frage ist etwas zu lang. Kannst du sie kürzer formulieren? 😊';
      }

      // System-Prompt für das Kind
      final systemPrompt = _getTutorSystemPrompt(child);

      // Chat-History aufbauen
      final history = <Content>[];

      // ✅ KRITISCH: System-Prompt IMMER als erste Nachricht
      history.add(Content.text(systemPrompt));

      // Letzte 10 Nachrichten für Kontext
      final recentMessages = conversationHistory.length > 10
          ? conversationHistory.sublist(conversationHistory.length - 10)
          : conversationHistory;

      for (var message in recentMessages) {
        if (message.isLoading) continue;

        history.add(Content(
          message.isUser ? 'user' : 'model',
          [TextPart(message.text)],
        ));
      }

      // Chat starten und Nachricht senden
      final chat = _tutorModel!.startChat(history: history);
      final response = await chat.sendMessage(Content.text(userMessage));

      final text = response.text;

      if (text == null || text.isEmpty) {
        return 'Hmm, ich bin mir bei dieser Frage nicht sicher. Kannst du sie anders formulieren? 🤔';
      }

      return text;

    } catch (e) {
      print('❌ Tutor-Fehler: $e');
      return 'Ups, da ist etwas schiefgelaufen. Versuch es nochmal! 😅';
    }
  }

  /// System-Prompt für KI-Tutor (kindgerecht) - VERSTÄRKT
  String _getTutorSystemPrompt(ChildModel child) {
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
1. Beantworte NUR Fragen zu Schulfächern (Mathe, Deutsch, Englisch, Sachkunde, Naturwissenschaften, etc.)
2. Erkläre Konzepte Schritt für Schritt und altersgerecht
3. Verwende Beispiele, die für Klasse ${child.grade} passen
4. Sei motivierend, ermutigend und geduldig
5. Leite ${child.name} sanft zurück zum Lernen bei Nicht-Schul-Themen

🚫 ABSOLUTE GRENZEN (WICHTIG - STRIKT EINHALTEN!):
- Beantworte KEINE Fragen zu: Kochen, Rezepten, Videospielen, Filmen, Serien, Hobbys, Freizeit
- Beantworte KEINE "Wie mache ich..."-Fragen zu Alltagsthemen (z.B. "Wie mache ich Nudeln?")
- Bei JEDER Nicht-Schul-Frage: Lehne HÖFLICH ab und leite zurück zu Schulfächern
- Keine Gewalt, unangemessene Inhalte oder gefährliche Themen
- Bei Hausaufgaben: Hilf beim Verstehen, aber gib nicht die komplette Lösung vor

📖 BEISPIELE FÜR NICHT-SCHUL-FRAGEN (IMMER ABLEHNEN!):
❌ "Wie koche ich Nudelsalat?" → "Das ist keine Schulfrage. Frag mich lieber zu Mathe, Deutsch oder Englisch!"
❌ "Wie spiele ich Minecraft?" → "Das gehört nicht zum Lernen. Hast du eine Frage zu einem Schulfach?"
❌ "Wie baue ich ein Baumhaus?" → "Das ist eine Freizeitfrage. Ich helfe dir bei Schulfächern!"

✅ BEISPIELE FÜR SCHUL-FRAGEN (BEANTWORTEN!):
✅ "Wie rechne ich 15 + 27?" → Ausführlich erklären!
✅ "Was ist ein Adjektiv?" → Altersgerecht erklären!
✅ "Wie schreibe ich eine Bildergeschichte?" → Schritte zeigen!

💬 KOMMUNIKATIONSSTIL:
- Verwende einfache, kindgerechte Sprache (passend für ${child.age} Jahre)
- Kurze, klare Antworten (max. 3-4 Sätze pro Erklärung)
- Nutze gelegentlich passende Emojis (nicht übertreiben!)
- Lobe Fortschritte und ermutige zum Weiterlernen
- Stelle Rückfragen, um ${child.name} zum Nachdenken anzuregen

🎓 LERNPHILOSOPHIE:
- Verstehen ist wichtiger als auswendig lernen
- Fehler sind Lernchancen
- Jede SCHUL-Frage ist eine gute Frage
- Selbstständiges Denken fördern

WICHTIG: Deine EINZIGE Aufgabe ist es, bei SCHULFÄCHERN zu helfen. Alle anderen Themen lehnst du freundlich ab!
''';
  }

  /// Begrüßungsnachricht für KI-Tutor
  String getTutorWelcomeMessage(ChildModel child) {
    return 'Hallo ${child.name}! 👋 Ich bin **Lerndex**, dein persönlicher Lernbegleiter! 🎓 Ich helfe dir bei allen Fragen zu Mathe, Deutsch, Englisch und anderen Schulfächern. Was möchtest du heute lernen? 📚✨';
  }

  // ========================================================================
  // AUFGABENGENERATOR AUS FOTOS (FÜR ELTERN)
  // ========================================================================

  /// Analysiert Foto von Schulaufgabe und generiert personalisierte Übungen
  Future<GeneratedTaskResult> generateTasksFromImage({
    required File imageFile,
    required ChildModel child,
    required String userId,
    int numberOfTasks = 5,
  }) async {
    try {
      print('📸 Analysiere Schulaufgabe für ${child.name}...');

      // 1. Bild hochladen zu Firebase Storage
      final imageUrl = await _uploadImage(imageFile, userId, child.id);

      // 2. Bild als Bytes lesen
      final Uint8List imageBytes = await imageFile.readAsBytes();

      // 3. System-Prompt für Aufgabengenerator
      final systemPrompt = _getTaskGeneratorSystemPrompt(child);

      // 4. Vision API: Bild + Prompt
      final prompt = '''
$systemPrompt

AUFGABE:
Analysiere das Foto der Schulaufgabe und erstelle $numberOfTasks ähnliche Übungsaufgaben.

ANFORDERUNGEN:
1. Analysiere das Thema und Schwierigkeitsniveau
2. Erstelle $numberOfTasks neue, ähnliche Aufgaben
3. Passe Schwierigkeit an Klasse ${child.grade} an
4. Gib bei jeder Aufgabe die Musterlösung an

FORMAT (WICHTIG - HALTE DICH EXAKT DARAN):
Antworte NUR mit einem JSON-Array in diesem Format:

[
  {
    "question": "Die Aufgabenstellung",
    "solution": "Die vollständige Musterlösung",
    "difficulty": "easy/medium/hard",
    "topic": "Das Thema (z.B. 'Addition', 'Rechtschreibung')"
  },
  ...
]

BEISPIEL:
[
  {
    "question": "Berechne: 15 + 27",
    "solution": "15 + 27 = 42",
    "difficulty": "medium",
    "topic": "Addition"
  }
]

WICHTIG: Antworte NUR mit dem JSON-Array, ohne Markdown-Formatierung oder Text davor/danach!
''';

      // 5. API-Call mit Vision
      final response = await _taskGeneratorModel!.generateContent([
        Content.multi([
          TextPart(prompt),
          InlineDataPart('image/jpeg', imageBytes),
        ])
      ]);

      final text = response.text;

      if (text == null || text.isEmpty) {
        throw Exception('Keine Antwort von AI erhalten');
      }

      print('📝 AI-Antwort erhalten');

      // 6. Parse JSON
      final tasks = _parseGeneratedTasks(text);

      if (tasks.isEmpty) {
        throw Exception('Keine Aufgaben generiert');
      }

      print('✅ ${tasks.length} Aufgaben generiert');

      // 7. Speichere Aufgaben in Firestore
      await _saveGeneratedTasks(
        userId: userId,
        childId: child.id,
        tasks: tasks,
        originalImageUrl: imageUrl,
      );

      return GeneratedTaskResult(
        success: true,
        tasks: tasks,
        imageUrl: imageUrl,
      );

    } catch (e, stackTrace) {
      print('❌ Fehler beim Generieren: $e');
      print('Stack: $stackTrace');

      return GeneratedTaskResult(
        success: false,
        tasks: [],
        errorMessage: e.toString(),
      );
    }
  }

  /// System-Prompt für Aufgabengenerator
  String _getTaskGeneratorSystemPrompt(ChildModel child) {
    return '''
Du bist ein KI-Assistent für Eltern, der aus Fotos von Schulaufgaben personalisierte Übungen erstellt.

SCHÜLER-INFORMATIONEN:
- Name: ${child.name}
- Alter: ${child.age} Jahre
- Schulform: ${child.schoolType}
- Klassenstufe: ${child.grade}

DEINE AUFGABE:
1. Analysiere das Foto der Original-Schulaufgabe
2. Erkenne Thema, Fach und Schwierigkeitsniveau
3. Erstelle NEUE, ähnliche Übungsaufgaben (keine Kopie!)
4. Passe Schwierigkeit an Klasse ${child.grade} an
5. Gib bei jeder Aufgabe die vollständige Musterlösung an

WICHTIG:
- Die Aufgaben sollen ähnlich, aber NICHT identisch zur Vorlage sein
- Variiere Zahlen, Wörter oder Kontext
- Achte auf altersgerechte Formulierung
- Stelle sicher, dass Aufgaben lösbar und sinnvoll sind
''';
  }

  /// Lädt Bild zu Firebase Storage hoch
  Future<String> _uploadImage(File imageFile, String userId, String childId) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = 'task_images/$userId/$childId/$timestamp.jpg';

    final ref = _storage.ref().child(path);
    await ref.putFile(imageFile);

    return await ref.getDownloadURL();
  }

  /// Parst generierte Aufgaben aus AI-Response
  List<GeneratedTask> _parseGeneratedTasks(String jsonText) {
    try {
      // Entferne Markdown-Formatierung falls vorhanden
      String cleaned = jsonText.trim();

      // Entferne ```json am Anfang
      if (cleaned.startsWith('```json')) {
        cleaned = cleaned.substring(7);
      } else if (cleaned.startsWith('```')) {
        cleaned = cleaned.substring(3);
      }

      // Entferne ``` am Ende
      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3);
      }

      cleaned = cleaned.trim();

      // Parse JSON
      final List<dynamic> jsonList = jsonDecode(cleaned);

      return jsonList.map((json) => GeneratedTask.fromJson(json)).toList();

    } catch (e) {
      print('❌ JSON Parse Fehler: $e');
      print('Text war: $jsonText');
      return [];
    }
  }

  /// Speichert generierte Aufgaben in Firestore
  Future<void> _saveGeneratedTasks({
    required String userId,
    required String childId,
    required List<GeneratedTask> tasks,
    required String originalImageUrl,
  }) async {
    final batch = _firestore.batch();

    final collectionRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('generated_tasks');

    // Batch-Dokument für alle Aufgaben
    final batchDoc = collectionRef.doc();

    batch.set(batchDoc, {
      'createdAt': FieldValue.serverTimestamp(),
      'imageUrl': originalImageUrl,
      'taskCount': tasks.length,
      'status': 'pending', // pending, used
    });

    // Einzelne Aufgaben als Sub-Collection
    for (var i = 0; i < tasks.length; i++) {
      final taskDoc = batchDoc.collection('tasks').doc();
      batch.set(taskDoc, {
        ...tasks[i].toFirestore(),
        'index': i,
      });
    }

    await batch.commit();
  }

  // ========================================================================
  // HILFSMETHODEN
  // ========================================================================

  /// Sicherheitsfilter für Kinderfragen
  bool _isAppropriateQuestion(String userMessage) {
    final lower = userMessage.toLowerCase();

    // Gefährliche/unangemessene Inhalte
    final inappropriate = [
      'gewalt', 'waffe', 'sex', 'drogen',
      'schlagen', 'töten', 'selbstmord', 'blut',
    ];

    // Prüfe auf unangemessene Inhalte
    if (inappropriate.any((word) => lower.contains(word))) {
      return false;
    }

    return true;
  }

  /// ✅ NEU: Erkennt Nicht-Schul-Themen (Alltagsfragen)
  bool _isNonSchoolQuestion(String userMessage) {
    final lower = userMessage.toLowerCase();

    // Typische Nicht-Schul-Themen Keywords
    final nonSchoolKeywords = [
      // Kochen & Essen
      'rezept', 'kochen', 'backen', 'nudeln', 'pizza', 'kuchen',
      'zubereiten', 'essen machen', 'gericht', 'nudelsalat',

      // Unterhaltung & Medien
      'videospiel', 'spiel spielen', 'gaming', 'zocken',
      'film', 'serie', 'netflix', 'youtube', 'tiktok', 'instagram',
      'fernsehen', 'streaming',

      // Technologie (Alltag)
      'handy kaufen', 'smartphone', 'computer kaufen', 'laptop',
      'spiel herunterladen', 'app installieren',

      // Hobby & Freizeit
      'fußball spielen', 'freunde treffen', 'party',
      'urlaub', 'reise', 'ausflug',

      // Alltägliche "Wie-geht"-Fragen
      'wie mache ich', 'wie koche', 'wie spiele',
      'wie baue ich', 'wie bastle',
    ];

    // Prüfe Keywords
    for (var keyword in nonSchoolKeywords) {
      if (lower.contains(keyword)) {
        return true;
      }
    }

    // Zusätzliche Heuristik: Fragen nach praktischen Tätigkeiten
    if (lower.contains('wie') &&
        (lower.contains('mache') || lower.contains('koche') ||
            lower.contains('baue') || lower.contains('bastle'))) {
      // Aber: Schulbezogene "Wie mache ich"-Fragen erlauben
      final schoolRelated = [
        'hausaufgabe', 'aufgabe', 'rechnen', 'lösen',
        'berechnen', 'schreiben', 'lernen', 'verstehen',
        'erklären', 'mathe', 'deutsch', 'englisch',
      ];

      bool isSchoolRelated = schoolRelated.any((word) => lower.contains(word));

      if (!isSchoolRelated) {
        return true; // Nicht-Schul-Thema
      }
    }

    return false;
  }

  String _getInappropriateQuestionMessage() {
    return 'Diese Frage kann ich leider nicht beantworten. Ich bin Lerndex und helfe dir nur beim Lernen! 📚 Hast du eine Frage zu Mathe, Deutsch, Englisch oder anderen Schulfächern? 🎓';
  }

  /// Nachricht bei Nicht-Schul-Frage
  String _getNonSchoolQuestionMessage(String childName) {
    return 'Das ist eine interessante Frage, $childName! Aber ich bin Lerndex, dein Lernbegleiter, und helfe dir nur bei Schulfächern. 📚 Hast du vielleicht eine Frage zu Mathe, Deutsch, Englisch oder einem anderen Schulfach? 🎓';
  }
}

// ============================================================================
// DATENMODELLE
// ============================================================================

/// Ergebnis der Aufgabengenerierung
class GeneratedTaskResult {
  final bool success;
  final List<GeneratedTask> tasks;
  final String? imageUrl;
  final String? errorMessage;

  GeneratedTaskResult({
    required this.success,
    required this.tasks,
    this.imageUrl,
    this.errorMessage,
  });
}

/// Einzelne generierte Aufgabe
class GeneratedTask {
  final String question;
  final String solution;
  final String difficulty; // easy, medium, hard
  final String topic;

  GeneratedTask({
    required this.question,
    required this.solution,
    required this.difficulty,
    required this.topic,
  });

  factory GeneratedTask.fromJson(Map<String, dynamic> json) {
    return GeneratedTask(
      question: json['question'] ?? '',
      solution: json['solution'] ?? '',
      difficulty: json['difficulty'] ?? 'medium',
      topic: json['topic'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'question': question,
      'solution': solution,
      'difficulty': difficulty,
      'topic': topic,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}