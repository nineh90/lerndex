import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lerndex/src/features/auth/data/auth_repository.dart';
import 'package:lerndex/src/features/auth/domain/child_model.dart';
import 'package:lerndex/src/features/rewards/presentation/rewards_screen.dart';
import 'rewards_count_provider.dart';
import 'early_learner_quiz_screen.dart';

// ============================================================================
// EARLY LEARNER DASHBOARD – Klasse 1–2
//
// Design-Prinzipien:
// • Kein Text der gelesen werden muss (außer dem Namen)
// • Alles durch große Emojis & Farben erkennbar
// • Riesige Tipp-Flächen, kindgerechte Proportionen
// • Fröhliche Farben: Orange, Gelb, Grün, Blau, Pink
// • Fortschritt als Sterne-Sammlung (visuell, keine Zahlen)
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
    colors: [Color(0xFFFF8C00), Color(0xFFE64A19)],
    subject: 'Mathe',
  ),
  _EarlySubject(
    emoji: '🔤',
    label: 'Buchstaben',
    colors: [Color(0xFFEC407A), Color(0xFF8E24AA)],
    subject: 'Deutsch',
  ),
  _EarlySubject(
    emoji: '🦋',
    label: 'Tiere & Farben',
    colors: [Color(0xFF1E88E5), Color(0xFF0D47A1)],
    subject: 'Englisch',
  ),
  _EarlySubject(
    emoji: '🌿',
    label: 'Natur',
    colors: [Color(0xFF43A047), Color(0xFF1B5E20)],
    subject: 'Sachkunde',
  ),
];

enum _EarlyTab { home, rewards, stars }

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
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _waveController.dispose();
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
        backgroundColor: const Color(0xFFFFF8E1),
        body: SafeArea(child: _buildBody()),
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
        );
      case _EarlyTab.rewards:
        return const RewardsScreen();
      case _EarlyTab.stars:
        return _StarsContent(child: widget.child);
    }
  }

  void _openSubject(_EarlySubject subject) {
    HapticFeedback.mediumImpact();
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
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _BigNavButton(
            emoji: '🏠',
            isSelected: _currentTab == _EarlyTab.home,
            color: const Color(0xFFFF8C00),
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
            color: const Color(0xFFFFB300),
            onTap: () => setState(() => _currentTab = _EarlyTab.stars),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// HOME CONTENT
// ============================================================================

class _HomeContent extends StatelessWidget {
  final ChildModel child;
  final AnimationController waveController;
  final void Function(_EarlySubject) onSubjectTap;

  const _HomeContent({
    required this.child,
    required this.waveController,
    required this.onSubjectTap,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        children: [
          _EarlyHeader(child: child, waveController: waveController),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.88,
              children: _earlySubjects
                  .map(
                    (s) => _BigSubjectTile(
                      subject: s,
                      onTap: () => onSubjectTap(s),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// EARLY HEADER
// ============================================================================

class _EarlyHeader extends ConsumerWidget {
  final ChildModel child;
  final AnimationController waveController;

  const _EarlyHeader({required this.child, required this.waveController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateChangesProvider).value;

    if (user == null) return _buildContent(context, child.stars, child.level);

    return StreamBuilder<DocumentSnapshot>(
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
        return _buildContent(context, stars, level);
      },
    );
  }

  Widget _buildContent(BuildContext context, int stars, int level) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFF8C00), Color(0xFFFFB300)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(40),
          bottomRight: Radius.circular(40),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        children: [
          // ── Zurück + Avatar ────────────────────────────────────────────
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
              const Spacer(),
              // Wackelnder Avatar
              AnimatedBuilder(
                animation: waveController,
                builder: (_, __) => Transform.translate(
                  offset: Offset(0, waveController.value * 5 - 2.5),
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.shade900.withOpacity(0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
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
                ),
              ),
              const Spacer(),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 16),

          // ── Name ──────────────────────────────────────────────────────
          Text(
            child.name,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              shadows: [Shadow(color: Colors.black26, blurRadius: 4)],
            ),
          ),
          const SizedBox(height: 16),

          // ── Sterne + Level ────────────────────────────────────────────
          _StarLevelRow(stars: stars, level: level),
        ],
      ),
    );
  }

  Widget _initials(String name) {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '😊',
        style: const TextStyle(fontSize: 38, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _StarLevelRow extends StatelessWidget {
  final int stars;
  final int level;

  const _StarLevelRow({required this.stars, required this.level});

  @override
  Widget build(BuildContext context) {
    final fullStars = stars % 10;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Level Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🏆', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 4),
                Text(
                  'Level $level',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFE65100),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 5 Sterne
          ...List.generate(
            5,
            (i) => Text(
              i < fullStars ? '⭐' : '☆',
              style: TextStyle(
                fontSize: 22,
                color: i < fullStars ? Colors.amber : Colors.white54,
              ),
            ),
          ),
          if (stars >= 10) ...[
            const SizedBox(width: 6),
            Text(
              '+${(stars ~/ 10) * 10}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// GROSSE FACH-KACHEL
// ============================================================================

class _BigSubjectTile extends StatefulWidget {
  final _EarlySubject subject;
  final VoidCallback onTap;

  const _BigSubjectTile({required this.subject, required this.onTap});

  @override
  State<_BigSubjectTile> createState() => _BigSubjectTileState();
}

class _BigSubjectTileState extends State<_BigSubjectTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
    );
    _scale = Tween(
      begin: 1.0,
      end: 0.91,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) {
          _ctrl.reverse();
          widget.onTap();
        },
        onTapCancel: () => _ctrl.reverse(),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: widget.subject.colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: widget.subject.colors.last.withOpacity(0.45),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Deko-Blasen
              Positioned(
                right: -20,
                top: -20,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                left: -10,
                bottom: -15,
                child: Container(
                  width: 55,
                  height: 55,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              // Riesiges Emoji + Play-Button
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        widget.subject.emoji,
                        style: const TextStyle(fontSize: 68),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.28),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 28,
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
// STARS CONTENT
// ============================================================================

class _StarsContent extends ConsumerWidget {
  final ChildModel child;

  const _StarsContent({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateChangesProvider).value;

    if (user == null) return _buildView(child.stars, child.level);

    return StreamBuilder<DocumentSnapshot>(
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
        return _buildView(stars, level);
      },
    );
  }

  Widget _buildView(int stars, int level) {
    final displayCount = stars.clamp(0, 50);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const Text('⭐', style: TextStyle(fontSize: 72)),
          const SizedBox(height: 8),
          Text(
            '$stars',
            style: const TextStyle(
              fontSize: 60,
              fontWeight: FontWeight.w900,
              color: Color(0xFFFF8C00),
            ),
          ),
          const SizedBox(height: 32),
          // Sterne-Sammlung
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: List.generate(displayCount.clamp(10, 50), (i) {
              final filled = i < displayCount;
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 100 + (i * 30).clamp(0, 1000)),
                curve: Curves.elasticOut,
                builder: (_, v, __) => Transform.scale(
                  scale: v,
                  child: Text(
                    filled ? '⭐' : '☆',
                    style: TextStyle(
                      fontSize: 32,
                      color: filled ? Colors.amber : Colors.grey.shade300,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 36),
          // Level Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF8C00), Color(0xFFFFB300)],
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🏆', style: TextStyle(fontSize: 36)),
                const SizedBox(width: 12),
                Text(
                  'Level $level',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// GROSSER NAV BUTTON
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
          color: isSelected ? color.withOpacity(0.15) : Colors.transparent,
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
