import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// 🏆 SYSTEM-BELOHNUNGEN INITIALIZER
/// Erstellt automatisch In-App-Achievements für neue Kinder.
/// Systembelohnungen sind ausschließlich digitale Belohnungen (XP, Avatare,
/// Badges, Titel) – keine echten Geschenke. Echte Geschenke werden von
/// Eltern über eigene Belohnungen (RewardType.parent) vergeben.

class SystemRewardsInitializer {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Vordefinierte System-Belohnungen (rein digital, kein Eltern-OK nötig)
  static final List<Map<String, dynamic>> _defaultSystemRewards = [
    // ========== LEVEL-BASIERTE BELOHNUNGEN ==========
    {
      'title': '🎉 Erste Schritte!',
      'description': 'Du hast Level 2 erreicht – dein Abenteuer beginnt!',
      'reward': '+25 Bonus-XP & Titel „Einsteiger"',
      'trigger': 'level',
      'requiredLevel': 2,
      'bonusXP': 25,
      'badgeId': 'badge-level-2',
    },
    {
      'title': '🌟 Auf dem Weg nach oben!',
      'description': 'Level 3 geschafft – du wächst!',
      'reward': '+50 Bonus-XP & Titel „Lernender"',
      'trigger': 'level',
      'requiredLevel': 3,
      'bonusXP': 50,
      'badgeId': 'badge-level-3',
    },
    {
      'title': '🚀 Fortgeschrittener!',
      'description': 'Wow, Level 5! Du bist richtig gut!',
      'reward': '+100 Bonus-XP & Titel „Fortgeschrittener"',
      'trigger': 'level',
      'requiredLevel': 5,
      'bonusXP': 100,
      'badgeId': 'badge-level-5',
    },
    {
      'title': '⭐ Experte!',
      'description': 'Level 7 – das ist beeindruckend!',
      'reward': '+150 Bonus-XP & Titel „Experte" freigeschaltet',
      'trigger': 'level',
      'requiredLevel': 7,
      'bonusXP': 150,
      'badgeId': 'badge-level-7',
    },
    {
      'title': '👑 Meister!',
      'description': 'Level 10 erreicht! Du bist ein echter Meister!',
      'reward': '+250 Bonus-XP & Titel „Meister"',
      'trigger': 'level',
      'requiredLevel': 10,
      'bonusXP': 250,
      'badgeId': 'badge-level-10',
    },
    {
      'title': '🏆 Champion!',
      'description': 'Level 15 – Unglaublich!',
      'reward': '+400 Bonus-XP & exklusiver Champion-Avatar freigeschaltet',
      'trigger': 'level',
      'requiredLevel': 15,
      'bonusXP': 400,
      'badgeId': 'badge-level-15',
      'avatarUnlockId': 'avatar-champion',
    },
    {
      'title': '💎 Legende!',
      'description': 'Level 20! Du bist eine Legende!',
      'reward': '+750 Bonus-XP & legendärer Avatar + Titel „Legende"',
      'trigger': 'level',
      'requiredLevel': 20,
      'bonusXP': 750,
      'badgeId': 'badge-level-20',
      'avatarUnlockId': 'avatar-legend',
    },

    // ========== XP-BASIERTE BELOHNUNGEN ==========
    {
      'title': '💪 Fleißige Lernerin!',
      'description': 'Meilenstein: 100 XP gesammelt – weiter so!',
      'reward': '+20 Bonus-XP & Badge „Fleißig"',
      'trigger': 'xp',
      'requiredXP': 100,
      'bonusXP': 20,
      'badgeId': 'badge-xp-100',
    },
    {
      'title': '🔥 Super Lernerin!',
      'description':
          'Meilenstein: 500 XP gesammelt! Du bist auf dem richtigen Weg!',
      'reward': '+75 Bonus-XP & Titel „XP-Sammler"',
      'trigger': 'xp',
      'requiredXP': 500,
      'bonusXP': 75,
      'badgeId': 'badge-xp-500',
    },
    {
      'title': '⚡ Unaufhaltsam!',
      'description': 'Meilenstein: 1.000 XP! Das ist eine großartige Leistung!',
      'reward': '+150 Bonus-XP & Titel „XP-Jäger" + Badge „1k Club"',
      'trigger': 'xp',
      'requiredXP': 1000,
      'bonusXP': 150,
      'badgeId': 'badge-xp-1000',
    },
    {
      'title': '🌠 5.000 XP – Wahnsinn!',
      'description': '5.000 XP gesammelt – du bist unaufhaltsam!',
      'reward': '+500 Bonus-XP & exklusiver „5k"-Avatar freigeschaltet',
      'trigger': 'xp',
      'requiredXP': 5000,
      'bonusXP': 500,
      'badgeId': 'badge-xp-5000',
      'avatarUnlockId': 'avatar-xp-5k',
    },

    // ========== STREAK-BASIERTE BELOHNUNGEN ==========
    {
      'title': '🔥 7 Tage Streak!',
      'description': 'Eine ganze Woche am Stück gelernt – mega!',
      'reward': '+50 Bonus-XP',
      'trigger': 'streak',
      'requiredStreak': 7,
      'bonusXP': 50,
      'badgeId': 'badge-streak-7',
    },
    {
      'title': '⚡ 14 Tage Streak!',
      'description':
          'Zwei Wochen Durchhaltevermögen! Du bist ein Streak-Profi!',
      'reward': '+100 Bonus-XP & exklusiver Streak-Avatar freigeschaltet',
      'trigger': 'streak',
      'requiredStreak': 14,
      'bonusXP': 100,
      'badgeId': 'badge-streak-14',
      'avatarUnlockId': 'avatar-streak-uncommon',
    },
    {
      'title': '🌟 21 Tage Streak!',
      'description': 'Drei Wochen! Unglaublich konsequent!',
      'reward': '+200 Bonus-XP & Titel „Streak-Krieger"',
      'trigger': 'streak',
      'requiredStreak': 21,
      'bonusXP': 200,
      'badgeId': 'badge-streak-21',
    },
    {
      'title': '👑 28 Tage Streak!',
      'description': 'Vier Wochen am Stück – du bist ein echter Champion!',
      'reward': '+300 Bonus-XP & epischer Streak-Avatar freigeschaltet',
      'trigger': 'streak',
      'requiredStreak': 28,
      'bonusXP': 300,
      'badgeId': 'badge-streak-28',
      'avatarUnlockId': 'avatar-streak-epic',
    },
    {
      'title': '💎 35 Tage Streak!',
      'description': 'Fünf Wochen! Du bist eine Lernmaschine!',
      'reward': '+500 Bonus-XP & Titel „Lernmaschine"',
      'trigger': 'streak',
      'requiredStreak': 35,
      'bonusXP': 500,
      'badgeId': 'badge-streak-35',
    },
    {
      'title': '🏆 42 Tage Streak!',
      'description':
          'Sechs Wochen! Legendär! Der mächtigste Avatar gehört dir!',
      'reward': '+750 Bonus-XP & legendärer Streak-Avatar freigeschaltet',
      'trigger': 'streak',
      'requiredStreak': 42,
      'bonusXP': 750,
      'badgeId': 'badge-streak-42',
      'avatarUnlockId': 'avatar-streak-legendary',
    },

    // ========== QUIZ-COUNT BELOHNUNGEN ==========
    {
      'title': '📚 10 Quizze geschafft!',
      'description': 'Du bist fleißig am Lernen!',
      'reward': '+30 Bonus-XP & Badge „Quiz-Starter"',
      'trigger': 'quiz_count',
      'requiredQuizCount': 10,
      'bonusXP': 30,
      'badgeId': 'badge-quiz-10',
    },
    {
      'title': '🎯 25 Quizze absolviert!',
      'description': 'So viel Wissen angesammelt!',
      'reward': '+75 Bonus-XP & Titel „Wissenshungrig"',
      'trigger': 'quiz_count',
      'requiredQuizCount': 25,
      'bonusXP': 75,
      'badgeId': 'badge-quiz-25',
    },
    {
      'title': '🏅 50 Quizze gemeistert!',
      'description': 'Ein halbes Hundert – beeindruckend!',
      'reward': '+150 Bonus-XP & Titel „Quiz-Profi"',
      'trigger': 'quiz_count',
      'requiredQuizCount': 50,
      'bonusXP': 150,
      'badgeId': 'badge-quiz-50',
    },
    {
      'title': '💯 100 Quizze abgeschlossen!',
      'description': 'Du bist ein echter Quiz-Meister!',
      'reward': '+300 Bonus-XP & legendärer Quiz-Avatar freigeschaltet',
      'trigger': 'quiz_count',
      'requiredQuizCount': 100,
      'bonusXP': 300,
      'badgeId': 'badge-quiz-100',
      'avatarUnlockId': 'avatar-quiz-master',
    },

    // ========== SPEZIAL-BELOHNUNGEN ==========
    {
      'title': '⭐ Perfektes Quiz!',
      'description': 'Alle Fragen auf Anhieb richtig beantwortet!',
      'reward': '+40 Bonus-XP & Badge „Perfektionist"',
      'trigger': 'perfect_quiz',
      'bonusXP': 40,
      'badgeId': 'badge-perfect-quiz',
    },
  ];

