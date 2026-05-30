import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/subscription/data/subscription_model.dart';

void main() {
  group('SubscriptionPlan.childLimit', () {
    test('none erlaubt keine Kinder', () {
      expect(SubscriptionPlan.none.childLimit, 0);
    });
    test('trial gibt alles frei (4)', () {
      expect(SubscriptionPlan.trial.childLimit, 4);
    });
    test('solo erlaubt 1 Kind', () {
      expect(SubscriptionPlan.solo.childLimit, 1);
    });
    test('duo erlaubt 2 Kinder', () {
      expect(SubscriptionPlan.duo.childLimit, 2);
    });
    test('family erlaubt 4 Kinder', () {
      expect(SubscriptionPlan.family.childLimit, 4);
    });
  });

  group('SubscriptionPlan.hasAccess', () {
    test('nur none hat keinen Zugriff', () {
      expect(SubscriptionPlan.none.hasAccess, isFalse);
      expect(SubscriptionPlan.trial.hasAccess, isTrue);
      expect(SubscriptionPlan.solo.hasAccess, isTrue);
      expect(SubscriptionPlan.duo.hasAccess, isTrue);
      expect(SubscriptionPlan.family.hasAccess, isTrue);
    });
  });

  group('SubscriptionPlanExtension.fromString', () {
    test('mappt bekannte Strings', () {
      expect(SubscriptionPlanExtension.fromString('trial'),
          SubscriptionPlan.trial);
      expect(SubscriptionPlanExtension.fromString('solo'),
          SubscriptionPlan.solo);
      expect(SubscriptionPlanExtension.fromString('duo'), SubscriptionPlan.duo);
      expect(SubscriptionPlanExtension.fromString('family'),
          SubscriptionPlan.family);
    });
    test('null und unbekannt → none', () {
      expect(SubscriptionPlanExtension.fromString(null), SubscriptionPlan.none);
      expect(SubscriptionPlanExtension.fromString('quatsch'),
          SubscriptionPlan.none);
    });
  });

  group('SubscriptionPlanExtension.fromEntitlement', () {
    test('null → none', () {
      expect(SubscriptionPlanExtension.fromEntitlement(null),
          SubscriptionPlan.none);
    });
    test('erkennt Produkt-Identifier per Substring', () {
      expect(SubscriptionPlanExtension.fromEntitlement('lerndex_solo_monthly'),
          SubscriptionPlan.solo);
      expect(SubscriptionPlanExtension.fromEntitlement('lerndex_duo'),
          SubscriptionPlan.duo);
      expect(SubscriptionPlanExtension.fromEntitlement('lerndex_family'),
          SubscriptionPlan.family);
    });
    test('unbekanntes Produkt → none', () {
      expect(SubscriptionPlanExtension.fromEntitlement('something_else'),
          SubscriptionPlan.none);
    });
  });

  group('toFirestore Roundtrip', () {
    test('fromString(toFirestore(x)) == x', () {
      for (final plan in SubscriptionPlan.values) {
        expect(SubscriptionPlanExtension.fromString(plan.toFirestore()), plan);
      }
    });
  });

  group('revenueCatPackageId', () {
    test('nur bezahlte Pläne haben eine Package-Id', () {
      expect(SubscriptionPlan.solo.revenueCatPackageId, isNotNull);
      expect(SubscriptionPlan.duo.revenueCatPackageId, 'lerndex_duo');
      expect(SubscriptionPlan.family.revenueCatPackageId, 'lerndex_family');
      expect(SubscriptionPlan.none.revenueCatPackageId, isNull);
      expect(SubscriptionPlan.trial.revenueCatPackageId, isNull);
    });
  });

  group('SubscriptionStatus', () {
    test('empty hat keinen Zugriff und kein Kind-Limit', () {
      expect(SubscriptionStatus.empty.hasAccess, isFalse);
      expect(SubscriptionStatus.empty.childLimit, 0);
    });

    test('hasAccess erfordert isActive UND Plan mit Zugriff', () {
      const inactiveFamily =
          SubscriptionStatus(plan: SubscriptionPlan.family, isActive: false);
      const activeNone =
          SubscriptionStatus(plan: SubscriptionPlan.none, isActive: true);
      const activeFamily =
          SubscriptionStatus(plan: SubscriptionPlan.family, isActive: true);
      expect(inactiveFamily.hasAccess, isFalse);
      expect(activeNone.hasAccess, isFalse);
      expect(activeFamily.hasAccess, isTrue);
    });

    test('childLimit addiert zugekaufte Slots', () {
      const status = SubscriptionStatus(
        plan: SubscriptionPlan.family,
        isActive: true,
        extraChildSlots: 3,
      );
      expect(status.childLimit, 7); // 4 + 3
    });

    test('canPurchaseExtraChildSlot nur bei aktivem Family-Plan', () {
      const activeFamily =
          SubscriptionStatus(plan: SubscriptionPlan.family, isActive: true);
      const activeDuo =
          SubscriptionStatus(plan: SubscriptionPlan.duo, isActive: true);
      const inactiveFamily =
          SubscriptionStatus(plan: SubscriptionPlan.family, isActive: false);
      expect(activeFamily.canPurchaseExtraChildSlot, isTrue);
      expect(activeDuo.canPurchaseExtraChildSlot, isFalse);
      expect(inactiveFamily.canPurchaseExtraChildSlot, isFalse);
    });

    test('fromFirestore(null) → empty', () {
      final status = SubscriptionStatus.fromFirestore(null);
      expect(status.plan, SubscriptionPlan.none);
      expect(status.isActive, isFalse);
    });

    test('fromFirestore liest alle Felder', () {
      final expires = DateTime(2026, 12, 31, 23, 59);
      final status = SubscriptionStatus.fromFirestore({
        'plan': 'family',
        'isActive': true,
        'isTrial': false,
        'expiresAt': Timestamp.fromDate(expires),
        'extraChildSlots': 2,
      });
      expect(status.plan, SubscriptionPlan.family);
      expect(status.isActive, isTrue);
      expect(status.extraChildSlots, 2);
      expect(status.expiresAt, expires);
      expect(status.childLimit, 6);
    });

    test('toFirestore enthält Plan und Status', () {
      const status = SubscriptionStatus(
        plan: SubscriptionPlan.solo,
        isActive: true,
        isTrial: false,
      );
      final map = status.toFirestore();
      expect(map['plan'], 'solo');
      expect(map['isActive'], isTrue);
      // extraChildSlots wird bewusst NICHT überschrieben
      expect(map.containsKey('extraChildSlots'), isFalse);
    });
  });
}
