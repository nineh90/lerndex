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

  /// RevenueCat Produkt-ID für den zugekauften Kind-Slot (Consumable IAP).
  /// Muss exakt so in App Store Connect & Google Play Console angelegt sein.
  static const _extraChildSlotProductId = 'lerndex_extra_child_slot';

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
      final status = _parseCustomerInfo(customerInfo);
      // Immer in Firestore syncen – auch bei Kündigung (leerer Status),
      // damit der App-Start-Cache nie einen abgelaufenen Zugriff zurückgibt.
      _syncToFirestore(status);
      controller.add(status);
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
      PurchaseResult result;

      // Aktives Abo ermitteln – beim Plan-Wechsel muss das alte Produkt
      // als googleProductChangeInfo übergeben werden, damit Google Play
      // das alte Abo ersetzt statt ein zweites parallel zu starten.
      try {
        final customerInfo = await Purchases.getCustomerInfo();
        final activeSubscriptions = customerInfo.activeSubscriptions;

        if (activeSubscriptions.isNotEmpty) {
          final oldProductId = activeSubscriptions.first;

          // Dasselbe Produkt bereits aktiv → kein Kauf nötig
          if (oldProductId == package.storeProduct.identifier) {
            debugPrint('ℹ️ Dasselbe Produkt bereits aktiv: $oldProductId');
            final status = _parseCustomerInfo(customerInfo);
            await _syncToFirestore(status);
            return status;
          }

          // Anderes Produkt aktiv → Plan-Wechsel mit GoogleProductChangeInfo
          debugPrint(
            '🔄 Plan-Wechsel: $oldProductId → ${package.storeProduct.identifier}',
          );
          result = await Purchases.purchasePackage(
            package,
            googleProductChangeInfo: GoogleProductChangeInfo(
              oldProductId,
              prorationMode: GoogleProrationMode.immediateWithTimeProration,
            ),
          );
        } else {
          // Kein aktives Abo → normaler Erstkauf
          result = await Purchases.purchase(PurchaseParams.package(package));
        }
      } catch (innerError) {
        final msg = innerError.toString();
        if (msg.contains('purchaseCancelled') || msg.contains('abgebrochen')) {
          rethrow;
        }
        // Fallback: normaler Kauf wenn getCustomerInfo fehlschlägt
        debugPrint('⚠️ Plan-Wechsel Fallback: $innerError');
        result = await Purchases.purchase(PurchaseParams.package(package));
      }

      final status = _parseCustomerInfo(result.customerInfo);
      await _syncToFirestore(status);
      return status;
    } on PurchasesErrorCode catch (e) {
      if (e == PurchasesErrorCode.purchaseCancelledError) {
        throw 'Kauf abgebrochen.';
      }
      throw 'Kauf fehlgeschlagen: ${e.name}';
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('abgebrochen') || msg.contains('Kauf')) rethrow;
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

  /// Kauft einen zusätzlichen Kind-Slot (Consumable, 6,99 €).
  /// Erhöht nach erfolgreichem Kauf `extraChildSlots` in Firestore um 1.
  /// Nur erlaubt wenn der User einen aktiven Family-Plan hat.
  Future<void> purchaseExtraChildSlot() async {
    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      if (current == null) throw 'Angebote konnten nicht geladen werden.';

      // Produkt aus dem aktuellen Offering holen
      StoreProduct? product;
      for (final pkg in current.availablePackages) {
        if (pkg.storeProduct.identifier == _extraChildSlotProductId) {
          product = pkg.storeProduct;
          break;
        }
      }

      // Falls nicht im Offering → direkt als Produkt laden
      product ??= (await Purchases.getProducts([
        _extraChildSlotProductId,
      ], productCategory: ProductCategory.nonSubscription)).firstOrNull;

      if (product == null) {
        throw 'Produkt "$_extraChildSlotProductId" nicht gefunden. '
            'Bitte sicherstellen, dass es in RevenueCat konfiguriert ist.';
      }

      await Purchases.purchaseStoreProduct(product);

      // Kauf erfolgreich → Slot-Zähler in Firestore atomar erhöhen
      await _incrementExtraChildSlot();
      debugPrint('✅ Extra Kind-Slot gekauft und in Firestore gespeichert');
    } on PurchasesErrorCode catch (e) {
      if (e == PurchasesErrorCode.purchaseCancelledError) {
        throw 'Kauf abgebrochen.';
      }
      throw 'Kauf fehlgeschlagen: ${e.name}';
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('abgebrochen') || msg.contains('Kauf')) rethrow;
      throw 'Unbekannter Fehler beim Kauf: $e';
    }
  }

  /// Erhöht `extraChildSlots` im Firestore-Userdokument atomar um 1.
  Future<void> _incrementExtraChildSlot() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    await _firestore.collection('users').doc(uid).update({
      'subscription.extraChildSlots': FieldValue.increment(1),
      'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
    });
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
