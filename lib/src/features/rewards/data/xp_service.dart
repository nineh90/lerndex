import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/child_model.dart';
import '../domain/xp_result.dart';

/// Service für XP-Verwaltung und Level-Berechnung
class XPService {
  final FirebaseFirestore _firestore;

  XPService(this._firestore);

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

      // Transaktion für atomare Aktualisierung
      final result = await _firestore.runTransaction<XPResult>((transaction) async {
        final snapshot = await transaction.get(docRef);

        if (!snapshot.exists) {
          throw Exception('Kind nicht gefunden');
        }

        final data = snapshot.data()!;
        final currentXP = data['xp'] ?? 0;
        final currentLevel = data['level'] ?? 1;

        // Neue XP berechnen
        final newXP = currentXP + xpToAdd;
        final newLevel = calculateLevelFromXP(newXP);
        final leveledUp = newLevel > currentLevel;
        final xpToNext = calculateXPToNextLevel(newXP, newLevel);

        // Firestore aktualisieren
        transaction.update(docRef, {
          'xp': newXP,
          'level': newLevel,
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

      print('✅ Quiz-Statistiken aktualisiert');
    } catch (e) {
      print('❌ Fehler beim Aktualisieren der Quiz-Stats: $e');
    }
  }

  /// Aktualisiert Streak (Lern-Serie)
  Future<void> updateStreak({
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

      if (data == null) return;

      final lastLearning = (data['lastLearningDate'] as Timestamp?)?.toDate();
      final currentStreak = data['streak'] ?? 0;
      final now = DateTime.now();

      int newStreak = 1;

      if (lastLearning != null) {
        final daysSinceLastLearning = now.difference(lastLearning).inDays;

        if (daysSinceLastLearning == 0) {
          // Heute schon gelernt → Streak bleibt
          newStreak = currentStreak;
        } else if (daysSinceLastLearning == 1) {
          // Gestern gelernt → Streak erhöhen
          newStreak = currentStreak + 1;
        } else {
          // Länger als 1 Tag → Streak zurücksetzen
          newStreak = 1;
        }
      }

      await docRef.update({
        'streak': newStreak,
        'lastLearningDate': FieldValue.serverTimestamp(),
      });

      print('✅ Streak aktualisiert: $newStreak Tage');
    } catch (e) {
      print('❌ Fehler beim Aktualisieren des Streaks: $e');
    }
  }

  /// Holt aktuelle Kind-Daten
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