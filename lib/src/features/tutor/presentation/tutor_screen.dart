import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex/src/shared/widgets/message_bubble.dart';
import '../domain/chat_message.dart';
import 'tutor_provider.dart';
import '../../auth/presentation/active_child_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/child_model.dart';
import '../../learning_time/learning_time_tracker.dart';
import '../../rewards/data/xp_service.dart';
import '../../rewards/data/reward_service.dart';
import '../../rewards/presentation/student_notification_popup.dart';
import '../../student_dashboard/presentation/widgets/rewards_count_provider.dart';
import 'widgets/xp_gain_overlay.dart';
import 'widgets/tutor_xp_banner.dart';

/// Chat-Screen mit dem KI-Tutor
class TutorScreen extends ConsumerStatefulWidget {
  const TutorScreen({super.key});

  @override
  ConsumerState<TutorScreen> createState() => _TutorScreenState();
}

class _TutorScreenState extends ConsumerState<TutorScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  LearningTimeTracker? _timeTracker;
  OverlayEntry? _xpOverlay;

  // Werden in initState gespeichert – kein ref in dispose nötig
  XPService? _xpService;
  RewardService? _rewardService;
  TutorNotifier? _tutorNotifier;
  ActiveChildNotifier? _activeChildNotifier;
  ChildModel? _child;
  String? _userId;

  // Verhindert gleichzeitige parallele Reward-Checks (Debounce)
  bool _isCheckingRewards = false;

  @override
  void initState() {
    super.initState();

    final child = ref.read(activeChildProvider);
    final user = ref.read(authStateChangesProvider).value;

    if (child != null && user != null) {
      _child = child;
      _userId = user.uid;
      _xpService = ref.read(xpServiceProvider);
      _rewardService = ref.read(rewardServiceProvider);
      _activeChildNotifier = ref.read(activeChildProvider.notifier);

      final providerInstance = ref.read(tutorProvider);
      if (providerInstance != null) {
        _tutorNotifier = ref.read(providerInstance.notifier);
      }

      _timeTracker = LearningTimeTracker(userId: user.uid, childId: child.id);
      _timeTracker!.startTracking();
      debugPrint('⏱️ Tutor: Zeit-Tracking gestartet');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Notifier aktuell halten – wird bei Provider-Invalidierung neu gesetzt
    final providerInstance = ref.read(tutorProvider);
    if (providerInstance != null) {
      _tutorNotifier = ref.read(providerInstance.notifier);
    }
  }

  void _showXpAnimation(int xpGained) {
    if (!mounted) return;
    _xpOverlay?.remove();
    _xpOverlay = OverlayEntry(
      builder: (context) => XpGainOverlay(
        xpGained: xpGained,
        onDone: () {
          _xpOverlay?.remove();
          _xpOverlay = null;
        },
      ),
    );
    Overlay.of(context).insert(_xpOverlay!);
  }

  Future<void> _checkRewardsAfterXp(dynamic child) async {
    // Verhindert parallele/gespammte Checks nach jeder einzelnen Nachricht
    if (_isCheckingRewards) return;
    _isCheckingRewards = true;

    final user = ref.read(authStateChangesProvider).value;
    final xpService = _xpService;
    final rewardService = _rewardService;
    if (user == null || xpService == null || rewardService == null) {
      _isCheckingRewards = false;
      return;
    }

    try {
      // Kurz warten damit Firestore den XP-Write abgeschlossen hat
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) {
        _isCheckingRewards = false;
        return;
      }

      ChildModel? updatedChild = await xpService.getChild(
        userId: user.uid,
        childId: child.id,
      );
      if (updatedChild == null || !mounted) {
        _isCheckingRewards = false;
        return;
      }

      // ✅ FIX: activeChildProvider aktualisieren damit Dashboard-FAB
      // sofort das neue Level anzeigt (Tutor-Freischaltung bei Level 2)
      ref.read(activeChildProvider.notifier).update(updatedChild);

      final unlockedRewards = await rewardService.checkAndApproveRewards(
        userId: user.uid,
        child: updatedChild,
      );

      if (unlockedRewards.isNotEmpty && mounted) {
        showRewardNotifications(context, rewards: unlockedRewards);
      }
    } catch (e) {
      debugPrint('❌ Tutor: Reward-Check fehlgeschlagen: $e');
    } finally {
      _isCheckingRewards = false;
    }
  }

  @override
  void dispose() {
    _xpOverlay?.remove();
    _messageController.dispose();
    _scrollController.dispose();

    // Alle gespeicherten Referenzen verwenden – kein ref nötig
    final child = _child;
    final userId = _userId;
    final xpService = _xpService;
    final rewardService = _rewardService;
    final notifier = _tutorNotifier;
    final activeChildNotifier = _activeChildNotifier;
    final tracker = _timeTracker;

    if (tracker != null) {
      tracker.stopTracking();

      Future(() async {
        try {
          await tracker.saveTime();
          debugPrint('✅ Tutor: Lernzeit gespeichert');

          if (child != null &&
              userId != null &&
              xpService != null &&
              rewardService != null) {
            final newStreak = await xpService.updateStreak(
              userId: userId,
              childId: child.id,
            );
            debugPrint('✅ Tutor: Streak aktualisiert → $newStreak Tage');

            ChildModel? updatedChild = await xpService.getChild(
              userId: userId,
              childId: child.id,
            );

            if (updatedChild != null) {
              updatedChild = updatedChild.copyWith(streak: newStreak);

              // ✅ FIX: Provider aktualisieren → Dashboard zeigt sofort neuen Streak
              activeChildNotifier?.update(updatedChild);

              final unlockedRewards = await rewardService
                  .checkAndApproveRewards(userId: userId, child: updatedChild);
              if (unlockedRewards.isNotEmpty) {
                debugPrint(
                  '🎁 Tutor: ${unlockedRewards.length} Belohnungen freigeschaltet!',
                );
              }
            }
          }
        } catch (e) {
          debugPrint('❌ Fehler beim Speichern der Tutor-Lernzeit: $e');
        }
        tracker.dispose();
        notifier?.completeCurrentSession();
      });
    } else {
      notifier?.completeCurrentSession();
    }

    super.dispose();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final providerInstance = ref.read(tutorProvider);
    if (providerInstance != null) {
      ref.read(providerInstance.notifier).sendMessage(text);
    }
    _messageController.clear();

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final providerInstance = ref.watch(tutorProvider);
    final messages = providerInstance != null
        ? ref.watch(providerInstance)
        : <ChatMessage>[];
    final child = ref.watch(activeChildProvider);

    if (child == null) {
      return const Scaffold(body: Center(child: Text('Kein Kind ausgewählt')));
    }

    // ✅ XP-Gain Listener → Animation + Reward-Check
    ref.listen(tutorXpGainProvider(child.id), (previous, gained) {
      if (gained > 0 && mounted) {
        _showXpAnimation(gained);
        // Reset damit nächstes Event wieder feuert
        Future.microtask(() {
          if (mounted) {
            ref.read(tutorXpGainProvider(child.id).notifier).state = 0;
          }
        });
        // Reward-Check nach XP-Vergabe
        _checkRewardsAfterXp(child);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.deepPurple.shade300,
              child: ClipOval(
                child: Image.asset(
                  'assets/images/lerndex_logo.png',
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.school, size: 20, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text('Lexi'),
          ],
        ),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: const [],
      ),
      body: Column(
        children: [
          // Reaktiver XP-Banner mit Fortschrittsbalken
          TutorXpBanner(childId: child.id),

          // Chat-Nachrichten
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.smart_toy,
                          size: 80,
                          color: Colors.deepPurple.shade200,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Hallo ${child.name}! 👋',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Ich bin dein persönlicher Lernbegleiter.\nStell mir eine Frage!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return MessageBubble(
                        message: message,
                        childName: child.name,
                        childSelectedAvatar: child.selectedAvatar,
                      );
                    },
                  ),
          ),

          // ── Eingabe-Leiste ──────────────────────────────────────────────
          // FIX 1: SafeArea (nur bottom) → kein Überlappen mit Home-Indikator
          SafeArea(
            left: false,
            right: false,
            top: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    // FIX 2: maxLines: null + keyboardType multiline → Zeilenumbruch
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: 'Stell mir eine Frage...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        maxLines: null,
                        minLines: 1,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Senden-Button unten ausgerichtet bei mehrzeiligem Text
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: FloatingActionButton(
                      onPressed: _sendMessage,
                      backgroundColor: Colors.deepPurple,
                      mini: true,
                      child: const Icon(
                        Icons.send,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
