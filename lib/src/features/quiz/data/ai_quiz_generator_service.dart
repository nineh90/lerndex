import 'dart:convert';
import 'package:firebase_vertexai/firebase_vertexai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex1/src/features/auth/domain/child_model.dart';
import 'package:lerndex1/src/features/quiz/domain/question_model.dart';

/// 🤖 AI QUIZ GENERATOR SERVICE
///
/// Generiert personalisierte Quiz-Fragen on-the-fly via Vertex AI.
/// Kein Eltern-Approval nötig – nur saubere Schulaufgaben.
///
/// Firestore-Pfad für Cache:
///   users/{userId}/children/{childId}/ai_quiz_cache/{subject}/questions (subcollection)
class AiQuizGeneratorService {
  GenerativeModel? _model;
  bool _isInitialized = false;

  Future<void> _ensureInitialized() async {
    if (_isInitialized) return;
    _model = FirebaseVertexAI.instance.generativeModel(
      model: 'gemini-2.5-flash',
      generationConfig: GenerationConfig(
        temperature: 0.7,
        maxOutputTokens: 8192,
        topP: 0.9,
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
          HarmBlockThreshold.high,
          HarmBlockMethod.severity,
        ),
        SafetySetting(
          HarmCategory.dangerousContent,
          HarmBlockThreshold.high,
          HarmBlockMethod.severity,
        ),
      ],
    );
    _isInitialized = true;
  }

  /// Generiert [count] Fragen für ein Kind in einem Fach.
  /// Gibt eine leere Liste zurück wenn die KI nicht erreichbar ist –
  /// der Aufrufer fällt dann auf statische JSON-Fragen zurück.
  Future<List<Question>> generateQuestions({
    required ChildModel child,
    required String subject,
    int count = 10,
  }) async {
    try {
      await _ensureInitialized();

      final prompt = _buildPrompt(child: child, subject: subject, count: count);
      final response = await _model!.generateContent([Content.text(prompt)]);
      final text = response.text ?? '';

      return _parseResponse(text, child.grade);
    } catch (e) {
      print('❌ AiQuizGeneratorService: Fehler bei Generierung: $e');
      return [];
    }
  }

  // ── Prompt ────────────────────────────────────────────────────────────────

  String _buildPrompt({
    required ChildModel child,
    required String subject,
    required int count,
  }) {
    final subjectDisplay = _subjectDisplayName(subject);
    final difficultyHint = _difficultyHint(child.level);

    return '''
Du bist ein Schulaufgaben-Generator für deutsche Schüler.

SCHÜLER-PROFIL:
- Name: ${child.name}
- Alter: ${child.age} Jahre
- Schulform: ${child.schoolType}
- Klasse: ${child.grade}
- Level: ${child.level} (${difficultyHint})

AUFGABE:
Generiere genau $count Multiple-Choice-Fragen für das Fach "$subjectDisplay".
Die Fragen müssen dem deutschen Lehrplan für Klasse ${child.grade} (${child.schoolType}) entsprechen.
Variiere die Schwierigkeit: ca. 40% leicht, 40% mittel, 20% schwer.

WICHTIGE REGELN:
- Alle Fragen auf Deutsch (außer bei Englisch als Fach)
- Genau 4 Antwortmöglichkeiten pro Frage
- Genau 1 richtige Antwort
- Die richtige Antwort muss IDENTISCH mit einer der 4 Options sein
- Keine anstößigen, gefährlichen oder unangemessenen Inhalte
- Fragen sollen lehrreich und klar formuliert sein

ANTWORT-FORMAT (nur reines JSON, keine Markdown-Blöcke, kein Text davor/danach):
[
  {
    "question": "Was ist 7 × 8?",
    "options": ["54", "56", "48", "64"],
    "answer": "56",
    "difficulty": "easy",
    "topic": "Multiplikation"
  }
]
''';
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
      default:
        return subject;
    }
  }

  String _difficultyHint(int level) {
    if (level <= 2) return 'Anfänger, sehr einfache Aufgaben';
    if (level <= 5) return 'Fortgeschrittener, mittlere Aufgaben';
    if (level <= 8) return 'Geübt, anspruchsvollere Aufgaben';
    return 'Experte, herausfordernde Aufgaben';
  }

  // ── JSON Parsing ──────────────────────────────────────────────────────────

  List<Question> _parseResponse(String rawText, int grade) {
    try {
      // Bereinige mögliche Markdown-Wrapper die die KI trotzdem liefert
      final cleaned = rawText
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      // JSON-Array suchen (von [ bis ])
      final startIndex = cleaned.indexOf('[');
      final endIndex = cleaned.lastIndexOf(']');
      if (startIndex == -1 || endIndex == -1) {
        print('⚠️ AiQuizGeneratorService: Kein JSON-Array gefunden');
        return [];
      }

      final jsonStr = cleaned.substring(startIndex, endIndex + 1);
      final List<dynamic> jsonList = json.decode(jsonStr);

      final questions = <Question>[];
      for (final item in jsonList) {
        try {
          final q = _parseQuestion(item, grade);
          if (q != null) questions.add(q);
        } catch (e) {
          print('⚠️ AiQuizGeneratorService: Frage übersprungen: $e');
        }
      }

      print('✅ AiQuizGeneratorService: ${questions.length} Fragen generiert');
      return questions;
    } catch (e) {
      print('❌ AiQuizGeneratorService: JSON-Parsing fehlgeschlagen: $e');
      return [];
    }
  }

  Question? _parseQuestion(Map<String, dynamic> item, int grade) {
    final question = item['question'] as String? ?? '';
    final options = (item['options'] as List?)?.cast<String>() ?? [];
    final answer = item['answer'] as String? ?? '';
    final difficulty = item['difficulty'] as String? ?? 'medium';

    // Validierung
    if (question.isEmpty || options.length != 4 || answer.isEmpty) return null;
    if (!options.contains(answer)) return null;

    return Question(
      grade: grade,
      question: question,
      options: options,
      answer: answer,
      difficulty: difficulty,
    );
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final aiQuizGeneratorServiceProvider = Provider<AiQuizGeneratorService>((ref) {
  return AiQuizGeneratorService();
});
