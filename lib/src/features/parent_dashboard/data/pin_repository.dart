import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/parent_pin_model.dart';
import '../../auth/data/child_device_repository.dart';

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

/// Repository für Eltern-PIN Verwaltung.
///
/// Der PIN wird auf dem Server geprüft (Cloud Functions setParentPin /
/// verifyParentPin in functions/index.js). Hash, Salt und Fehlversuche liegen
/// in users/{uid}/private/pin, das kein Client lesen kann – auch kein
/// gekoppeltes Kindergerät, das das users-Dokument für den Abo-Status lesen
/// darf. Die Sperre nach 5 Fehlversuchen macht ebenfalls der Server.
/// Alte Hashes im users-Dokument zieht der Server beim ersten Prüfen um.
class PinRepository {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  PinRepository(this._firestore, this._functions);

  /// Prüft ob ein PIN existiert (pinSet setzt der Server; hashedPin gibt es
  /// noch bei Konten, deren PIN noch nicht umgezogen ist).
  Future<bool> hasPinSet(String userId) async {
    final data = (await _firestore.collection('users').doc(userId).get())
        .data();
    return data?['pinSet'] == true || data?['hashedPin'] != null;
  }

  /// Erstellt den PIN (erstmalig).
  Future<void> setPin(String userId, String pin) async {
    if (!ParentPin.isValidPin(pin)) {
      throw Exception('PIN muss 4-6 Ziffern enthalten!');
    }
    await _functions.httpsCallable('setParentPin').call({'pin': pin});
  }

  /// Verifiziert den eingegebenen PIN.
  ///
  /// Wirft [PinLockedException], wenn der PIN aktuell gesperrt ist.
  Future<bool> verifyPin(String userId, String pin) async {
    if (!ParentPin.isValidPin(pin)) return false;
    try {
      final result = await _functions.httpsCallable('verifyParentPin').call({
        'pin': pin,
      });
      return (result.data as Map)['ok'] == true;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        final seconds =
            (e.details as Map?)?['retryAfterSeconds'] as int? ?? 300;
        throw PinLockedException(Duration(seconds: seconds));
      }
      rethrow;
    }
  }

  /// Ändert den PIN (benötigt alten PIN zur Verifikation).
  Future<bool> changePin(String userId, String oldPin, String newPin) async {
    try {
      await _functions.httpsCallable('setParentPin').call({
        'pin': newPin,
        'oldPin': oldPin,
      });
      return true;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'permission-denied') return false;
      if (e.code == 'resource-exhausted') {
        final seconds =
            (e.details as Map?)?['retryAfterSeconds'] as int? ?? 300;
        throw PinLockedException(Duration(seconds: seconds));
      }
      rethrow;
    }
  }
}

/// Provider für PIN Repository
final pinRepositoryProvider = Provider<PinRepository>((ref) {
  return PinRepository(FirebaseFirestore.instance, lerndexFunctions());
});
