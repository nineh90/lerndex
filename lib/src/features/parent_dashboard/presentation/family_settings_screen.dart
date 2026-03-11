import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../tutorial_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Einstellungen im Family-Dashboard (für alle sichtbar – auch Kinder).
/// Enthält nur unkritische Optionen: App-Tour & Rechtliches.
/// Passwort, PIN und Konto-Löschung sind im Eltern-Dashboard (hinter PIN-Sperre).
class FamilySettingsScreen extends ConsumerWidget {
  const FamilySettingsScreen({super.key});

  Future<void> _launchUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Konnte $url nicht öffnen')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstellungen'),
        backgroundColor: const Color(0xFF6B21A8),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        children: [
          // ── Abschnitt: Hilfe ─────────────────────────────────────────
          const _SectionHeader(title: 'Hilfe'),

          ListTile(
            leading: const Icon(Icons.tour_outlined, color: Color(0xFF6B21A8)),
            title: const Text('App-Tour wiederholen'),
            subtitle: const Text(
              'Interaktives Tutorial durch die wichtigsten Funktionen',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              // Tutorial zurücksetzen und direkt starten
              await ref.read(tutorialProvider.notifier).resetAndStart();
              if (context.mounted) {
                // Einstellungen schließen → zurück zum FamilyDashboard wo das Tutorial läuft
                Navigator.of(context).pop();
              }
            },
          ),

          const Divider(indent: 16, endIndent: 16),

          // ── Abschnitt: Rechtliches ───────────────────────────────────
          const _SectionHeader(title: 'Rechtliches'),

          ListTile(
            leading: const Icon(
              Icons.privacy_tip_outlined,
              color: Color(0xFF6B21A8),
            ),
            title: const Text('Datenschutz'),
            subtitle: const Text(
              'Datenschutzerklärung von Lerndex',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(
              Icons.open_in_new,
              size: 18,
              color: Colors.grey,
            ),
            onTap: () =>
                _launchUrl(context, 'https://lerndex.de/datenschutz.php'),
          ),

          ListTile(
            leading: const Icon(Icons.gavel_outlined, color: Color(0xFF6B21A8)),
            title: const Text('Nutzungsbedingungen'),
            subtitle: const Text(
              'AGB von Lerndex',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(
              Icons.open_in_new,
              size: 18,
              color: Colors.grey,
            ),
            onTap: () => _launchUrl(context, 'https://lerndex.de/agb.php'),
          ),

          ListTile(
            leading: const Icon(Icons.info_outline, color: Color(0xFF6B21A8)),
            title: const Text('Impressum'),
            subtitle: const Text(
              'Angaben gemäß § 5 TMG',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(
              Icons.open_in_new,
              size: 18,
              color: Colors.grey,
            ),
            onTap: () =>
                _launchUrl(context, 'https://lerndex.de/impressum.php'),
          ),
        ],
      ),
    );
  }
}

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
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.grey[500],
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
