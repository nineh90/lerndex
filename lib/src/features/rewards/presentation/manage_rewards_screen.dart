import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/child_model.dart';

/// Temporärer Stub für Manage Rewards Screen
class ManageRewardsScreen extends ConsumerWidget {
  final ChildModel child;

  const ManageRewardsScreen({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Belohnungen für ${child.name}'),
        backgroundColor: Colors.amber,
      ),
      body: const Center(
        child: Text(
          '🎁 Belohnungs-Verwaltung kommt bald!\n\n(Zuerst testen wir das XP-System)',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}