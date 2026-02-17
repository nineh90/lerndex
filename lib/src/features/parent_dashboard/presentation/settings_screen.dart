import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/data/profile_repository.dart';

/// Einstellungsbereich im Elterndashboard
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isDeletingAccount = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstellungen'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        children: [
          // ── Abschnitt: Konto ─────────────────────────────────────────
          const _SectionHeader(title: 'Konto'),

          // TODO: E-Mail ändern (später)
          // TODO: Passwort ändern (später)
          // TODO: PIN ändern (später)

          // ── Konto löschen ────────────────────────────────────────────
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text(
              'Konto löschen',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Löscht dein Konto und alle Daten dauerhaft',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _isDeletingAccount ? null : () => _confirmDeleteAccount(context),
          ),

          const Divider(),
        ],
      ),
    );
  }

  /// Zeigt Bestätigungs-Dialog vor dem Löschen
  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _DeleteAccountDialog(),
    );

    if (confirmed == true && mounted) {
      await _deleteAccount();
    }
  }

  /// Führt das Löschen durch
  Future<void> _deleteAccount() async {
    setState(() => _isDeletingAccount = true);

    try {
      // 1. Alle Firestore-Daten löschen
      await ref.read(profileRepositoryProvider).deleteAllUserData();

      // 2. Firebase Auth Account löschen
      await ref.read(authRepositoryProvider).deleteAccount();

      // Firebase Auth-State-Change navigiert automatisch zur Login-Seite
      // (authStateChanges Stream emittiert null → App-Root zeigt LoginScreen)

    } catch (e) {
      if (mounted) {
        setState(() => _isDeletingAccount = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Löschen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// ── Wiederverwendbarer Abschnitts-Header ──────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.deepPurple[700],
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// ── Bestätigungs-Dialog ───────────────────────────────────────────────────
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  bool _understood = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
          SizedBox(width: 8),
          Text('Konto löschen?'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Diese Aktion kann nicht rückgängig gemacht werden.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text('Folgendes wird dauerhaft gelöscht:'),
          const SizedBox(height: 8),
          _buildBullet('Dein Eltern-Account'),
          _buildBullet('Alle Kinderprofile'),
          _buildBullet('Sämtliche Lernfortschritte & XP'),
          _buildBullet('Alle Tutor-Gespräche'),
          _buildBullet('Alle Belohnungen'),
          const SizedBox(height: 16),
          Row(
            children: [
              Checkbox(
                value: _understood,
                activeColor: Colors.red,
                onChanged: (val) => setState(() => _understood = val ?? false),
              ),
              const Expanded(
                child: Text(
                  'Ich verstehe, dass alle Daten unwiderruflich gelöscht werden.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton(
          onPressed: _understood
              ? () => Navigator.pop(context, true)
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.red.withOpacity(0.3),
          ),
          child: const Text('Konto löschen'),
        ),
      ],
    );
  }

  Widget _buildBullet(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Colors.red)),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}