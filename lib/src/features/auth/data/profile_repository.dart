import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:lerndex/src/features/subscription/data/subscription_model.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../domain/child_model.dart';
import '../../rewards/data/system_rewards_initializer.dart';
import '../../rewards/data/xp_service.dart';
import '../../quiz/data/quiz_prefetch_service.dart';
import 'auth_repository.dart';
// NEU: Subscription
import '../../subscription/data/subscription_service.dart';

part 'profile_repository.g.dart';

/// Repository für Profil-Verwaltung (Kinder hinzufügen, XP vergeben, etc.)
/// Kommuniziert mit Firestore
class ProfileRepository {
  ProfileRepository(this._firestore, this._auth);
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  /// Aktuell eingeloggter User (Eltern-Account)
  String get _uid => _auth.currentUser?.uid ?? '';

  /// Stream aller Kinder des eingeloggten Eltern-Accounts
  /// Aktualisiert sich automatisch bei Änderungen in Firestore
  Stream<List<ChildModel>> watchChildren() {
    debugPrint('🔍 currentUser: ${_auth.currentUser?.uid}');
    debugPrint('🔍 _uid getter: $_uid');

    return _firestore
        .collection('users')
        .doc(_uid)
        .collection('children')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ChildModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  /// Erstellt ein neues Kind — prüft vorher das Abo-Limit
  Future<String> createChild({
    required String name,
    required int age,
    required String schoolType,
    required int grade,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // ── Abo-Limit prüfen ───────────────────────────────────────────────────
    final subscriptionService = SubscriptionService(_firestore, _auth);
    final subscriptionStatus = await subscriptionService
        .getSubscriptionStatus();

    final existingSnapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('children')
        .count()
        .get();

    final currentCount = existingSnapshot.count ?? 0;
    final limit = subscriptionStatus.childLimit;

    if (currentCount >= limit) {
      throw ChildLimitReachedException(
        currentCount: currentCount,
        limit: limit,
        plan: subscriptionStatus.plan,
      );
    }
    // ── Ende Limit-Prüfung ─────────────────────────────────────────────────

    final childData = {
      'name': name,
      'age': age,
      'schoolType': schoolType,
      'grade': grade,
      'xp': 0,
      'level': 1,
      'streak': 0,
      'totalLearningSeconds': 0,
      'xpToNextLevel': XPService.calculateXPForLevel(1),
      'createdAt': FieldValue.serverTimestamp(),
    };

    final docRef = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('children')
        .add(childData);

    // System-Belohnungen erstellen
    try {
      final rewardsInitializer = SystemRewardsInitializer();
      await rewardsInitializer.initializeSystemRewards(
        userId: user.uid,
        childId: docRef.id,
      );

      final count = await rewardsInitializer.countSystemRewards(
        userId: user.uid,
        childId: docRef.id,
      );

      debugPrint('✅ Kind erstellt mit $count System-Belohnungen');
    } catch (e) {
      debugPrint('⚠️ Fehler beim Erstellen der System-Belohnungen: $e');
    }

    // Quiz-Fragen im Hintergrund vorgenerieren (fire-and-forget)
    // Das Kind hat beim ersten Login sofort Fragen bereit!
    _prefetchQuestionsForNewChild(
      userId: user.uid,
      childId: docRef.id,
      name: name,
      age: age,
      schoolType: schoolType,
      grade: grade,
    );

    return docRef.id;
  }

  /// Generiert Quiz-Fragen fuer ein neu erstelltes Kind.
  /// Laeuft komplett im Hintergrund (fire-and-forget).
  /// Fehler werden still verschluckt — beim ersten Quiz wuerde
  /// der Cache-Mechanismus einfach on-the-fly generieren.
  void _prefetchQuestionsForNewChild({
    required String userId,
    required String childId,
    required String name,
    required int age,
    required String schoolType,
    required int grade,
  }) {
    // ChildModel fuer den Prefetch zusammenbauen
    final child = ChildModel(
      id: childId,
      name: name,
      age: age,
      schoolType: schoolType,
      grade: grade,
      xp: 0,
      level: 1,
      streak: 0,
      totalLearningSeconds: 0,
      xpToNextLevel: XPService.calculateXPForLevel(1),
    );

    debugPrint(
      '🔮 Starte Quiz-Pre-Fetch fuer neues Kind: $name '
      '($schoolType, Klasse $grade)...',
    );

    // Fire-and-forget: Blockiert createChild() NICHT
    QuizPrefetchService.prefetchAllSubjects(userId: userId, child: child);
  }

  /// Migriert existierende Kinder (fügt System-Belohnungen hinzu)
  /// Kann einmalig von Eltern über einen Button aufgerufen werden
  Future<void> migrateExistingChildren() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final rewardsInitializer = SystemRewardsInitializer();

    final children = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('children')
        .get();

    for (final doc in children.docs) {
      final childId = doc.id;
      final childName = doc.data()['name'] ?? 'Unknown';

      debugPrint('🔧 Migriere Kind: $childName ($childId)');

      try {
        final hasRewards = await rewardsInitializer.hasSystemRewards(
          userId: user.uid,
          childId: childId,
        );

        if (!hasRewards) {
          debugPrint('  → Erstelle alle System-Belohnungen');
          await rewardsInitializer.initializeSystemRewards(
            userId: user.uid,
            childId: childId,
          );
        } else {
          debugPrint('  → Füge fehlende Belohnungen hinzu');
          await rewardsInitializer.addMissingSystemRewards(
            userId: user.uid,
            childId: childId,
          );
        }
      } catch (e) {
        debugPrint('  ❌ Fehler bei Migration für $childName: $e');
      }
    }

    debugPrint('✅ Migration abgeschlossen');
  }

  /// Aktualisiert die Sterne eines Kindes.
  ///
  /// ⚠️ HINWEIS: Wird aktuell nicht aufgerufen — Sterne werden nicht mehr
  /// aktiv vergeben. Bleibt erhalten für eine zukünftige Verwendung.
  /// Für Klasse 1–2 dienen Sterne nur noch als visuelle XP-Darstellung
  /// (Early-Learner-Dashboard), werden aber nicht über diese Methode gesetzt.
  Future<void> updateStars(
    String childId,
    int stars, {
    bool increment = true,
  }) async {
    final update = increment
        ? {'stars': FieldValue.increment(stars)}
        : {'stars': stars};

    await _firestore
        .collection('users')
        .doc(_uid)
        .collection('children')
        .doc(childId)
        .update(update);
  }

  /// Fügt Lernzeit in Sekunden hinzu
  Future<void> addLearningTime(String childId, int seconds) async {
    await _firestore
        .collection('users')
        .doc(_uid)
        .collection('children')
        .doc(childId)
        .update({'totalLearningSeconds': FieldValue.increment(seconds)});
  }

  /// Aktualisiert die Stammdaten eines Kindes (Name, Alter, Schulform, Klasse)
  /// Lernfortschritte (XP, Level, Sterne) werden NICHT verändert
  Future<void> updateChild({
    required String childId,
    required String name,
    required int age,
    required String schoolType,
    required int grade,
    List<String>? hiddenSubjects,
  }) async {
    final updates = <String, dynamic>{
      'name': name,
      'age': age,
      'schoolType': schoolType,
      'grade': grade,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (hiddenSubjects != null) {
      updates['hiddenSubjects'] = hiddenSubjects;
    }

    await _firestore
        .collection('users')
        .doc(_uid)
        .collection('children')
        .doc(childId)
        .update(updates);
  }

  /// Deaktiviert ein Kind (pausiert es) — Daten bleiben erhalten.
  /// Wird beim Plan-Downgrade aufgerufen.
  Future<void> deactivateChild(String childId) async {
    await _firestore
        .collection('users')
        .doc(_uid)
        .collection('children')
        .doc(childId)
        .update({'isActive': false});
    debugPrint('⏸ Kind deaktiviert: $childId');
  }

  /// Reaktiviert ein pausiertes Kind (nach Upgrade).
  Future<void> reactivateChild(String childId) async {
    await _firestore
        .collection('users')
        .doc(_uid)
        .collection('children')
        .doc(childId)
        .update({'isActive': true});
    debugPrint('▶️ Kind reaktiviert: $childId');
  }

  /// Stream nur der AKTIVEN Kinder (isActive != false)
  Stream<List<ChildModel>> watchActiveChildren() {
    return _firestore
        .collection('users')
        .doc(_uid)
        .collection('children')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ChildModel.fromMap(doc.data(), doc.id))
              .where((c) => c.isActive)
              .toList(),
        );
  }

