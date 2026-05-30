import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/child_model.dart';
import '../domain/question_model.dart';
import '../data/extended_quiz_repository.dart';
import '../../rewards/data/xp_service.dart';
import '../../rewards/data/reward_service.dart';
import '../../rewards/domain/reward_model.dart';
import '../../generated_tasks/data/generated_task_repository.dart';
import '../../learning_time/learning_time_tracker.dart';
import 'quiz_state.dart';

export 'quiz_state.dart';

// ============================================================================
// QUIZ ENGINE v1
//
// Zentrale State-Maschine für alle Quiz-Typen (Klasse 1–2, 3–4, 5–8+).
// Ersetzt den duplizierten State in quiz_screen.dart und
// early_learner_quiz_screen.dart.
//
// Zuständigkeiten:
//   - Fragen laden (via ExtendedQuizRepository)
//   - Antworten prüfen + Retry-Logik für ALLE Klassen
//   - XP vergeben pro richtiger Antwort (5 XP normal, 2 XP bei Retry)
//   - Quiz beenden: Streak, Lernzeit, Quiz-Stats, Rewards
//   - Falsch beantwortete Fragen tracken für Endscreen
//
// Die Screens sind nur noch UI — sie rufen Engine-Methoden auf und
// beobachten QuizState über den quizEngineProvider.
// ============================================================================

// ── Engine ───────────────────────────────────────────────────────────────────

class QuizEngine extends StateNotifier<QuizState> {
  final ExtendedQuizRepository _quizRepo;
  final XPService _xpService;
  final RewardService _rewardService;
  final GeneratedTaskRepository _taskRepo;

  String? _userId;
  ChildModel? _child;
  LearningTimeTracker? _timeTracker;
  bool _finishCalled = false;

  /// Completer der finish() blockiert bis der Level-Up-Dialog geschlossen wurde.
  /// Wird von notifyLevelUpDone() aufgelöst (aus quiz_screen nach Dialog-Dismiss).
  Completer<void>? _levelUpCompleter;

  /// Callback: wird nach Level-Up aufgerufen damit der Screen den Dialog zeigt.
  void Function(int newLevel)? onLevelUp;

  /// Callback: wird nach Quiz-Abschluss aufgerufen mit dem finalen Kind-Stand
  /// (nach allen Bonus-XP). Der Screen nutzt dies um activeChildProvider zu
  /// aktualisieren und ggf. einen Level-Up-Dialog für Bonus-XP-Level-Ups zu zeigen.
  /// Der [done] Completer muss vom Screen nach Abschluss aller Aktionen completed werden.
  void Function(
    ChildModel updatedChild,
    int previousLevel,
    Completer<void> done,
  )?
  onChildUpdated;

  /// Muss vom Screen aufgerufen werden nachdem der Level-Up-Dialog geschlossen
  /// wurde – gibt finish() frei, sodass Reward-Popups danach erscheinen.
  void notifyLevelUpDone() {
    if (_levelUpCompleter != null && !_levelUpCompleter!.isCompleted) {
      _levelUpCompleter!.complete();
    }
  }

  /// Callback: wird nach Quiz-Abschluss mit freigeschalteten Rewards aufgerufen.
  void Function(List<RewardModel> rewards)? onRewardsUnlocked;

  /// Callback: wird nach Quiz-Abschluss aufgerufen wenn der Streak sich
  /// tatsächlich erhöht hat (nicht bei "heute bereits gelernt").
  void Function(int streak)? onStreakUpdated;

  QuizEngine(
    this._quizRepo,
    this._xpService,
    this._rewardService,
    this._taskRepo,
  ) : super(const QuizState());

  // ── Öffentliche API ────────────────────────────────────────────────────────

  /// Startet ein neues Quiz. Lädt Fragen und beginnt Lernzeit-Tracking.
  Future<void> start({
    required String userId,
    required ChildModel child,
    required String subject,
    int questionCount = 5,
  }) async {
    _userId = userId;
    _child = child;
    _finishCalled = false;

    state = const QuizState(phase: QuizPhase.loading);

    _timeTracker = LearningTimeTracker(
      userId: userId,
      childId: child.id,
      subject: subject,
    );
    _timeTracker!.startTracking();

    try {
      final questions = await _quizRepo.loadQuizForChild(
        userId: userId,
        childId: child.id,
        child: child,
        subject: subject,
        questionCount: questionCount,
      );

      if (questions.isEmpty) {
        state = const QuizState(
          phase: QuizPhase.error,
          errorMessage: 'Keine Fragen verfügbar. Bitte versuche es später.',
        );
        return;
      }

      state = QuizState(phase: QuizPhase.question, questions: questions);

      debugPrint(
        '✅ QuizEngine: ${questions.length} Fragen geladen für $subject '
        '(${child.name}, Kl. ${child.grade}, Lv. ${child.level})',
      );
    } catch (e) {
      debugPrint('❌ QuizEngine.start Fehler: $e');
      state = const QuizState(
        phase: QuizPhase.error,
        errorMessage: 'Fragen konnten nicht geladen werden.',
      );
    }
  }

