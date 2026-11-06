import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'widgets/parental_gate.dart';

/// Rechtstexte auf lerndex.de (Impressum nach § 5 DDG, Datenschutz nach
/// Art. 13 DSGVO, AGB). Eine Stelle für alle Links in der App.
abstract final class LegalLinks {
  static const privacy = 'https://lerndex.de/datenschutz.php';
  static const terms = 'https://lerndex.de/agb.php';
  static const imprint = 'https://lerndex.de/impressum.php';
}

/// Öffnet einen Rechtstext im Browser (in der App außerhalb, damit keine
/// Anmeldung im eingebetteten Fenster hängen bleibt).
Future<void> openLegalLink(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// Dezente Fußzeile mit Impressum und Datenschutz für Seiten, die man ohne
/// Anmeldung oder ohne Elternbereich sieht (Anmeldung, Schulbereich,
/// Kindergerät). [color]: Textfarbe, auf dunklem Hintergrund hell wählen.
class LegalFooter extends StatelessWidget {
  const LegalFooter({super.key, this.color, this.adultGate = false});

  final Color? color;

  /// Auf Seiten für Kinder: vor dem Verlassen der App eine Rechenaufgabe für
  /// Erwachsene (wie in den Infos, Apple Kids 1.3).
  final bool adultGate;

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? Colors.grey[700]!;
    Widget link(String label, String url) => TextButton(
      onPressed: () async {
        if (adultGate && await showAdultGateDialog(context) != true) return;
        await openLegalLink(url);
      },
      style: TextButton.styleFrom(
        foregroundColor: textColor,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          decoration: TextDecoration.underline,
        ),
      ),
    );

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        link('Impressum', LegalLinks.imprint),
        Text('·', style: TextStyle(color: textColor)),
        link('Datenschutz', LegalLinks.privacy),
      ],
    );
  }
}
