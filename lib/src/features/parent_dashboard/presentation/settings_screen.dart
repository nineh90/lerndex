import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/data/profile_repository.dart';
import '../../auth/presentation/login_screen.dart';

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
            trailing: _isDeletingAccount
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.chevron_right),
            onTap: _isDeletingAccount
                ? null
                : () => _confirmDeleteAccount(context),
          ),

          const Divider(),
        ],
      ),
    );
  }

  /// Schritt 1: Bestätigungs-Dialog zeigen
  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _DeleteAccountDialog(),
    );

    if (confirmed == true && mounted) {
      // Schritt 2: Passwort zur Re-Authentifizierung abfragen
      await _askPasswordAndDelete(context);
    }
  }

  /// Schritt 2: Passwort abfragen und Re-Auth + Löschen durchführen
  Future<void> _askPasswordAndDelete(BuildContext context) async {
    final passwordController = TextEditingController();
    bool obscure = true;

    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Passwort bestätigen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Bitte gib dein Passwort ein, um das Konto endgültig zu löschen.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: obscure,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Passwort',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                        obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () =>
                        setDialogState(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(context, passwordController.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Konto löschen'),
            ),
          ],
        ),
      ),
    );

    passwordController.dispose();

    if (password == null || password.isEmpty) return;
    if (!mounted) return;

    await _deleteAccount(password);
  }

  /// Schritt 3: Re-Authentifizierung + Daten löschen + Auth-Account löschen
  Future<void> _deleteAccount(String password) async {
    setState(() => _isDeletingAccount = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        throw Exception('Kein Benutzer angemeldet.');
      }

      // Re-Authentifizierung – Firebase verlangt das vor user.delete()
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);

      // Alle Firestore-Daten löschen
      await ref.read(profileRepositoryProvider).deleteAllUserData();

      // Firebase Auth Account löschen
      await ref.read(authRepositoryProvider).deleteAccount();

      // Stack komplett leeren und zum Login navigieren
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
        );
      }

      // authStateChanges emittiert null → App navigiert automatisch zum Login

    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isDeletingAccount = false);

      String message;
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        message = 'Falsches Passwort. Bitte versuche es erneut.';
      } else if (e.code == 'too-many-requests') {
        message = 'Zu viele Versuche. Bitte warte kurz und versuche es erneut.';
      } else {
        message = 'Fehler: ${e.message}';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
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
                onChanged: (val) =>
                    setState(() => _understood = val ?? false),
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
          onPressed: _understood ? () => Navigator.pop(context, true) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.red.withOpacity(0.3),
          ),
          child: const Text('Weiter'),
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