  /// Initialisiert alle System-Belohnungen für ein neues Kind
  Future<void> initializeSystemRewards({
    required String userId,
    required String childId,
  }) async {
    try {
      debugPrint('🎁 Initialisiere System-Belohnungen für Kind: $childId');

      final batch = _firestore.batch();
      final rewardsCollection = _firestore
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(childId)
          .collection('rewards');

      int count = 0;
      for (final rewardData in _defaultSystemRewards) {
        final docRef = rewardsCollection.doc();

        final data = {
          'childId': childId,
          'title': rewardData['title'],
          'description': rewardData['description'],
          'reward': rewardData['reward'],
          'type': 'system',
          'trigger': rewardData['trigger'],
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': 'system',
        };

        // Trigger-Bedingungen
        if (rewardData.containsKey('requiredLevel')) {
          data['requiredLevel'] = rewardData['requiredLevel'];
        }
        if (rewardData.containsKey('requiredXP')) {
          data['requiredXP'] = rewardData['requiredXP'];
        }
        if (rewardData.containsKey('requiredStars')) {
          data['requiredStars'] = rewardData['requiredStars'];
        }
        if (rewardData.containsKey('requiredStreak')) {
          data['requiredStreak'] = rewardData['requiredStreak'];
        }
        if (rewardData.containsKey('requiredQuizCount')) {
          data['requiredQuizCount'] = rewardData['requiredQuizCount'];
        }
        // In-App-Belohnungs-Metadaten
        if (rewardData.containsKey('bonusXP')) {
          data['bonusXP'] = rewardData['bonusXP'];
        }
        if (rewardData.containsKey('avatarUnlockId')) {
          data['avatarUnlockId'] = rewardData['avatarUnlockId'];
        }
        if (rewardData.containsKey('badgeId')) {
          data['badgeId'] = rewardData['badgeId'];
        }

        batch.set(docRef, data);
        count++;
      }

      await batch.commit();
      debugPrint('✅ $count System-Belohnungen erstellt');
    } catch (e, stackTrace) {
      debugPrint('❌ Fehler beim Initialisieren der System-Belohnungen: $e');
      debugPrint('Stack: $stackTrace');
      rethrow;
    }
  }

