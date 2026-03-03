import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/child_model.dart';
import '../domain/xp_result.dart';

/// Service für XP-Verwaltung und Level-Berechnung
class XPService {
  final FirebaseFirestore _firestore;

  XPService(this._firestore);

  // =========================================================================
  // LEVEL & XP BERECHNUNG
  // 50 Level mit progressiver Kurve und Rang-Titeln:
  //   Level  1–10 → Lernling  📚  (je ~50–100 XP)
  //   Level 11–20 → Entdecker 🔍  (je ~110–200 XP)
  //   Level 21–30 → Forscher  🔬  (je ~220–350 XP)
  //   Level 31–40 → Experte   🎓  (je ~380–550 XP)
  //   Level 41–50 → Meister   🏆  (je ~590–800 XP)
  // =========================================================================

  /// Maximales Level
  static const int maxLevel = 50;

  /// Berechnet benötigte XP um ein bestimmtes Level zu erreichen.
  /// Progressive Kurve — frühe Level schnell, spätere Level dauern länger.
  /// Level  1 →   30 XP   Level 10 →  110 XP   (Gesamt ~525 XP)
  /// Level 20 →  310 XP   Level 30 →  630 XP   (Gesamt ~6.855 XP)
  /// Level 40 → 1070 XP   Level 50 → 1630 XP   (Gesamt ~28.155 XP)
  /// Bei ~100 XP/Tag erreichbar in ca. 280 Lerntagen.
  static int calculateXPForLevel(int level) {
    if (level <= 0) return 0;
    if (level > maxLevel) return calculateXPForLevel(maxLevel);
    // Formel: 30 + 2*level + 0.6*level²  (gerundet auf 5er-Schritte)
    final raw = 30 + (2 * level) + (level * level * 0.6).toInt();
    return (raw / 5).round() * 5;
  }

  /// Rang-Titel und Emoji für ein gegebenes Level
  static ({String title, String emoji, Color color}) getRankForLevel(
    int level,
  ) {
    if (level <= 10) {
      return (title: 'Lernling', emoji: '📚', color: const Color(0xFF78909C));
    }
    if (level <= 20) {
      return (title: 'Entdecker', emoji: '🔍', color: const Color(0xFF29B6F6));
    }
    if (level <= 30) {
      return (title: 'Forscher', emoji: '🔬', color: const Color(0xFF66BB6A));
    }
    if (level <= 40) {
      return (title: 'Experte', emoji: '🎓', color: const Color(0xFFFFA726));
    }
    return (title: 'Meister', emoji: '🏆', color: const Color(0xFFEF5350));
  }

  /// Berechnet Level basierend auf Gesamt-XP (1–50)
  static int calculateLevelFromXP(int totalXP) {
    int level = 1;
    int accumulatedXP = 0;

    while (level < maxLevel) {
      final xpForThisLevel = calculateXPForLevel(level);
      if (totalXP < accumulatedXP + xpForThisLevel) break;
      accumulatedXP += xpForThisLevel;
      level++;
    }

    return level;
  }

  /// Berechnet XP die der Spieler im aktuellen Level bereits gesammelt hat
  static int calculateXPInCurrentLevel(int totalXP, int currentLevel) {
    int accumulatedXP = 0;
    for (int i = 1; i < currentLevel; i++) {
      accumulatedXP += calculateXPForLevel(i);
    }
    return totalXP - accumulatedXP;
  }

  /// Berechnet verbleibende XP zum nächsten Level
  static int calculateXPToNextLevel(int totalXP, int currentLevel) {
    if (currentLevel >= maxLevel) return 0; // Max-Level erreicht
    final xpInLevel = calculateXPInCurrentLevel(totalXP, currentLevel);
    return calculateXPForLevel(currentLevel) - xpInLevel;
  }

  // =========================================================================
  // XP HINZUFÜGEN
  // =========================================================================

