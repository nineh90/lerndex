import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// SECONDARY ONBOARDING SCREEN
//
// Wird genau einmal angezeigt wenn ein Schüler zum ersten Mal das
// Teenager-Dashboard öffnet (Klasse 5+).
// Danach wird in SharedPreferences ein Flag gesetzt: niemals wieder zeigen.
// ============================================================================

/// Prüft ob der Onboarding-Screen für dieses Kind bereits gesehen wurde.
Future<bool> shouldShowSecondaryOnboarding(String childId) async {
  final prefs = await SharedPreferences.getInstance();
  return !(prefs.getBool('secondary_onboarding_seen_$childId') ?? false);
}

/// Markiert den Onboarding-Screen als gesehen.
Future<void> markSecondaryOnboardingSeen(String childId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('secondary_onboarding_seen_$childId', true);
}

class SecondaryOnboardingScreen extends StatefulWidget {
  final String childName;
  final String childId;
  final VoidCallback onDone;

  const SecondaryOnboardingScreen({
    super.key,
    required this.childName,
    required this.childId,
    required this.onDone,
  });

  @override
  State<SecondaryOnboardingScreen> createState() =>
      _SecondaryOnboardingScreenState();
}

class _SecondaryOnboardingScreenState extends State<SecondaryOnboardingScreen>
    with TickerProviderStateMixin {
  int _currentPage = 0;
  final _pageController = PageController();

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  // Onboarding-Seiten
  static const _pages = [
    _OnboardingPage(
      emoji: '🎓',
      title: 'Dein neues Dashboard!',
      subtitle:
          'Du bist jetzt auf der weiterführenden Schule – dein Dashboard wurde für dich neu gestaltet.',
      color: Color(0xFF5C6BC0),
    ),
    _OnboardingPage(
      emoji: '🎨',
      title: 'Mach es zu deinem',
      subtitle:
          'Wähle dein Farbtheme und lade ein eigenes Hintergrundbild hoch. Tippe auf das Paletten-Symbol oben rechts.',
      color: Color(0xFF8E24AA),
    ),
    _OnboardingPage(
      emoji: '📊',
      title: 'Deine Statistiken',
      subtitle:
          'Alle deine Lernfortschritte, Streak und Quiz-Ergebnisse auf einen Blick – im Statistik-Tab.',
      color: Color(0xFF0097A7),
    ),
    _OnboardingPage(
      emoji: '🤖',
      title: 'KI-Tutor',
      subtitle:
          'Hast du eine Frage zu einem Thema? Tippe auf den Button in der Mitte – dein persönlicher KI-Tutor hilft dir.',
      color: Color(0xFF2E7D32),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_currentPage];
    final isLast = _currentPage == _pages.length - 1;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        body: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [page.color, page.color.withValues(alpha: 0.7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // ── Skip-Button ─────────────────────────────────────────
                Align(
                  alignment: Alignment.topRight,
                  child: TextButton(
                    onPressed: _finish,
                    child: Text(
                      'Überspringen',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),

                // ── Page View ───────────────────────────────────────────
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (i) {
                      HapticFeedback.selectionClick();
                      _fadeCtrl.forward(from: 0);
                      setState(() => _currentPage = i);
                    },
                    itemCount: _pages.length,
                    itemBuilder: (_, i) => _buildPage(_pages[i]),
                  ),
                ),

                // ── Punkte-Indikator ────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _pages.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _currentPage ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _currentPage
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // ── Weiter / Los geht's Button ──────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: GestureDetector(
                    onTap: isLast ? _finish : _nextPage,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            isLast ? 'Los geht\'s! 🚀' : 'Weiter',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: page.color,
                            ),
                          ),
                          if (!isLast) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_rounded,
                              color: page.color,
                              size: 20,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPage(_OnboardingPage page) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Großes Emoji
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.5, end: 1.0),
              duration: const Duration(milliseconds: 500),
              curve: Curves.elasticOut,
              builder: (_, v, _) => Transform.scale(
                scale: v,
                child: Text(page.emoji, style: const TextStyle(fontSize: 88)),
              ),
            ),
            const SizedBox(height: 36),

            // Titel
            Text(
              page.title,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // Beschreibung
            Text(
              page.subtitle,
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withValues(alpha: 0.85),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _finish() async {
    HapticFeedback.mediumImpact();
    await markSecondaryOnboardingSeen(widget.childId);
    widget.onDone();
  }
}

// ── Datenklasse für eine Onboarding-Seite ────────────────────────────────────

class _OnboardingPage {
  final String emoji;
  final String title;
  final String subtitle;
  final Color color;

  const _OnboardingPage({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.color,
  });
}
