import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'family_dashboard_screen.dart';
import '../data/auth_repository.dart';
import '../../parent_dashboard/data/pin_repository.dart';
import '../../../tutorial_provider.dart';

// ============================================================================
// SETUP DIALOG
//
// Ersetzt den alten OnboardingScreen.
// Wird einmalig nach der Registrierung / E-Mail-Verifikation angezeigt.
//
// Schritt 1 – Name bestätigen (vorausgefüllt wenn Google-Login)
// Schritt 2 – Eltern-PIN erstellen
//
// Danach: direkt FamilyDashboardScreen + Tutorial starten.
// ============================================================================

class SetupDialog extends ConsumerStatefulWidget {
  const SetupDialog({super.key});

  @override
  ConsumerState<SetupDialog> createState() => _SetupDialogState();
}

class _SetupDialogState extends ConsumerState<SetupDialog> {
  final _pageCtrl = PageController();
  int _page = 0;

  // Name
  final _nameCtrl = TextEditingController();
  final _nameKey = GlobalKey<FormState>();

  // PIN
  final _pinCtrl = TextEditingController();
  final _pinConfirmCtrl = TextEditingController();
  final _pinKey = GlobalKey<FormState>();
  String? _pinError;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user?.displayName?.isNotEmpty == true) {
      _nameCtrl.text = user!.displayName!;
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _nameCtrl.dispose();
    _pinCtrl.dispose();
    _pinConfirmCtrl.dispose();
    super.dispose();
  }

  void _toPage(int p) {
    setState(() => _page = p);
    _pageCtrl.animateToPage(
      p,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _finish() async {
    if (!_pinKey.currentState!.validate()) return;
    if (_pinCtrl.text != _pinConfirmCtrl.text) {
      setState(() => _pinError = 'PINs stimmen nicht überein');
      return;
    }

    setState(() {
      _isLoading = true;
      _pinError = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Nicht eingeloggt');

      await ref.read(pinRepositoryProvider).setPin(user.uid, _pinCtrl.text);
      await ref
          .read(authRepositoryProvider)
          .completeOnboarding(displayName: _nameCtrl.text.trim());

      if (!mounted) return;

      // forceStart() ist synchron → State ist gesetzt BEVOR Navigator pusht
      ref.read(tutorialProvider.notifier).forceStart();

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const FamilyDashboardScreen()),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6B21A8), Color(0xFF7E22CE)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Progress-Balken
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: Row(
                  children: List.generate(2, (i) {
                    return Expanded(
                      child: Container(
                        margin: EdgeInsets.only(right: i == 0 ? 8 : 0),
                        height: 4,
                        decoration: BoxDecoration(
                          color: i <= _page
                              ? Colors.white
                              : Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),
              ),

              Expanded(
                child: PageView(
                  controller: _pageCtrl,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [_buildNamePage(), _buildPinPage()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Seite 1: Name ─────────────────────────────────────────────────────────

  Widget _buildNamePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          const Icon(Icons.waving_hand, size: 60, color: Colors.white),
          const SizedBox(height: 20),
          const Text(
            'Wie heißt du?',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Mit diesem Namen begrüßen wir dich in der App.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.white70),
          ),
          const SizedBox(height: 32),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _nameKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Dein vollständiger Name',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _nextNameStep(),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Bitte gib deinen Namen ein';
                        }
                        if (v.trim().length < 2) return 'Name zu kurz';
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _nextNameStep,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6B21A8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Weiter',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward,
                              color: Colors.white,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _nextNameStep() {
    if (_nameKey.currentState!.validate()) _toPage(1);
  }

  // ── Seite 2: PIN ──────────────────────────────────────────────────────────

  Widget _buildPinPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          const Icon(Icons.lock_outline, size: 60, color: Colors.white),
          const SizedBox(height: 20),
          const Text(
            'Eltern-PIN erstellen',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Dieser PIN schützt das Eltern-Dashboard.\nDeine Kinder können es damit nicht öffnen.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.white70),
          ),
          const SizedBox(height: 32),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _pinKey,
                child: Column(
                  children: [
                    // Hinweis
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6B21A8).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF6B21A8).withOpacity(0.2),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Color(0xFF6B21A8),
                            size: 20,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Merke dir diesen PIN! Du brauchst ihn um Fortschritte und Einstellungen deiner Kinder einzusehen.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF6B21A8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    TextFormField(
                      controller: _pinCtrl,
                      decoration: InputDecoration(
                        labelText: 'PIN (4–6 Ziffern)',
                        prefixIcon: const Icon(Icons.pin_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        errorText: _pinError,
                      ),
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        if (v == null || v.length < 4) {
                          return 'PIN muss 4–6 Ziffern haben';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _pinConfirmCtrl,
                      decoration: InputDecoration(
                        labelText: 'PIN bestätigen',
                        prefixIcon: const Icon(Icons.check_circle_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _finish(),
                      validator: (v) {
                        if (v != _pinCtrl.text) {
                          return 'PINs stimmen nicht überein';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _finish,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6B21A8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Fertig & App starten',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Icon(
                                    Icons.rocket_launch,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
