import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/app_links.dart';
import '../../auth/domain/child_model.dart';
import '../../rewards/data/xp_service.dart';
import '../../rewards/data/reward_service.dart';
import '../../rewards/domain/reward_model.dart';
import '../../rewards/presentation/student_notification_popup.dart';
import '../../learning_time/learning_time_tracker.dart';
import '../../learning_time/offline_write.dart';
import '../../auth/presentation/active_child_provider.dart';

// ============================================================================
// QUIZ FINISH SERVICE
//
// Abschluss der Quizze für Klasse 1–2 (Zahlen, Buchstaben, Farben & Formen):
// XP, Streak, Lernzeit, Quiz-Statistik und Belohnungen.
//
// Läuft unabhängig vom Bildschirm: alles, was `ref` braucht, wird beim Start
// sofort gelesen, danach gibt es weder `ref` noch `context`. Verlässt das Kind
// das Quiz (Home, Zurück-Geste auf der Schatzkiste), läuft der Abschluss zu
// Ende. Popups zeigt [showPopups] erst, wenn der Bildschirm so weit ist.
//
// Offline-tauglich: Kind-Dokument und Tagesstatistik werden in EINEM Batch
// geschrieben (keine Transaktion), der lokal sofort gilt und nachgereicht
// wird. Nur die Belohnungsprüfung braucht danach den Server.
//
// Nutzung:
//   _finish = QuizFinishService.finish(
//     ref: ref,
//     userId: userId,
//     childId: childId,
//     isPerfect: isPerfect,
//     earnedXP: earnedXP,
//     timeTracker: _timeTracker,
//   );
//   … später …
//   final result = await _finish;
//   if (result != null) QuizFinishService.showPopups(context, result);
// ============================================================================

/// Was der Quiz-Abschluss ergeben hat.
class QuizFinishResult {
  const QuizFinishResult({
    required this.child,
    required this.streakBefore,
    required this.newStreak,
    this.rewards = const [],
  });

  /// Kind nach dem Abschluss (lokal berechnet, nicht vom Server gelesen).
  final ChildModel child;
  final int streakBefore;
  final int newStreak;

  /// Belohnungen, die dieses Quiz freigeschaltet hat.
  final List<RewardModel> rewards;

  bool get showStreakMilestone =>
      QuizFinishService.shouldShowStreakMilestone(streakBefore, newStreak);
}

class QuizFinishService {
  QuizFinishService._();

  /// Startet den Abschluss. [ref] wird nur synchron am Anfang benutzt, der
  /// Rest läuft auch weiter, wenn das Widget danach entsorgt wird.
  ///
  /// [timeTracker] wird hier gestoppt; seine Sekunden kommen in denselben
  /// Batch wie XP, Streak und Quiz-Statistik.
  static Future<QuizFinishResult?> finish({
    required WidgetRef ref,
    required String userId,
    required String childId,
    required bool isPerfect,
    int earnedXP = 0,
    LearningTimeTracker? timeTracker,
  }) {
    final rewardService = ref.read(rewardServiceProvider);
    final activeChild = ref.read(activeChildProvider.notifier);
    return run(
      writer: QuizProgressWriter(FirebaseFirestore.instance),
      rewardService: rewardService,
      onChildUpdated: (child) {
        // Dashboard zeigt sofort das neue Level (Tutor ab Level 2).
        if (activeChild.mounted) activeChild.update(child);
      },
      userId: userId,
      childId: childId,
      isPerfect: isPerfect,
      earnedXP: earnedXP,
      timeTracker: timeTracker,
    );
  }

  /// Der eigentliche Abschluss, ohne Riverpod (testbar).
  static Future<QuizFinishResult?> run({
    required QuizProgressWriter writer,
    required RewardService rewardService,
    required void Function(ChildModel child) onChildUpdated,
    required String userId,
    required String childId,
    required bool isPerfect,
    int earnedXP = 0,
    LearningTimeTracker? timeTracker,
  }) async {
    try {
      timeTracker?.stopTracking();
      final progress = await writer.write(
        userId: userId,
        childId: childId,
        earnedXP: earnedXP,
        countQuiz: true,
        isPerfect: isPerfect,
        timeTracker: timeTracker,
      );
      if (progress == null) return null;

      onChildUpdated(progress.child);

      var rewards = const <RewardModel>[];
      try {
        rewards = await rewardService.checkAndApproveRewards(
          userId: userId,
          child: progress.child,
          isPerfectQuiz: isPerfect,
        );
      } catch (e) {
        debugPrint('⚠️ QuizFinishService: Belohnungen nicht geprüft: $e');
      }

      return QuizFinishResult(
        child: progress.child,
        streakBefore: progress.streakBefore,
        newStreak: progress.newStreak,
        rewards: rewards,
      );
    } catch (e, st) {
      debugPrint('❌ QuizFinishService.finish Fehler: $e\n$st');
      return null;
    }
  }