  /// Löscht ein Kind
  Future<void> deleteChild(String childId) async {
    await _firestore
        .collection('users')
        .doc(_uid)
        .collection('children')
        .doc(childId)
        .delete();
  }

  /// Löscht alle Firestore-Daten eines Users komplett
  /// Wird vor dem Löschen des Firebase Auth Accounts aufgerufen
  Future<void> deleteAllUserData() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Kein Benutzer angemeldet.');

    final uid = user.uid;

    // Alle Kinder laden
    final childrenSnapshot = await _firestore
        .collection('users')
        .doc(uid)
        .collection('children')
        .get();

    // Für jedes Kind: Subcollections per Batch löschen (max 500 Ops pro Batch)
    for (final childDoc in childrenSnapshot.docs) {
      final childId = childDoc.id;

      for (final subcollection in [
        'tutor_chat',
        'tutor_sessions',
        'rewards',
        'learning_stats',
      ]) {
        final subDocs = await _firestore
            .collection('users')
            .doc(uid)
            .collection('children')
            .doc(childId)
            .collection(subcollection)
            .get();

        // Batch-Delete: bis zu 400 pro Batch (Firestore-Limit ist 500)
        for (var i = 0; i < subDocs.docs.length; i += 400) {
          final batch = _firestore.batch();
          final end = (i + 400 < subDocs.docs.length)
              ? i + 400
              : subDocs.docs.length;
          for (var j = i; j < end; j++) {
            batch.delete(subDocs.docs[j].reference);
          }
          await batch.commit();
        }
      }

      // Kind-Dokument selbst löschen
      await childDoc.reference.delete();
    }

