import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lerndex/src/features/auth/data/auth_repository.dart';
import 'package:lerndex/src/features/auth/domain/child_model.dart';
import 'package:lerndex/src/features/rewards/data/xp_service.dart';
import 'package:lerndex/src/features/parent_dashboard/presentation/tracing_game_screen.dart';
import 'package:lerndex/src/features/parent_dashboard/presentation/widgets/early_learner_rewards_screen.dart';
import 'package:lerndex/src/features/tts/tts_provider.dart';
import 'package:lerndex/src/features/rewards/data/system_rewards_initializer.dart';
import 'avatar_settings_sheet.dart';
import 'rewards_count_provider.dart';
import 'early_learner_quiz_screen.dart';
import 'math_quiz_screen.dart';
import 'letter_quiz_screen.dart';
import 'color_shape_quiz_screen.dart';

// ============================================================================
// EARLY LEARNER DASHBOARD – Klasse 1–2 (v2: Carousel-Layout)
//
// Änderungen gegenüber v1:
// • Horizontales PageView-Carousel statt 2×2 Grid
// • Kompakterer Header: Avatar links, Name Mitte, TTS-Toggle rechts
// • Avatar-Tap → TTS-Begrüßung
// • Fach-Karten: Fullscreen-ähnlich mit riesigem Emoji + Play-Button
// • Page-Indicator Dots unter dem Carousel
// • Tages-Tipp Sektion (Streak / Sterne / Ermutigung)
// • TTS-Integration: Fachname wird beim Swipen vorgelesen
//
// Design-Prinzipien (unverändert):
// • Kein Text der gelesen werden muss (außer dem Namen)
// • Alles durch große Emojis & Farben erkennbar
// • Riesige Tipp-Flächen, kindgerechte Proportionen
// • Navigation: 3 große Icon-Buttons, kein Text nötig
// ============================================================================

class _EarlySubject {
  final String emoji;
  final String label;
  final List<Color> colors;
  final String subject;

  const _EarlySubject({
    required this.emoji,
    required this.label,
    required this.colors,
    required this.subject,
  });
}

const _earlySubjects = [
  _EarlySubject(
    emoji: '🔢',
    label: 'Zahlen',
    colors: [Color(0xFF7E57C2), Color(0xFF512DA8)],
    subject: 'Zahlen',
  ),
  _EarlySubject(
    emoji: '🔤',
    label: 'Buchstaben',
    colors: [Color(0xFFEC407A), Color(0xFF8E24AA)],
    subject: 'Buchstaben',
  ),
  _EarlySubject(
    emoji: '🎨',
    label: 'Farben & Formen',
    colors: [Color(0xFF1E88E5), Color(0xFF00897B)],
    subject: 'FarbenFormen',
  ),

  _EarlySubject(
    emoji: '✏️',
    label: 'Buchstaben malen',
    colors: [Color(0xFFFF7043), Color(0xFFBF360C)],
    subject: 'MalenBuchstaben',
  ),
  _EarlySubject(
    emoji: '🖊️',
    label: 'Zahlen malen',
    colors: [Color(0xFF26A69A), Color(0xFF00695C)],
    subject: 'MalenZahlen',
  ),
];

enum _EarlyTab { home, rewards, stars }

// Alle Fächer anzeigen (Zahlen jetzt mit neuem MathQuizScreen)
const _visibleSubjects = _earlySubjects;

// ============================================================================
// MAIN SCREEN
// ============================================================================

class EarlyLearnerDashboardScreen extends ConsumerStatefulWidget {
  final ChildModel child;

  const EarlyLearnerDashboardScreen({super.key, required this.child});

  @override
  ConsumerState<EarlyLearnerDashboardScreen> createState() =>
      _EarlyLearnerDashboardScreenState();
}

