import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex/src/features/subscription/data/subscription_model.dart';
import 'package:lerndex/src/features/subscription/data/subscription_provider.dart';
import 'package:purchases_flutter/models/offering_wrapper.dart';
import 'package:purchases_flutter/models/package_wrapper.dart';

/// Paywall-Screen — wird angezeigt wenn der User kein aktives Abo hat
/// oder ein bestehendes Abo ändern möchte.
class PaywallScreen extends ConsumerStatefulWidget {
  /// Wenn true, zeigt einen "Schließen"-Button (z.B. aus den Einstellungen)
  final bool canDismiss;

  const PaywallScreen({super.key, this.canDismiss = false});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  SubscriptionPlan? _selectedPlan; // null bis Status geladen
  bool _isLoading = false;

  static const _purple = Color(0xFF6B21A8);
  static const _lightPurple = Color(0xFFF3E8FF);

  @override
  Widget build(BuildContext context) {
    final offeringsAsync = ref.watch(offeringsProvider);
    final statusAsync = ref.watch(subscriptionStatusProvider);

    // Aktiven Plan bestimmen
    final activePlan = statusAsync.whenOrNull(
      data: (s) => s.isActive ? s.plan : null,
    );
    final hasActivePlan =
        activePlan != null && activePlan != SubscriptionPlan.none;

    // Vorauswahl: aktiver Plan wenn vorhanden, sonst Duo
    if (_selectedPlan == null) {
      _selectedPlan = hasActivePlan ? activePlan! : SubscriptionPlan.duo;
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(hasActivePlan ? 'Abo verwalten' : 'Abo wählen'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        actions: [
          if (widget.canDismiss)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: offeringsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _buildError(e.toString()),
          data: (offerings) {
            if (offerings == null || offerings.current == null) {
              return _buildError(
                'Produkte konnten nicht geladen werden.\nBitte prüfe deine Internetverbindung.',
              );
            }
            return _buildContent(offerings.current!, activePlan);
          },
        ),
      ),
    );
  }

  Widget _buildContent(Offering offering, SubscriptionPlan? activePlan) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final hasActivePlan =
        activePlan != null && activePlan != SubscriptionPlan.none;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 0, 24, bottomPadding + 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          const SizedBox(height: 16),
          Text(
            hasActivePlan ? 'Dein Abo' : 'Lerndex Premium',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasActivePlan
                ? 'Hier kannst du deinen Plan jederzeit wechseln.'
                : '14 Tage kostenlos testen —\ndanach monatlich kündbar.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: Colors.black54),
          ),

          // ── Aktives Abo Badge ────────────────────────────────────────────
          if (hasActivePlan) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle,
                    color: Colors.green.shade600,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Aktiver Plan: ${activePlan!.displayName}  •  ${activePlan.priceLabel}',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // ── Plan-Karten ──────────────────────────────────────────────────
          _PlanCard(
            plan: SubscriptionPlan.solo,
            isSelected: _selectedPlan == SubscriptionPlan.solo,
            isActive: activePlan == SubscriptionPlan.solo,
            offering: offering,
            onTap: () => setState(() => _selectedPlan = SubscriptionPlan.solo),
          ),
          const SizedBox(height: 12),
          _PlanCard(
            plan: SubscriptionPlan.duo,
            isSelected: _selectedPlan == SubscriptionPlan.duo,
            isActive: activePlan == SubscriptionPlan.duo,
            offering: offering,
            badge: activePlan == null || activePlan == SubscriptionPlan.none
                ? 'Beliebt'
                : null,
            onTap: () => setState(() => _selectedPlan = SubscriptionPlan.duo),
          ),
          const SizedBox(height: 12),
          _PlanCard(
            plan: SubscriptionPlan.family,
            isSelected: _selectedPlan == SubscriptionPlan.family,
            isActive: activePlan == SubscriptionPlan.family,
            offering: offering,
            onTap: () =>
                setState(() => _selectedPlan = SubscriptionPlan.family),
          ),

          const SizedBox(height: 24),

