export 'quiz_data.dart';

import 'safe_emojis.dart';

/// Repräsentiert eine Quiz-Frage.
///
/// Diese Klasse ist die EINZIGE Question-Klasse im gesamten Projekt.
/// Sie ersetzt die frühere QuizQuestion-Klasse vollständig.
///
/// Quellen:
///   - KI-generierte Fragen (via VertexAIService / AiQuestionCacheRepository)
///   - Von Eltern freigegebene Aufgaben (parentTaskRef != null)
///   - Statische JSON-Fallback-Fragen
class Question {
  final int grade;
  final String question;
  final List<String> options;
  final String answer;
  final String difficulty;
  final String topic;

  /// Optionales Emoji-Bild zur Veranschaulichung der Frage.
  /// MUSS aus [SafeEmojis.whitelist] kommen — sonst null.
  /// Wird im UI groß über der Frage gerendert (Grundschul-Verständlichkeit).
  final String? emoji;

  /// Wenn gesetzt: Diese Frage stammt von einem Eltern-gepflegten Task.
  /// Format: "batchId/questionId"
  /// Wird beim korrekten Beantworten in Firestore markiert.
  final String? parentTaskRef;

  /// Optionale Referenz zur ursprünglichen generierten Aufgaben-ID.
  /// Entspricht GeneratedQuestion.id — wird für Task-Tracking genutzt.
  final String? generatedTaskId;

  const Question({
    required this.grade,
    required this.question,
    required this.options,
    required this.answer,
    required this.difficulty,
    this.topic = '',
    this.emoji,
    this.parentTaskRef,
    this.generatedTaskId,
  });

  // ── Factories ──────────────────────────────────────────────────────────────

  factory Question.fromJson(Map<String, dynamic> json) {
    // Emoji-Sanitization: nur akzeptieren, wenn in Whitelist.
    final rawEmoji = json['emoji'] as String?;
    final safeEmoji = SafeEmojis.sanitize(rawEmoji);

    // Frage-Text sanitisieren: Platzhalter wie "(Bild eines Apfels)"
    // werden entfernt, da wir stattdessen das emoji-Feld nutzen.
    final rawQuestion = json['question'] as String;
    final cleanedQuestion = _stripImagePlaceholders(rawQuestion);

    return Question(
      grade: json['grade'] as int? ?? 1,
      question: cleanedQuestion,
      options: List<String>.from(json['options']),
      answer: json['answer'] as String,
      difficulty: json['difficulty'] as String? ?? 'medium',
      topic: json['topic'] as String? ?? '',
      emoji: safeEmoji,
      parentTaskRef: json['parentTaskRef'] as String?,
      generatedTaskId: json['generatedTaskId'] as String?,
    );
  }

  /// Entfernt Klammer-Platzhalter wie "(Bild eines Apfels)" oder
  /// "[Bild: Hund]" aus dem Fragetext. Diese kamen früher von der KI
  /// wenn das Modell ein Bild "wollte" aber keines liefern konnte.
  /// Jetzt nutzen wir das emoji-Feld dafür.
  static String _stripImagePlaceholders(String text) {
    final patterns = [
      RegExp(r'\(\s*Bild[^)]*\)', caseSensitive: false),
      RegExp(r'\[\s*Bild[^\]]*\]', caseSensitive: false),
      RegExp(r'\(\s*siehe Bild[^)]*\)', caseSensitive: false),
      RegExp(r'\(\s*Image[^)]*\)', caseSensitive: false),
      RegExp(r'\[\s*Image[^\]]*\]', caseSensitive: false),
    ];
    var cleaned = text;
    for (final p in patterns) {
      cleaned = cleaned.replaceAll(p, '');
    }
    // Doppelte Leerzeichen + Whitespace bereinigen
    return cleaned.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  // ── Methoden ───────────────────────────────────────────────────────────────

  bool isCorrect(String selectedAnswer) => selectedAnswer == answer;

  /// True wenn diese Frage von Eltern gepflegt wurde
  bool get isParentTask => parentTaskRef != null;

  /// True wenn ein Emoji-Bild verfügbar ist
  bool get hasEmoji => emoji != null && emoji!.isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'grade': grade,
      'question': question,
      'options': options,
      'answer': answer,
      'difficulty': difficulty,
      'topic': topic,
      if (emoji != null) 'emoji': emoji,
      if (parentTaskRef != null) 'parentTaskRef': parentTaskRef,
      if (generatedTaskId != null) 'generatedTaskId': generatedTaskId,
    };
  }

  Question copyWith({
    int? grade,
    String? question,
    List<String>? options,
    String? answer,
    String? difficulty,
    String? topic,
    String? emoji,
    String? parentTaskRef,
    String? generatedTaskId,
  }) {
    return Question(
      grade: grade ?? this.grade,
      question: question ?? this.question,
      options: options ?? List<String>.from(this.options),
      answer: answer ?? this.answer,
      difficulty: difficulty ?? this.difficulty,
      topic: topic ?? this.topic,
      emoji: emoji ?? this.emoji,
      parentTaskRef: parentTaskRef ?? this.parentTaskRef,
      generatedTaskId: generatedTaskId ?? this.generatedTaskId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Question &&
          runtimeType == other.runtimeType &&
          question == other.question &&
          answer == other.answer &&
          grade == other.grade;

  @override
  int get hashCode => Object.hash(question, answer, grade);

  @override
  String toString() =>
      'Question(grade: $grade, topic: $topic, difficulty: $difficulty, '
      'q: "${question.length > 50 ? "${question.substring(0, 50)}..." : question}")';
}
