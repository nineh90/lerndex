import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../domain/child_model.dart';
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

  /// Fügt ein neues Kind hinzu
  Future<void> addChild({
    required String name,
    required int grade,
    required String schoolType,
    required int age,
  }) async {
    await _firestore
        .collection('users')
        .doc(_uid)
        .collection('children')
        .add({
      'name': name,
      'level': 1,
      'grade': grade,
      'schoolType': schoolType,
      'age': age,
      'stars': 0,
      'totalLearningSeconds': 0,
      'xp': 0,
      'xpToNextLevel': 25,
    });
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