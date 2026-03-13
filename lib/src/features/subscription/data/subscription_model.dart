import 'package:cloud_firestore/cloud_firestore.dart';

/// Repräsentiert einen Abo-Plan in Lerndex
enum SubscriptionPlan {
  none, // Kein Abo (Trial abgelaufen oder nie gestartet)
  trial, // 14-Tage Testzeitraum aktiv
  solo, // 12,99€ – 1 Kind
  duo, // 24,99€ – 2 Kinder
  family, // 39,99€ – 4 Kinder
}

extension SubscriptionPlanExtension on SubscriptionPlan {
  /// Anzeigename für die UI
  String get displayName {
    switch (this) {
      case SubscriptionPlan.none:
        return 'Kein Abo';
      case SubscriptionPlan.trial:
        return '14-Tage Test';
      case SubscriptionPlan.solo:
        return 'Solo';
      case SubscriptionPlan.duo:
        return 'Duo';
      case SubscriptionPlan.family:
        return 'Family';
    }
  }

  /// Preis-String für die UI
  String get priceLabel {
    switch (this) {
      case SubscriptionPlan.none:
        return 'Kostenlos';
      case SubscriptionPlan.trial:
        return 'Kostenlos (14 Tage)';
      case SubscriptionPlan.solo:
        return '12,99 € / Monat';
      case SubscriptionPlan.duo:
        return '24,99 € / Monat';
      case SubscriptionPlan.family:
        return '39,99 € / Monat';
    }
  }

  /// Maximale Anzahl an Kindern die angelegt werden dürfen
  int get childLimit {
    switch (this) {
      case SubscriptionPlan.none:
        return 0; // Gesperrt nach Trial
      case SubscriptionPlan.trial:
        return 4; // Im Trial alles freigegeben
      case SubscriptionPlan.solo:
        return 1;
      case SubscriptionPlan.duo:
        return 2;
      case SubscriptionPlan.family:
        return 4;
    }
  }

  /// Ist der Zugriff auf die App erlaubt?
  bool get hasAccess {
    return this != SubscriptionPlan.none;
  }

  /// RevenueCat Package-Identifier (muss exakt mit dem Dashboard übereinstimmen)
  String? get revenueCatPackageId {
    switch (this) {
      case SubscriptionPlan.solo:
        return '\$rc_monthly'; // Standard-Package
      case SubscriptionPlan.duo:
        return 'lerndex_duo';
      case SubscriptionPlan.family:
        return 'lerndex_family';
      default:
        return null;
    }
  }

  /// Aus RevenueCat Entitlement-String parsen
  static SubscriptionPlan fromEntitlement(String? productIdentifier) {
    if (productIdentifier == null) return SubscriptionPlan.none;
    if (productIdentifier.contains('solo')) return SubscriptionPlan.solo;
    if (productIdentifier.contains('duo')) return SubscriptionPlan.duo;
    if (productIdentifier.contains('family')) return SubscriptionPlan.family;
    return SubscriptionPlan.none;
  }

  /// Aus Firestore-String parsen
  static SubscriptionPlan fromString(String? value) {
    switch (value) {
      case 'trial':
        return SubscriptionPlan.trial;
      case 'solo':
        return SubscriptionPlan.solo;
      case 'duo':
        return SubscriptionPlan.duo;
      case 'family':
        return SubscriptionPlan.family;
      default:
        return SubscriptionPlan.none;
    }
  }

  /// Zu Firestore-String konvertieren
  String toFirestore() {
    switch (this) {
      case SubscriptionPlan.trial:
        return 'trial';
      case SubscriptionPlan.solo:
        return 'solo';
      case SubscriptionPlan.duo:
        return 'duo';
      case SubscriptionPlan.family:
        return 'family';
      default:
        return 'none';
    }
  }
}

/// Vollständiger Abo-Status eines Users
class SubscriptionStatus {
  final SubscriptionPlan plan;
  final bool isActive;
  final bool isTrial;
  final DateTime? expiresAt;
  final DateTime? trialEndsAt;

  const SubscriptionStatus({
    required this.plan,
    required this.isActive,
    this.isTrial = false,
    this.expiresAt,
    this.trialEndsAt,
  });

  /// Kein Zugriff
  static const SubscriptionStatus empty = SubscriptionStatus(
    plan: SubscriptionPlan.none,
    isActive: false,
  );

  /// Hat Zugriff (aktives Abo oder laufender Trial)
  bool get hasAccess => isActive && plan.hasAccess;

  /// Wie viele Kinder darf dieser User anlegen?
  int get childLimit => plan.childLimit;

  /// Aus Firestore-Map laden
  factory SubscriptionStatus.fromFirestore(Map<String, dynamic>? data) {
    if (data == null) return SubscriptionStatus.empty;

    final plan = SubscriptionPlanExtension.fromString(data['plan'] as String?);
    final isActive = data['isActive'] as bool? ?? false;
    final isTrial = data['isTrial'] as bool? ?? false;

    DateTime? expiresAt;
    if (data['expiresAt'] != null) {
      expiresAt = (data['expiresAt'] as Timestamp).toDate();
    }

    DateTime? trialEndsAt;
    if (data['trialEndsAt'] != null) {
      trialEndsAt = (data['trialEndsAt'] as Timestamp).toDate();
    }

    return SubscriptionStatus(
      plan: plan,
      isActive: isActive,
      isTrial: isTrial,
      expiresAt: expiresAt,
      trialEndsAt: trialEndsAt,
    );
  }

  /// Zu Firestore-Map konvertieren
  Map<String, dynamic> toFirestore() {
    return {
      'plan': plan.toFirestore(),
      'isActive': isActive,
      'isTrial': isTrial,
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt!),
      if (trialEndsAt != null) 'trialEndsAt': Timestamp.fromDate(trialEndsAt!),
    };
  }
}
