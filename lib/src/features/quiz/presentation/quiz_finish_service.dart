import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../rewards/data/xp_service.dart';
import '../../rewards/data/reward_service.dart';
import '../../rewards/presentation/student_notification_popup.dart';
import '../../student_dashboard/presentation/widgets/rewards_count_provider.dart';
import '../../learning_time/learning_time_tracker.dart';
import '../../auth/presentation/active_child_provider.dart';

// ============================================================================
// QUIZ FINISH SERVICE
//
// Kapselt den Quiz-Abschluss-Block (Streak, Lernzeit, Stats, Rewards)
// der früher dupliziert in quiz_screen.dart UND early_learner_quiz_screen.dart
// stand.
//
// Nutzung:
//   await QuizFinishService.finish(
//     ref: ref,
//     context: context,
//     userId: userId,
//     childId: childId,
//     isPerfect: isPerfect,
//     timeTracker: _timeTracker,
//     onGoToRewards: () { ... },
//   );
// ============================================================================

class QuizFinishService {
  QuizFinishService._();

  /// Führt alle Abschluss-Operationen durch:
  /// 1. Streak aktualisieren
  /// 2. Lernzeit speichern
  /// 3. Quiz-Stats schreiben
  /// 4. Kind neu laden + Rewards prüfen
  /// 5. Reward-Popup oder Streak-Meilenstein anzeigen
  ///
  /// [timeTracker] sollte bereits gestoppt sein (stopTracking() aufgerufen).
  static Future<void> finish({
    required WidgetRef ref,
    required BuildContext context,
    required String userId,
    required String childId,
    required bool isPerfect,
    LearningTimeTracker? timeTracker,
  }) async {
    try {
      final xpService = ref.read(xpServiceProvider);
      final rewardService = ref.read(rewardServiceProvider);

      // 1. Streak (MUSS vor saveTime kommen — sonst wird lastLearningDate
      //    durch saveTime() überschrieben bevor der Streak-Check läuft)
      final newStreak = await xpService.updateStreak(
        userId: userId,
        childId: childId,
      );

      // 2. Lernzeit (timeTracker sollte bereits gestoppt sein)
      if (timeTracker != null) {
        await timeTracker.saveTime();
      }

      // 3. Quiz-Statistiken
      await xpService.updateQuizStats(
        userId: userId,
        childId: childId,
        isPerfect: isPerfect,
      );

      // 4. Kind neu laden + Streak-Wert überschreiben
      var updatedChild = await xpService.getChild(
        userId: userId,
        childId: childId,
      );

      if (updatedChild == null || !context.mounted) return;

      // KRITISCH: Streak aus updateStreak() nehmen, nicht aus getChild()
      // (Firestore-Lese-Latenz kann alten Wert zurückgeben)
      updatedChild = updatedChild.copyWith(streak: newStreak);

      // ✅ FIX: activeChildProvider aktualisieren damit Dashboard-FAB
      // sofort das neue Level anzeigt (Tutor-Freischaltung bei Level 2)
      ref.read(activeChildProvider.notifier).update(updatedChild);

      // 5. Rewards prüfen
      final unlockedRewards = await rewardService.checkAndApproveRewards(
        userId: userId,
        child: updatedChild,
        isPerfectQuiz: isPerfect,
      );

      if (!context.mounted) return;

      if (unlockedRewards.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (context.mounted) {
            showRewardNotifications(context, rewards: unlockedRewards);
          }
        });
      } else if (_isStreakMilestone(newStreak)) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (context.mounted) {
            StudentNotificationPopup.show(
              context,
              type: StudentNotificationType.streakMilestone,
            );
          }
        });
      }
    } catch (e, st) {
      debugPrint('❌ QuizFinishService.finish Fehler: $e\n$st');
    }
  }

  static bool _isStreakMilestone(int streak) =>
      streak == 3 ||
      streak == 7 ||
      streak == 14 ||
      streak == 30 ||
      streak == 50 ||
      streak == 100;
}