  /// Fügt XP hinzu und gibt Ergebnis zurück
  Future<XPResult> addXP({
    required String userId,
    required String childId,
    required int xpToAdd,
  }) async {
    try {
      final docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(childId);

      final result = await _firestore.runTransaction<XPResult>((
        transaction,
      ) async {
        final snapshot = await transaction.get(docRef);

        if (!snapshot.exists) {
          throw Exception('Kind nicht gefunden');
        }

        final data = snapshot.data()!;
        final currentXP = data['xp'] ?? 0;
        final currentLevel = data['level'] ?? 1;

        final newXP = currentXP + xpToAdd;
        final newLevel = calculateLevelFromXP(newXP);
        final leveledUp = newLevel > currentLevel;
        final xpToNext = calculateXPToNextLevel(newXP, newLevel);

        transaction.update(docRef, {
          'xp': newXP,
          'level': newLevel,
          'xpToNextLevel': xpToNext,
          'lastXPGain': FieldValue.serverTimestamp(),
        });

        return XPResult(
          newXP: newXP,
          newLevel: newLevel,
          leveledUp: leveledUp,
          xpGained: xpToAdd,
          xpToNextLevel: xpToNext,
        );
      });

      print(
        '✅ XP hinzugefügt: +$xpToAdd XP → Gesamt: ${result.newXP} XP, Level: ${result.newLevel}',
      );
      return result;
    } catch (e) {
      print('❌ Fehler beim Hinzufügen von XP: $e');
      rethrow;
    }
  }

  // =========================================================================
  // TUTOR XP – mit Session- und Tageslimit
  // =========================================================================