  /// Zeigt freigeschaltete Belohnungen bzw. den Streak-Meilenstein.
  ///
  /// Ist [context] nicht mehr da (Kind hat das Quiz schon verlassen), kommt
  /// das Popup über den Navigator der App auf dem Bildschirm, auf dem das
  /// Kind jetzt ist.
  static void showPopups(BuildContext? context, QuizFinishResult result) {
    if (result.rewards.isEmpty && !result.showStreakMilestone) return;

    BuildContext? target() {
      if (context != null && context.mounted) return context;
      final overlay = appNavigatorKey.currentState?.overlay?.context;
      return overlay != null && overlay.mounted ? overlay : null;
    }

    if (result.rewards.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 600), () {
        final ctx = target();
        if (ctx == null || !ctx.mounted) return;
        showRewardNotifications(ctx, rewards: result.rewards);
      });
    } else {
      Future.delayed(const Duration(milliseconds: 800), () {
        final ctx = target();
        if (ctx == null || !ctx.mounted) return;
        StudentNotificationPopup.show(
          ctx,
          type: StudentNotificationType.streakMilestone,
        );
      });
    }
  }

  /// Meilenstein-Popup nur, wenn der Streak durch dieses Quiz gewachsen ist.
  /// Am selben Tag liefert der Streak denselben Wert – ohne die Bedingung
  /// käme das Popup an einem Meilenstein-Tag nach jedem Quiz.
  static bool shouldShowStreakMilestone(int before, int after) =>
      after > before && isStreakMilestone(after);

  static bool isStreakMilestone(int streak) =>
      streak == 3 ||
      streak == 7 ||
      streak == 14 ||
      streak == 30 ||
      streak == 50 ||
      streak == 100;

  /// Neuer Streak nach Kalendertagen (wie `XPService.updateStreak`):
  /// heute schon gelernt → bleibt (mindestens 1), gestern → +1, sonst 1.
  static int nextStreak({
    required DateTime? lastLearning,
    required int currentStreak,
    required DateTime now,
  }) {
    if (lastLearning == null) return 1;
    final last = DateTime.utc(
      lastLearning.year,
      lastLearning.month,
      lastLearning.day,
    );
    final today = DateTime.utc(now.year, now.month, now.day);
    final days = today.difference(last).inDays;
    if (days == 0) return currentStreak < 1 ? 1 : currentStreak;
    if (days == 1) return currentStreak + 1;
    return 1;
  }
}

/// Ergebnis von [QuizProgressWriter.write].
class QuizProgress {
  const QuizProgress({
    required this.child,
    required this.streakBefore,
    required this.newStreak,
  });

  final ChildModel child;
  final int streakBefore;
  final int newStreak;
}

