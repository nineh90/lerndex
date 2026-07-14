import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  /// Löscht ein Kind INKLUSIVE aller Subcollections.
  ///
  /// ✅ FIX (DSGVO): Vorher wurde nur das Kind-Dokument gelöscht – sämtliche
  /// Subcollections (Tutor-Chats inkl. messages, Rewards, Lernstatistiken,
  /// KI-Fragen-Cache) blieben als verwaiste Daten dauerhaft in Firestore.
  Future<void> deleteChild(String childId) async {
    final uid = _uid;
    if (uid.isEmpty) throw Exception('Kein Benutzer angemeldet.');

    await _deleteChildData(uid, childId);

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('children')
        .doc(childId)
        .delete();
  }

  /// Löscht alle Firestore-Daten eines Users komplett.
  /// Wird vor dem Löschen des Firebase Auth Accounts aufgerufen.
  ///
  /// ✅ FIX (DSGVO Art. 17): Löscht jetzt vollständig:
  /// - tutor_sessions inkl. messages-Sub-Subcollection (vorher verwaist!)
  /// - active_tutor_chat
  /// - ai_quiz_cache/{fach}/questions
  /// - generated_batches inkl. questions-Subcollection
  /// - hochgeladene Aufgaben-Fotos in Firebase Storage (task_images/{uid})
  Future<void> deleteAllUserData() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Kein Benutzer angemeldet.');

    final uid = user.uid;
    final userRef = _firestore.collection('users').doc(uid);

    // ── 1. Alle Kinder inkl. Subcollections ───────────────────────────────
    final childrenSnapshot = await userRef.collection('children').get();
    for (final childDoc in childrenSnapshot.docs) {
      await _deleteChildData(uid, childDoc.id);
      await childDoc.reference.delete();
    }

    // ── 2. Generierte Aufgaben-Batches (Top-Level unter users/{uid}) ──────
    final batchesSnapshot = await userRef.collection('generated_batches').get();
    for (final batchDoc in batchesSnapshot.docs) {
      await _deleteCollectionInBatches(
        batchDoc.reference.collection('questions'),
      );
      await batchDoc.reference.delete();
    }

    // ── 3. Hochgeladene Fotos in Firebase Storage ──────────────────────────
    // task_images: Eltern-Fotos für Aufgaben-Generierung
    // tutor_worksheets: vom Kind hochgeladene Aufgabenblätter
    // feedback: optionale Screenshots aus dem Feedback-Formular
    for (final folder in ['task_images', 'tutor_worksheets', 'feedback']) {
      try {
        await _deleteStorageFolder(
          FirebaseStorage.instance.ref().child('$folder/$uid'),
        );
      } catch (e) {
        // Storage-Fehler dürfen die Konto-Löschung nicht blockieren
        debugPrint('⚠️ Storage-Cleanup ($folder) fehlgeschlagen: $e');
      }
    }

    // ── 4. Haupt-User-Dokument löschen (enthält PIN, etc.) ─────────────────
    await userRef.delete();
  }

  /// Löscht alle bekannten Subcollections eines Kindes.
  Future<void> _deleteChildData(String uid, String childId) async {
    final childRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('children')
        .doc(childId);

    // tutor_sessions: erst messages-Subcollection jeder Session, dann Session
    final sessions = await childRef.collection('tutor_sessions').get();
    for (final sessionDoc in sessions.docs) {
      await _deleteCollectionInBatches(
        sessionDoc.reference.collection('messages'),
      );
      await sessionDoc.reference.delete();
    }

    // ai_quiz_cache: pro Fach-Dokument die questions-Subcollection
    final cacheDocs = await childRef.collection('ai_quiz_cache').get();
    for (final cacheDoc in cacheDocs.docs) {
      await _deleteCollectionInBatches(
        cacheDoc.reference.collection('questions'),
      );
      await cacheDoc.reference.delete();
    }

    // Flache Subcollections
    for (final name in [
      'active_tutor_chat',
      'rewards',
      'learning_stats',
      'tutor_chat', // Legacy-Collection, falls noch Altdaten existieren
    ]) {
      await _deleteCollectionInBatches(childRef.collection(name));
    }

    // Generierte Aufgaben-Batches dieses Kindes (liegen top-level unter
    // users/{uid}/generated_batches, nicht unter dem Kind-Dokument)
    final batches = await _firestore
        .collection('users')
        .doc(uid)
        .collection('generated_batches')
        .where('childId', isEqualTo: childId)
        .get();
    for (final batchDoc in batches.docs) {
      await _deleteCollectionInBatches(batchDoc.reference.collection('questions'));
      await batchDoc.reference.delete();
    }

    // Hochgeladene Fotos dieses Kindes in Firebase Storage (DSGVO Art. 17):
    // Eltern-Fotos (task_images) und vom Kind fotografierte Aufgabenblätter
    // (tutor_worksheets) liegen jeweils unter .../{uid}/{childId}/...
    for (final folder in ['task_images', 'tutor_worksheets']) {
      try {
        await _deleteStorageFolder(
          FirebaseStorage.instance.ref().child('$folder/$uid/$childId'),
        );
      } catch (e) {
        debugPrint('⚠️ Storage-Cleanup ($folder/$childId) fehlgeschlagen: $e');
      }
    }
  }

  /// Löscht eine Collection in Batches (max. 400 Ops pro Batch,
  /// Firestore-Limit ist 500). Paginiert, statt alles auf einmal zu laden.
  Future<void> _deleteCollectionInBatches(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    const batchSize = 400;
    while (true) {
      final snapshot = await collection.limit(batchSize).get();
      if (snapshot.docs.isEmpty) break;

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (snapshot.docs.length < batchSize) break;
    }
  }

  /// Löscht rekursiv alle Dateien unter einer Storage-Referenz.
  Future<void> _deleteStorageFolder(Reference ref) async {
    final result = await ref.listAll();
    for (final item in result.items) {
      await item.delete();
    }
    for (final prefix in result.prefixes) {
      await _deleteStorageFolder(prefix);
    }
  }
} // Ende ProfileRepository

/// Provider für ProfileRepository
@riverpod
ProfileRepository profileRepository(Ref ref) {
  return ProfileRepository(FirebaseFirestore.instance, FirebaseAuth.instance);
}

@riverpod
Stream<List<ChildModel>> childrenList(Ref ref) {
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
