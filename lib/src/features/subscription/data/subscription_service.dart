import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'subscription_model.dart';

class SubscriptionService {
  SubscriptionService(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  static const bool _devBypass = false;

  // API-Keys werden zur Build-Zeit per --dart-define-from-file injiziert.
  // Niemals direkt hier eintragen! Siehe dart_defines.json (liegt in .gitignore).
  static const _androidApiKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_KEY',
  );
  static const _iosApiKey = String.fromEnvironment('REVENUECAT_IOS_KEY');

  static const _entitlementId = 'premium';

  static Future<void> initialize() async {
    final apiKey = Platform.isIOS ? _iosApiKey : _androidApiKey;

    await Purchases.configure(PurchasesConfiguration(apiKey));

    if (kDebugMode) {
      await Purchases.setLogLevel(LogLevel.debug);
    }

    debugPrint('✅ RevenueCat initialisiert');
  }

  Future<void> identifyUser(String uid) async {
    try {
      await Purchases.logIn(uid);
      debugPrint('✅ RevenueCat User identifiziert: $uid');
    } catch (e) {
      debugPrint('❌ RevenueCat identify Fehler: $e');
    }
  }

  Future<void> logOut() async {
    try {
      await Purchases.logOut();
      debugPrint('✅ RevenueCat ausgeloggt');
    } catch (e) {
      debugPrint('❌ RevenueCat logout Fehler: $e');
    }
  }

  Future<SubscriptionStatus> getSubscriptionStatus() async {
    try {
      if (_devBypass) {
        return SubscriptionStatus(
          plan: SubscriptionPlan.family,
          isActive: true,
          isTrial: false,
          expiresAt: DateTime.now().add(const Duration(days: 365)),
        );
      }
      final customerInfo = await Purchases.getCustomerInfo();
      return _parseCustomerInfo(customerInfo);
    } catch (e) {
      debugPrint('❌ Fehler beim Abrufen des Abo-Status: $e');
      return SubscriptionStatus.empty;
    }
  }

  Stream<SubscriptionStatus> get customerInfoStream {
    final controller = StreamController<SubscriptionStatus>.broadcast();
    Purchases.addCustomerInfoUpdateListener((customerInfo) {
      controller.add(_parseCustomerInfo(customerInfo));
    });
    return controller.stream;
  }

  SubscriptionStatus _parseCustomerInfo(CustomerInfo info) {
    final entitlement = info.entitlements.active[_entitlementId];

    if (entitlement == null) {
      return SubscriptionStatus.empty;
    }

    final plan = SubscriptionPlanExtension.fromEntitlement(
      entitlement.productIdentifier,
    );

    final isTrial = entitlement.periodType == PeriodType.trial;

    final expiresAt = entitlement.expirationDate != null
        ? DateTime.tryParse(entitlement.expirationDate!)
        : null;

    return SubscriptionStatus(
      plan: plan,
      isActive: true,
      isTrial: isTrial,
      expiresAt: expiresAt,
    );
  }

  Future<Offerings?> getOfferings() async {
    try {
      return await Purchases.getOfferings();
    } catch (e) {
      debugPrint('❌ Fehler beim Laden der Offerings: $e');
      return null;
    }
  }

  Future<SubscriptionStatus> purchasePackage(Package package) async {
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      final status = _parseCustomerInfo(result.customerInfo);

      await _syncToFirestore(status);

      return status;
    } on PurchasesErrorCode catch (e) {
      if (e == PurchasesErrorCode.purchaseCancelledError) {
        throw 'Kauf abgebrochen.';
      }
      throw 'Kauf fehlgeschlagen: ${e.name}';
    } catch (e) {
      throw 'Unbekannter Fehler: $e';
    }
  }

  Future<SubscriptionStatus> restorePurchases() async {
    try {
      final customerInfo = await Purchases.restorePurchases();
      final status = _parseCustomerInfo(customerInfo);
      await _syncToFirestore(status);
      return status;
    } catch (e) {
      throw 'Wiederherstellen fehlgeschlagen: $e';
    }
  }

  Future<void> _syncToFirestore(SubscriptionStatus status) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      await _firestore.collection('users').doc(uid).update({
        'subscription': status.toFirestore(),
        'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint(
        '✅ Abo-Status in Firestore gespeichert: ${status.plan.displayName}',
      );
    } catch (e) {
      debugPrint('❌ Fehler beim Speichern des Abo-Status: $e');
    }
  }

  Future<SubscriptionStatus> getStatusFromFirestore() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return SubscriptionStatus.empty;

    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      final subscriptionData =
          doc.data()?['subscription'] as Map<String, dynamic>?;
      return SubscriptionStatus.fromFirestore(subscriptionData);
    } catch (e) {
      debugPrint('❌ Fehler beim Laden aus Firestore: $e');
      return SubscriptionStatus.empty;
    }
  }
}
