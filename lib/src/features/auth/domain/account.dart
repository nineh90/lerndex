import 'package:firebase_auth/firebase_auth.dart';

// ============================================================================
// WER IST ANGEMELDET?
//
// Eltern melden sich mit E-Mail/Google an, ihre Daten liegen unter
// users/{uid}. Ein gekoppeltes Kindergerät (QR-Code/Kopplungscode) meldet
// sich mit einem eigenen Konto an, das die Cloud Function redeemPairingCode
// anlegt. Dessen UID sagt, wem die Daten gehören:
//
//   kid:<parentUid>:<childId>
//
// Alle Firestore-/Storage-Pfade bauen deshalb auf [AccountUser.ownerUid] auf,
// nicht auf user.uid. Was das Kindergerät darf, regeln die Rules über die
// Claims im Token (role, parentUid, childId) – die UID-Form hier dient nur
// dazu, ohne asynchronen Token-Abruf an die IDs zu kommen.
// ============================================================================

const _kidPrefix = 'kid';

/// UID des Kontos, unter dem die Daten liegen (users/{ownerUid}).
String ownerUidFor(String uid) => _parseKidUid(uid)?.parentUid ?? uid;

/// Kind-ID, wenn [uid] ein gekoppeltes Kindergerät ist, sonst null.
String? pairedChildIdFor(String uid) => _parseKidUid(uid)?.childId;

/// UID des Kontos für ein gekoppeltes Kindergerät (gleiche Form wie in
/// functions/index.js).
String kidUid(String parentUid, String childId) =>
    '$_kidPrefix:$parentUid:$childId';

({String parentUid, String childId})? _parseKidUid(String uid) {
  final parts = uid.split(':');
  if (parts.length != 3 || parts[0] != _kidPrefix) return null;
  if (parts[1].isEmpty || parts[2].isEmpty) return null;
  return (parentUid: parts[1], childId: parts[2]);
}

extension AccountUser on User {
  /// Wem gehören die Daten? Bei Eltern die eigene UID, bei einem
  /// Kindergerät die UID der Eltern.
  String get ownerUid => ownerUidFor(uid);

  /// Kind-ID bei einem gekoppelten Kindergerät, sonst null.
  String? get pairedChildId => pairedChildIdFor(uid);

  /// Läuft die App auf einem gekoppelten Kindergerät? Dann gibt es keinen
  /// Elternbereich, keine Kinderauswahl und keine Käufe.
  bool get isChildDevice => pairedChildId != null;
}
