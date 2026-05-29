import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/data/auth_repository.dart';
import '../auth/domain/child_model.dart';
import '../auth/presentation/login_screen.dart';
import '../auth/presentation/setup_dialog.dart';
import '../auth/presentation/family_dashboard_screen.dart';
import '../quiz/data/ai_question_cache_repository.dart';
import '../quiz/data/quiz_prefetch_service.dart';
import '../../tutorial_provider.dart';
// NEU: Subscription
import '../subscription/data/subscription_provider.dart';

// ============================================================================
// LERNDEX SPLASH SCREEN
//
// Zeigt eine kindgerechte Animation beim App-Start.
// Gleichzeitig werden im Hintergrund alle Kinder + alle Fächer parallel
// gecacht, sodass das Quiz beim ersten Tippen sofort startet.
// ============================================================================

class LerndexSplashScreen extends ConsumerStatefulWidget {
  const LerndexSplashScreen({super.key});

  @override
  ConsumerState<LerndexSplashScreen> createState() =>
      _LerndexSplashScreenState();
}

class _LerndexSplashScreenState extends ConsumerState<LerndexSplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoCtrl;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;

  late AnimationController _particleCtrl;

  late AnimationController _textCtrl;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;

  late AnimationController _twinkleCtrl;

  final List<_FloatingItem> _particles = [];
  final _random = math.Random();

  String _statusText = 'Starte Lerndex...';
  bool _isNavigating = false;

  // Echter Fortschritt: wird pro fertigem Fach erhöht (0.0 – 1.0).
  // TweenAnimationBuilder animiert den Sprung weich.
  double _progress = 0.0;
  int _totalSubjects = 0;
  int _doneSubjects = 0;

  // Anteil am Balken der für Auth + Kinder laden reserviert ist
  static const double _bootstrapShare = 0.12;

  static const _bgGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3B0764), Color(0xFF6B21A8), Color(0xFF7C3AED)],
  );

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _generateParticles();
    _startSplash();
  }

  void _initAnimations() {
    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _logoScale = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut));
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoCtrl,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
      ),
    );

    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    _textCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _textOpacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _textCtrl, curve: Curves.easeOut));
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _textCtrl, curve: Curves.easeOut));

    _twinkleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  void _generateParticles() {
    const emojis = ['⭐', '📚', '✨', '🎓', '💡', '🌟', '📖', '🎯', '🚀', '🦋'];
    for (int i = 0; i < 18; i++) {
      _particles.add(
        _FloatingItem(
          emoji: emojis[_random.nextInt(emojis.length)],
          x: _random.nextDouble(),
          y: _random.nextDouble(),
          size: 18 + _random.nextDouble() * 22,
          speed: 0.3 + _random.nextDouble() * 0.7,
          phase: _random.nextDouble(),
          amplitude: 0.015 + _random.nextDouble() * 0.025,
        ),
      );
    }
  }

  Future<void> _startSplash() async {
    await Future.delayed(const Duration(milliseconds: 100));
    _logoCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 500));
    _textCtrl.forward();
    await _initializeAndNavigate();
  }

  Future<void> _initializeAndNavigate() async {
    if (_isNavigating) return;

    const minSplashDuration = Duration(milliseconds: 1800);
    final startTime = DateTime.now();

    String destination = 'login';

    try {
      final authRepo = ref.read(authRepositoryProvider);
      final user = authRepo.currentUser;

      _setProgress(_bootstrapShare * 0.5, 'Anmeldung prüfen...');

      if (user == null) {
        destination = 'login';
        _setProgress(1.0, 'Los geht\'s! ✨');
      } else {
        // NEU: RevenueCat User identifizieren
        final subscriptionService = ref.read(subscriptionServiceProvider);
        await subscriptionService.identifyUser(user.uid);

        // NEU: Abo-Status laden & in Provider speichern
        _setProgress(_bootstrapShare * 0.7, 'Abo prüfen...');
        await ref.read(subscriptionStatusProvider.notifier).refresh();

        final onboardingDone = await authRepo.isOnboardingComplete();
        _setProgress(_bootstrapShare, 'Lade deine Kinder...');

        if (!onboardingDone) {
          destination = 'onboarding';
          _setProgress(1.0, 'Los geht\'s! ✨');
        } else {
          destination = 'dashboard';
          await _prefetchAllChildren(user.uid);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Splash init error: $e');
      destination = 'login';
      _setProgress(1.0, 'Weiter...');
    }

    // Mindestzeit nur wenn Prefetch sehr schnell war (alles gecacht)
    final elapsed = DateTime.now().difference(startTime);
    final remaining = minSplashDuration - elapsed;
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }

    if (!mounted || _isNavigating) return;
    _isNavigating = true;
    _navigate(destination);
  }

  /// Lädt alle Kinder des Users aus Firestore und startet
  /// den parallelen Quiz-Prefetch für alle Kinder + Fächer.
  Future<void> _prefetchAllChildren(String userId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('children')
          .get();

      final children = snapshot.docs
          .map((doc) => ChildModel.fromMap(doc.data(), doc.id))
          .toList();

      if (children.isEmpty) {
        _setProgress(1.0, 'Alles bereit! ✨');
        return;
      }

      // Gesamtanzahl der Fach-Slots berechnen damit der Balken
      // gleichmäßig pro fertigem Fach wächst.
      final subjectCounts = children.map(
        (c) => QuizPrefetchService.subjectCountForChild(c),
      );
      _totalSubjects = subjectCounts.fold(0, (a, b) => a + b);
      _doneSubjects = 0;

      const prefetchShare = 1.0 - _bootstrapShare;

      _setProgress(
        _bootstrapShare,
        children.length == 1
            ? 'Bereite Fragen für ${children.first.name} vor...'
            : 'Bereite Fragen für ${children.length} Kinder vor...',
      );

      final cache = ref.read(aiQuestionCacheRepositoryProvider);

      await QuizPrefetchService.prefetchAllChildren(
        userId: userId,
        children: children,
        cache: cache,
        onSubjectDone: (childName, subject) {
          if (!mounted) return;
          _doneSubjects++;
          final p =
              _bootstrapShare +
              prefetchShare *
                  (_doneSubjects / (_totalSubjects > 0 ? _totalSubjects : 1));
          _setProgress(p, '$subject für $childName bereit ✓');
        },
      );

      _setProgress(1.0, 'Alles bereit! ✨');
    } catch (e) {
      debugPrint('⚠️ Prefetch-Fehler im Splash: $e');
      _setProgress(1.0, 'Weiter...');
    }
  }

  void _setProgress(double value, String status) {
    if (!mounted) return;
    setState(() {
      _progress = value.clamp(0.0, 1.0);
      _statusText = status;
    });
  }

  Future<void> _navigate(String destination) async {
    if (!mounted) return;
    Widget target;
    switch (destination) {
      case 'onboarding':
        target = const SetupDialog();
        break;
      case 'dashboard':
        // Tutorial ggf. fortsetzen wenn noch nicht abgeschlossen.
        // await nötig damit State gesetzt ist bevor FamilyDashboard baut.
        await ref.read(tutorialProvider.notifier).startTutorial();
        target = const FamilyDashboardScreen();
        break;
      default:
        target = const LoginScreen();
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => target,
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _particleCtrl.dispose();
    _textCtrl.dispose();
    _twinkleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: _bgGradient),
        child: Stack(
          children: [
            ..._buildBackgroundStars(size),
            AnimatedBuilder(
              animation: _particleCtrl,
              builder: (_, __) => Stack(
                children: _particles
                    .map((p) => _buildParticle(p, size))
                    .toList(),
              ),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),
                  AnimatedBuilder(
                    animation: _logoCtrl,
                    builder: (_, __) => Opacity(
                      opacity: _logoOpacity.value,
                      child: Transform.scale(
                        scale: _logoScale.value,
                        child: _buildLogo(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SlideTransition(
                    position: _textSlide,
                    child: FadeTransition(
                      opacity: _textOpacity,
                      child: _buildTextSection(),
                    ),
                  ),
                  const Spacer(flex: 2),
                  FadeTransition(
                    opacity: _textOpacity,
                    child: _buildProgressBar(),
                  ),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: _twinkleCtrl,
      builder: (_, __) => Image.asset(
        'assets/images/lerndex_logo.png',
        width: 220,
        height: 220,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildTextSection() {
    return Column(
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Colors.white, Color(0xFFE9D5FF)],
          ).createShader(bounds),
          child: const Text(
            'Lerndex',
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Lernen macht Spaß! 🚀',
          style: TextStyle(
            fontSize: 16,
            color: Colors.white.withValues(alpha: 0.8),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 60),
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: _progress),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            builder: (_, value, __) => ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFFC084FC),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _statusText,
              key: ValueKey(_statusText),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildBackgroundStars(Size size) {
    final stars = [
      const _StarData(0.1, 0.08, 3),
      const _StarData(0.85, 0.12, 2),
      const _StarData(0.6, 0.05, 4),
      const _StarData(0.25, 0.2, 2),
      const _StarData(0.92, 0.35, 3),
      const _StarData(0.05, 0.45, 2),
      const _StarData(0.75, 0.55, 3),
      const _StarData(0.4, 0.08, 2),
      const _StarData(0.55, 0.88, 3),
      const _StarData(0.15, 0.75, 2),
      const _StarData(0.88, 0.78, 4),
      const _StarData(0.33, 0.92, 2),
      const _StarData(0.7, 0.25, 3),
      const _StarData(0.48, 0.42, 2),
    ];

    return stars.map((s) {
      return AnimatedBuilder(
        animation: _twinkleCtrl,
        builder: (_, __) {
          final opacity =
              (0.3 +
                      0.5 *
                          math
                              .sin((_twinkleCtrl.value + s.phase) * math.pi)
                              .abs())
                  .clamp(0.0, 1.0);
          return Positioned(
            left: s.x * size.width,
            top: s.y * size.height,
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: s.size,
                height: s.size,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        },
      );
    }).toList();
  }

  Widget _buildParticle(_FloatingItem p, Size size) {
    final t = (_particleCtrl.value + p.phase) % 1.0;
    final y = (p.y - t * p.speed) % 1.0;
    final xOffset = math.sin(t * 2 * math.pi + p.phase * math.pi) * p.amplitude;
    final x = (p.x + xOffset).clamp(0.0, 0.95);

    double opacity;
    if (y > 0.85) {
      opacity = (1.0 - y) / 0.15;
    } else if (y < 0.05) {
      opacity = y / 0.05;
    } else {
      opacity = 0.7;
    }

    return Positioned(
      left: x * size.width,
      top: y * size.height,
      child: Opacity(
        opacity: opacity.clamp(0.0, 0.7),
        child: Text(p.emoji, style: TextStyle(fontSize: p.size)),
      ),
    );
  }
}

class _FloatingItem {
  final String emoji;
  final double x;
  final double y;
  final double size;
  final double speed;
  final double phase;
  final double amplitude;

  const _FloatingItem({
    required this.emoji,
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.phase,
    required this.amplitude,
  });
}

class _StarData {
  final double x;
  final double y;
  final double size;
  double get phase => x + y;

  const _StarData(this.x, this.y, this.size);
}