  /// Verarbeitet eine Antwort des Kindes.
  /// Gibt zurück ob die Antwort korrekt war (für sofortige UI-Reaktion).
  Future<bool> answerQuestion(String selectedAnswer) async {
    final current = state.currentQuestion;
    if (current == null || state.phase != QuizPhase.question) return false;

    final isCorrect = current.isCorrect(selectedAnswer);
    final isRetry = state.isRetry;

    int xpGained = 0;
    bool leveledUp = false;
    int newLevel = state.newLevel;

    if (isCorrect) {
      // Erster Versuch: 5 XP, Retry: 2 XP
      final xpToAdd = isRetry ? 2 : 5;

      try {
        final xpResult = await _xpService.addXP(
          userId: _userId!,
          childId: _child!.id,
          xpToAdd: xpToAdd,
        );
        xpGained = xpToAdd;
        leveledUp = xpResult.leveledUp;
        newLevel = xpResult.newLevel;
      } catch (e) {
        debugPrint('⚠️ QuizEngine: XP-Vergabe fehlgeschlagen: $e');
      }

      // Eltern-Aufgabe als korrekt beantwortet markieren
      if (current.isParentTask) {
        try {
          await _taskRepo.markQuestionAnsweredCorrectly(
            userId: _userId!,
            parentTaskRef: current.parentTaskRef!,
          );
        } catch (e) {
          debugPrint(
            '⚠️ QuizEngine: Eltern-Aufgabe Markierung fehlgeschlagen: $e',
          );
        }
      }
    }

    // Wrong-Listen aktualisieren
    final updatedWrong = List<Question>.from(state.wrongQuestions);
    final updatedRetriedCorrectly = List<Question>.from(state.retriedCorrectly);

    if (isRetry && isCorrect) {
      // Retry erfolgreich → aus wrongQuestions raus
      updatedWrong.removeWhere((q) => q.question == current.question);
      if (!updatedRetriedCorrectly.any((q) => q.question == current.question)) {
        updatedRetriedCorrectly.add(current);
      }
    }

    state = state.copyWith(
      phase: QuizPhase.feedback,
      wasCorrect: isCorrect,
      correctAnswers: isCorrect
          ? state.correctAnswers + 1
          : state.correctAnswers,
      earnedXP: state.earnedXP + xpGained,
      leveledUp: leveledUp,
      newLevel: newLevel,
      wrongQuestions: updatedWrong,
      retriedCorrectly: updatedRetriedCorrectly,
    );

    if (leveledUp) {
      // Completer aufsetzen bevor der Callback feuert – finish() wartet darauf
      _levelUpCompleter = Completer<void>();
      onLevelUp?.call(newLevel);
    }

    return isCorrect;
  }

  /// Wechselt nach falscher Antwort in den Retry-Prompt.
  /// Wird nach dem Feedback-Delay aufgerufen.
  /// Kinder haben pro Frage nur EINEN Retry-Versuch — war isRetry bereits
  /// true, wird die Frage direkt als falsch gewertet und übersprungen.
  void showRetryPrompt() {
    if (state.phase != QuizPhase.feedback || state.wasCorrect) return;

    // Zweiter Fehlversuch → kein erneuter Retry, Frage endgültig falsch werten
    if (state.isRetry) {
      final current = state.currentQuestion;
      if (current != null) {
        final updatedWrong = List<Question>.from(state.wrongQuestions);
        if (!updatedWrong.any((q) => q.question == current.question)) {
          updatedWrong.add(current);
        }
        state = state.copyWith(wrongQuestions: updatedWrong);
      }
      _advance();
      return;
    }

    state = state.copyWith(phase: QuizPhase.retryPrompt);
  }

  /// Kind möchte die falsch beantwortete Frage nochmal versuchen.
  void retryQuestion() {
    state = state.copyWith(phase: QuizPhase.question, isRetry: true);
  }

  /// Kind überspringt den Retry → Frage bleibt in wrongQuestions.
  void skipRetry() {
    final current = state.currentQuestion;
    if (current == null) return;

    final updatedWrong = List<Question>.from(state.wrongQuestions);
    if (!updatedWrong.any((q) => q.question == current.question)) {
      updatedWrong.add(current);
    }

    state = state.copyWith(wrongQuestions: updatedWrong);
    _advance();
  }

  /// Weiter nach richtiger Antwort oder nach Retry-Entscheidung.
  void advance() => _advance();

