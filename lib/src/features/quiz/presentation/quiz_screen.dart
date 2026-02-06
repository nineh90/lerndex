import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/question_model.dart';
import '../data/quiz_repository.dart';
import '../../auth/presentation/active_child_provider.dart';
import '../../auth/data/profile_repository.dart';

class QuizScreen extends ConsumerStatefulWidget {
  final String subject;

  const QuizScreen({super.key, required this.subject});

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen>
    with SingleTickerProviderStateMixin {
  List<Question> _questions = [];
  int _currentIndex = 0;
  int _correctAnswers = 0;
  bool _isLoading = true;
  bool _showingFeedback = false;
  bool _wasCorrect = false;
  bool _isFinished = false;

  late AnimationController _feedbackController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
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

    final questions = await ref.read(quizRepositoryProvider).loadQuizForChild(
      subject: widget.subject,
      grade: child.grade,
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
    if (_showingFeedback) return; // Verhindere Doppel-Klicks

    final isCorrect = _questions[_currentIndex].isCorrect(selected);

    setState(() {
      _showingFeedback = true;
      _wasCorrect = isCorrect;
    });

    if (isCorrect) _correctAnswers++;

    // Feedback-Animation
    _feedbackController.forward().then((_) {
      _feedbackController.reverse();
    });

    // 1.5 Sekunden Feedback anzeigen
    await Future.delayed(const Duration(milliseconds: 1500));

    if (!mounted) return;

    setState(() => _showingFeedback = false);

    // Nächste Frage oder Erfolgsscreen
    if (_currentIndex < _questions.length - 1) {
      setState(() => _currentIndex++);
    } else {
      _finishQuiz();
    }
  }

  void _finishQuiz() async {
    setState(() => _isFinished = true);

    // Belohnungen vergeben
    final child = ref.read(activeChildProvider);
    if (child != null) {
      final leveledUp = await ref.read(profileRepositoryProvider).awardMissionReward(
        child.id,
        correctAnswers: _correctAnswers,
        totalQuestions: _questions.length,
      );

      // Level-Up-Snackbar anzeigen
      if (leveledUp && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 LEVEL UP! Du bist aufgestiegen!'),
            backgroundColor: Colors.amber,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
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
          // Haupt-Content
          Column(
            children: [
              // Fortschrittsbalken
              _buildProgressHeader(),

              // Frage
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

          // Feedback-Overlay
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
        child: _AnswerButton(
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
          color: (_wasCorrect ? Colors.green : Colors.red)
              .withOpacity(_fadeAnimation.value * 0.9),
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
    final earnedXP = _correctAnswers;
    final earnedStars = _correctAnswers * 2;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_getSubjectColor(), _getSubjectColor().withOpacity(0.7)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.emoji_events, size: 120, color: Colors.amber),
                const SizedBox(height: 20),
                const Text(
                  'Super gemacht!',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 40),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$percentage%',
                        style: TextStyle(
                          fontSize: 60,
                          fontWeight: FontWeight.bold,
                          color: percentage >= 80 ? Colors.green : Colors.orange,
                        ),
                      ),
                      Text(
                        '$_correctAnswers von ${_questions.length} richtig',
                        style: const TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      const Divider(height: 40),
                      _RewardRow(
                        icon: Icons.star,
                        text: '+$earnedStars Sterne',
                        color: Colors.amber,
                      ),
                      const SizedBox(height: 12),
                      _RewardRow(
                        icon: Icons.flash_on,
                        text: '+$earnedXP XP',
                        color: Colors.orange,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _getSubjectColor(),
                    padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text(
                    'Zurück zum Dashboard',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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

// Hilfswidge: Antwort-Button
class _AnswerButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final Color color;

  const _AnswerButton({
    required this.text,
    this.onPressed,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          padding: const EdgeInsets.all(20),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(
              color: onPressed == null ? Colors.grey.shade300 : color.withOpacity(0.3),
              width: 2,
            ),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

// Hilfswidge: Belohnungs-Zeile
class _RewardRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _RewardRow({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 12),
        Text(
          text,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}