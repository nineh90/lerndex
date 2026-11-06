import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/device_access.dart';
import 'package:lerndex/src/features/subscription/data/subscription_model.dart';

void main() {
  const active = SubscriptionStatus(
    plan: SubscriptionPlan.family,
    isActive: true,
  );
  final now = DateTime(2026, 11, 6);

  test('Daten entscheiden', () {
    expect(
      resolveDeviceAccess(const AsyncValue.data(active)),
      DeviceAccess.granted,
    );
    expect(
      resolveDeviceAccess(const AsyncValue.data(SubscriptionStatus.empty)),
      DeviceAccess.denied,
    );
  });

  test('Fehler ohne bekannten Status: nicht offen, sondern erneut prüfen', () {
    expect(
      resolveDeviceAccess(AsyncValue.error('offline', StackTrace.empty)),
      DeviceAccess.failed,
    );
    expect(
      resolveDeviceAccess(const AsyncValue.loading()),
      DeviceAccess.checking,
    );
  });

  test('kurzer Netzfehler: zuletzt bekannter Status gilt weiter', () {
    expect(
      resolveDeviceAccess(
        AsyncValue.error('offline', StackTrace.empty),
        lastKnown: active,
        now: now,
      ),
      DeviceAccess.granted,
    );
    expect(
      resolveDeviceAccess(
        AsyncValue.error('offline', StackTrace.empty),
        lastKnown: SubscriptionStatus.empty,
        now: now,
      ),
      DeviceAccess.denied,
    );
  });

  test('abgelaufener bekannter Status öffnet nicht', () {
    final expired = SubscriptionStatus(
      plan: SubscriptionPlan.family,
      isActive: true,
      expiresAt: DateTime(2026, 11, 1),
    );
    expect(
      resolveDeviceAccess(
        AsyncValue.error('offline', StackTrace.empty),
        lastKnown: expired,
        now: now,
      ),
      DeviceAccess.denied,
    );
  });
}