          // ── Feature-Liste ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _lightPurple,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              children: [
                _FeatureRow(
                  icon: Icons.quiz_outlined,
                  text: 'Unbegrenzte Quiz-Fragen',
                ),
                _FeatureRow(
                  icon: Icons.smart_toy_outlined,
                  text: 'KI-Tutor ohne Limit',
                ),
                _FeatureRow(
                  icon: Icons.emoji_events_outlined,
                  text: 'Alle Belohnungen & Avatare',
                ),
                _FeatureRow(
                  icon: Icons.bar_chart_outlined,
                  text: 'Detaillierte Lernstatistiken',
                ),
                _FeatureRow(
                  icon: Icons.family_restroom,
                  text: 'Eltern-Dashboard',
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Kauf-Button ──────────────────────────────────────────────────
          _buildPurchaseButton(offering, activePlan),

          const SizedBox(height: 12),

          // ── Restore ─────────────────────────────────────────────────────
          if (!hasActivePlan)
            TextButton(
              onPressed: _isLoading ? null : _restorePurchases,
              child: const Text(
                'Käufe wiederherstellen',
                style: TextStyle(color: Colors.black45, fontSize: 13),
              ),
            ),

          const SizedBox(height: 8),
          const Text(
            'Zahlung über Google Play. Automatische Verlängerung. Jederzeit kündbar.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.black38),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchaseButton(Offering offering, SubscriptionPlan? activePlan) {
    final package = _findPackage(offering, _selectedPlan!);
    final isCurrentPlan = _selectedPlan == activePlan;
    final hasActivePlan =
        activePlan != null && activePlan != SubscriptionPlan.none;

    String buttonLabel;
    if (_isLoading) {
      buttonLabel = '';
    } else if (isCurrentPlan) {
      buttonLabel = '✓ Aktueller Plan';
    } else if (hasActivePlan) {
      buttonLabel =
          'Zu ${_selectedPlan!.displayName} wechseln – ${_selectedPlan!.priceLabel}';
    } else {
      buttonLabel = '14 Tage kostenlos starten – ${_selectedPlan!.priceLabel}';
    }

    return ElevatedButton(
      onPressed: (_isLoading || package == null || isCurrentPlan)
          ? null
          : () => _purchase(package, hasActivePlan),
      style: ElevatedButton.styleFrom(
        backgroundColor: isCurrentPlan ? Colors.grey.shade300 : _purple,
        foregroundColor: isCurrentPlan ? Colors.grey.shade600 : Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: isCurrentPlan ? 0 : 2,
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
          : Text(
              buttonLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.invalidate(offeringsProvider),
              child: const Text('Erneut versuchen'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Package? _findPackage(Offering offering, SubscriptionPlan plan) {
    final packageId = plan.revenueCatPackageId;
    if (packageId == null) return null;

    try {
      return offering.availablePackages.firstWhere(
        (p) => p.identifier == packageId,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _purchase(Package package, bool isUpgrade) async {
    setState(() => _isLoading = true);
    try {
      await ref.read(subscriptionStatusProvider.notifier).purchase(package);
      if (mounted) {
        final msg = isUpgrade
            ? '✅ Plan erfolgreich gewechselt!'
            : '🎉 Willkommen bei Lerndex Premium!';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: const Color(0xFF6B21A8),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _restorePurchases() async {
    setState(() => _isLoading = true);
    try {
      final status = await ref
          .read(subscriptionStatusProvider.notifier)
          .restore();
      if (mounted) {
        final msg = status.hasAccess
            ? '✅ Abo erfolgreich wiederhergestellt!'
            : 'Kein aktives Abo gefunden.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        if (status.hasAccess) Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

// =============================================================================
// PLAN-KARTE
// =============================================================================

class _PlanCard extends StatelessWidget {
  final SubscriptionPlan plan;
  final bool isSelected;
  final bool isActive;
  final Offering offering;
  final String? badge;
  final VoidCallback onTap;

  const _PlanCard({
    required this.plan,
    required this.isSelected,
    required this.isActive,
    required this.offering,
    required this.onTap,
    this.badge,
  });

  static const _purple = Color(0xFF6B21A8);

  @override
  Widget build(BuildContext context) {
    final priceString = plan.priceLabel;

    // Aktiver Plan bekommt grünen Rand, ausgewählter lila
    final borderColor = isActive
        ? Colors.green.shade400
        : isSelected
        ? _purple
        : Colors.grey.shade300;
    final borderWidth = (isActive || isSelected) ? 2.0 : 1.0;
    final bgColor = isActive
        ? Colors.green.shade50
        : isSelected
        ? const Color(0xFFF3E8FF)
        : Colors.white;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: isSelected
              ? [BoxShadow(color: _purple.withOpacity(0.15), blurRadius: 8)]
              : isActive
              ? [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.15),
                    blurRadius: 8,
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            // Auswahl-Indikator
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isActive
                      ? Colors.green.shade400
                      : isSelected
                      ? _purple
                      : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: isActive
                  ? Icon(Icons.circle, size: 12, color: Colors.green.shade500)
                  : isSelected
                  ? const Icon(Icons.circle, size: 12, color: _purple)
                  : null,
            ),
            const SizedBox(width: 12),

            // Plan-Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        plan.displayName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isActive
                              ? Colors.green.shade700
                              : isSelected
                              ? _purple
                              : Colors.black87,
                        ),
                      ),
                      if (isActive) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade500,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Aktiv',
                            style: TextStyle(color: Colors.white, fontSize: 11),
                          ),
                        ),
                      ] else if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _purple,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'bis zu ${plan.childLimit} ${plan.childLimit == 1 ? "Kind" : "Kinder"}',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),

            // Preis
            Text(
              priceString,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: isActive
                    ? Colors.green.shade700
                    : isSelected
                    ? _purple
                    : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// FEATURE-ZEILE
// =============================================================================

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF6B21A8)),
          const SizedBox(width: 10),
          Text(text, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}