class _EarlyLearnerDashboardScreenState
    extends ConsumerState<EarlyLearnerDashboardScreen>
    with TickerProviderStateMixin {
  _EarlyTab _currentTab = _EarlyTab.home;

  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark, // iOS
      ),
    );
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Systembelohnungen (Achievements) sicherstellen –
    // falls das Kind noch keine hat, werden sie jetzt angelegt.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authStateChangesProvider).value;
      if (user != null) {
        SystemRewardsInitializer().addMissingSystemRewards(
          userId: user.uid,
          childId: widget.child.id,
        );
      }
    });
  }

  @override
  void dispose() {
    _waveController.dispose();
    // Statusleisten-Style zurücksetzen für andere Screens
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rewardsCount =
        ref.watch(availableRewardsCountProvider).valueOrNull ?? 0;

    return PopScope(
      canPop: _currentTab == _EarlyTab.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _currentTab = _EarlyTab.home);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F0FF),
        extendBodyBehindAppBar: true,
        body: _buildBody(),
        bottomNavigationBar: _buildBottomNav(rewardsCount),
      ),
    );
  }

  Widget _buildBody() {
    switch (_currentTab) {
      case _EarlyTab.home:
        return _HomeContent(
          child: widget.child,
          waveController: _waveController,
          onSubjectTap: _openSubject,
          onRewardsTap: () => setState(() => _currentTab = _EarlyTab.rewards),
        );
      case _EarlyTab.rewards:
        return const EarlyLearnerRewardsScreen();
      case _EarlyTab.stars:
        return _StarsContent(child: widget.child);
    }
  }

  void _openSubject(_EarlySubject subject) {
    HapticFeedback.mediumImpact();
    // TTS stoppen bevor wir navigieren
    ref.read(ttsControllerProvider.notifier).stop();

    // Sonderfall: Mal-Spiele (Buchstaben oder Zahlen malen)
    if (subject.subject == 'MalenBuchstaben' ||
        subject.subject == 'MalenZahlen') {
      final mode = subject.subject == 'MalenBuchstaben'
          ? TracingMode.letters
          : TracingMode.numbers;
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, animation, __) =>
              TracingGameScreen(subjectColors: subject.colors, mode: mode),
          transitionsBuilder: (_, animation, __, child) {
            return ScaleTransition(
              scale: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutBack,
              ),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
      return;
    }

    // Zahlen → neuer algorithmischer MathQuizScreen (Klasse 1 & 2)
    if (subject.subject == 'Zahlen') {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, animation, __) => MathQuizScreen(
            grade: widget.child.grade,
            subjectColors: subject.colors,
          ),
          transitionsBuilder: (_, animation, __, child) {
            return ScaleTransition(
              scale: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutBack,
              ),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
      return;
    }

    // Buchstaben → neuer algorithmischer LetterQuizScreen (Klasse 1 & 2)
    if (subject.subject == 'Buchstaben') {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, animation, __) => LetterQuizScreen(
            grade: widget.child.grade,
            subjectColors: subject.colors,
          ),
          transitionsBuilder: (_, animation, __, child) {
            return ScaleTransition(
              scale: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutBack,
              ),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
      return;
    }

    // FarbenFormen → neuer algorithmischer ColorShapeQuizScreen
    if (subject.subject == 'FarbenFormen') {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, animation, __) => ColorShapeQuizScreen(
            grade: widget.child.grade,
            subjectColors: subject.colors,
          ),
          transitionsBuilder: (_, animation, __, child) {
            return ScaleTransition(
              scale: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutBack,
              ),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => EarlyLearnerQuizScreen(
          subject: subject.subject,
          subjectEmoji: subject.emoji,
          subjectColors: subject.colors,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return ScaleTransition(
            scale: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutBack,
            ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  Widget _buildBottomNav(int rewardsCount) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      height: 80 + bottomPadding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _BigNavButton(
              emoji: '🏠',
              isSelected: _currentTab == _EarlyTab.home,
              color: const Color(0xFF7C4DFF),
              onTap: () => setState(() => _currentTab = _EarlyTab.home),
            ),
            _BigNavButton(
              emoji: '🎁',
              isSelected: _currentTab == _EarlyTab.rewards,
              color: const Color(0xFFEC407A),
              badgeCount: rewardsCount,
              onTap: () => setState(() => _currentTab = _EarlyTab.rewards),
            ),
            _BigNavButton(
              emoji: '⭐',
              isSelected: _currentTab == _EarlyTab.stars,
              color: const Color(0xFF9C64FF),
              onTap: () => setState(() => _currentTab = _EarlyTab.stars),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// HOME CONTENT – Carousel-Layout
// ============================================================================

class _HomeContent extends ConsumerStatefulWidget {
  final ChildModel child;
  final AnimationController waveController;
  final void Function(_EarlySubject) onSubjectTap;
  final VoidCallback onRewardsTap;

  const _HomeContent({
    required this.child,
    required this.waveController,
    required this.onSubjectTap,
    required this.onRewardsTap,
  });

  @override
  ConsumerState<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends ConsumerState<_HomeContent> {
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.85);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    HapticFeedback.selectionClick();

    // Fachname vorlesen wenn TTS aktiv
    final childId = widget.child.id;
    final ttsEnabled = ref.read(ttsSettingsProvider(childId));
    if (ttsEnabled) {
      ref
          .read(ttsControllerProvider.notifier)
          .speakSubject(_visibleSubjects[index].label);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Kompakter Header ──────────────────────────────────────────
        _CompactHeader(
          child: widget.child,
          waveController: widget.waveController,
        ),

        const SizedBox(height: 16),

        // ── Carousel ──────────────────────────────────────────────────
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: _visibleSubjects.length,
            onPageChanged: _onPageChanged,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              return AnimatedBuilder(
                animation: _pageController,
                builder: (context, child) {
                  double scale = 1.0;
                  double opacity = 1.0;

                  if (_pageController.position.haveDimensions) {
                    final page = _pageController.page ?? 0.0;
                    final distance = (page - index).abs();
                    scale = (1.0 - (distance * 0.12)).clamp(0.85, 1.0);
                    opacity = (1.0 - (distance * 0.3)).clamp(0.6, 1.0);
                  }

                  return Transform.scale(
                    scale: scale,
                    child: Opacity(
                      opacity: opacity,
                      child: _CarouselSubjectCard(
                        subject: _visibleSubjects[index],
                        isActive: index == _currentPage,
                        onTap: () =>
                            widget.onSubjectTap(_visibleSubjects[index]),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),

        const SizedBox(height: 12),

        // ── Page Indicator Dots ───────────────────────────────────────
        _PageIndicatorDots(
          count: _visibleSubjects.length,
          currentIndex: _currentPage,
        ),

        const SizedBox(height: 12),

        // ── Geschenk-Teaser (wenn Eltern-Belohnung vorhanden) ────────
        _GiftTeaser(child: widget.child, onTap: widget.onRewardsTap),

        const SizedBox(height: 12),
      ],
    );
  }
}

// ============================================================================
// COMPACT HEADER – Avatar links, Name Mitte, TTS-Toggle rechts
// ============================================================================

class _CompactHeader extends ConsumerWidget {
  final ChildModel child;
  final AnimationController waveController;

  const _CompactHeader({required this.child, required this.waveController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateChangesProvider).value;
    final ttsEnabled = ref.watch(ttsSettingsProvider(child.id));
    final ttsState = ref.watch(ttsControllerProvider);

    // Live-Daten aus Firestore für Sterne + Level
    return user == null
        ? _buildContent(
            context,
            ref,
            child.stars,
            child.level,
            ttsEnabled,
            ttsState.isSpeaking,
          )
        : StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .collection('children')
                .doc(child.id)
                .snapshots(),
            builder: (context, snapshot) {
              final data = snapshot.data?.data() as Map<String, dynamic>?;
              final stars = data?['stars'] as int? ?? child.stars;
              final level = data?['level'] as int? ?? child.level;
              return _buildContent(
                context,
                ref,
                stars,
                level,
                ttsEnabled,
                ttsState.isSpeaking,
              );
            },
          );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    int stars,
    int level,
    bool ttsEnabled,
    bool isSpeaking,
  ) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF7C4DFF), Color(0xFF512DA8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 8,
        16,
        16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // ── Zurück-Button ──────────────────────────────────────
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // ── Avatar (tippbar → Avatar-Auswahl) ────────────────
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => AvatarSettingsSheet(child: child),
                  );
                },
                child: AnimatedBuilder(
                  animation: waveController,
                  builder: (_, __) => Transform.translate(
                    offset: Offset(0, waveController.value * 3 - 1.5),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF512DA8).withValues(alpha: 0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: child.selectedAvatar != null
                              ? ClipOval(
                                  child: Image.asset(
                                    'assets/images/${child.selectedAvatar}.png',
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        _initials(child.name),
                                  ),
                                )
                              : _initials(child.name),
                        ),
                        // Kleines ✏️-Badge
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Text('✏️', style: TextStyle(fontSize: 10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // ── Name + Level/Sterne ────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      child.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        shadows: [Shadow(color: Colors.black26, blurRadius: 4)],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Sterne + Level kompakt
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('🏆', style: TextStyle(fontSize: 12)),
                              const SizedBox(width: 3),
                              Text(
                                '$level',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('⭐', style: TextStyle(fontSize: 12)),
                              const SizedBox(width: 3),
                              Text(
                                '$stars',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── TTS Toggle ─────────────────────────────────────────
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref.read(ttsSettingsProvider(child.id).notifier).toggle();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: ttsEnabled
                        ? Colors.white.withValues(alpha: 0.35)
                        : Colors.black.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        ttsEnabled
                            ? (isSpeaking
                                  ? Icons.volume_up_rounded
                                  : Icons.volume_up_rounded)
                            : Icons.volume_off_rounded,
                        key: ValueKey(ttsEnabled),
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _initials(String name) {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '😊',
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ============================================================================
// CAROUSEL SUBJECT CARD – Riesige Fach-Karte im PageView
// ============================================================================

class _CarouselSubjectCard extends StatefulWidget {
  final _EarlySubject subject;
  final bool isActive;
  final VoidCallback onTap;

  const _CarouselSubjectCard({
    required this.subject,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_CarouselSubjectCard> createState() => _CarouselSubjectCardState();
}

class _CarouselSubjectCardState extends State<_CarouselSubjectCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _pressScale;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _pressScale = Tween(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _pressScale,
      child: GestureDetector(
        onTapDown: (_) => _pressController.forward(),
        onTapUp: (_) {
          _pressController.reverse();
          widget.onTap();
        },
        onTapCancel: () => _pressController.reverse(),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: widget.subject.colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(40),
            boxShadow: [
              BoxShadow(
                color: widget.subject.colors.last.withValues(alpha: 0.45),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Stack(
            children: [
              // ── Deko-Blasen (Hintergrund) ────────────────────────────
              Positioned(
                right: -30,
                top: -30,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                left: -20,
                bottom: -25,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                right: 30,
                bottom: 20,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                ),
              ),

              // ── Haupt-Inhalt ────────────────────────────────────────
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Riesiges Fach-Emoji
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.95, end: 1.05),
                      duration: const Duration(milliseconds: 1500),
                      curve: Curves.easeInOut,
                      builder: (_, value, child) {
                        return Transform.scale(
                          scale: widget.isActive ? value : 0.9,
                          child: child,
                        );
                      },
                      // Endlos-Loop: Neustart wenn fertig
                      onEnd: () {
                        // TweenAnimationBuilder hat kein repeat –
                        // wir nutzen stattdessen einen dezenten Idle-Effekt
                      },
                      child: Text(
                        widget.subject.emoji,
                        style: const TextStyle(fontSize: 100),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Fachname (groß, weiß, gut lesbar)
                    Text(
                      widget.subject.label,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.5,
                        shadows: [Shadow(color: Colors.black26, blurRadius: 6)],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Play-Button
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 2,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 36,
                          ),
                        ],
                      ),
                    ),
                  ],
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
// PAGE INDICATOR DOTS – AnimatedContainer-basiert (kein externes Package)
// ============================================================================

class _PageIndicatorDots extends StatelessWidget {
  final int count;
  final int currentIndex;

  const _PageIndicatorDots({required this.count, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == currentIndex;
        final color = _visibleSubjects[i].colors.first;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 28 : 10,
          height: 10,
          decoration: BoxDecoration(
            color: isActive ? color : color.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(5),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
        );
      }),
    );
  }
}

// ============================================================================
// GESCHENK-TEASER – Pulsierendes Geschenk-Icon wenn Belohnung verfügbar
// ============================================================================

class _GiftTeaser extends ConsumerStatefulWidget {
  final ChildModel child;
  final VoidCallback onTap;

  const _GiftTeaser({required this.child, required this.onTap});

  @override
  ConsumerState<_GiftTeaser> createState() => _GiftTeaserState();
}

class _GiftTeaserState extends ConsumerState<_GiftTeaser>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rewardsCount =
        ref.watch(availableRewardsCountProvider).valueOrNull ?? 0;

    // Nichts anzeigen wenn keine Belohnungen verfügbar
    if (rewardsCount == 0) return const SizedBox.shrink();

    final ttsEnabled = ref.watch(ttsSettingsProvider(widget.child.id));

    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        if (ttsEnabled) {
          ref
              .read(ttsControllerProvider.notifier)
              .speak(
                rewardsCount == 1
                    ? 'Du hast ein Geschenk!'
                    : 'Du hast $rewardsCount Geschenke!',
              );
        }
        widget.onTap();
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFEC407A), Color(0xFFAB47BC)],
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFEC407A).withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Pulsierendes Geschenk-Emoji
            ScaleTransition(
              scale: _pulseAnim,
              child: const Text('🎁', style: TextStyle(fontSize: 32)),
            ),
            const SizedBox(width: 14),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rewardsCount == 1
                        ? 'Ein Geschenk wartet!'
                        : '$rewardsCount Geschenke warten!',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tippe hier zum Anschauen',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            // Sparkle-Icon
            const Text('✨', style: TextStyle(fontSize: 20)),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// STARS CONTENT – zeigt XP als ⭐ Sterne (kindgerechte XP-Darstellung)
// ============================================================================

class _StarsContent extends ConsumerWidget {
  final ChildModel child;

  const _StarsContent({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateChangesProvider).value;

    if (user == null) return _buildView(child.xp, child.level);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('children')
          .doc(child.id)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final xp = data?['xp'] as int? ?? child.xp;
        final level = data?['level'] as int? ?? child.level;
        return _buildView(xp, level);
      },
    );
  }

  Widget _buildView(int xp, int level) {
    final xpForThisLevel = XPService.calculateXPForLevel(level);
    final xpInLevel = XPService.calculateXPInCurrentLevel(xp, level);
    final isMaxLevel = level >= XPService.maxLevel;
    final progress = isMaxLevel
        ? 1.0
        : (xpInLevel / xpForThisLevel).clamp(0.0, 1.0);
    final xpToNext = xpForThisLevel - xpInLevel;

    // 5 Sterne in einer Reihe — je Stern = 20% Fortschritt
    final filledStars = isMaxLevel ? 5 : (progress * 5).floor().clamp(0, 5);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── Gesamt-XP als große ⭐-Zahl ──────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C4DFF), Color(0xFF512DA8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7C4DFF).withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Text('⭐', style: TextStyle(fontSize: 56)),
                  const SizedBox(height: 8),
                  Text(
                    '$xp',
                    style: const TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Sterne gesammelt',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Level-Badges ─────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LevelBadge(level: level, isCurrent: true),
                const SizedBox(width: 12),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: Color(0xFFBDBDBD),
                  size: 24,
                ),
                const SizedBox(width: 12),
                _LevelBadge(level: level + 1, isCurrent: false),
              ],
            ),

            const SizedBox(height: 20),

            // ── Animierter Fortschrittsbalken ────────────────────────
            Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: progress),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOut,
                    builder: (_, value, __) => LinearProgressIndicator(
                      value: value,
                      minHeight: 22,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFFFFB300),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (!isMaxLevel)
                  Text(
                    'Noch $xpToNext ⭐ bis Level ${level + 1}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 24),

            // ── 5 Sterne in einer Reihe (je 20% = 1 Stern) ──────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(5, (i) {
                final filled = i < filledStars;
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: Duration(milliseconds: 300 + i * 120),
                  curve: Curves.elasticOut,
                  builder: (_, v, __) => Transform.scale(
                    scale: filled ? v : 1.0,
                    child: Text(
                      filled ? '⭐' : '☆',
                      style: TextStyle(
                        fontSize: 44,
                        color: filled ? Colors.amber : Colors.grey.shade300,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Kleines Level-Badge Widget ────────────────────────────────────────────────

class _LevelBadge extends StatelessWidget {
  final int level;
  final bool isCurrent;

  const _LevelBadge({required this.level, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: isCurrent ? const Color(0xFF7C4DFF) : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: const Color(0xFF7C4DFF).withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('🏆', style: TextStyle(fontSize: isCurrent ? 20 : 16)),
          const SizedBox(width: 6),
          Text(
            'Level $level',
            style: TextStyle(
              fontSize: isCurrent ? 18 : 15,
              fontWeight: FontWeight.w800,
              color: isCurrent ? Colors.white : Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// GROSSER NAV BUTTON (unverändert aus v1)
// ============================================================================

class _BigNavButton extends StatelessWidget {
  final String emoji;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;
  final int badgeCount;

  const _BigNavButton({
    required this.emoji,
    required this.isSelected,
    required this.color,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 80,
        height: 62,
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Text(emoji, style: TextStyle(fontSize: isSelected ? 38 : 30)),
            if (badgeCount > 0)
              Positioned(
                top: 4,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    badgeCount > 9 ? '9+' : '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
