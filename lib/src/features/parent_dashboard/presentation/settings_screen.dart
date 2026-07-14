import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lerndex/src/features/subscription/data/subscription_model.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/data/profile_repository.dart';
import '../../../../main.dart';
import '../../auth/presentation/account_deleted_screen.dart';
import '../data/pin_repository.dart';
// NEU: Subscription
import '../../subscription/data/subscription_provider.dart';
import '../../subscription/presentation/paywall_screen.dart';
import 'feedback_dialog.dart';

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
          // ── Abschnitt: Abo ───────────────────────────────────────────────
          const _SectionHeader(title: 'Abonnement'),
          _SubscriptionTile(),

          const Divider(indent: 16, endIndent: 16),

          // ── Abschnitt: Konto ─────────────────────────────────────────
          const _SectionHeader(title: 'Konto'),

          // ── Passwort ändern (nur für E-Mail/Passwort-Anmeldung) ───────
          // ✅ FIX: Google-/Apple-Nutzer haben kein Passwort – für sie führte
          // der Dialog ins Leere (Re-Auth schlug immer fehl).
          if (FirebaseAuth.instance.currentUser?.providerData.any(
                (p) => p.providerId == 'password',
              ) ??
              false)
            ListTile(
              leading: const Icon(
                Icons.lock_outline,
                color: Colors.deepPurple,
              ),
              title: const Text('Passwort ändern'),
              subtitle: const Text(
                'Lege ein neues Anmelde-Passwort fest',
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showChangePasswordDialog(context),
            ),

          // ── PIN ändern ────────────────────────────────────────────────
          ListTile(
            leading: const Icon(Icons.pin_outlined, color: Colors.deepPurple),
            title: const Text('Eltern-PIN ändern'),
            subtitle: const Text(
              'Ändere deinen 4–6-stelligen Eltern-PIN',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showChangePinDialog(context),
          ),

          const Divider(indent: 16, endIndent: 16),

          // ── Abschnitt: Hilfe & Feedback ──────────────────────────────
          const _SectionHeader(title: 'Hilfe & Feedback'),

          ListTile(
            leading: const Icon(
              Icons.feedback_outlined,
              color: Colors.deepPurple,
            ),
            title: const Text('Feedback senden'),
            subtitle: const Text(
              'Schreib uns an support@lerndex.de',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showFeedbackDialog(context),
          ),

          const Divider(indent: 16, endIndent: 16),

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

          const Divider(indent: 16, endIndent: 16),
        ],
      ),
    );
  }

  // ── Passwort ändern ──────────────────────────────────────────────────────
  Future<void> _showChangePasswordDialog(BuildContext context) async {
    final currentPwController = TextEditingController();
    final newPwController = TextEditingController();
    final confirmPwController = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    String? error;
    bool loading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.lock_outline, color: Colors.deepPurple),
              SizedBox(width: 8),
              Text('Passwort ändern'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPasswordField(
                  controller: currentPwController,
                  label: 'Aktuelles Passwort',
                  obscure: obscureCurrent,
                  onToggle: () =>
                      setDialogState(() => obscureCurrent = !obscureCurrent),
                ),
                const SizedBox(height: 12),
                _buildPasswordField(
                  controller: newPwController,
                  label: 'Neues Passwort',
                  obscure: obscureNew,
                  onToggle: () =>
                      setDialogState(() => obscureNew = !obscureNew),
                ),
                const SizedBox(height: 12),
                _buildPasswordField(
                  controller: confirmPwController,
                  label: 'Neues Passwort bestätigen',
                  obscure: obscureConfirm,
                  onToggle: () =>
                      setDialogState(() => obscureConfirm = !obscureConfirm),
                  errorText: error,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.of(context).pop(),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                      final current = currentPwController.text.trim();
                      final newPw = newPwController.text;
                      final confirm = confirmPwController.text;

                      if (current.isEmpty || newPw.isEmpty || confirm.isEmpty) {
                        setDialogState(
                          () => error = 'Bitte alle Felder ausfüllen.',
                        );
                        return;
                      }
                      if (newPw.length < 6) {
                        setDialogState(
                          () => error =
                              'Neues Passwort muss mind. 6 Zeichen haben.',
                        );
                        return;
                      }
                      if (newPw != confirm) {
                        setDialogState(
                          () => error = 'Passwörter stimmen nicht überein.',
                        );
                        return;
                      }

                      setDialogState(() {
                        loading = true;
                        error = null;
                      });

                      try {
                        final user = FirebaseAuth.instance.currentUser!;
                        final cred = EmailAuthProvider.credential(
                          email: user.email!,
                          password: current,
                        );
                        await user.reauthenticateWithCredential(cred);
                        await user.updatePassword(newPw);

                        if (context.mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Passwort erfolgreich geändert ✓'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } on FirebaseAuthException catch (e) {
                        String msg;
                        if (e.code == 'wrong-password' ||
                            e.code == 'invalid-credential') {
                          msg = 'Aktuelles Passwort ist falsch.';
                        } else if (e.code == 'too-many-requests') {
                          msg = 'Zu viele Versuche. Bitte warte kurz.';
                        } else {
                          msg = e.message ?? 'Unbekannter Fehler.';
                        }
                        setDialogState(() {
                          error = msg;
                          loading = false;
                        });
                      } catch (e) {
                        setDialogState(() {
                          error = 'Fehler: $e';
                          loading = false;
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    String? errorText,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        errorText: errorText,
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
          onPressed: onToggle,
        ),
      ),
    );
  }

  // ── PIN ändern ───────────────────────────────────────────────────────────
  Future<void> _showChangePinDialog(BuildContext context) async {
    final oldPinController = TextEditingController();
    final newPinController = TextEditingController();
    final confirmPinController = TextEditingController();
    String? error;
    bool loading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.pin_outlined, color: Colors.deepPurple),
              SizedBox(width: 8),
              Text('Eltern-PIN ändern'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPinField(
                  controller: oldPinController,
                  label: 'Aktueller PIN',
                  errorText: error,
                ),
                const SizedBox(height: 12),
                _buildPinField(
                  controller: newPinController,
                  label: 'Neuer PIN (4–6 Ziffern)',
                ),
                const SizedBox(height: 12),
                _buildPinField(
                  controller: confirmPinController,
                  label: 'Neuer PIN bestätigen',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.of(context).pop(),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                      final old = oldPinController.text;
                      final newPin = newPinController.text;
                      final confirm = confirmPinController.text;

                      if (old.isEmpty || newPin.isEmpty || confirm.isEmpty) {
                        setDialogState(
                          () => error = 'Bitte alle Felder ausfüllen.',
                        );
                        return;
                      }
                      if (newPin.length < 4 || newPin.length > 6) {
                        setDialogState(
                          () => error = 'Neuer PIN muss 4–6 Ziffern haben.',
                        );
                        return;
                      }
                      if (newPin != confirm) {
                        setDialogState(
                          () => error = 'PINs stimmen nicht überein.',
                        );
                        return;
                      }

                      setDialogState(() {
                        loading = true;
                        error = null;
                      });

                      try {
                        final user = ref.read(authStateChangesProvider).value;
                        if (user == null) throw Exception('Nicht eingeloggt');

                        final changed = await ref
                            .read(pinRepositoryProvider)
                            .changePin(user.uid, old, newPin);

                        if (!changed) {
                          setDialogState(() {
                            error = 'Aktueller PIN ist falsch.';
                            loading = false;
                          });
                          return;
                        }

                        if (context.mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('PIN erfolgreich geändert ✓'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() {
                          error = 'Fehler: $e';
                          loading = false;
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinField({
    required TextEditingController controller,
    required String label,
    String? errorText,
  }) {
    return TextField(
      controller: controller,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 6,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.pin),
        border: const OutlineInputBorder(),
        errorText: errorText,
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
      // ignore: use_build_context_synchronously – mounted guard is correct here
      await _startReauthAndDelete(this.context);
    }
  }

  /// Schritt 2: Re-Authentifizierung je nach Anmelde-Provider starten.
  ///
  /// ✅ FIX (DSGVO Art. 17): Vorher wurde IMMER ein Passwort abgefragt.
  /// Google- und Apple-Nutzer haben aber kein Passwort und konnten ihr
  /// Konto dadurch gar nicht löschen. Jetzt wird je nach Provider die
  /// passende Re-Auth-Methode verwendet.
  Future<void> _startReauthAndDelete(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final providers = user.providerData.map((p) => p.providerId).toSet();

    if (providers.contains('password')) {
      await _askPasswordAndDelete(context);
    } else if (providers.contains('google.com')) {
      await _reauthWithProviderAndDelete(GoogleAuthProvider());
    } else if (providers.contains('apple.com')) {
      await _reauthWithProviderAndDelete(AppleAuthProvider());
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        const SnackBar(
          content: Text(
            'Konto-Löschung für diese Anmeldemethode nicht möglich. '
            'Bitte kontaktiere den Support.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Re-Auth über OAuth-Provider (Google/Apple) und anschließend löschen.
  Future<void> _reauthWithProviderAndDelete(AuthProvider provider) async {
    setState(() => _isDeletingAccount = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Kein Benutzer angemeldet.');

      await user.reauthenticateWithProvider(provider);
      await _wipeDataAndDeleteAuth();
    } on FirebaseAuthException catch (e) {
      _handleDeleteError(_mapDeleteAuthError(e));
    } catch (e) {
      _handleDeleteError('Fehler beim Löschen: $e');
    }
  }

  /// Schritt 2 (E-Mail/Passwort): Passwort abfragen
  Future<void> _askPasswordAndDelete(BuildContext context) async {
    final passwordController = TextEditingController();
    bool obscure = true;

    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
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
                      obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setDialogState(() => obscure = !obscure),
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
              onPressed: () => Navigator.pop(context, passwordController.text),
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

    if (password == null || password.isEmpty) return;
    if (!mounted) return;

    await _deleteAccount(password);
  }

  /// Schritt 3 (E-Mail/Passwort): Re-Authentifizierung + Löschen
  Future<void> _deleteAccount(String password) async {
    setState(() => _isDeletingAccount = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        throw Exception('Kein Benutzer angemeldet.');
      }

      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);

      await _wipeDataAndDeleteAuth();
    } on FirebaseAuthException catch (e) {
      _handleDeleteError(_mapDeleteAuthError(e));
    } catch (e) {
      _handleDeleteError('Fehler beim Löschen: $e');
    }
  }

  /// Gemeinsamer letzter Schritt: Firestore-/Storage-Daten löschen,
  /// dann Auth-Account löschen, dann zum Abschluss-Screen navigieren.
  Future<void> _wipeDataAndDeleteAuth() async {
    // Referenzen cachen
    final profileRepo = ref.read(profileRepositoryProvider);

    // Firestore- und Storage-Daten löschen
    await profileRepo.deleteAllUserData();

    // Flag setzen damit MyApp nicht auf authStateChanges reagiert
    ref.read(accountDeletionInProgressProvider.notifier).state = true;

    // Auth-Account löschen
    await FirebaseAuth.instance.currentUser?.delete();

    // Zum Übergangs-Screen navigieren und ALLES aus dem Stack werfen
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AccountDeletedScreen()),
        (route) => false,
      );
    }
  }

  String _mapDeleteAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'Falsches Passwort. Bitte versuche es erneut.';
      case 'too-many-requests':
        return 'Zu viele Versuche. Bitte warte kurz und versuche es erneut.';
      case 'requires-recent-login':
        return 'Bitte melde dich erneut an und versuche es dann noch einmal.';
      case 'user-mismatch':
        return 'Die Anmeldung gehört nicht zu diesem Konto.';
      case 'web-context-canceled':
      case 'canceled':
        return 'Anmeldung abgebrochen.';
      default:
        return 'Fehler: ${e.message}';
    }
  }

  void _handleDeleteError(String message) {
    if (!mounted) return;
    setState(() => _isDeletingAccount = false);
    ref.read(accountDeletionInProgressProvider.notifier).state = false;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
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
          onPressed: _understood ? () => Navigator.pop(context, true) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.red.withValues(alpha: 0.3),
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

// =============================================================================
// ABO-KACHEL
// =============================================================================

class _SubscriptionTile extends ConsumerWidget {
  static const _purple = Colors.deepPurple;

  // Google Play Abo-Verwaltung — öffnet die offizielle Google Play Seite

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(subscriptionStatusProvider);

    return statusAsync.when(
      loading: () => const ListTile(
        leading: Icon(Icons.star_outline, color: Colors.deepPurple),
        title: Text('Abo wird geladen...'),
      ),
      error: (_, _) => const ListTile(
        leading: Icon(Icons.star_outline, color: Colors.deepPurple),
        title: Text('Abo'),
        subtitle: Text('Fehler beim Laden'),
      ),
      data: (status) {
        final plan = status.plan;
        final isTrial = status.isTrial;

        // Ablaufdatum formatieren
        String? expiryText;
        if (status.expiresAt != null) {
          final d = status.expiresAt!;
          expiryText = 'Verlängert am ${d.day}.${d.month}.${d.year}';
        }
        if (isTrial && status.trialEndsAt != null) {
          final d = status.trialEndsAt!;
          expiryText = 'Test endet am ${d.day}.${d.month}.${d.year}';
        }

        return Column(
          children: [
            // ── Aktueller Plan ─────────────────────────────────────────
            ListTile(
              leading: Icon(
                status.hasAccess ? Icons.star_rounded : Icons.star_outline,
                color: status.hasAccess ? Colors.amber : Colors.grey,
              ),
              title: Text(
                isTrial
                    ? '14-Tage Test aktiv'
                    : plan == SubscriptionPlan.none
                    ? 'Kein aktives Abo'
                    : '${plan.displayName}-Plan',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                expiryText ?? plan.priceLabel,
                style: const TextStyle(fontSize: 12),
              ),
              trailing: status.hasAccess && plan != SubscriptionPlan.none
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Text(
                        isTrial ? 'Test' : 'Aktiv',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : null,
            ),

            // ── Buttons ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  // Plan wechseln / Abo abschließen
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: Text(
                        status.hasAccess ? 'Plan wechseln' : 'Abo abschließen',
                        style: const TextStyle(fontSize: 13),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _purple,
                        side: const BorderSide(color: Colors.deepPurple),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PaywallScreen(canDismiss: true),
                        ),
                      ),
                    ),
                  ),

                  if (status.hasAccess && plan != SubscriptionPlan.none) ...[
                    const SizedBox(width: 10),
                    // Abo bei Google Play verwalten (kündigen etc.)
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text(
                          'Verwalten',
                          style: TextStyle(fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey.shade700,
                          side: BorderSide(color: Colors.grey.shade400),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: () => _openGooglePlaySubscriptions(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openGooglePlaySubscriptions(BuildContext context) async {
    // Öffnet Google Play → Meine Abos direkt für diese App
    final uri = Uri.parse(
      'https://play.google.com/store/account/subscriptions'
      '?package=de.nilsdigital.lerndex',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google Play konnte nicht geöffnet werden.'),
          ),
        );
      }
    }
  }
}
