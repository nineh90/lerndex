import 'package:cloud_firestore/cloud_firestore.dart';

/// Model für Eltern-PIN
class ParentPin {
  final String userId;
  final String hashedPin;  // Wir speichern PIN nie im Klartext!
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
      createdAt: (data['createdAt'] as Timestamp).toDate(),
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
      'lastUsed': lastUsed != null ? Timestamp.fromDate(lastUsed!) : null,  // ← ! hinzugefügt
    };
  }
  /// PIN hashen (einfache Methode für den Anfang)
  static String hashPin(String pin) {
    // Für den Anfang: Einfacher Hash
    // Später: crypto package für bessere Sicherheit
    int hash = 0;
    for (int i = 0; i < pin.length; i++) {
      hash = ((hash << 5) - hash) + pin.codeUnitAt(i);
      hash = hash & hash; // Convert to 32bit integer
    }
    return hash.abs().toString();
  }

  /// PIN validieren (nur Zahlen, 4-6 Stellen)
  static bool isValidPin(String pin) {
    if (pin.length < 4 || pin.length > 6) return false;
    return RegExp(r'^[0-9]+$').hasMatch(pin);
  }
}