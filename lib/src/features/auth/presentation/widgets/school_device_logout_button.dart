import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth_repository.dart';
import '../active_child_provider.dart';
import '../login_screen.dart';

/// Abmelden auf einem Schul-Tablet, damit das nächste Kind seine Karte
/// scannen kann. Zu Hause (gekoppeltes Kindergerät) gibt es das nicht –
/// dort meldet der Elternteil das Gerät ab.
class SchoolDeviceLogoutButton extends ConsumerWidget {
  const SchoolDeviceLogoutButton({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Abmelden',
      icon: Icon(Icons.logout_rounded, color: color),
      onPressed: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Abmelden?'),
            content: const Text(
              'Danach kann das nächste Kind seine Karte scannen.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Abmelden'),
              ),
            ],
          ),
        );
        if (ok != true || !context.mounted) return;
        // Navigator vorher holen: Abmelden baut das Dashboard um, danach
        // gäbe es diesen Knopf (und seinen context) nicht mehr.
        final navigator = Navigator.of(context);
        final activeChild = ref.read(activeChildProvider.notifier);
        await ref.read(authRepositoryProvider).signOut();
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
        activeChild.deselect();
      },
    );
  }
}