  /// Vergib XP für eine Tutor-Nachricht.
  /// Gibt null zurück wenn das Session- oder Tageslimit bereits erreicht ist.
  Future<XPResult?> addTutorXP({
    required String userId,
    required String childId,
    required int sessionXpSoFar,
    int xpPerMessage = 2,
    int maxXpPerSession = 20,
    int maxXpPerDay = 50,
  }) async {
    if (sessionXpSoFar >= maxXpPerSession) return null;

    try {
      final docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(childId);

      return await _firestore.runTransaction<XPResult?>((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) return null;

        final data = snapshot.data()!;

        // Tageslimit prüfen mit Tages-Reset
        final lastDate = (data['tutorXpLastDate'] as Timestamp?)?.toDate();
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        int tutorXpToday = data['tutorXpToday'] ?? 0;
        if (lastDate == null ||
            DateTime(lastDate.year, lastDate.month, lastDate.day) != today) {
          tutorXpToday = 0; // Neuer Tag → Reset
        }

        if (tutorXpToday >= maxXpPerDay) return null;

        // Kleinsten erlaubten Wert aus allen Limits wählen
        final remainingDay = maxXpPerDay - tutorXpToday;
        final remainingSession = maxXpPerSession - sessionXpSoFar;
        final actualXP = [
          xpPerMessage,
          remainingDay,
          remainingSession,
        ].reduce((a, b) => a < b ? a : b);

        if (actualXP <= 0) return null;

        final currentXP = data['xp'] ?? 0;
        final currentLevel = data['level'] ?? 1;
        final newXP = currentXP + actualXP;
        final newLevel = calculateLevelFromXP(newXP);
        final leveledUp = newLevel > currentLevel;
        final xpToNext = calculateXPToNextLevel(newXP, newLevel);

        transaction.update(docRef, {
          'xp': newXP,
          'level': newLevel,
          'xpToNextLevel': xpToNext,
          'tutorXpToday': tutorXpToday + actualXP,
          'tutorXpLastDate': Timestamp.fromDate(now),
          'lastXPGain': FieldValue.serverTimestamp(),
        });

        return XPResult(
          newXP: newXP,
          newLevel: newLevel,
          leveledUp: leveledUp,
          xpGained: actualXP,
          xpToNextLevel: xpToNext,
        );
      });
    } catch (e) {
      print('❌ addTutorXP Fehler: $e');
      return null;
    }
  }

  // =========================================================================
  // QUIZ-STATISTIKEN
  // =========================================================================

  /// Aktualisiert Quiz-Statistiken
  Future<void> updateQuizStats({
    required String userId,
    required String childId,
    required bool isPerfect,
  }) async {
    try {
      final docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(childId);

      await docRef.update({
        'totalQuizzes': FieldValue.increment(1),
        if (isPerfect) 'perfectQuizzes': FieldValue.increment(1),
        'lastQuizDate': FieldValue.serverTimestamp(),
      });

      print('✅ Quiz-Statistiken aktualisiert (Perfect: $isPerfect)');
    } catch (e) {
      print('❌ Fehler beim Aktualisieren der Quiz-Stats: $e');
    }
  }

  // =========================================================================
  // STREAK — KORRIGIERTE IMPLEMENTIERUNG
  // =========================================================================

  /// Berechnet ob zwei DateTime-Werte am selben Kalendertag liegen
  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Berechnet ob zwei DateTime-Werte genau einen Kalendertag auseinander liegen
  static bool _isYesterday(DateTime earlier, DateTime later) {
    final earlierDay = DateTime(earlier.year, earlier.month, earlier.day);
    final laterDay = DateTime(later.year, later.month, later.day);
    return laterDay.difference(earlierDay).inDays == 1;
  }

  /// Aktualisiert den Streak basierend auf Kalender-Tagen (nicht 24h-Blöcken).
  ///
  /// ✅ FIX: Nutzt midnight-basierte Differenz statt .inDays (hours/24).
  ///    Beispiel: Lernen um 23:00, nächster Tag 00:30 → korrekt als "gestern" erkannt.
  ///
  /// Gibt den neuen Streak-Wert zurück.
  Future<int> updateStreak({
    required String userId,
    required String childId,
  }) async {
    // Kein try/catch mehr – Fehler sollen sichtbar nach oben propagieren
    // damit _finishQuiz() sie im Stack-Trace sieht.
    final docRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId);

    print('🔥 updateStreak() gestartet für childId=$childId');

    final snapshot = await docRef.get();
    final data = snapshot.data();

    if (data == null) {
      print('❌ updateStreak: Kein Dokument gefunden für childId=$childId');
      return 0;
    }

    print(
      '🔥 Firestore: streak=' +
          data['streak'].toString() +
          ', lastLearning=' +
          data['lastLearningDate'].toString(),
    );

    final lastLearning = (data['lastLearningDate'] as Timestamp?)?.toDate();
    final currentStreak = (data['streak'] as int?) ?? 0;
    final now = DateTime.now();

    int newStreak;

    if (lastLearning == null) {
      newStreak = 1;
      print('🔥 Streak: Erster Lerntag → Streak = 1');
    } else if (_isSameDay(lastLearning, now)) {
      // Heute bereits gelernt: war streak noch 0 (Bug-Legacy), auf 1 korrigieren
      newStreak = currentStreak < 1 ? 1 : currentStreak;
      print(
        '🔥 Streak: Heute bereits gelernt → $newStreak (war $currentStreak)',
      );
    } else if (_isYesterday(lastLearning, now)) {
      newStreak = currentStreak + 1;
      print('🔥 Streak: Gestern gelernt → erhöht auf $newStreak');
    } else {
      newStreak = 1;
      print('🔥 Streak: Pause > 1 Tag → zurückgesetzt auf 1');
    }

    await docRef.update({
      'streak': newStreak,
      'lastLearningDate': FieldValue.serverTimestamp(),
    });

    print('✅ Streak gespeichert: $newStreak Tage');
    return newStreak;
  }

  // =========================================================================
  // KIND-DATEN LADEN
  // =========================================================================

  /// Holt aktuelle Kind-Daten aus Firestore
  Future<ChildModel?> getChild({
    required String userId,
    required String childId,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(childId)
          .get();

      if (!snapshot.exists) return null;

      return ChildModel.fromFirestore(snapshot.data()!, childId);
    } catch (e) {
      print('❌ Fehler beim Laden des Kindes: $e');
      return null;
    }
  }
}

/// Provider für XP Service
final xpServiceProvider = Provider<XPService>((ref) {
  return XPService(FirebaseFirestore.instance);
});