  /// Prüft ob System-Belohnungen bereits existieren
  Future<bool> hasSystemRewards({
    required String userId,
    required String childId,
  }) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('rewards')
        .where('type', isEqualTo: 'system')
        .limit(1)
        .get();

    return snapshot.docs.isNotEmpty;
  }

  /// Fügt fehlende System-Belohnungen hinzu (für existierende Kinder)
  Future<void> addMissingSystemRewards({
    required String userId,
    required String childId,
  }) async {
    try {
      debugPrint('🔍 Prüfe fehlende System-Belohnungen für Kind: $childId');

      final existingSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(childId)
          .collection('rewards')
          .where('type', isEqualTo: 'system')
          .get();

      final existingTitles = existingSnapshot.docs
          .map((doc) => doc.data()['title'] as String)
          .toSet();

      final missingRewards = _defaultSystemRewards
          .where((reward) => !existingTitles.contains(reward['title']))
          .toList();

      if (missingRewards.isEmpty) {
        debugPrint('✅ Alle System-Belohnungen bereits vorhanden');
        return;
      }

      debugPrint('📝 Füge ${missingRewards.length} fehlende Belohnungen hinzu');

      final batch = _firestore.batch();
      final rewardsCollection = _firestore
          .collection('users')
          .doc(userId)
          .collection('children')
          .doc(childId)
          .collection('rewards');

      for (final rewardData in missingRewards) {
        final docRef = rewardsCollection.doc();

        final data = {
          'childId': childId,
          'title': rewardData['title'],
          'description': rewardData['description'],
          'reward': rewardData['reward'],
          'type': 'system',
          'trigger': rewardData['trigger'],
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': 'system',
        };

        if (rewardData.containsKey('requiredLevel')) {
          data['requiredLevel'] = rewardData['requiredLevel'];
        }
        if (rewardData.containsKey('requiredXP')) {
          data['requiredXP'] = rewardData['requiredXP'];
        }
        if (rewardData.containsKey('requiredStars')) {
          data['requiredStars'] = rewardData['requiredStars'];
        }
        if (rewardData.containsKey('requiredStreak')) {
          data['requiredStreak'] = rewardData['requiredStreak'];
        }
        if (rewardData.containsKey('requiredQuizCount')) {
          data['requiredQuizCount'] = rewardData['requiredQuizCount'];
        }
        if (rewardData.containsKey('bonusXP')) {
          data['bonusXP'] = rewardData['bonusXP'];
        }
        if (rewardData.containsKey('avatarUnlockId')) {
          data['avatarUnlockId'] = rewardData['avatarUnlockId'];
        }
        if (rewardData.containsKey('badgeId')) {
          data['badgeId'] = rewardData['badgeId'];
        }

        batch.set(docRef, data);
      }

      await batch.commit();
      debugPrint('✅ ${missingRewards.length} Belohnungen hinzugefügt');
    } catch (e, stackTrace) {
      debugPrint('❌ Fehler beim Hinzufügen fehlender Belohnungen: $e');
      debugPrint('Stack: $stackTrace');
    }
  }

  /// Zählt wie viele System-Belohnungen ein Kind hat
  Future<int> countSystemRewards({
    required String userId,
    required String childId,
  }) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('children')
        .doc(childId)
        .collection('rewards')
        .where('type', isEqualTo: 'system')
        .count()
        .get();

    return snapshot.count ?? 0;
  }
}