/// Schreibt den Fortschritt eines Quiz (XP, Streak, Quiz-Statistik,
/// Lernzeit) als EINEN Batch: ein Update aufs Kind-Dokument plus ein
/// `set(merge)` auf die Tagesstatistik. Keine Transaktion – funktioniert
/// offline.
///
/// Gekoppelte Kindergeräte dürfen genau diese Fortschrittsfelder ändern.
class QuizProgressWriter {
  QuizProgressWriter(this._firestore, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final FirebaseFirestore _firestore;
  final DateTime Function() _now;

  /// [countQuiz]: abgeschlossenes Quiz (Streak, `totalQuizzes`). Beim
  /// Abbruch nur XP und Lernzeit retten (`countQuiz: false`).
  ///
  /// Gibt `null` zurück, wenn das Kind-Dokument nicht lesbar ist oder der
  /// Server den Batch sofort ablehnt (die Sekunden bekommt der Tracker
  /// dann zurück).
  Future<QuizProgress?> write({
    required String userId,
    required String childId,
    required int earnedXP,
    required bool countQuiz,
    bool isPerfect = false,
    LearningTimeTracker? timeTracker,
  }) async {
    // Synchron VOR dem ersten await: so ist die Lernzeit auch dann
    // abgeholt, wenn der Aufrufer direkt danach entsorgt wird.
    final seconds = timeTracker?.takeUnsavedSeconds() ?? 0;
    if (!countQuiz && earnedXP <= 0 && seconds == 0) return null;

    final childRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId);

    try {
      final data = await _readChild(childRef);
      if (data == null) {
        timeTracker?.restoreSeconds(seconds);
        debugPrint('❌ QuizProgressWriter: Kind $childId nicht lesbar');
        return null;
      }

      final now = _now();
      final local = Map<String, dynamic>.of(data);
      final updates = <String, dynamic>{};

      if (earnedXP > 0) {
        final newXP = ((data['xp'] as num?)?.toInt() ?? 0) + earnedXP;
        final newLevel = XPService.calculateLevelFromXP(newXP);
        final xpToNext = XPService.calculateXPToNextLevel(newXP, newLevel);
        // Inkrement statt absolutem Wert: der gelesene Stand kann offline
        // aus dem Cache kommen, parallel vergebene XP gehen so nicht verloren.
        updates['xp'] = FieldValue.increment(earnedXP);
        updates['level'] = newLevel;
        updates['xpToNextLevel'] = xpToNext;
        updates['lastXPGain'] = FieldValue.serverTimestamp();
        local['xp'] = newXP;
        local['level'] = newLevel;
        local['xpToNextLevel'] = xpToNext;
        local['lastXPGain'] = Timestamp.fromDate(now);
      }

      final streakBefore = (data['streak'] as num?)?.toInt() ?? 0;
      var newStreak = streakBefore;
      if (countQuiz) {
        newStreak = QuizFinishService.nextStreak(
          lastLearning: (data['lastLearningDate'] as Timestamp?)?.toDate(),
          currentStreak: streakBefore,
          now: now,
        );
        updates['streak'] = newStreak;
        updates['lastLearningDate'] = FieldValue.serverTimestamp();
        updates['totalQuizzes'] = FieldValue.increment(1);
        if (isPerfect) updates['perfectQuizzes'] = FieldValue.increment(1);
        updates['lastQuizDate'] = FieldValue.serverTimestamp();
        local['streak'] = newStreak;
        local['lastLearningDate'] = Timestamp.fromDate(now);
        local['totalQuizzes'] =
            ((data['totalQuizzes'] as num?)?.toInt() ?? 0) + 1;
        if (isPerfect) {
          local['perfectQuizzes'] =
              ((data['perfectQuizzes'] as num?)?.toInt() ?? 0) + 1;
        }
        local['lastQuizDate'] = Timestamp.fromDate(now);
      }

      final batch = _firestore.batch();
      if (seconds > 0) {
        final setFirst = data['firstLearningDate'] == null;
        updates.addAll(
          LearningTimeTracker.childTimeFields(
            seconds,
            setFirstLearningDate: setFirst,
          ),
        );
        local['totalLearningSeconds'] =
            ((data['totalLearningSeconds'] as num?)?.toInt() ?? 0) + seconds;
        if (setFirst) local['firstLearningDate'] = Timestamp.fromDate(now);
        timeTracker!.addDailyStatsToBatch(batch, seconds);
      }
      batch.update(childRef, updates);

      await commitOfflineTolerant(
        batch,
        onLateError: (_) => timeTracker?.restoreSeconds(seconds),
      );

      debugPrint(
        '✅ Quiz-Fortschritt gespeichert: +$earnedXP XP, Streak $newStreak, '
        '${seconds}s Lernzeit',
      );
      return QuizProgress(
        child: ChildModel.fromFirestore(local, childId),
        streakBefore: streakBefore,
        newStreak: newStreak,
      );
    } catch (e) {
      timeTracker?.restoreSeconds(seconds);
      debugPrint('❌ QuizProgressWriter: $e');
      return null;
    }
  }

  /// Server (kurz), sonst lokaler Cache.
  Future<Map<String, dynamic>?> _readChild(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      final snap = await ref.get().timeout(const Duration(seconds: 5));
      if (snap.exists) return snap.data();
    } catch (_) {
      // offline / Timeout → Cache
    }
    try {
      final snap = await ref.get(const GetOptions(source: Source.cache));
      return snap.data();
    } catch (_) {
      return null;
    }
  }
}
