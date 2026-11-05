import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../../shared/platform_info.dart';
import 'subscription_model.dart';
import 'package:lerndex/src/features/auth/domain/account.dart';
import '../../auth/data/child_device_repository.dart' show lerndexFunctions;

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
  // Web Billing (Stripe) – eigener Key aus dem RevenueCat-Dashboard.
  static const _webApiKey = String.fromEnvironment('REVENUECAT_WEB_KEY');

  static const _entitlementId = 'premium';

  /// True sobald `Purchases.configure` erfolgreich lief. Solange false sind
  /// keine IAP-Funktionen verfügbar (z.B. wenn der Plattform-API-Key fehlt) –
  /// die App startet trotzdem normal.
  static bool isConfigured = false;

  /// RevenueCat Produkt-ID für den zugekauften Kind-Slot (Consumable IAP).
  /// Muss exakt so in App Store Connect & Google Play Console angelegt sein.
  static const _extraChildSlotProductId = 'lerndex_extra_child_slot';

  static Future<void> initialize() async {
    final apiKey = kIsWeb
        ? _webApiKey
        : isIOSApp
        ? _iosApiKey
        : _androidApiKey;

    // Kein API-Key (z.B. Apple-Key noch nicht vorhanden) → IAP überspringen,
    // damit die App trotzdem startet. Käufe sind dann schlicht deaktiviert.
    if (apiKey.isEmpty) {
      debugPrint(
        '⚠️ RevenueCat: Kein API-Key für $platformName '
        '– In-App-Käufe deaktiviert, App läuft normal weiter.',
      );
      return;
    }

    try {
      await Purchases.configure(PurchasesConfiguration(apiKey));
      if (kDebugMode) {
        await Purchases.setLogLevel(LogLevel.debug);
      }
      isConfigured = true;
      debugPrint('✅ RevenueCat initialisiert');
    } catch (e) {
      // Konfiguration darf den App-Start niemals verhindern.
      debugPrint('❌ RevenueCat-Konfiguration fehlgeschlagen: $e');
    }
  }

  Future<void> identifyUser(String uid) async {
    if (!isConfigured) return;
    try {
      await Purchases.logIn(uid);
      debugPrint('✅ RevenueCat User identifiziert: $uid');
    } catch (e) {
      debugPrint('❌ RevenueCat identify Fehler: $e');
    }
  }

  Future<void> logOut() async {
    if (!isConfigured) return;
    try {
      await Purchases.logOut();
      debugPrint('✅ RevenueCat ausgeloggt');
    } catch (e) {
      debugPrint('❌ RevenueCat logout Fehler: $e');
    }
  }

  /// Ohne RevenueCat (Browser ohne Web-Key) und auf gekoppelten Kinder-
  /// geräten zählt der Abo-Status, den das kaufende Gerät in Firestore
  /// gespeichert hat. Sonst meldete RevenueCat dort „kein Abo“, und zahlende
  /// Familien verlören im Browser bzw. auf dem Kinderhandy den Zugang.
  bool get _useStoredStatus =>
      !isConfigured || (_auth.currentUser?.isChildDevice ?? false);

  Future<SubscriptionStatus> getSubscriptionStatus() async {
    if (_useStoredStatus) return getStatusFromFirestore();
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
    if (!isConfigured) {
      // Ohne RevenueCat-Konfiguration kein Listener – es gilt der Status aus
      // Firestore (siehe _useStoredStatus).
      return controller.stream;
    }
    Purchases.addCustomerInfoUpdateListener((customerInfo) {
      // Kindergerät: RevenueCat kennt dort nur einen anonymen Nutzer ohne Abo
      if (_auth.currentUser?.isChildDevice ?? false) return;
      // Nach dem Abmelden meldet RevenueCat den anonymen Nutzer ohne Abo –
      // der gehört zu keinem Konto mehr.
      if (customerInfo.originalAppUserId.startsWith(r'$RCAnonymousID')) return;
      final status = _parseCustomerInfo(customerInfo);
      // Den gespeicherten Status (Browser, Kindergeräte) schreibt der Server.
      unawaited(syncWithServer());
      controller.add(status);
    });
    return controller.stream;
  }

  SubscriptionStatus _parseCustomerInfo(CustomerInfo info) {
    final entitlement = info.entitlements.active[_entitlementId];

    if (entitlement == null) {
      // Zusatzplätze gelten nur mit Family-Abo, bleiben aber gezählt
      return SubscriptionStatus(
        plan: SubscriptionPlan.none,
        isActive: false,
        isTrial: false,
        extraChildSlots: _extraSlots(info),
      );
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
      extraChildSlots: _extraSlots(info),
    );
  }

  /// Link zur Abo-Verwaltung des Stores, in dem gekauft wurde (Google Play,
  /// App Store oder das Stripe-Kundenportal bei Web-Käufen).
  Future<String?> getManagementUrl() async {
    if (!isConfigured) return null;
    try {
      return (await Purchases.getCustomerInfo()).managementURL;
    } catch (e) {
      debugPrint('❌ Fehler beim Laden der Abo-Verwaltung: $e');
      return null;
    }
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
            unawaited(syncWithServer());
            return status;
          }

          // Anderes Produkt aktiv → Plan-Wechsel mit GoogleProductChangeInfo
          debugPrint(
            '🔄 Plan-Wechsel: $oldProductId → ${package.storeProduct.identifier}',
          );
          result = await Purchases.purchase(
            PurchaseParams.package(
              package,
              googleProductChangeInfo: GoogleProductChangeInfo(
                oldProductId,
                prorationMode: GoogleProrationMode.immediateWithTimeProration,
              ),
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
      unawaited(syncWithServer());
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
      unawaited(syncWithServer());
      return status;
    } catch (e) {
      throw 'Wiederherstellen fehlgeschlagen: $e';
    }
  }

  /// Kauft einen zusätzlichen Kind-Slot (Consumable, 6,99 €).
  /// Die Zahl der Plätze ergibt sich aus den Käufen bei RevenueCat
  /// (App: CustomerInfo, Server: syncSubscription).
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

      await Purchases.purchase(PurchaseParams.storeProduct(product));
      await syncWithServer();
      debugPrint('✅ Extra Kind-Slot gekauft');
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

  /// Gekaufte Zusatz-Kinderplätze (Consumable, jeder Kauf ein Platz).
  static int _extraSlots(CustomerInfo info) => info.nonSubscriptionTransactions
      .where((t) => t.productIdentifier == _extraChildSlotProductId)
      .length;

  /// Der Server holt den Status bei RevenueCat und speichert ihn am
  /// Elternkonto (Browser und Kindergeräte lesen ihn dort). Fehler sind hier
  /// unkritisch: der RevenueCat-Webhook gleicht ebenfalls ab.
  Future<void> syncWithServer() async {
    final user = _auth.currentUser;
    if (user == null || user.isChildDevice || !isConfigured) return;
    try {
      await lerndexFunctions().httpsCallable('syncSubscription').call();
    } catch (e) {
      debugPrint('⚠️ Abo-Abgleich mit dem Server fehlgeschlagen: $e');
    }
  }

  /// Gespeicherter Status (vom Server geschrieben).
  Future<SubscriptionStatus> getStatusFromFirestore() async {
    final uid = _auth.currentUser?.ownerUid;
    if (uid == null) return SubscriptionStatus.empty;

    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      final data = doc.data();
      // Review-Testaccount: Top-Level-Flag gewinnt über alles. Es liegt
      // bewusst NICHT unter `subscription`, damit der Abo-Abgleich des
      // Servers es nie wegräumt.
      if (data?['testAccess'] == true) {
        return SubscriptionStatus.testAccess;
      }
      // Schul-Lizenz (users/school_<id>): setzt nur Lerndex, z.B. in der
      // Firebase Console – gilt für alle Schüler der Schule.
      final licenseUntil = (data?['schoolLicenseUntil'] as Timestamp?)
          ?.toDate();
      if (licenseUntil != null && licenseUntil.isAfter(DateTime.now())) {
        return SubscriptionStatus(
          plan: SubscriptionPlan.family,
          isActive: true,
          expiresAt: licenseUntil,
        );
      }
      final subscriptionData = data?['subscription'] as Map<String, dynamic>?;
      return SubscriptionStatus.fromFirestore(subscriptionData);
    } catch (e) {
      debugPrint('❌ Fehler beim Laden aus Firestore: $e');
      return SubscriptionStatus.empty;
    }
  }

  /// Ist der eingeloggte User ein Review-/Testaccount?
  /// Gesteuert über `testAccess: true` am users/{uid}-Dokument – wird nur
  /// manuell in der Firebase Console gesetzt und ist per Security Rules
  /// gegen Selbst-Freischaltung durch Clients geschützt.
  Future<bool> hasTestAccess() async {
    final uid = _auth.currentUser?.ownerUid;
    if (uid == null) return false;

    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      return doc.data()?['testAccess'] == true;
    } catch (_) {
      return false;
    }
  }
}
