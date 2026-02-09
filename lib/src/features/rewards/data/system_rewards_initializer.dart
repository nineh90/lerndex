import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/reward_enums.dart';

/// 🎁 SYSTEM-BELOHNUNGEN INITIALIZER
/// Erstellt automatisch System-Belohnungen für neue Kinder

class SystemRewardsInitializer {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Vordefinierte System-Belohnungen für alle Kinder
  static final List<Map<String, dynamic>> _defaultSystemRewards = [
    // ========== LEVEL-BASIERTE BELOHNUNGEN ==========
    {
      'title': '🎉 Erste Schritte!',
      'description': 'Du hast dein erstes Level erreicht!',
      'reward': '15 Minuten Extra-Spielzeit',
      'trigger': 'level',
      'requiredLevel': 2,
    },
    {
      'title': '🌟 Auf dem Weg nach oben!',
      'description': 'Level 3 geschafft - super!',
      'reward': '30 Minuten Extra-Spielzeit',
      'trigger': 'level',
      'requiredLevel': 3,
    },
    {
      'title': '🚀 Fortgeschrittener!',
      'description': 'Wow, Level 5! Du bist richtig gut!',
      'reward': '1 Stunde Extra-Spielzeit',
      'trigger': 'level',
      'requiredLevel': 5,
    },
    {
      'title': '⭐ Experte!',
      'description': 'Level 7 - das ist beeindruckend!',
      'reward': 'Wunsch-Essen aussuchen',
      'trigger': 'level',
      'requiredLevel': 7,
    },
    {
      'title': '👑 Meister!',
      'description': 'Level 10 erreicht! Du bist ein echter Meister!',
      'reward': 'Kleines Geschenk deiner Wahl',
      'trigger': 'level',
      'requiredLevel': 10,
    },
    {
      'title': '🏆 Champion!',
      'description': 'Level 15 - Unglaublich!',
      'reward': 'Ausflug nach Wahl',
      'trigger': 'level',
      'requiredLevel': 15,
    },
    {
      'title': '💎 Legende!',
      'description': 'Level 20! Du bist eine Legende!',
      'reward': 'Besonderes Geschenk + Familien-Aktivität',
      'trigger': 'level',
      'requiredLevel': 20,
    },

    // ========== XP-BASIERTE BELOHNUNGEN ==========
    {
      'title': '💪 100 XP gesammelt!',
      'description': 'Du hast fleißig gelernt!',
      'reward': 'Extra Nachtisch',
      'trigger': 'xp',
      'requiredXP': 100,
    },
    {
      'title': '🔥 500 XP Meilenstein!',
      'description': 'Wow, so viel XP!',
      'reward': 'Film-Abend selbst aussuchen',
      'trigger': 'xp',
      'requiredXP': 500,
    },
    {
      'title': '⚡ 1000 XP erreicht!',
      'description': 'Das ist eine großartige Leistung!',
      'reward': 'Freund zum Spielen einladen',
      'trigger': 'xp',
      'requiredXP': 1000,
    },

    // ========== STREAK-BASIERTE BELOHNUNGEN ==========
    {
      'title': '🔥 3 Tage Streak!',
      'description': '3 Tage am Stück gelernt!',
      'reward': 'Sticker-Set',
      'trigger': 'streak',
      'requiredStreak': 3,
    },
    {
      'title': '⚡ 7 Tage Streak!',
      'description': 'Eine ganze Woche durchgehalten!',
      'reward': 'Extra Taschengeld',
      'trigger': 'streak',
      'requiredStreak': 7,
    },
    {
      'title': '🌟 14 Tage Streak!',
      'description': 'Zwei Wochen Durchhaltevermögen!',
      'reward': 'Neues Buch oder Comic',
      'trigger': 'streak',
      'requiredStreak': 14,
    },
    {
      'title': '👑 30 Tage Streak!',
      'description': 'Ein ganzer Monat! Unglaublich!',
      'reward': 'Größeres Geschenk nach Wahl',
      'trigger': 'streak',
      'requiredStreak': 30,
    },

    // ========== QUIZ-COUNT BELOHNUNGEN ==========
    {
      'title': '📚 10 Quizze geschafft!',
      'description': 'Du bist fleißig am Lernen!',
      'reward': 'Kleine Überraschung',
      'trigger': 'quiz_count',
      'requiredQuizCount': 10,
    },
    {
      'title': '🎯 25 Quizze absolviert!',
      'description': 'So viel Wissen!',
      'reward': 'Familien-Spieleabend',
      'trigger': 'quiz_count',
      'requiredQuizCount': 25,
    },
    {
      'title': '🏅 50 Quizze gemeistert!',
      'description': 'Ein halbes Hundert geschafft!',
      'reward': 'Ausflug ins Kino oder Museum',
      'trigger': 'quiz_count',
      'requiredQuizCount': 50,
    },
    {
      'title': '💯 100 Quizze abgeschlossen!',
      'description': 'Du bist ein Quiz-Meister!',
      'reward': 'Großer Ausflug nach Wahl',
      'trigger': 'quiz_count',
      'requiredQuizCount': 100,
    },

    // ========== SPEZIAL-BELOHNUNGEN ==========
    {
      'title': '⭐ Perfektes Quiz!',
      'description': 'Alle Fragen richtig beantwortet!',
      'reward': 'Bonus-Sterne + Süßigkeit',
      'trigger': 'perfect_quiz',
    },
  ];

  /// Initialisiert alle System-Belohnungen für ein neues Kind
  Future<void> initializeSystemRewards({
    required String userId,
    required String childId,
  }) async {
    try {
      print('🎁 Initialisiere System-Belohnungen für Kind: $childId');

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

        // Füge Trigger-Bedingungen hinzu
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

        batch.set(docRef, data);
        count++;
      }

      await batch.commit();
      print('✅ $count System-Belohnungen erstellt');

    } catch (e, stackTrace) {
      print('❌ Fehler beim Initialisieren der System-Belohnungen: $e');
      print('Stack: $stackTrace');
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
      print('🔍 Prüfe fehlende System-Belohnungen für Kind: $childId');

      // Hole existierende System-Belohnungen
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

      // Filtere fehlende Belohnungen
      final missingRewards = _defaultSystemRewards
          .where((reward) => !existingTitles.contains(reward['title']))
          .toList();

      if (missingRewards.isEmpty) {
        print('✅ Alle System-Belohnungen bereits vorhanden');
        return;
      }

      print('📝 Füge ${missingRewards.length} fehlende Belohnungen hinzu');

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

        batch.set(docRef, data);
      }

      await batch.commit();
      print('✅ ${missingRewards.length} Belohnungen hinzugefügt');

    } catch (e, stackTrace) {
      print('❌ Fehler beim Hinzufügen fehlender Belohnungen: $e');
      print('Stack: $stackTrace');
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