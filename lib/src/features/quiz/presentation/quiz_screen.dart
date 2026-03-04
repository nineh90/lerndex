import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex/src/features/generated_tasks/data/generated_task_repository.dart';
import '../domain/question_model.dart';
import '../../auth/presentation/active_child_provider.dart';
import '../../auth/data/profile_repository.dart';
import '../../rewards/data/xp_service.dart';
import '../../rewards/data/reward_service.dart';
import '../../rewards/presentation/reward_unlocked_dialog.dart';
import '../../auth/domain/child_model.dart';
import '../../auth/data/auth_repository.dart';
import '../../learning_time/learning_time_tracker.dart';
import '../data/extended_quiz_repository.dart';
import 'widgets/answer_button.dart';
import 'widgets/reward_row.dart';

class QuizScreen extends ConsumerStatefulWidget {
  final String subject;

  const QuizScreen({super.key, required this.subject});

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen>
    with SingleTickerProviderStateMixin {
  // Variablen
  List<Question> _questions = [];
  int _currentIndex = 0;
  int _correctAnswers = 0;
  bool _isLoading = true;
  bool _showingFeedback = false;
  bool _wasCorrect = false;
  bool _isFinished = false;

  // Falsch beantwortete Fragen tracken
  final List<_WrongAnswer> _wrongAnswers = [];
  String? _selectedWrongAnswer; // Was der Schüler falsch gewählt hatte

  late AnimationController _feedbackController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  LearningTimeTracker? _timeTracker;

  @override
  void initState() {
    super.initState();

    // ⏱️ ZEIT-TRACKER INITIALISIEREN
    final child = ref.read(activeChildProvider);
    final user = ref.read(authStateChangesProvider).value;

    if (child != null && user != null) {
      _timeTracker = LearningTimeTracker(userId: user.uid, childId: child.id);
      _timeTracker!.startTracking();
    }

    _setupAnimations();
    _loadQuestions();
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

  Future<void> _loadQuestions() async {
    final child = ref.read(activeChildProvider);
    if (child == null) return;

    final user = ref.read(authStateChangesProvider).value;
    final userId = user?.uid ?? '';

    final questions = await ref
        .read(extendedQuizRepositoryProvider)
        .loadQuizForChild(
          userId: userId,
          childId: child.id,
          child: child,
          subject: widget.subject,
          questionCount: 5,
        );

    if (mounted) {
      setState(() {
        _questions = questions;
        _isLoading = false;
      });
    }
  }

  void _checkAnswer(String selected) async {
    if (_showingFeedback) return;

    final isCorrect = _questions[_currentIndex].isCorrect(selected);

    setState(() {
      _showingFeedback = true;
      _wasCorrect = isCorrect;
      _selectedWrongAnswer = isCorrect ? null : selected;
    });

    // Falsch beantwortete Fragen speichern
    if (!isCorrect) {
      _wrongAnswers.add(
        _WrongAnswer(
          question: _questions[_currentIndex],
          selectedAnswer: selected,
        ),
      );
    }

    if (isCorrect) {
      _correctAnswers++;

      final xpService = ref.read(xpServiceProvider);
      final activeChild = ref.read(activeChildProvider);
      final user = ref.read(authStateChangesProvider).value;

      final currentQuestion = _questions[_currentIndex];
      if (currentQuestion.isParentTask) {
        final user = ref.read(authStateChangesProvider).value;
        if (user != null) {
          ref
              .read(generatedTaskRepositoryProvider)
              .markQuestionAnsweredCorrectly(
                userId: user.uid,
                parentTaskRef: currentQuestion.parentTaskRef!,
              );
          print(
            '✅ Eltern-Aufgabe als beantwortet markiert: ${currentQuestion.parentTaskRef}',
          );
        }
      }

      if (activeChild != null && user != null) {
        try {
          print('🔄 Speichere XP für Kind: ${activeChild.name}...');

          final xpResult = await xpService.addXP(
            userId: user.uid,
            childId: activeChild.id,
            xpToAdd: 5,
          );

          print(
            '✅ XP gespeichert: ${xpResult.newXP} XP, Level: ${xpResult.newLevel}',
          );

          if (xpResult.leveledUp && mounted) {
            print('🎉 LEVEL UP zu Level ${xpResult.newLevel}');

            _feedbackController.forward().then((_) {
              _feedbackController.reverse();
            });

            await Future.delayed(const Duration(milliseconds: 500));

            if (!mounted) return;

            setState(() => _showingFeedback = false);

            await _showLevelUpDialogImmediate(
              newLevel: xpResult.newLevel,
              childName: activeChild.name,
              userId: user.uid,
              childId: activeChild.id,
            );

            if (!mounted) return;

            if (_currentIndex < _questions.length - 1) {
              setState(() => _currentIndex++);
            } else {
              _finishQuiz();
            }

            return;
          }
        } catch (e, stackTrace) {
          print('❌ Fehler beim Speichern von XP: $e');
          print('Stack: $stackTrace');

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('XP konnten nicht gespeichert werden'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    }

    // Normaler Feedback-Flow
    _feedbackController.forward().then((_) {
      _feedbackController.reverse();
    });

    await Future.delayed(const Duration(milliseconds: 1500));

    if (!mounted) return;

    setState(() => _showingFeedback = false);

    if (_currentIndex < _questions.length - 1) {
      setState(() => _currentIndex++);
    } else {
      _finishQuiz();
    }
  }

  Future<void> _showLevelUpDialogImmediate({
    required int newLevel,
    required String childName,
    required String userId,
    required String childId,
  }) async {
    print('🎯 _showLevelUpDialogImmediate aufgerufen');

    if (!mounted) return;

    try {
      final rewardService = ref.read(rewardServiceProvider);

      final reward = await rewardService.createLevelUpReward(
        userId: userId,
        childId: childId,
        level: newLevel,
      );

      print('✅ Belohnung erstellt: ${reward?.title ?? "null"}');

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

      print('✅ Dialog geschlossen');
    } catch (e, stackTrace) {
      print('❌ Fehler in _showLevelUpDialogImmediate: $e');
      print('Stack: $stackTrace');

      if (mounted) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('🎉 Level Up!'),
            content: Text('Du hast Level $newLevel erreicht!\n\n($e)'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Super!'),
              ),
            ],
          ),
        );
      }
    }
  }

  void _finishQuiz() async {
    setState(() => _isFinished = true);

    final child = ref.read(activeChildProvider);
    final user = ref.read(authStateChangesProvider).value;

    if (child != null && user != null) {
      try {
        print('📊 Quiz beendet - speichere Daten...');

        final xpService = ref.read(xpServiceProvider);
        final isPerfect = _correctAnswers == _questions.length;

        // 1️⃣ Streak aktualisieren — ZUERST, bevor lastLearningDate
        // durch saveTime() überschrieben wird! Sonst würde der erste
        // Lerntag nie auf Streak=1 gesetzt werden.
        final newStreak = await xpService.updateStreak(
          userId: user.uid,
          childId: child.id,
        );
        print('✅ Streak aktualisiert: $newStreak Tage');

        // 2️⃣ Zeit speichern
        if (_timeTracker != null) {
          _timeTracker!.stopTracking();
          await _timeTracker!.saveTime();
          print('✅ Lernzeit gespeichert: ${_timeTracker!.formattedTime}');
        }

        // 3️⃣ Quiz-Stats aktualisieren
        await xpService.updateQuizStats(
          userId: user.uid,
          childId: child.id,
          isPerfect: isPerfect,
        );
        print('✅ Quiz-Statistiken aktualisiert (Perfect: $isPerfect)');

        // 4️⃣ Sterne vergeben
        await ref
            .read(profileRepositoryProvider)
            .updateStars(child.id, _correctAnswers * 2);
        print('✅ Sterne vergeben: ${_correctAnswers * 2}');

        // 5️⃣ Kind-Daten laden und Streak-Wert überschreiben
        final rewardService = ref.read(rewardServiceProvider);
        ChildModel? updatedChild = await xpService.getChild(
          userId: user.uid,
          childId: child.id,
        );

        if (updatedChild != null) {
          // ✅ KRITISCH: Streak-Wert aus updateStreak() nehmen, nicht aus getChild()
          updatedChild = updatedChild.copyWith(streak: newStreak);

          // 6️⃣ Belohnungs-Check mit korrektem Streak-Wert
          final unlockedRewards = await rewardService.checkAndApproveRewards(
            userId: user.uid,
            child: updatedChild,
            isPerfectQuiz: isPerfect,
          );

          if (unlockedRewards.isNotEmpty && mounted) {
            print('🎁 ${unlockedRewards.length} Belohnungen freigeschaltet!');

            final streakRewards = unlockedRewards
                .where((r) => r.trigger.toString().contains('streak'))
                .toList();
            if (streakRewards.isNotEmpty) {
              print(
                '🔥 Streak-Belohnung(en): ${streakRewards.map((r) => r.title).join(', ')}',
              );
            }

            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '🎁 ${unlockedRewards.length} neue Belohnung(en) freigeschaltet!',
                    ),
                    backgroundColor: Colors.amber,
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            });
          }

          // 7️⃣ Streak-Meilenstein-Feedback
          if (mounted && _isStreakMilestone(newStreak)) {
            Future.delayed(const Duration(milliseconds: 800), () {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Text('🔥', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 8),
                        Text(
                          '$newStreak Tage Streak! Weiter so!',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.orange,
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            });
          }
        }
      } catch (e, stackTrace) {
        print('❌ Fehler beim Speichern der Quiz-Daten: $e');
        print('Stack: $stackTrace');
      }
    }
  }

  bool _isStreakMilestone(int streak) {
    return streak == 3 ||
        streak == 7 ||
        streak == 14 ||
        streak == 30 ||
        streak == 50 ||
        streak == 100;
  }

  @override
  void dispose() {
    // ⏱️ Zeit wurde bereits in _finishQuiz gespeichert — nur cleanup
    _timeTracker?.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildLoadingScreen();
    if (_questions.isEmpty) return _buildNoQuestionsScreen();
    if (_isFinished) return _buildSuccessScreen();

    final currentQuestion = _questions[_currentIndex];

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
              _buildProgressHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      _buildQuestionCard(currentQuestion),
                      const SizedBox(height: 40),
                      ..._buildAnswerButtons(currentQuestion),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_showingFeedback) _buildFeedbackOverlay(),
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

  Widget _buildNoQuestionsScreen() {
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
              'Für ${widget.subject} gibt es noch keine Fragen.',
              style: const TextStyle(color: Colors.grey),
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

  Widget _buildProgressHeader() {
    return Container(
      color: _getSubjectColor(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Frage ${_currentIndex + 1} von ${_questions.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '$_correctAnswers richtig',
                style: const TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: (_currentIndex + 1) / _questions.length,
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
      child: Text(
        question.question,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          height: 1.4,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  List<Widget> _buildAnswerButtons(Question question) {
    return question.options.map((option) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: AnswerButton(
          text: option,
          onPressed: _showingFeedback ? null : () => _checkAnswer(option),
          color: _getSubjectColor(),
        ),
      );
    }).toList();
  }

  Widget _buildFeedbackOverlay() {
    return AnimatedBuilder(
      animation: _feedbackController,
      builder: (context, child) {
        return Container(
          color: (_wasCorrect ? Colors.green : Colors.red).withOpacity(
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
                  _wasCorrect ? Icons.check : Icons.close,
                  size: 80,
                  color: _wasCorrect ? Colors.green : Colors.red,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSuccessScreen() {
    final percentage = (_correctAnswers / _questions.length * 100).round();
    final earnedXP = _correctAnswers * 5;
    final earnedStars = _correctAnswers * 2;
    final hasWrong = _wrongAnswers.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_getSubjectColor(), _getSubjectColor().withOpacity(0.4)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Icon(
                  hasWrong ? Icons.school : Icons.emoji_events,
                  size: 80,
                  color: Colors.amber,
                ),
                const SizedBox(height: 12),
                Text(
                  hasWrong ? 'Quiz beendet! 💪' : 'Super gemacht! 🎉',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),

                // ── Ergebniskarte ─────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$percentage%',
                        style: TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.bold,
                          color: percentage >= 80
                              ? Colors.green
                              : Colors.orange,
                        ),
                      ),
                      Text(
                        '$_correctAnswers von ${_questions.length} richtig',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                      const Divider(height: 32),
                      RewardRow(
                        icon: Icons.star,
                        text: '+$earnedStars Sterne',
                        color: Colors.amber,
                      ),
                      const SizedBox(height: 10),
                      RewardRow(
                        icon: Icons.flash_on,
                        text: '+$earnedXP XP',
                        color: Colors.orange,
                      ),
                    ],
                  ),
                ),

                // ── Falsch beantwortete Fragen ────────────────────────────
                if (hasWrong) ...[
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.lightbulb_outline,
                              color: Colors.orange,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_wrongAnswers.length} Frage${_wrongAnswers.length > 1 ? "n" : ""} zum Nachlernen',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ..._wrongAnswers.map(
                          (wa) => _WrongAnswerCard(
                            wrongAnswer: wa,
                            subjectColor: _getSubjectColor(),
                            subject: widget.subject,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Nochmal üben Button ───────────────────────────────
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _retryWrongAnswers,
                      icon: const Icon(Icons.replay),
                      label: Text(
                        'Falsche Fragen wiederholen (${_wrongAnswers.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _getSubjectColor(),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: _getSubjectColor(), width: 2),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],

                // ── Zurück Button ─────────────────────────────────────────
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: _getSubjectColor(),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 2,
                    ),
                    child: const Text(
                      'Zurück zum Dashboard',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _retryWrongAnswers() {
    setState(() {
      _questions = _wrongAnswers.map((wa) => wa.question).toList()..shuffle();
      _wrongAnswers.clear();
      _currentIndex = 0;
      _correctAnswers = 0;
      _isFinished = false;
      _showingFeedback = false;
      _wasCorrect = false;
    });
  }

  Color _getSubjectColor() {
    switch (widget.subject.toLowerCase()) {
      case 'mathe':
        return Colors.orange;
      case 'deutsch':
        return Colors.redAccent;
      case 'englisch':
        return Colors.blue;
      case 'sachkunde':
        return Colors.green;
      default:
        return Colors.deepPurple;
    }
  }
}

// ============================================================================
// DATENMODELL: Falsch beantwortete Frage
// ============================================================================

class _WrongAnswer {
  final Question question;
  final String selectedAnswer;

  const _WrongAnswer({required this.question, required this.selectedAnswer});
}

// ============================================================================
// WIDGET: Karte für eine falsch beantwortete Frage mit KI-Erklärung
// ============================================================================

class _WrongAnswerCard extends StatefulWidget {
  final _WrongAnswer wrongAnswer;
  final Color subjectColor;
  final String subject;

  const _WrongAnswerCard({
    required this.wrongAnswer,
    required this.subjectColor,
    required this.subject,
  });

  @override
  State<_WrongAnswerCard> createState() => _WrongAnswerCardState();
}

class _WrongAnswerCardState extends State<_WrongAnswerCard> {
  bool _expanded = false;
  String? _explanation;
  bool _loadingExplanation = false;

  Future<void> _loadExplanation() async {
    if (_explanation != null) return;
    setState(() => _loadingExplanation = true);

    try {
      final q = widget.wrongAnswer.question;
      final prompt =
          'Du bist ein freundlicher Schullehrer. Ein Schüler hat folgende Frage falsch beantwortet:\n\n'
          'Fach: ${widget.subject}\n'
          'Frage: ${q.question}\n'
          'Richtige Antwort: ${q.answer}\n'
          'Schüler hat gewählt: ${widget.wrongAnswer.selectedAnswer}\n\n'
          'Erkläre kurz und klar auf Deutsch (2-4 Sätze, altersgerecht), '
          'warum die richtige Antwort korrekt ist und warum die gewählte Antwort falsch war. '
          'Sei ermutigend und positiv.';

      final response = await _callGeminiApi(prompt);
      if (mounted) {
        setState(() {
          _explanation = response;
          _loadingExplanation = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _explanation = 'Erklärung konnte nicht geladen werden.';
          _loadingExplanation = false;
        });
      }
    }
  }

  Future<String> _callGeminiApi(String prompt) async {
    final model = FirebaseAI.vertexAI().generativeModel(
      model: 'gemini-2.0-flash',
      generationConfig: GenerationConfig(
        temperature: 0.7,
        maxOutputTokens: 300,
      ),
    );
    final response = await model.generateContent([Content.text(prompt)]);
    return response.text ?? 'Keine Erklärung verfügbar.';
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.wrongAnswer.question;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        children: [
          // ── Frage + Antworten ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  q.question,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                _AnswerChip(
                  label: 'Deine Antwort: ${widget.wrongAnswer.selectedAnswer}',
                  color: Colors.red,
                  icon: Icons.close,
                ),
                const SizedBox(height: 4),
                _AnswerChip(
                  label: 'Richtig: ${q.answer}',
                  color: Colors.green,
                  icon: Icons.check,
                ),
              ],
            ),
          ),

          // ── Erklärung anzeigen ─────────────────────────────────────────
          InkWell(
            onTap: () {
              setState(() => _expanded = !_expanded);
              if (_expanded && _explanation == null) _loadExplanation();
            },
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(14),
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: widget.subjectColor.withOpacity(0.12),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_less : Icons.lightbulb_outline,
                    size: 18,
                    color: widget.subjectColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _expanded ? 'Erklärung ausblenden' : 'Erklärung anzeigen',
                    style: TextStyle(
                      color: widget.subjectColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: _loadingExplanation
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'KI erklärt...',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : Text(
                      _explanation ?? '',
                      style: const TextStyle(fontSize: 13, height: 1.5),
                    ),
            ),
        ],
      ),
    );
  }
}

class _AnswerChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _AnswerChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
