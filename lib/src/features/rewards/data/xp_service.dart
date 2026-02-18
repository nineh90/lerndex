import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/child_model.dart';
import '../domain/xp_result.dart';

/// Service für XP-Verwaltung und Level-Berechnung
class XPService {
  final FirebaseFirestore _firestore;

  XPService(this._firestore);

  // =========================================================================
  // LEVEL & XP BERECHNUNG
  // =========================================================================

  /// Berechnet benötigte XP für ein Level
  /// Formel: 25 + (level * 25) bis Level 10, dann 250
  static int calculateXPForLevel(int level) {
    if (level <= 0) return 0;
    if (level >= 10) return 250;
    return 25 + (level * 25);
  }

  /// Berechnet Level basierend auf XP
  static int calculateLevelFromXP(int totalXP) {
    int level = 1;
    int xpForNextLevel = calculateXPForLevel(level);
    int accumulatedXP = 0;

    while (totalXP >= accumulatedXP + xpForNextLevel) {
      accumulatedXP += xpForNextLevel;
      level++;
      xpForNextLevel = calculateXPForLevel(level);
    }

    return level;
  }

  /// Berechnet verbleibende XP zum nächsten Level
  static int calculateXPToNextLevel(int totalXP, int currentLevel) {
    int xpForCurrentLevel = 0;
    for (int i = 1; i < currentLevel; i++) {
      xpForCurrentLevel += calculateXPForLevel(i);
    }
    int xpInCurrentLevel = totalXP - xpForCurrentLevel;
    int xpNeededForNextLevel = calculateXPForLevel(currentLevel);
    return xpNeededForNextLevel - xpInCurrentLevel;
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

      final result = await _firestore.runTransaction<XPResult>((transaction) async {
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

      print('✅ XP hinzugefügt: +$xpToAdd XP → Gesamt: ${result.newXP} XP, Level: ${result.newLevel}');
      return result;
    } catch (e) {
      print('❌ Fehler beim Hinzufügen von XP: $e');
      rethrow;
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
    try {
      final docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(childId);

      final snapshot = await docRef.get();
      final data = snapshot.data();

      if (data == null) return 0;

      final lastLearning = (data['lastLearningDate'] as Timestamp?)?.toDate();
      final currentStreak = (data['streak'] as int?) ?? 0;
      final now = DateTime.now();

      int newStreak;

      if (lastLearning == null) {
        // Erstes Mal überhaupt gelernt
        newStreak = 1;
        print('🔥 Streak: Erster Lerntag → Streak = 1');
      } else if (_isSameDay(lastLearning, now)) {
        // Heute bereits gelernt → Streak bleibt unverändert
        newStreak = currentStreak;
        print('🔥 Streak: Heute bereits gelernt → bleibt bei $currentStreak');
      } else if (_isYesterday(lastLearning, now)) {
        // Gestern gelernt → Streak um 1 erhöhen
        newStreak = currentStreak + 1;
        print('🔥 Streak: Gestern gelernt → erhöht auf $newStreak');
      } else {
        // Mehr als 1 Tag Pause → Streak zurücksetzen
        newStreak = 1;
        print('🔥 Streak: Pause > 1 Tag → zurückgesetzt auf 1');
      }

      await docRef.update({
        'streak': newStreak,
        'lastLearningDate': FieldValue.serverTimestamp(),
      });

      print('✅ Streak gespeichert: $newStreak Tage');
      return newStreak;
    } catch (e) {
      print('❌ Fehler beim Aktualisieren des Streaks: $e');
      return 0;
    }
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