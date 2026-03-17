import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/models/offerings_wrapper.dart';
import 'package:purchases_flutter/models/package_wrapper.dart';
import 'subscription_model.dart';
import 'subscription_service.dart';

// =============================================================================
// SERVICE PROVIDER
// =============================================================================

final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  return SubscriptionService(FirebaseFirestore.instance, FirebaseAuth.instance);
});

// =============================================================================
// ABO-STATUS PROVIDER (Haupt-Provider)
// =============================================================================

/// Hält den aktuellen Abo-Status.
/// Hört auf den RevenueCat CustomerInfo-Stream → aktualisiert sich automatisch
/// bei Kauf, Kündigung oder Ablauf.
final subscriptionStatusProvider =
    StateNotifierProvider<SubscriptionNotifier, AsyncValue<SubscriptionStatus>>(
      (ref) {
        final service = ref.watch(subscriptionServiceProvider);
        return SubscriptionNotifier(service);
      },
    );

class SubscriptionNotifier
    extends StateNotifier<AsyncValue<SubscriptionStatus>> {
  SubscriptionNotifier(this._service) : super(const AsyncValue.loading()) {
    _init();
  }

  final SubscriptionService _service;

  Future<void> _init() async {
    // 1. Sofort den gespeicherten Status aus Firestore laden (schnell, offline-fähig)
    final cachedStatus = await _service.getStatusFromFirestore();
    if (mounted) {
      state = AsyncValue.data(cachedStatus);
    }

    // 2. Frischen Status von RevenueCat holen
    await refresh();

    // 3. Auf zukünftige Änderungen hören (z.B. Kauf im Hintergrund)
    _service.customerInfoStream.listen((status) {
      if (mounted) state = AsyncValue.data(status);
    });
  }

  /// Manuell aktualisieren (z.B. nach App-Resume oder nach Kauf)
  Future<void> refresh() async {
    try {
      final status = await _service.getSubscriptionStatus();
      if (mounted) state = AsyncValue.data(status);
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  /// Kauf starten
  Future<SubscriptionStatus> purchase(Package package) async {
    final status = await _service.purchasePackage(package);
    if (mounted) state = AsyncValue.data(status);
    return status;
  }

  /// Käufe wiederherstellen
  Future<SubscriptionStatus> restore() async {
    final status = await _service.restorePurchases();
    if (mounted) state = AsyncValue.data(status);
    return status;
  }
}

// =============================================================================
// OFFERINGS PROVIDER
// =============================================================================

/// Lädt die verfügbaren Produkte/Preise aus RevenueCat.
/// Wird im Paywall-Screen genutzt um die echten Preise anzuzeigen.
final offeringsProvider = FutureProvider<Offerings?>((ref) {
  return ref.watch(subscriptionServiceProvider).getOfferings();
});

// =============================================================================
// CONVENIENCE PROVIDER
// =============================================================================

/// Schneller Zugriff: Hat der User gerade Zugriff auf die App?
final hasSubscriptionAccessProvider = Provider<bool>((ref) {
  final status = ref.watch(subscriptionStatusProvider);
  return status.when(
    data: (s) => s.hasAccess,
    loading: () => true, // Im Zweifel Zugriff lassen (vermeidet Flackern)
    error: (_, __) => true,
  );
});

/// Schneller Zugriff: Wie viele Kinder darf der User anlegen?
final childLimitProvider = Provider<int>((ref) {
  final status = ref.watch(subscriptionStatusProvider);
  return status.when(
    data: (s) => s.childLimit,
    loading: () => 4, // Im Zweifel großzügig
    error: (_, __) => 4,
  );
});

/// Schneller Zugriff: Aktueller Plan (oder none)
final currentPlanProvider = Provider<SubscriptionPlan>((ref) {
  final status = ref.watch(subscriptionStatusProvider);
  return status.when(
    data: (s) => s.plan,
    loading: () => SubscriptionPlan.none,
    error: (_, __) => SubscriptionPlan.none,
  );
});
