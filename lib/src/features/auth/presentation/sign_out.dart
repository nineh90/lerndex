import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../school/data/parent_link_repository.dart';
import '../../school/data/school_repository.dart';
import '../../subscription/data/subscription_provider.dart';
import '../data/auth_repository.dart';
import 'active_child_provider.dart';
import 'login_screen.dart';

// ============================================================================
// ABMELDEN
//
// Alle Abmeldewege (Eltern, Schule, Kinder- und Schülergeräte, Abbruch der
// E-Mail-Bestätigung, Kontowechsel über Links) laufen über signOutAccount.
// Nur so ist sicher, dass nichts vom alten Konto hängen bleibt.
// ============================================================================

/// Nachfragen, abmelden und zur Anmeldung.
Future<void> confirmSignOut(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Abmelden?'),
      content: const Text('Möchtest du dich wirklich abmelden?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('Abmelden'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final navigator = Navigator.of(context);
  await signOutAccount(ref);
  navigator.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (_) => false,
  );
}

/// Abmelden ohne Rückfrage:
/// 1. gemerkten Eltern-Code vergessen (sonst löst ihn das nächste Konto ein),
/// 2. Firebase (und Google) abmelden,
/// 3. erst danach RevenueCat – so landet kein Abo-Status des anonymen
///    RevenueCat-Nutzers beim alten Konto,
/// 4. im Browser wieder dauerhaft anmelden (Schulkonten nur im Tab),
/// 5. Provider mit Daten des alten Kontos zurücksetzen.
///
/// Darf aufgerufen werden, auch wenn das aufrufende Widget beim Abmelden
/// verschwindet: Alles läuft über den ProviderContainer.
Future<void> signOutAccount(WidgetRef ref) =>
    signOutWithContainer(ProviderScope.containerOf(ref.context, listen: false));

/// Wie [signOutAccount], für Stellen ohne WidgetRef.
Future<void> signOutWithContainer(ProviderContainer container) async {
  final auth = container.read(authRepositoryProvider);

  try {
    await container.read(parentLinkRepositoryProvider).clearPending();
  } catch (e) {
    debugPrint('⚠️ Gemerkter Eltern-Code nicht gelöscht: $e');
  }

  await auth.signOut();

  try {
    await container.read(subscriptionServiceProvider).logOut();
  } catch (e) {
    debugPrint('⚠️ RevenueCat-Abmeldung: $e');
  }

  await auth.keepLoginOnThisDevice();

  container
    ..invalidate(activeChildProvider)
    ..invalidate(subscriptionStatusProvider)
    ..invalidate(schoolMembershipProvider)
    ..invalidate(schoolChildLinksProvider);
}
