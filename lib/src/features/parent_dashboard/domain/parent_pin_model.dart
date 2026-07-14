import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

/// Model für Eltern-PIN
///
/// SICHERHEITS-FIX:
/// Der alte hashPin() war ein trivialer 32-Bit-Hash (JS-Style), der sich
/// für einen 4–6-stelligen PIN in Millisekunden brute-forcen lässt, sobald
/// jemand das Firestore-Dokument lesen kann.
///
/// Neu: SHA-256 mit zufälligem Salt pro User + 10.000 Iterationen
/// (Key-Stretching). Das crypto-Package ist bereits Dependency.
///
/// Migration: [legacyHashPin] bleibt erhalten, damit bestehende PINs beim
/// nächsten erfolgreichen Login automatisch auf das neue Schema
/// umgeschrieben werden können (siehe PinRepository.verifyPin).
class ParentPin {
  final String userId;
  final String hashedPin; // Wir speichern PIN nie im Klartext!
  final DateTime createdAt;
  final DateTime? lastUsed;

  ParentPin({
    required this.userId,
    required this.hashedPin,
    required this.createdAt,
    this.lastUsed,
  });

  /// Aus Firestore-Daten erstellen
  factory ParentPin.fromFirestore(Map<String, dynamic> data, String userId) {
    return ParentPin(
      userId: userId,
      hashedPin: data['hashedPin'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastUsed: data['lastUsed'] != null
          ? (data['lastUsed'] as Timestamp).toDate()
          : null,
    );
  }

  /// Zu Firestore-Daten konvertieren
  Map<String, dynamic> toFirestore() {
    return {
      'hashedPin': hashedPin,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastUsed': lastUsed != null ? Timestamp.fromDate(lastUsed!) : null,
    };
  }

  // ==========================================================================
  // HASHING (neu)
  // ==========================================================================

  /// Anzahl Iterationen für Key-Stretching.
  /// 10.000 × SHA-256 ist auf Mobilgeräten < 50 ms, macht Offline-Brute-Force
  /// aber um Faktor 10.000 teurer.
  static const int hashIterations = 10000;

  /// Erzeugt einen kryptografisch sicheren, zufälligen Salt (Base64, 16 Byte).
  static String generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  /// Hasht den PIN mit Salt und Iterationen (SHA-256-basiertes Stretching).
  static String hashPinSecure(String pin, String salt) {
    var digest = sha256.convert(utf8.encode('$salt:$pin')).bytes;
    for (var i = 1; i < hashIterations; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return base64UrlEncode(digest);
  }

  // ==========================================================================
  // LEGACY (nur noch für Migration alter PINs)
  // ==========================================================================

  /// ⚠️ UNSICHER – nur für die Verifikation/Migration von PINs, die mit dem
  /// alten Schema gespeichert wurden. Niemals für neue PINs verwenden.
  static String legacyHashPin(String pin) {
    int hash = 0;
    for (int i = 0; i < pin.length; i++) {
      hash = ((hash << 5) - hash) + pin.codeUnitAt(i);
      hash = hash & hash;
    }
    return hash.abs().toString();
  }

  // ==========================================================================
  // VALIDIERUNG
  // ==========================================================================

  /// PIN validieren (nur Zahlen, 4-6 Stellen)
  static bool isValidPin(String pin) {
    if (pin.length < 4 || pin.length > 6) return false;
    return RegExp(r'^[0-9]+$').hasMatch(pin);
  }
}
