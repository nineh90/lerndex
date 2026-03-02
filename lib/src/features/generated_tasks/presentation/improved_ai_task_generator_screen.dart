import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex/src/features/generated_tasks/data/generated_task_models.dart';
import 'package:lerndex/src/features/quiz/data/curriculum_data.dart';
import '../domain/generated_task_result.dart';
import '../../auth/domain/child_model.dart';

/// 🤖 VERBESSERTER FIREBASE AI SERVICE v2
///
/// Generiert Multiple-Choice-Aufgaben aus hochgeladenen Fotos.
///
/// Verbesserungen v2:
///   ✅ Gemini 3 Flash Preview für bessere Bilderkennung + Reasoning
///   ✅ Curriculum-verankerte Prompts mit Lehrplaninhalten
///   ✅ Schulform-Differenzierung in den fachspezifischen Kontexten
///   ✅ IQB-Kompetenzstufenmapping für Level-abhängige Schwierigkeit

class ImprovedFirebaseAIService {
  GenerativeModel? _taskGeneratorModel;
  bool _isInitialized = false;

  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Initialisiert das AI-Modell
  Future<void> initialize() async {
    if (_isInitialized) {
      print('ℹ️ Firebase AI ist bereits initialisiert');
      return;
    }

    print('🚀 Firebase AI wird initialisiert (Gemini 3 Flash)...');

    try {
      _taskGeneratorModel = FirebaseAI.googleAI().generativeModel(
        model: 'gemini-3-flash-preview',
        generationConfig: GenerationConfig(
          temperature: 0.7,
          maxOutputTokens: 4096,
          topP: 0.95,
          responseMimeType: 'application/json',
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
  // AUFGABENGENERIERUNG AUS FOTOS
  // ========================================================================

  /// Analysiert Foto und generiert Multiple-Choice-Aufgaben
  Future<GeneratedTaskResult> generateTasksFromImage({
    required File imageFile,
    required ChildModel child,
    required String userId,
    required Subject subject,
    int numberOfTasks = 5,
  }) async {
    try {
      if (!_isInitialized) await initialize();

      print(
        '📸 Analysiere Schulaufgabe für ${child.name} '
        '(${child.schoolType}, Kl. ${child.grade}, Lv. ${child.level}, '
        '${subject.displayName})...',
      );

      // 1. Bild hochladen zu Firebase Storage (optional)
      String? imageUrl;
      try {
        imageUrl = await _uploadImage(imageFile, userId, child.id, subject);
      } catch (uploadError) {
        print('⚠️ Bild-Upload fehlgeschlagen (wird ignoriert): $uploadError');
      }

      // 2. Bild als Bytes lesen
      final Uint8List imageBytes = await imageFile.readAsBytes();

      // 3. Curriculum-verankerter Prompt
      final systemPrompt = _getTaskGeneratorPrompt(
        child: child,
        subject: subject,
        numberOfTasks: numberOfTasks,
      );

      // 4. Vision API: Bild + Prompt
      final content = [
        Content.multi([
          TextPart(systemPrompt),
          InlineDataPart('image/jpeg', imageBytes),
        ]),
      ];

      print('🤖 Sende Anfrage an Gemini 3 Flash...');
      final response = await _taskGeneratorModel!.generateContent(content);
      final text = response.text;

      if (text == null || text.isEmpty) {
        throw Exception('KI hat keine Antwort generiert');
      }

      print('📝 Antwort erhalten, parse JSON...');

      // 5. Parse JSON zu GeneratedQuestion-Objekten
      final questions = _parseGeneratedQuestions(text);

      if (questions.isEmpty) {
        throw Exception('Keine validen Aufgaben generiert');
      }

      print('✅ ${questions.length} Aufgaben erfolgreich generiert!');

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

  // ========================================================================
  // PROMPT MIT CURRICULUM-KONTEXT
  // ========================================================================

  /// System-Prompt für Aufgabengenerierung (fachspezifisch + curriculum-verankert)
  String _getTaskGeneratorPrompt({
    required ChildModel child,
    required Subject subject,
    required int numberOfTasks,
  }) {
    // Curriculum-Kontext aus der neuen Datenbank
    final curriculumContext = CurriculumData.buildCurriculumContext(
      schoolType: child.schoolType,
      grade: child.grade,
      subject: subject.value,
      level: child.level,
    );

    // Schwierigkeitsprofil
    final profile = CurriculumData.getDifficultyProfile(
      schoolType: child.schoolType,
      level: child.level,
    );

    // Fach-spezifischer Zusatzkontext
    final subjectContext = _getSubjectContext(subject, child);

    return '''
Du bist ein pädagogischer Experte, der personalisierte Übungsaufgaben für Schüler erstellt.
Deine Aufgaben orientieren sich an den offiziellen KMK-Bildungsstandards und Landeslehrplänen.

═══════════════════════════════════════════════════
SCHÜLER-PROFIL
═══════════════════════════════════════════════════
- Name: ${child.name}
- Alter: ${child.age} Jahre
- Klassenstufe: ${child.grade}
- Schulform: ${child.schoolType}
- Level: ${child.level}
- Fach: ${subject.displayName}

═══════════════════════════════════════════════════
LEHRPLAN-KONTEXT
═══════════════════════════════════════════════════
$curriculumContext

$subjectContext

═══════════════════════════════════════════════════
AUFGABE
═══════════════════════════════════════════════════
Analysiere das hochgeladene Foto einer Schulaufgabe und erstelle $numberOfTasks ähnliche 
Multiple-Choice-Übungsaufgaben.

SCHWIERIGKEITSVERTEILUNG (basierend auf Kompetenzstufe):
- ca. ${(profile.easyRatio * numberOfTasks).round()}× leicht (AFB I: Reproduzieren)
- ca. ${(profile.mediumRatio * numberOfTasks).round()}× mittel (AFB II: Transfer)
- ca. ${(profile.hardRatio * numberOfTasks).round()}× schwer (AFB III: Reflexion)

ANFORDERUNGEN:
1. Analysiere Thema, Schwierigkeitsniveau und Stil der Vorlage
2. Erstelle $numberOfTasks neue, ähnliche Aufgaben (NICHT identisch!)
3. Jede Aufgabe muss EXAKT 4 Antwortmöglichkeiten haben
4. GENAU 1 Antwort muss korrekt sein, 3 müssen plausible Ablenkungen sein
5. Die Schwierigkeit MUSS dem Niveau ${child.schoolType} Klasse ${child.grade} entsprechen
6. Gib bei jeder Aufgabe eine kurze Lösungserklärung an

${child.schoolType == 'Hauptschule' || (child.schoolType == 'Gesamtschule' && child.level <= 4) ? '''
⚠️ WICHTIG — HAUPTSCHULE/G-KURS-NIVEAU:
- Aufgaben mit Alltagsbezug, keine Abstraktion
- Einfache, klare Formulierungen
- Keine formalen Beweise oder komplexe Fachsprache
''' : ''}

MULTIPLE-CHOICE-REGELN:
- Falsche Antworten müssen plausibel klingen (typische Schülerfehler!)
- Alle 4 Optionen sollten ähnlich lang sein
- Vermeide "alle oben genannten" oder "keine der oben genannten"
- Die richtige Antwort darf NICHT immer an Position 1 stehen

FORMAT — reines JSON-Array:
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

  /// Fach-spezifischer Kontext — jetzt mit schulformspezifischen Themen
  String _getSubjectContext(Subject subject, ChildModel child) {
    final topics = CurriculumData.getTopics(
      schoolType: child.schoolType,
      grade: child.grade,
      subject: subject.value,
      level: child.level,
    );

    if (topics.isEmpty) return _getLegacySubjectContext(subject);

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

  /// Fallback für Fächer ohne spezifische Curriculum-Daten (aus v1 übernommen)
  String _getLegacySubjectContext(Subject subject) {
    switch (subject) {
      case Subject.mathe:
        return 'FACH: MATHEMATIK — Achte auf mathematische Korrektheit und eindeutige Lösungswege!';
      case Subject.deutsch:
        return 'FACH: DEUTSCH — Achte auf sprachliche Korrektheit und altersgerechte Formulierungen!';
      case Subject.englisch:
        return 'FACH: ENGLISCH — Achte auf grammatikalische Korrektheit! Verwende konsistent British English!';
      case Subject.sachkunde:
        return 'FACH: SACHKUNDE — Achte auf wissenschaftliche Korrektheit und altersgerechte Erklärungen!';
      case Subject.biologie:
        return 'FACH: BIOLOGIE — Achte auf biologische Fachbegriffe und wissenschaftliche Korrektheit!';
      case Subject.chemie:
        return 'FACH: CHEMIE — Achte auf chemische Fachbegriffe und korrekte Formeln!';
      case Subject.physik:
        return 'FACH: PHYSIK — Achte auf physikalische Einheiten und Formeln!';
      case Subject.geschichte:
        return 'FACH: GESCHICHTE — Achte auf historische Fakten und zeitliche Einordnung!';
    }
  }

  // ========================================================================
  // HILFSMETHODEN (unverändert)
  // ========================================================================

  /// Lädt Bild zu Firebase Storage hoch
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

  /// Parst generierte Aufgaben aus AI-Response
  List<GeneratedQuestion> _parseGeneratedQuestions(String jsonText) {
    try {
      String cleaned = jsonText.trim();

      if (cleaned.startsWith('```json')) {
        cleaned = cleaned.substring(7);
      } else if (cleaned.startsWith('```')) {
        cleaned = cleaned.substring(3);
      }

      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3);
      }

      cleaned = cleaned.trim();

      final List<dynamic> jsonList = jsonDecode(cleaned);

      final questions = <GeneratedQuestion>[];

      for (var json in jsonList) {
        try {
          if (json['question'] == null || json['question'].toString().isEmpty) {
            print('⚠️ Überspringe Aufgabe ohne Frage');
            continue;
          }

          if (json['options'] == null ||
              (json['options'] as List).length != 4) {
            print('⚠️ Überspringe Aufgabe: Nicht genau 4 Optionen');
            continue;
          }

          final options = List<String>.from(json['options']);
          final correctAnswer = json['correctAnswer']?.toString() ?? '';

          if (!options.contains(correctAnswer)) {
            print('⚠️ Überspringe Aufgabe: Richtige Antwort nicht in Optionen');
            continue;
          }

          questions.add(
            GeneratedQuestion(
              id: '',
              question: json['question'].toString(),
              options: options,
              correctAnswer: correctAnswer,
              solution: json['solution']?.toString(),
              difficulty: json['difficulty']?.toString() ?? 'medium',
              topic: json['topic']?.toString() ?? '',
              status: TaskApprovalStatus.pending,
              createdAt: DateTime.now(),
            ),
          );
        } catch (e) {
          print('⚠️ Fehler beim Parsen einer Aufgabe: $e');
          continue;
        }
      }

      return questions;
    } catch (e) {
      print('❌ JSON Parse Fehler: $e');
      print('Text war: $jsonText');
      return [];
    }
  }
}

// ========================================================================
// RIVERPOD PROVIDER
// ========================================================================

final improvedFirebaseAIServiceProvider = Provider<ImprovedFirebaseAIService>((
  ref,
) {
  final service = ImprovedFirebaseAIService();
  service.initialize();
  return service;
});
