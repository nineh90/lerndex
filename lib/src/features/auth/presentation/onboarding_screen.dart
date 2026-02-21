import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/auth_repository.dart';
import '../../parent_dashboard/data/pin_repository.dart';
import '../../parent_dashboard/presentation/pin_input_dialog.dart';
import '../../parent_dashboard/presentation/parent_dashboard_screen.dart';

/// Onboarding-Screen — gilt für ALLE neuen Nutzer (E-Mail + Google)
///
/// Schritt 1: Name bestätigen / anpassen
/// Schritt 2: Eltern-PIN erstellen
/// Schritt 3: Fertig!
///
/// Setzt am Ende onboardingCompleted = true in Firestore
/// Navigation ins Dashboard übernimmt danach main.dart via authStateChanges
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  // Step 1 — Name
  final _nameController = TextEditingController();
  final _nameFormKey = GlobalKey<FormState>();

  // Step 2 — PIN
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  final _pinFormKey = GlobalKey<FormState>();
  String? _pinError;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Name vorausfüllen falls vorhanden (z.B. von Google)
    final user = FirebaseAuth.instance.currentUser;
    if (user?.displayName != null && user!.displayName!.isNotEmpty) {
      _nameController.text = user.displayName!;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep == 0) {
      if (!_nameFormKey.currentState!.validate()) return;
    }
    setState(() => _currentStep++);
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _finishOnboarding() async {
    if (!_pinFormKey.currentState!.validate()) return;

    final pin = _pinController.text;
    final confirm = _confirmPinController.text;

    if (pin != confirm) {
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

      // 1. PIN speichern
      await ref.read(pinRepositoryProvider).setPin(user.uid, pin);

      // 2. Name + onboardingCompleted setzen
      await ref.read(authRepositoryProvider).completeOnboarding(
        displayName: _nameController.text.trim(),
      );

      if (!mounted) return;

      // Zur Fertig-Seite
      setState(() => _currentStep = 2);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
              // Progress Indicator
              Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  children: List.generate(3, (i) {
                    return Expanded(
                      child: Container(
                        margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                        height: 4,
                        decoration: BoxDecoration(
                          color: i <= _currentStep
                              ? Colors.white
                              : Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),
              ),

              // Inhalt
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildNameStep(),
                    _buildPinStep(),
                    _buildDoneStep(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // DASHBOARD ÖFFNEN MIT PIN-ABFRAGE
  // =========================================================================

  Future<void> _openDashboard() async {
    if (!mounted) return;

    // PIN-Abfrage direkt starten — PIN wurde gerade im Onboarding gesetzt
    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PinInputDialog(),
    );

    if (verified == true && mounted) {
      // Stack komplett leeren und zum Eltern-Dashboard navigieren
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ParentDashboardScreen()),
            (route) => false,
      );
    }
  }

  // =========================================================================
  // SCHRITT 1: NAME
  // =========================================================================

  Widget _buildNameStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 20),
          const Icon(Icons.waving_hand, size: 64, color: Colors.white),
          const SizedBox(height: 20),
          const Text(
            'Wie heißt du?',
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white),
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
                borderRadius: BorderRadius.circular(20)),
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _nameFormKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Dein vollständiger Name',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _nextStep(),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Bitte gib deinen Namen ein';
                        }
                        if (v.trim().length < 2) {
                          return 'Name zu kurz';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _nextStep,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6B21A8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Weiter',
                                style: TextStyle(
                                    fontSize: 16, color: Colors.white)),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward,
                                color: Colors.white, size: 18),
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

  // =========================================================================
  // SCHRITT 2: PIN
  // =========================================================================

  Widget _buildPinStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 20),
          const Icon(Icons.lock_outline, size: 64, color: Colors.white),
          const SizedBox(height: 20),
          const Text(
            'Eltern-PIN erstellen',
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white),
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
                borderRadius: BorderRadius.circular(20)),
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _pinFormKey,
                child: Column(
                  children: [
                    // Hinweis-Box
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6B21A8).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xFF6B21A8).withOpacity(0.2)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Color(0xFF6B21A8), size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Merke dir diesen PIN gut! Du brauchst ihn um Fortschritte, Chats und Einstellungen deiner Kinder einzusehen.',
                              style: TextStyle(
                                  fontSize: 13, color: Color(0xFF6B21A8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // PIN eingeben
                    TextFormField(
                      controller: _pinController,
                      decoration: InputDecoration(
                        labelText: 'PIN (4-6 Ziffern)',
                        prefixIcon: const Icon(Icons.pin_outlined),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        errorText: _pinError,
                      ),
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 6,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        if (v == null || v.length < 4) {
                          return 'PIN muss 4-6 Ziffern haben';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // PIN bestätigen
                    TextFormField(
                      controller: _confirmPinController,
                      decoration: InputDecoration(
                        labelText: 'PIN bestätigen',
                        prefixIcon: const Icon(Icons.check_circle_outline),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 6,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _finishOnboarding(),
                      validator: (v) {
                        if (v != _pinController.text) {
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
                        onPressed: _isLoading ? null : _finishOnboarding,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6B21A8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                            : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('PIN speichern & weiter',
                                style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white)),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward,
                                color: Colors.white, size: 18),
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

  // =========================================================================
  // SCHRITT 3: FERTIG
  // =========================================================================

  Widget _buildDoneStep() {
    final firstName = _nameController.text.trim().split(' ').first;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Erfolgs-Animation
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.celebration, size: 64, color: Colors.white),
          ),
          const SizedBox(height: 32),

          Text(
            'Herzlich willkommen,\n$firstName! 🎉',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white),
          ),
          const SizedBox(height: 16),
          const Text(
            'Dein Lerndex-Konto ist bereit.\nDu kannst jetzt deine Kinder anlegen und ihr Lernabenteuer beginnen!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.white70),
          ),
          const SizedBox(height: 48),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () => _openDashboard(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text(
                'Los geht\'s! 🚀',
                style: TextStyle(
                    fontSize: 18,
                    color: Color(0xFF6B21A8),
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}