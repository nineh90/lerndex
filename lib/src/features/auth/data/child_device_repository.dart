import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../parent_dashboard/data/pin_repository.dart'
    show PinLockedException;
import '../../../shared/user_message.dart';

// ============================================================================
// KINDERGERÄTE KOPPELN
//
// Eltern erzeugen einen Code (QR oder Link), das Kindergerät löst ihn ein und
// meldet sich mit einem eigenen Konto an (siehe account.dart). Die Logik
// liegt in den Cloud Functions (functions/index.js), hier nur die Aufrufe.
// ============================================================================

/// Region der Cloud Functions (Frankfurt, wie Vertex AI).
FirebaseFunctions lerndexFunctions() =>
    FirebaseFunctions.instanceFor(region: 'europe-west3');

/// Adresse der Web-App für den Kopplungslink. Im Browser die aktuelle Seite,
/// in den Apps per --dart-define=WEB_APP_URL=… (Standard app.lerndex.de).
String webAppOrigin() {
  if (kIsWeb) return Uri.base.origin;
  const url = String.fromEnvironment(
    'WEB_APP_URL',
    defaultValue: 'https://app.lerndex.de',
  );
  return url;
}

class PairingCode {
  const PairingCode({required this.code, required this.expiresAt});

  /// 8 Zeichen, z.B. K7MXQ2PA
  final String code;
  final DateTime expiresAt;

  /// Zum Abtippen: K7MX-Q2PA
  String get display => '${code.substring(0, 4)}-${code.substring(4)}';

  /// Link für den QR-Code: Kamera-App öffnet die Web-App, die den Code
  /// sofort einlöst.
  Uri get link => Uri.parse('${webAppOrigin()}/k/$code');
}

/// Kopplungscode aus einem Pfad wie /k/K7MXQ2PA lesen (Web-Link).
String? pairingCodeFromPath(String path) {
  final match = RegExp(r'^/k/([A-Za-z0-9-]{8,9})/?$').firstMatch(path);
  return match?.group(1);
}

/// Token einer Schüler-QR-Karte aus einem Pfad wie /s/ABCD… lesen.
String? studentCardFromPath(String path) {
  final match = RegExp(r'^/s/([A-Za-z0-9]{16,64})/?$').firstMatch(path);
  return match?.group(1);
}

class ChildDeviceRepository {
  ChildDeviceRepository(this._functions, this._auth, this._firestore);

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  /// Geräte-ID aus redeemPairingCode (Eintrag in der Geräteliste der Eltern)
  static const _deviceIdKey = 'paired_device_id';
  final FirebaseFirestore _firestore;

  /// Eltern: neuen Code für ein Kind (15 Minuten gültig, einmalig).
  Future<PairingCode> createPairingCode(String childId) async {
    final result = await _functions.httpsCallable('createPairingCode').call({
      'childId': childId,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return PairingCode(
      code: data['code'] as String,
      expiresAt: DateTime.parse(data['expiresAt'] as String),
    );
  }

  /// Kindergerät: Code einlösen und als Kind anmelden. Gibt den Namen des
  /// Kindes zurück. Wirft [PairingException] mit kindgerechtem Text.
  Future<String> redeemPairingCode(String code) async {
    try {
      final result = await _functions.httpsCallable('redeemPairingCode').call({
        'code': code,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      await _auth.signInWithCustomToken(data['token'] as String);
      final deviceId = data['deviceId'] as String?;
      if (deviceId != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_deviceIdKey, deviceId);
      }
      return data['childName'] as String? ?? '';
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found') {
        throw const PairingException(
          'Der Code stimmt nicht oder ist abgelaufen. '
          'Bitte deine Eltern um einen neuen Code.',
        );
      }
      throw const PairingException(
        'Das hat gerade nicht geklappt. Bitte versuch es gleich nochmal.',
      );
    }
  }

  /// Schülergerät: QR-Karte der Schule einlösen und als Schüler anmelden.
  Future<String> redeemStudentCard(String token) async {
    try {
      final result = await _functions.httpsCallable('redeemStudentCard').call({
        'token': token,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      await _auth.signInWithCustomToken(data['token'] as String);
      return data['childName'] as String? ?? '';
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found') {
        throw const PairingException(
          'Diese Karte gilt nicht mehr. Bitte frag deine Lehrerin oder '
          'deinen Lehrer nach einer neuen.',
        );
      }
      throw const PairingException(
        'Das hat gerade nicht geklappt. Bitte versuch es gleich nochmal.',
      );
    }
  }

  /// Kindergerät zu Hause: dieses Gerät mit dem Eltern-PIN abmelden. Gibt
  /// false bei falschem PIN zurück. Bei true ist das Gerät aus der Liste der
  /// Eltern ausgetragen; abmelden (signOut) muss danach der Aufrufer.
  ///
  /// Wirft [PinLockedException] nach zu vielen Fehlversuchen und
  /// [PairingException], wenn noch kein Eltern-PIN festgelegt ist.
  Future<bool> leaveDevice(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final result = await _functions.httpsCallable('leaveChildDevice').call({
        'pin': pin,
        'deviceId': prefs.getString(_deviceIdKey),
      });
      final ok = (result.data as Map)['ok'] == true;
      if (ok) await prefs.remove(_deviceIdKey);
      return ok;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        final seconds =
            (e.details as Map?)?['retryAfterSeconds'] as int? ?? 300;
        throw PinLockedException(Duration(seconds: seconds));
      }
      if (e.code == 'failed-precondition') {
        throw const PairingException(
          'Es gibt noch keinen Eltern-PIN. Lege ihn im Elternbereich fest '
          'oder melde das Gerät dort unter „Kind bearbeiten“ ab.',
        );
      }
      rethrow;
    }
  }

  /// Eltern: alle gekoppelten Geräte eines Kindes abmelden.
  Future<int> unpairDevices(String childId) async {
    final result = await _functions.httpsCallable('unpairChildDevices').call({
      'childId': childId,
    });
    return (result.data as Map)['unpaired'] as int? ?? 0;
  }

  /// Eltern: Anzahl der gekoppelten Geräte (schreibt nur die Function).
  Stream<int> watchDeviceCount(String ownerUid, String childId) => _firestore
      .collection('users')
      .doc(ownerUid)
      .collection('children')
      .doc(childId)
      .collection('devices')
      .snapshots()
      .map((s) => s.size);
}

class PairingException implements FriendlyException {
  const PairingException(this.message);
  @override
  final String message;

  @override
  String toString() => message;
}

final childDeviceRepositoryProvider = Provider<ChildDeviceRepository>((ref) {
  return ChildDeviceRepository(
    lerndexFunctions(),
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
  );
});
