import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex/src/features/auth/domain/child_model.dart';
import 'package:lerndex/src/features/quiz/presentation/quiz_engine.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/widgets/dashboard_theme_provider.dart';
import '../domain/question_model.dart';
import '../../auth/presentation/active_child_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../rewards/data/reward_service.dart';
import '../../rewards/data/xp_service.dart';
import '../../rewards/domain/reward_model.dart';
import '../../rewards/presentation/reward_unlocked_dialog.dart';
import '../../rewards/presentation/student_notification_popup.dart';
import '../../student_dashboard/presentation/widgets/rewards_count_provider.dart';
import 'widgets/answer_button.dart';
import '../data/quiz_prefetch_service.dart';
import '../../../ai/vertex_ai_service.dart';

// ============================================================================
// QUIZ SCREEN – Klasse 3+ (v2)
//
// State-Logik vollständig in QuizEngine ausgelagert.
// Design: identisch zu v1, erweitert um:
//   • Retry-Prompt nach falscher Antwort (für alle Klassen)
//   • Falsch-beantwortete Fragen im Endscreen
//   • Theme-Unterstützung für Klasse 5+ (DashboardTheme)
// ============================================================================

class QuizScreen extends ConsumerStatefulWidget {
  final String subject;

  const QuizScreen({super.key, required this.subject});

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _feedbackController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();

