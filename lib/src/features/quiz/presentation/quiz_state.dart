import '../domain/question_model.dart';

// ============================================================================
// QUIZ STATE
//
// Reiner, immutabler Zustand der Quiz-State-Maschine — bewusst getrennt von der
// Firebase-/Riverpod-gekoppelten [QuizEngine], damit er isoliert unit-getestet
// werden kann. Die Engine importiert (und re-exportiert) diese Datei.
// ============================================================================

// ── Phasen ───────────────────────────────────────────────────────────────────

enum QuizPhase {
  loading, // Fragen werden geladen
  question, // Aktuelle Frage wird angezeigt
  feedback, // Richtig/Falsch-Feedback (kurze Einblendung)
  retryPrompt, // Kind kann nochmal versuchen oder überspringen
  finished, // Quiz beendet, Zusammenfassung anzeigen
  error, // Ladefehler
}

// ── State ────────────────────────────────────────────────────────────────────

class QuizState {
  final QuizPhase phase;
  final List<Question> questions;
  final int currentIndex;
  final bool wasCorrect;
  final bool isRetry; // Aktuelle Frage ist ein Retry-Versuch

  /// Fragen die endgültig falsch blieben (kein Retry oder Retry auch falsch).
  final List<Question> wrongQuestions;

  /// Fragen die beim ersten Versuch falsch waren, aber im Retry richtig.
  final List<Question> retriedCorrectly;

  final int correctAnswers;
  final int earnedXP;
  final bool leveledUp;
  final int newLevel;
  final String? errorMessage;

  const QuizState({
    this.phase = QuizPhase.loading,
    this.questions = const [],
    this.currentIndex = 0,
    this.wasCorrect = false,
    this.isRetry = false,
    this.wrongQuestions = const [],
    this.retriedCorrectly = const [],
    this.correctAnswers = 0,
    this.earnedXP = 0,
    this.leveledUp = false,
    this.newLevel = 1,
    this.errorMessage,
  });

  Question? get currentQuestion =>
      questions.isNotEmpty && currentIndex < questions.length
      ? questions[currentIndex]
      : null;

  bool get isLastQuestion => currentIndex >= questions.length - 1;

  double get progress =>
      questions.isEmpty ? 0.0 : (currentIndex + 1) / questions.length;

  /// Perfektes Quiz: alle Fragen beim ersten Versuch richtig, kein Retry nötig.
  bool get isPerfect =>
      questions.isNotEmpty &&
      wrongQuestions.isEmpty &&
      retriedCorrectly.isEmpty;

  QuizState copyWith({
    QuizPhase? phase,
    List<Question>? questions,
    int? currentIndex,
    bool? wasCorrect,
    bool? isRetry,
    List<Question>? wrongQuestions,
    List<Question>? retriedCorrectly,
    int? correctAnswers,
    int? earnedXP,
    bool? leveledUp,
    int? newLevel,
    String? errorMessage,
  }) {
    return QuizState(
      phase: phase ?? this.phase,
      questions: questions ?? this.questions,
      currentIndex: currentIndex ?? this.currentIndex,
      wasCorrect: wasCorrect ?? this.wasCorrect,
      isRetry: isRetry ?? this.isRetry,
      wrongQuestions: wrongQuestions ?? this.wrongQuestions,
      retriedCorrectly: retriedCorrectly ?? this.retriedCorrectly,
      correctAnswers: correctAnswers ?? this.correctAnswers,
      earnedXP: earnedXP ?? this.earnedXP,
      leveledUp: leveledUp ?? this.leveledUp,
      newLevel: newLevel ?? this.newLevel,
      errorMessage: errorMessage,
    );
  }
}
