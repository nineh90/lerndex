import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Temporärer Stub für Rewards Screen
class RewardsScreen extends ConsumerWidget {
  const RewardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Belohnungen'),
        backgroundColor: Colors.amber,
      ),
      body: const Center(
        child: Text(
          '🎁 Belohnungs-System kommt bald!\n\n(Zuerst testen wir das XP-System)',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}