    // Engine nach dem ersten Frame starten
    WidgetsBinding.instance.addPostFrameCallback((_) => _startQuiz());
  }

  void _setupAnimations() {
    _feedbackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.2).animate(
      CurvedAnimation(parent: _feedbackController, curve: Curves.elasticOut),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _feedbackController, curve: Curves.easeIn),
    );
  }

  Future<void> _startQuiz() async {
    final child = ref.read(activeChildProvider);
    final user = ref.read(authStateChangesProvider).value;
    if (child == null || user == null) return;

    final engine = ref.read(quizEngineProvider(widget.subject).notifier);

    // Callbacks setzen (Screen-spezifische Dialoge)
    engine.onLevelUp = (newLevel) => _handleLevelUp(newLevel);
    engine.onChildUpdated = (updatedChild, previousLevel, done) =>
        _handleChildUpdated(updatedChild, previousLevel, done);
    engine.onRewardsUnlocked = (rewards) => _handleRewards(rewards);
    engine.onStreakUpdated = (streak) => _handleStreak(streak);

    await engine.start(userId: user.uid, child: child, subject: widget.subject);
  }

  // ── Engine-Callbacks ───────────────────────────────────────────────────────

  Future<void> _handleLevelUp(int newLevel, {int? previousLevel}) async {
    if (!mounted) return;
    final child = ref.read(activeChildProvider);
    final user = ref.read(authStateChangesProvider).value;
    if (child == null || user == null) return;

    // previousLevel: entweder explizit übergeben (Bonus-XP-Fall)
    // oder aus dem aktuellen activeChildProvider lesen (answerQuestion-Fall)
    final levelBefore = previousLevel ?? child.level;

    // Session-Guard zurücksetzen damit neue Level-Fragen sofort
    // beim nächsten Prefetch (Dashboard-Reload) nachgeladen werden.
    QuizPrefetchService.invalidateSessionGuard(child.id, widget.subject);

    // Kurz warten damit Feedback-Overlay sichtbar bleibt
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    // ✅ FIX: activeChildProvider sofort aktualisieren damit der Tutor-FAB
    // im Dashboard das neue Level anzeigt, ohne App-Neustart.
    final xpService = ref.read(xpServiceProvider);
    final updatedChild = await xpService.getChild(
      userId: user.uid,
      childId: child.id,
    );
    if (updatedChild != null && mounted) {
      ref.read(activeChildProvider.notifier).update(updatedChild);
    }

    if (!mounted) return;

    try {
      // Belohnung erstellen
      final rewardService = ref.read(rewardServiceProvider);
      final reward = await rewardService.createLevelUpReward(
        userId: user.uid,
        childId: child.id,
        level: newLevel,
      );

      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => RewardUnlockedDialog(
          rewards: reward != null ? [reward] : [],
          isLevelUp: true,
          newLevel: newLevel,
        ),
      );

      // Tutor-Freischaltungs-Dialog: wenn Level-Schwelle 2 erstmalig überschritten
      if (newLevel >= 2 && levelBefore < 2 && mounted && child.grade >= 3) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => _TutorUnlockedDialog(childName: child.name),
        );
      }
    } catch (e) {
      if (mounted) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('🎉 Level Up!'),
            content: Text('Du hast Level $newLevel erreicht!'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Super!'),
              ),
            ],
          ),
        );
      }
    } finally {
      // ✅ finish() freigeben damit Reward-Popups nach dem Dialog erscheinen
      ref.read(quizEngineProvider(widget.subject).notifier).notifyLevelUpDone();
    }
  }

  void _handleRewards(List<RewardModel> rewards) {
    if (!mounted) return;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      showRewardNotifications(context, rewards: rewards);
    });
  }

  /// Wird von der Engine nach finish() aufgerufen mit dem finalen Kind-Stand.
  /// Aktualisiert activeChildProvider und zeigt Level-Up-Dialog wenn der
  /// Level-Up durch Bonus-XP (nicht durch answerQuestion) ausgelöst wurde.
  Future<void> _handleChildUpdated(
    ChildModel updatedChild,
    int previousLevel,
    Completer<void> done,
  ) async {
    try {
      // activeChildProvider immer aktualisieren (Tutor-FAB, Dashboard)
      if (mounted) {
        ref.read(activeChildProvider.notifier).update(updatedChild);
      }

      // Level-Up durch Bonus-XP? → onLevelUp hat das nicht erkannt, also hier
      if (updatedChild.level > previousLevel && mounted) {
        await _handleLevelUp(updatedChild.level, previousLevel: previousLevel);
      }
    } finally {
      if (!done.isCompleted) done.complete();
    }
  }

  void _handleStreak(int streak) {
    if (!mounted) return;
    final quizState = ref.read(quizEngineProvider(widget.subject));
    if (_isStreakMilestone(streak) && !quizState.leveledUp) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          StudentNotificationPopup.show(
            context,
            type: StudentNotificationType.streakMilestone,
          );
        }
      });
    }
  }

  bool _isStreakMilestone(int streak) =>
      streak == 3 ||
      streak == 7 ||
      streak == 14 ||
      streak == 30 ||
      streak == 50 ||
      streak == 100;

  // ── Antwort-Verarbeitung ───────────────────────────────────────────────────

  Future<void> _checkAnswer(String selected) async {
    final quizState = ref.read(quizEngineProvider(widget.subject));
    if (quizState.phase != QuizPhase.question) return;

    final engine = ref.read(quizEngineProvider(widget.subject).notifier);
    final isCorrect = await engine.answerQuestion(selected);

    // Feedback-Animation abspielen
    _feedbackController.forward().then((_) => _feedbackController.reverse());

    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    if (!isCorrect) {
      // Retry-Prompt anzeigen
      engine.showRetryPrompt();
    } else {
      // Richtig → direkt zur nächsten Frage
      engine.advance();
    }
  }

  // ── Theme ──────────────────────────────────────────────────────────────────

  /// Gibt die Fachfarbe zurück. Für Klasse 5+ wird zusätzlich das
  /// DashboardTheme berücksichtigt (primary-Farbe des gewählten Themes).
  Color _getSubjectColor() {
    final child = ref.read(activeChildProvider);
    final user = ref.read(authStateChangesProvider).value;

    // Klasse 5+: Theme-Farbe verwenden wenn vorhanden
    if (child != null && user != null && child.grade >= 5) {
      final themeState = ref.read(
        dashboardThemeProvider((userId: user.uid, childId: child.id)),
      );
      return themeState.theme.primary;
    }

    // Klasse 3-4: klassische Fachfarben
    switch (widget.subject.toLowerCase()) {
      case 'mathe':
        return Colors.deepPurple;
      case 'deutsch':
        return Colors.redAccent;
      case 'englisch':
        return Colors.blue;
      case 'sachkunde':
        return Colors.green;
      case 'biologie':
        return const Color(0xFF26A69A);
      case 'chemie':
        return const Color(0xFFAB47BC);
      case 'physik':
        return const Color(0xFF5C6BC0);
      case 'geschichte':
        return const Color(0xFF8D6E63);
      default:
        return Colors.deepPurple;
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final quizState = ref.watch(quizEngineProvider(widget.subject));

    return switch (quizState.phase) {
      QuizPhase.loading => _buildLoadingScreen(),
      QuizPhase.error => _buildNoQuestionsScreen(quizState.errorMessage),
      QuizPhase.finished => _buildSuccessScreen(quizState),
      _ => _buildQuizScreen(quizState),
    };
  }

  Widget _buildQuizScreen(QuizState quizState) {
    final currentQuestion = quizState.currentQuestion;
    if (currentQuestion == null) return _buildLoadingScreen();

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text('${widget.subject} Quiz'),
        centerTitle: true,
        backgroundColor: _getSubjectColor(),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildProgressHeader(quizState),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    24,
                    24,
                    24 + MediaQuery.of(context).padding.bottom,
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      // Retry-Badge wenn es ein Wiederholungsversuch ist
                      if (quizState.isRetry) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.orange.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.refresh,
                                size: 16,
                                color: Colors.orange.shade700,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Nochmal versuchen',
                                style: TextStyle(
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      _buildQuestionCard(currentQuestion),
                      const SizedBox(height: 40),
                      ..._buildAnswerButtons(
                        currentQuestion,
                        disabled: quizState.phase != QuizPhase.question,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Feedback-Overlay (Richtig/Falsch)
          if (quizState.phase == QuizPhase.feedback)
            _buildFeedbackOverlay(quizState.wasCorrect),
          // Retry-Prompt
          if (quizState.phase == QuizPhase.retryPrompt) _buildRetryPrompt(),
        ],
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: _getSubjectColor(),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 24),
            Text(
              'Bereite dein ${widget.subject}-Quiz vor...',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Gleich geht es los! ✨',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoQuestionsScreen([String? message]) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.subject} Quiz'),
        backgroundColor: _getSubjectColor(),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 80, color: Colors.orange),
            const SizedBox(height: 20),
            const Text(
              'Keine Fragen gefunden',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              message ?? 'Für ${widget.subject} gibt es noch keine Fragen.',
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Zurück'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressHeader(QuizState quizState) {
    return Container(
      color: _getSubjectColor(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Frage ${quizState.currentIndex + 1} von ${quizState.questions.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${quizState.correctAnswers} richtig',
                style: const TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: quizState.progress,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(Question question) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (question.hasEmoji) ...[
            Text(
              question.emoji!,
              style: const TextStyle(fontSize: 64, height: 1.1),
              textAlign: TextAlign.center,
              semanticsLabel: 'Bild zur Frage',
            ),
            const SizedBox(height: 16),
          ],
          Text(
            question.question,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAnswerButtons(Question question, {bool disabled = false}) {
    return question.options.map((option) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: AnswerButton(
          text: option,
          onPressed: disabled ? null : () => _checkAnswer(option),
          color: _getSubjectColor(),
        ),
      );
    }).toList();
  }

  Widget _buildFeedbackOverlay(bool wasCorrect) {
    return AnimatedBuilder(
      animation: _feedbackController,
      builder: (context, child) {
        return Container(
          color: (wasCorrect ? Colors.green : Colors.red).withOpacity(
            _fadeAnimation.value * 0.9,
          ),
          child: Center(
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 30,
                    ),
                  ],
                ),
                child: Icon(
                  wasCorrect ? Icons.check : Icons.close,
                  size: 80,
                  color: wasCorrect ? Colors.green : Colors.red,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Retry-Prompt: erscheint nach falscher Antwort als Bottom-Sheet-artiges Panel.
  /// Design: dezent, passt zum bestehenden Screen — kein Pop-up.
  Widget _buildRetryPrompt() {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottomInset),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '💪 Noch nicht ganz richtig',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Möchtest du es nochmal versuchen?',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                // Nochmal-Button
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ref
                          .read(quizEngineProvider(widget.subject).notifier)
                          .retryQuestion();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text(
                      'Nochmal!',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _getSubjectColor(),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Weiter-Button (überspringen)
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    onPressed: () {
                      ref
                          .read(quizEngineProvider(widget.subject).notifier)
                          .skipRetry();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey[600],
                      side: BorderSide(color: Colors.grey[300]!),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Weiter', style: TextStyle(fontSize: 14)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Endscreen ──────────────────────────────────────────────────────────────

  Widget _buildSuccessScreen(QuizState quizState) {
    final total = quizState.questions.length;
    final correct = quizState.correctAnswers;
    final percentage = total > 0 ? (correct / total * 100).round() : 0;
    final earnedXP = quizState.earnedXP;
    final wrongQuestions = quizState.wrongQuestions;
    final retriedCorrectly = quizState.retriedCorrectly;
    final subjectColor = _getSubjectColor();

    final String headline;
    final String tutorEmoji;
    if (quizState.isPerfect) {
      headline = 'Perfekt! 🌟';
      tutorEmoji = '🤩';
    } else if (percentage >= 80) {
      headline = 'Super gemacht! 🎉';
      tutorEmoji = '😄';
    } else if (percentage >= 60) {
      headline = 'Gut gemacht! 👍';
      tutorEmoji = '🙂';
    } else {
      headline = 'Weiter üben! 💪';
      tutorEmoji = '🤔';
    }

    return Scaffold(
      body: SizedBox.expand(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [subjectColor, subjectColor.withOpacity(0.75)],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // ── Scrollbarer Inhalt ──────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                    child: Column(
                      children: [
                        // Tutor-Avatar mit Emoji-Reaktion
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                            ),
                            ClipOval(
                              child: Image.asset(
                                'assets/images/tutor_avatar.png',
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Text(
                                  tutorEmoji,
                                  style: const TextStyle(fontSize: 64),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          headline,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 28),

                        // ── Ergebnis-Karte ──────────────────────────────────
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.12),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Text(
                                '$percentage%',
                                style: TextStyle(
                                  fontSize: 60,
                                  fontWeight: FontWeight.bold,
                                  color: percentage >= 80
                                      ? const Color(0xFF2E7D32)
                                      : (percentage >= 60
                                            ? Colors.orange[700]
                                            : Colors.red[600]),
                                ),
                              ),
                              Text(
                                '$correct von $total richtig',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                              if (retriedCorrectly.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  '${retriedCorrectly.length}× beim Nochmal-Versuch geschafft 🔄',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.orange[700],
                                  ),
                                ),
                              ],
                              Divider(height: 28, color: Colors.grey[200]),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.bolt_rounded,
                                    color: Colors.amber[600],
                                    size: 22,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '+$earnedXP XP',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber[700],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // ── Falsch-beantwortete Fragen ──────────────────────
                        if (wrongQuestions.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      '📚',
                                      style: TextStyle(fontSize: 18),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Noch zu üben (${wrongQuestions.length})',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                ...wrongQuestions.map(
                                  (q) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade50,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: Colors.red.shade100,
                                        ),
                                      ),
                                      child: _WrongQuestionTile(
                                        question: q,
                                        child: ref.read(activeChildProvider),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),

                // ── Fixierter Button am unteren Rand ────────────────────────
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    12,
                    24,
                    24 + MediaQuery.of(context).padding.bottom,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: subjectColor,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 4,
                      ),
                      child: const Text(
                        'Zurück zum Dashboard',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }
}

// ============================================================================
// TUTOR FREIGESCHALTET DIALOG
// ============================================================================

class _TutorUnlockedDialog extends StatelessWidget {
  final String childName;
  const _TutorUnlockedDialog({required this.childName});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text('🤖', style: TextStyle(fontSize: 46)),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '✨ KI-Tutor freigeschaltet!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Super gemacht, $childName! 🎉\n\nDein KI-Tutor wartet auf dich! '
                'Du kannst ihm jetzt Fragen zu allen Schulfächern stellen – '
                'er erklärt alles auf deine Art.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.9),
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Text('👇', style: TextStyle(fontSize: 18)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tippe auf den Kreis-Button unten!',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        softWrap: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF6A1B9A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'Super, weiter so! 🎉',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// FALSCH-FRAGE KACHEL MIT INLINE-ERKLÄRUNG
// ============================================================================

class _WrongQuestionTile extends ConsumerStatefulWidget {
  final Question question;
  final ChildModel? child;

  const _WrongQuestionTile({required this.question, required this.child});

  @override
  ConsumerState<_WrongQuestionTile> createState() => _WrongQuestionTileState();
}

class _WrongQuestionTileState extends ConsumerState<_WrongQuestionTile> {
  String? _explanation;
  bool _isLoading = false;

  Future<void> _loadExplanation() async {
    if (_isLoading || _explanation != null) return;
    setState(() => _isLoading = true);

    try {
      final aiService = ref.read(vertexAIServiceProvider);
      final child =
          widget.child ??
          ChildModel(
            id: 'tmp',
            name: 'Schüler',
            grade: 5,
            schoolType: 'Gymnasium',
            age: 10,
          );

      final explanation = await aiService.explainWrongAnswer(
        question: widget.question.question,
        correctAnswer: widget.question.answer,
        child: child,
      );

      if (mounted) setState(() => _explanation = explanation);
    } catch (_) {
      if (mounted) {
        setState(
          () => _explanation =
              'Die Erklärung konnte leider nicht geladen werden.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Frage
        Text(
          q.question,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),

        // Richtige Antwort
        Row(
          children: [
            const Icon(Icons.check_circle, size: 14, color: Colors.green),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'Richtig: ${q.answer}',
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.green,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),

        // "Antwort erklären"-Textlink / Ladeindikator / Erklärung
        if (_explanation == null && !_isLoading) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: _loadExplanation,
            child: const Text(
              '💡 Antwort erklären',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF6B21A8),
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
                decorationColor: Color(0xFF6B21A8),
              ),
            ),
          ),
        ] else if (_isLoading) ...[
          const SizedBox(height: 8),
          const Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF6B21A8),
                ),
              ),
              SizedBox(width: 8),
              Text(
                'Wird erklärt …',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ] else if (_explanation != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF3E8FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🤖 ', style: TextStyle(fontSize: 14)),
                Expanded(
                  child: Text(
                    _explanation!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF3B0764),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
