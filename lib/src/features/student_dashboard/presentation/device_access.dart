import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../subscription/data/subscription_model.dart';

/// Zugang eines Kindergeräts (Abo der Eltern bzw. Lizenz der Schule).
enum DeviceAccess {
  /// Freigeschaltet.
  granted,

  /// Nicht freigeschaltet.
  denied,

  /// Erste Prüfung läuft noch.
  checking,

  /// Prüfung fehlgeschlagen, kein früherer Stand bekannt → „Erneut versuchen“.
  failed,
}

/// Entscheidet über den Zugang.
///
/// - Daten da → danach.
/// - Lädt oder Fehler (z.B. kurz offline, RevenueCat nicht erreichbar) → der
///   zuletzt bekannte Status [lastKnown] dieser Sitzung, damit ein kurzer
///   Netzfehler das Kind nicht aussperrt. Ein Status, dessen Laufzeit
///   ([SubscriptionStatus.expiresAt]) inzwischen vorbei ist, öffnet aber
///   nicht mehr.
/// - Ohne bekannten Status: [DeviceAccess.checking] bzw. [DeviceAccess.failed]
///   – nie einfach offen.
DeviceAccess resolveDeviceAccess(
  AsyncValue<SubscriptionStatus> status, {
  SubscriptionStatus? lastKnown,
  DateTime? now,
}) {
  if (status.hasValue && !status.hasError) {
    return status.value!.hasAccess ? DeviceAccess.granted : DeviceAccess.denied;
  }
  if (lastKnown != null) {
    final expires = lastKnown.expiresAt;
    final expired = expires != null && expires.isBefore(now ?? DateTime.now());
    return lastKnown.hasAccess && !expired
        ? DeviceAccess.granted
        : DeviceAccess.denied;
  }
  return status.hasError ? DeviceAccess.failed : DeviceAccess.checking;
}
