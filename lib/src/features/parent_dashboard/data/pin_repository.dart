import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/parent_pin_model.dart';
import '../../auth/data/auth_repository.dart';

/// Wird geworfen, wenn der PIN nach zu vielen Fehlversuchen gesperrt ist.
/// toString() ist bewusst nutzerfreundlich, da Dialoge "Fehler: $e" anzeigen.
class PinLockedException implements Exception {
  final Duration remaining;
  const PinLockedException(this.remaining);

  @override
  String toString() {
    final mins = remaining.inMinutes + 1;
    return 'Zu viele Fehlversuche. Bitte warte $mins Minute${mins == 1 ? '' : 'n'}.';
  }
}

/// Repository für Eltern-PIN Verwaltung
///
/// SICHERHEITS-FIXES gegenüber der alten Version:
/// 1. Salted SHA-256 mit Key-Stretching statt trivialem 32-Bit-Hash.
/// 2. Automatische Migration alter (unsicherer) Hashes beim nächsten
///    erfolgreichen verifyPin().
/// 3. Brute-Force-Schutz: nach [_maxFailedAttempts] Fehlversuchen wird der
///    PIN für [_lockoutDuration] gesperrt (persistiert in Firestore – ein
///    Neustart der App oder erneutes Öffnen des Dialogs hilft nicht).
class PinRepository {
  final FirebaseFirestore _firestore;

  PinRepository(this._firestore);

  static const int _maxFailedAttempts = 5;
  static const Duration _lockoutDuration = Duration(minutes: 5);

  DocumentReference<Map<String, dynamic>> _userDoc(String userId) =>
      _firestore.collection('users').doc(userId);

  /// Prüft ob ein PIN existiert
  Future<bool> hasPinSet(String userId) async {
    final doc = await _userDoc(userId).get();
    return doc.data()?['hashedPin'] != null;
  }

  /// Erstellt oder aktualisiert den PIN (immer mit neuem Salt + sicherem Hash)
  Future<void> setPin(String userId, String pin) async {
    if (!ParentPin.isValidPin(pin)) {
      throw Exception('PIN muss 4-6 Ziffern enthalten!');
    }

    final salt = ParentPin.generateSalt();
    final hashedPin = ParentPin.hashPinSecure(pin, salt);

    await _userDoc(userId).set({
      'hashedPin': hashedPin,
      'pinSalt': salt,
      'pinCreatedAt': FieldValue.serverTimestamp(),
      // Beim Neusetzen Lockout-Status zurücksetzen
      'pinFailedAttempts': 0,
      'pinLockedUntil': FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  /// Verifiziert den eingegebenen PIN.
  ///
  /// Wirft [PinLockedException], wenn der PIN aktuell gesperrt ist.
  /// Migriert Legacy-Hashes (ohne Salt) bei erfolgreicher Eingabe
  /// automatisch auf das neue, sichere Schema.
  Future<bool> verifyPin(String userId, String pin) async {
    if (!ParentPin.isValidPin(pin)) return false;

    final docRef = _userDoc(userId);
    final doc = await docRef.get();
    final data = doc.data();

    if (data == null || data['hashedPin'] == null) {
      return false;
    }

    // ── Lockout prüfen ──────────────────────────────────────────────────
    final lockedUntil = (data['pinLockedUntil'] as Timestamp?)?.toDate();
    if (lockedUntil != null && DateTime.now().isBefore(lockedUntil)) {
      throw PinLockedException(lockedUntil.difference(DateTime.now()));
    }

    final storedHash = data['hashedPin'] as String;
    final salt = data['pinSalt'] as String?;

    bool isCorrect;
    bool needsMigration = false;

    if (salt != null) {
      // Neues Schema
      isCorrect = ParentPin.hashPinSecure(pin, salt) == storedHash;
    } else {
      // Legacy-Schema (alter unsicherer Hash) → bei Erfolg migrieren
      isCorrect = ParentPin.legacyHashPin(pin) == storedHash;
      needsMigration = isCorrect;
    }

    if (isCorrect) {
      if (needsMigration) {
        // Re-Hash mit Salt – setPin setzt auch die Lockout-Felder zurück
        await setPin(userId, pin);
        await docRef.update({'pinLastUsed': FieldValue.serverTimestamp()});
      } else {
        await docRef.update({
          'pinLastUsed': FieldValue.serverTimestamp(),
          'pinFailedAttempts': 0,
          'pinLockedUntil': FieldValue.delete(),
        });
      }
      return true;
    }

    // ── Fehlversuch zählen, ggf. sperren ────────────────────────────────
    final failed = ((data['pinFailedAttempts'] as int?) ?? 0) + 1;
    final updates = <String, dynamic>{'pinFailedAttempts': failed};
    if (failed >= _maxFailedAttempts) {
      updates['pinLockedUntil'] = Timestamp.fromDate(
        DateTime.now().add(_lockoutDuration),
      );
      updates['pinFailedAttempts'] = 0;
    }
    await docRef.update(updates);

    return false;
  }

  /// Löscht den PIN (für Reset)
  Future<void> deletePin(String userId) async {
    await _userDoc(userId).update({
      'hashedPin': FieldValue.delete(),
      'pinSalt': FieldValue.delete(),
      'pinCreatedAt': FieldValue.delete(),
      'pinLastUsed': FieldValue.delete(),
      'pinFailedAttempts': FieldValue.delete(),
      'pinLockedUntil': FieldValue.delete(),
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