  void _advance() {
    if (state.isLastQuestion) {
      finish();
      return;
    }
    state = state.copyWith(
      phase: QuizPhase.question,
      currentIndex: state.currentIndex + 1,
      isRetry: false,
      leveledUp: false, // Level-Up-Flag zurücksetzen nach Advance
    );
  }

  /// Beendet das Quiz und speichert alle Daten.
  Future<void> finish() async {
    if (_finishCalled) return;
    _finishCalled = true;

    state = state.copyWith(phase: QuizPhase.finished);

    // State-Werte JETZT festhalten: finish() hat lange await-Phasen
    // (Reward-Check, Level-Up-Dialog mit 30s-Timeout). Navigiert der Nutzer
    // in dieser Zeit weg, wird die autoDispose-Engine entsorgt und ein
    // späterer `state`-Zugriff würfe "used after dispose". Die Persistenz
    // (XP/Streak/Rewards) soll aber trotzdem sauber zu Ende laufen.
    final isPerfect = state.isPerfect;
    final correctAnswers = state.correctAnswers;
    final totalQuestions = state.questions.length;
    final earnedXP = state.earnedXP;
    final wrongCount = state.wrongQuestions.length;

    final userId = _userId;
    final child = _child;
    if (userId == null || child == null) return;

    try {
      // 1. Streak (MUSS vor saveTime kommen)
      final streakBefore = child.streak ?? 0;
      final newStreak = await _xpService.updateStreak(
        userId: userId,
        childId: child.id,
      );
      debugPrint('✅ Streak: $newStreak Tage (vorher: $streakBefore)');
      // Nur feuern wenn Streak sich tatsächlich erhöht hat — nicht bei
      // "heute bereits gelernt" (würde sonst Milestone-Popup doppelt zeigen)
      if (newStreak > streakBefore) {
        onStreakUpdated?.call(newStreak);
      }

      // 2. Lernzeit
      _timeTracker?.stopTracking();
      await _timeTracker?.saveTime();

      // 3. Quiz-Statistiken
      await _xpService.updateQuizStats(
        userId: userId,
        childId: child.id,
        isPerfect: isPerfect,
      );

      // 4. Kind neu laden (mit aktuellem Streak) + Rewards prüfen
      ChildModel? updatedChild = await _xpService.getChild(
        userId: userId,
        childId: child.id,
      );

      if (updatedChild != null) {
        final levelBeforeBonus = updatedChild.level;
        updatedChild = updatedChild.copyWith(streak: newStreak);

        // ✅ FIX: Warten bis Level-Up-Dialog geschlossen wurde bevor
        // Reward-Popups gezeigt werden (verhindert überlagerte Dialoge).
        if (_levelUpCompleter != null) {
          await _levelUpCompleter!.future.timeout(
            const Duration(seconds: 30),
            onTimeout: () {},
          );
        }

        final unlockedRewards = await _rewardService.checkAndApproveRewards(
          userId: userId,
          child: updatedChild,
          isPerfectQuiz: isPerfect,
        );

        // Kind nochmal laden – Bonus-XP könnten Level verändert haben
        final finalChild = await _xpService.getChild(
          userId: userId,
          childId: child.id,
        );
        if (finalChild != null) {
          final childUpdateCompleter = Completer<void>();
          onChildUpdated?.call(
            finalChild,
            levelBeforeBonus,
            childUpdateCompleter,
          );
          // Warten bis _handleChildUpdated (inkl. Level-Up-Dialog) fertig ist
          await childUpdateCompleter.future.timeout(
            const Duration(seconds: 30),
            onTimeout: () {},
          );
        }

        if (unlockedRewards.isNotEmpty) {
          debugPrint('🎁 ${unlockedRewards.length} Rewards freigeschaltet');
          onRewardsUnlocked?.call(unlockedRewards);
        }
      }

      debugPrint(
        '✅ Quiz abgeschlossen: $correctAnswers/$totalQuestions '
        'richtig | $earnedXP XP | '
        '$wrongCount endgültig falsch',
      );
    } catch (e, st) {
      debugPrint('❌ QuizEngine.finish Fehler: $e\n$st');
    }
  }

  @override
  void dispose() {
    _timeTracker?.dispose();
    super.dispose();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// Family-Provider nach Subject — ein Engine-Slot pro offenem Quiz-Screen.
/// autoDispose: Engine wird beim Verlassen des Screens automatisch aufgeräumt.
final quizEngineProvider = StateNotifierProvider.family
    .autoDispose<QuizEngine, QuizState, String>((ref, subject) {
      return QuizEngine(
        ref.watch(extendedQuizRepositoryProvider),
        ref.watch(xpServiceProvider),
        ref.watch(rewardServiceProvider),
        ref.watch(generatedTaskRepositoryProvider),
      );
    });
