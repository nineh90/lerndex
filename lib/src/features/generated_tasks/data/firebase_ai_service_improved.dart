import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/child_model.dart';
import '../domain/generated_task_result.dart';
import 'generated_task_models.dart';

/// 🤖 FIREBASE AI SERVICE
///
/// Generiert Multiple-Choice-Aufgaben aus hochgeladenen Fotos.
/// Jede Aufgabe wird einzeln generiert um Token-Truncation zu vermeiden.

class ImprovedFirebaseAIService {
  GenerativeModel? _taskGeneratorModel;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    print('🚀 Firebase AI wird initialisiert...');
    try {
      _taskGeneratorModel = FirebaseAI.googleAI().generativeModel(
        model: 'gemini-2.5-flash',
        generationConfig: GenerationConfig(
          temperature: 0.8,
          maxOutputTokens: 1024,
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
  // AUFGABENGENERIERUNG AUS FOTOS
  // ========================================================================

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
        '📸 Starte Generierung für ${child.name} (${subject.displayName})...',
      );

      // Bild einmal lesen, für alle Calls wiederverwenden
      final Uint8List imageBytes = await imageFile.readAsBytes();
      final subjectContext = _getSubjectContext(subject);

      final questions = <GeneratedQuestion>[];
      final previousQuestions = <String>[];

      for (int i = 1; i <= numberOfTasks; i++) {
        print('🤖 Generiere Aufgabe $i von $numberOfTasks...');
        try {
          final prompt = _buildSingleTaskPrompt(
            child: child,
            subject: subject,
            subjectContext: subjectContext,
            taskIndex: i,
            totalTasks: numberOfTasks,
            previousQuestions: previousQuestions,
          );

          final content = [
            Content.multi([
              TextPart(prompt),
              InlineDataPart('image/jpeg', imageBytes),
            ]),
          ];

          final response = await _taskGeneratorModel!.generateContent(content);
          final text = response.text;

          if (text == null || text.isEmpty) {
            print('⚠️ Aufgabe $i: Keine Antwort');
            continue;
          }

          final question = _parseSingleQuestion(text);
          if (question != null) {
            questions.add(question);
            previousQuestions.add(question.question);
            print(
              '✅ Aufgabe $i OK: ${question.question.substring(0, question.question.length.clamp(0, 50))}',
            );
          } else {
            print('⚠️ Aufgabe $i: Parse fehlgeschlagen');
          }
        } catch (e) {
          print('⚠️ Aufgabe $i Fehler: $e');
        }
      }

      if (questions.isEmpty) {
        throw Exception('Keine validen Aufgaben generiert');
      }

      print('✅ ${questions.length} von $numberOfTasks Aufgaben generiert!');

      return GeneratedTaskResult(
        success: true,
        questions: questions,
        imageUrl: null,
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
  // PROMPT FÜR EINZELNE AUFGABE
  // ========================================================================

  String _buildSingleTaskPrompt({
    required ChildModel child,
    required Subject subject,
    required String subjectContext,
    required int taskIndex,
    required int totalTasks,
    required List<String> previousQuestions,
  }) {
    final previousBlock = previousQuestions.isEmpty
        ? ''
        : '''
BEREITS GENERIERTE FRAGEN (nicht wiederholen!):
${previousQuestions.asMap().entries.map((e) => '- ${e.value}').join('\n')}
''';

    return '''
Du bist ein Lehrer und erstellst Aufgabe $taskIndex von $totalTasks.

SCHÜLER: ${child.name}, Klasse ${child.grade}, ${child.schoolType}, Fach: ${subject.displayName}

$subjectContext

$previousBlock

AUFGABE: Schau auf das Foto und erstelle GENAU 1 neue Multiple-Choice-Aufgabe zu einem ähnlichen Thema.

REGELN:
- Exakt 4 Antwortmöglichkeiten
- Genau 1 richtige Antwort
- Lösungserklärung: max. 1 Satz
- Passend für Klasse ${child.grade}

Antworte NUR mit diesem JSON-Objekt (kein Array, kein Text davor/danach):
{
  "question": "Frage hier",
  "options": ["Option A", "Option B", "Option C", "Option D"],
  "correctAnswer": "Die richtige Option (exakt wie oben)",
  "solution": "Kurze Erklärung in einem Satz.",
  "difficulty": "easy",
  "topic": "Thema"
}
''';
  }

  // ========================================================================
  // PARSE EINZELNE AUFGABE
  // ========================================================================

  GeneratedQuestion? _parseSingleQuestion(String text) {
    try {
      String cleaned = text.trim();

      // Markdown-Fences entfernen
      if (cleaned.startsWith('```json')) {
        cleaned = cleaned.substring(7);
      } else if (cleaned.startsWith('```'))
        cleaned = cleaned.substring(3);
      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3);
      }
      cleaned = cleaned.trim();

      // Echte Newlines in Strings fixen
      cleaned = _fixJsonNewlines(cleaned);

      final json = jsonDecode(cleaned) as Map<String, dynamic>;

      if (json['question'] == null || json['question'].toString().isEmpty) {
        return null;
      }
      if (json['options'] == null || (json['options'] as List).length != 4) {
        return null;
      }

      final options = List<String>.from(json['options']);
      final correctAnswer = json['correctAnswer']?.toString() ?? '';

      if (!options.contains(correctAnswer)) {
        print('⚠️ Richtige Antwort nicht in Optionen: "$correctAnswer"');
        return null;
      }

      return GeneratedQuestion(
        id: '',
        question: json['question'].toString(),
        options: options,
        correctAnswer: correctAnswer,
        solution: json['solution']?.toString(),
        difficulty: json['difficulty']?.toString() ?? 'medium',
        topic: json['topic']?.toString() ?? '',
        status: TaskApprovalStatus.pending,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      print('❌ Parse Fehler: $e');
      print('Text war: $text');
      return null;
    }
  }

  // ========================================================================
  // HILFSMETHODEN
  // ========================================================================

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

  String _getSubjectContext(Subject subject) {
    switch (subject) {
      case Subject.mathe:
        return 'FACH: MATHEMATIK – Themen: Grundrechenarten, Bruchrechnung, Algebra, Geometrie je nach Klasse.';
      case Subject.deutsch:
        return 'FACH: DEUTSCH – Themen: Rechtschreibung, Grammatik, Wortarten, Textverständnis je nach Klasse.';
      case Subject.englisch:
        return 'FACH: ENGLISCH – Themen: Vokabeln, Grammatik, Zeitformen, Textverständnis je nach Klasse.';
      case Subject.sachkunde:
        return 'FACH: SACHKUNDE – Themen: Natur, Tiere, Umwelt, einfache Naturwissenschaften.';
      case Subject.biologie:
        return 'FACH: BIOLOGIE – Themen: Zellen, Ökosysteme, Genetik, Evolution je nach Klasse.';
      case Subject.chemie:
        return 'FACH: CHEMIE – Themen: Stoffe, Reaktionen, Atombau, Säuren/Basen je nach Klasse.';
      case Subject.physik:
        return 'FACH: PHYSIK – Themen: Mechanik, Elektrizität, Optik, Energie je nach Klasse.';
      case Subject.geschichte:
        return 'FACH: GESCHICHTE – Themen: Antike, Mittelalter, Neuzeit, Weltkriege je nach Klasse.';
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