    // Haupt-User-Dokument löschen (enthält PIN, etc.)
    await _firestore.collection('users').doc(uid).delete();
  }
} // Ende ProfileRepository

/// Provider für ProfileRepository
@riverpod
ProfileRepository profileRepository(ProfileRepositoryRef ref) {
  return ProfileRepository(FirebaseFirestore.instance, FirebaseAuth.instance);
}

@riverpod
Stream<List<ChildModel>> childrenList(ChildrenListRef ref) {
  final authState = ref.watch(authStateChangesProvider);
  final user = authState.value;
  if (user == null) return Stream.value([]);
  return ref.watch(profileRepositoryProvider).watchChildren();
}

// =============================================================================
// EXCEPTIONS
// =============================================================================

/// Wird geworfen wenn das Kind-Limit des Abos erreicht ist.
/// Die UI fängt diese Exception und öffnet die Paywall.
class ChildLimitReachedException implements Exception {
  final int currentCount;
  final int limit;
  final SubscriptionPlan plan;

  const ChildLimitReachedException({
    required this.currentCount,
    required this.limit,
    required this.plan,
  });

  @override
  String toString() {
    if (plan == SubscriptionPlan.none) {
      return 'Kein aktives Abo. Bitte wähle einen Plan um fortzufahren.';
    }
    return 'Du hast das Limit von $limit '
        '${limit == 1 ? "Kind" : "Kindern"} für deinen '
        '${plan.displayName}-Plan erreicht.';
  }
}
