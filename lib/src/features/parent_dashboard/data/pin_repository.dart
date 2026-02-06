import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/parent_pin_model.dart';
import '../../auth/data/auth_repository.dart';

/// Repository für Eltern-PIN Verwaltung
class PinRepository {
  final FirebaseFirestore _firestore;

  PinRepository(this._firestore);

  /// Prüft ob ein PIN existiert
  Future<bool> hasPinSet(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    return doc.data()?['hashedPin'] != null;
  }

  /// Erstellt oder aktualisiert den PIN
  Future<void> setPin(String userId, String pin) async {
    if (!ParentPin.isValidPin(pin)) {
      throw Exception('PIN muss 4-6 Ziffern enthalten!');
    }

    final hashedPin = ParentPin.hashPin(pin);

    await _firestore.collection('users').doc(userId).set({
      'hashedPin': hashedPin,
      'pinCreatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Verifiziert den eingegebenen PIN
  Future<bool> verifyPin(String userId, String pin) async {
    if (!ParentPin.isValidPin(pin)) return false;

    final doc = await _firestore.collection('users').doc(userId).get();
    final data = doc.data();

    if (data == null || data['hashedPin'] == null) {
      return false;
    }

    final hashedInput = ParentPin.hashPin(pin);
    final storedHash = data['hashedPin'];

    if (hashedInput == storedHash) {
      // PIN korrekt - aktualisiere "lastUsed"
      await _firestore.collection('users').doc(userId).update({
        'pinLastUsed': FieldValue.serverTimestamp(),
      });
      return true;
    }

    return false;
  }

  /// Löscht den PIN (für Reset)
  Future<void> deletePin(String userId) async {
    await _firestore.collection('users').doc(userId).update({
      'hashedPin': FieldValue.delete(),
      'pinCreatedAt': FieldValue.delete(),
      'pinLastUsed': FieldValue.delete(),
    });
  }

  /// Ändert den PIN (benötigt alten PIN zur Verifikation)
  Future<bool> changePin(String userId, String oldPin, String newPin) async {
    final isValid = await verifyPin(userId, oldPin);
    if (!isValid) return false;

    await setPin(userId, newPin);
    return true;
  }
}

/// Provider für PIN Repository
final pinRepositoryProvider = Provider<PinRepository>((ref) {
  return PinRepository(FirebaseFirestore.instance);
});

/// Provider der prüft ob PIN gesetzt ist
final hasPinSetProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(authStateChangesProvider).value;
  if (user == null) return false;

  final pinRepo = ref.watch(pinRepositoryProvider);
  return await pinRepo.hasPinSet(user.uid);
});