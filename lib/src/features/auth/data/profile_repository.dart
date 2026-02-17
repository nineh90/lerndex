import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../domain/child_model.dart';
import '../../rewards/data/system_rewards_initializer.dart';
import 'auth_repository.dart';

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
    return _firestore
        .collection('users')
        .doc(_uid)
        .collection('children')
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => ChildModel.fromMap(doc.data(), doc.id))
        .toList());
  }

  /// Erstellt ein neues Kind mit System-Belohnungen
  Future<String> createChild({
    required String name,
    required int age,
    required String schoolType,
    required int grade,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // Child erstellen
    final childData = {
      'name': name,
      'age': age,
      'schoolType': schoolType,
      'grade': grade,
      'xp': 0,
      'level': 1,
      'stars': 0,
      'streak': 0,
      'totalLearningSeconds': 0,
      'xpToNextLevel': 25,
      'createdAt': FieldValue.serverTimestamp(),
    };

    final docRef = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('children')
        .add(childData);

    // ⭐ System-Belohnungen initialisieren
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

      print('✅ Kind erstellt mit $count System-Belohnungen');
    } catch (e) {
      print('⚠️ Fehler beim Erstellen der System-Belohnungen: $e');
      // Kind wurde erstellt, aber Belohnungen fehlgeschlagen
      // Das ist nicht kritisch - kann nachträglich gemacht werden
    }

    return docRef.id;
  }

  /// Migriert existierende Kinder (fügt System-Belohnungen hinzu)
  /// Kann einmalig von Eltern über einen Button aufgerufen werden
  Future<void> migrateExistingChildren() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final rewardsInitializer = SystemRewardsInitializer();

    // Hole alle Kinder
    final children = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('children')
        .get();

    for (final doc in children.docs) {
      final childId = doc.id;
      final childName = doc.data()['name'] ?? 'Unknown';

      print('🔧 Migriere Kind: $childName ($childId)');

      try {
        // Prüfe ob Belohnungen existieren
        final hasRewards = await rewardsInitializer.hasSystemRewards(
          userId: user.uid,
          childId: childId,
        );

        if (!hasRewards) {
          print('  → Erstelle alle System-Belohnungen');
          await rewardsInitializer.initializeSystemRewards(
            userId: user.uid,
            childId: childId,
          );
        } else {
          print('  → Füge fehlende Belohnungen hinzu');
          await rewardsInitializer.addMissingSystemRewards(
            userId: user.uid,
            childId: childId,
          );
        }
      } catch (e) {
        print('  ❌ Fehler bei Migration für $childName: $e');
      }
    }

    print('✅ Migration abgeschlossen');
  }

  /// Aktualisiert die Sterne eines Kindes
  /// increment = true: Fügt Sterne hinzu, false: Setzt auf exakten Wert
  Future<void> updateStars(String childId, int stars, {bool increment = true}) async {
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

  /// Fügt XP hinzu und prüft automatisch auf Level-Up
  /// Gibt true zurück, wenn ein Level-Up stattgefunden hat
  Future<bool> addXP(String childId, int xpAmount) async {
    final docRef = _firestore
        .collection('users')
        .doc(_uid)
        .collection('children')
        .doc(childId);

    // Transaction = mehrere Operationen atomar (alles oder nichts)
    return await _firestore.runTransaction<bool>((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return false;

      final data = snapshot.data()!;
      final currentXP = data['xp'] ?? 0;
      final currentLevel = data['level'] ?? 1;
      final xpToNextLevel = data['xpToNextLevel'] ?? 25;

      final newXP = currentXP + xpAmount;
      bool leveledUp = false;

      // Prüfe auf Level-Up
      if (newXP >= xpToNextLevel) {
        // Level-Up! Überschüssige XP werden behalten
        transaction.update(docRef, {
          'xp': newXP - xpToNextLevel,
          'level': currentLevel + 1,
          'xpToNextLevel': xpToNextLevel + 5, // Jedes Level wird etwas schwerer
        });
        leveledUp = true;
      } else {
        // Nur XP erhöhen
        transaction.update(docRef, {'xp': newXP});
      }

      return leveledUp;
    });
  }

  /// Vergibt Belohnungen nach einer Mission
  /// correctAnswers = Anzahl richtiger Antworten
  /// totalQuestions = Gesamtanzahl Fragen
  /// Gibt true zurück bei Level-Up
  Future<bool> awardMissionReward(
      String childId, {
        required int correctAnswers,
        required int totalQuestions,
      }) async {
    // Belohnungs-Formel:
    // - 2 Sterne pro richtiger Antwort
    // - 1 XP pro richtiger Antwort
    final stars = correctAnswers * 2;
    final xp = correctAnswers;

    await updateStars(childId, stars);
    final leveledUp = await addXP(childId, xp);

    return leveledUp;
  }

  /// Aktualisiert die Stammdaten eines Kindes (Name, Alter, Schulform, Klasse)
  /// Lernfortschritte (XP, Level, Sterne) werden NICHT verändert
  Future<void> updateChild({
    required String childId,
    required String name,
    required int age,
    required String schoolType,
    required int grade,
  }) async {
    await _firestore
        .collection('users')
        .doc(_uid)
        .collection('children')
        .doc(childId)
        .update({
      'name': name,
      'age': age,
      'schoolType': schoolType,
      'grade': grade,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }


  /// Löscht ein Kind (für später, wenn Eltern das wollen)
  Future<void> deleteChild(String childId) async {
    await _firestore
        .collection('users')
        .doc(_uid)
        .collection('children')
        .doc(childId)
        .delete();
  }
}

/// Löscht alle Daten eines Users komplett aus Firestore
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

  // Für jedes Kind: Subcollections löschen
  for (final childDoc in childrenSnapshot.docs) {
    final childId = childDoc.id;

    // Subcollections eines Kindes löschen
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

      for (final doc in subDocs.docs) {
        await doc.reference.delete();
      }
    }

    // Kind-Dokument selbst löschen
    await childDoc.reference.delete();
  }

  // Haupt-User-Dokument löschen (enthält PIN, etc.)
  await _firestore.collection('users').doc(uid).delete();
}

/// Provider für ProfileRepository
@riverpod
ProfileRepository profileRepository(ProfileRepositoryRef ref) {
  return ProfileRepository(
    FirebaseFirestore.instance,
    FirebaseAuth.instance,
  );
}

/// Provider für die Kinder-Liste (Stream)
/// Aktualisiert sich automatisch
@riverpod
Stream<List<ChildModel>> childrenList(ChildrenListRef ref) {
  return ref.watch(profileRepositoryProvider).watchChildren();
}