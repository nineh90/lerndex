import 'package:qr/qr.dart';

import '../domain/school_models.dart';

// ============================================================================
// DRUCKBARE SCHÜLERKARTEN
//
// Eine schlichte HTML-Seite (A4, 8 Karten pro Seite) mit den QR-Codes als
// SVG. Die druckt der Browser sauber – die Flutter-Oberfläche selbst ist im
// Browser eine Grafikfläche und lässt sich nicht vernünftig drucken.
// ============================================================================

/// QR-Code als SVG (Fehlerkorrektur M, mit Ruhezone).
String qrSvg(String data) {
  final image = QrImage(
    QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M),
  );
  final n = image.moduleCount;
  const quiet = 2;
  final size = n + 2 * quiet;
  final path = StringBuffer();
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      if (image.isDark(y, x)) {
        path.write('M${x + quiet} ${y + quiet}h1v1h-1z');
      }
    }
  }
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $size $size" '
      'shape-rendering="crispEdges"><rect width="$size" height="$size" '
      'fill="#fff"/><path d="$path" fill="#000"/></svg>';
}

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Komplette Druckseite für die Karten einer Klasse.
String studentCardsHtml(List<StudentCard> cards, {required String schoolName}) {
  final items = cards
      .map(
        (c) =>
            '''
<div class="card">
  <div class="text">
    <div class="school">${_escape(schoolName)}</div>
    <div class="name">${_escape(c.name)}</div>
    <div class="class">Klasse ${_escape(c.className)}</div>
    <div class="hint">Mit der Kamera des Tablets scannen – dann bist du angemeldet.</div>
  </div>
  <div class="qr">${qrSvg(c.link.toString())}</div>
</div>''',
      )
      .join('\n');

  return '''<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<title>Lerndex – Karten ${cards.isEmpty ? '' : _escape(cards.first.className)}</title>
<style>
  @page { size: A4; margin: 12mm; }
  body { margin: 0; font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; color: #222; }
  .note { margin: 0 0 6mm; font-size: 11pt; }
  .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 6mm; }
  .card { display: flex; align-items: center; justify-content: space-between; gap: 4mm;
          height: 58mm; padding: 5mm; border: 0.4mm dashed #999; border-radius: 3mm;
          box-sizing: border-box; break-inside: avoid; }
  .school { font-size: 8pt; color: #6B21A8; font-weight: 600; }
  .name { font-size: 16pt; font-weight: 700; margin: 2mm 0 1mm; }
  .class { font-size: 10pt; }
  .hint { font-size: 7.5pt; color: #666; margin-top: 3mm; }
  .qr svg { width: 34mm; height: 34mm; display: block; }
  @media print { .note { display: none; } }
</style>
</head>
<body>
<p class="note">Karten ausschneiden. Jede Karte meldet genau dieses Kind an. Geht eine Karte
verloren, in Lerndex für das Kind „Neue Karte“ wählen – die alte gilt dann nicht mehr.</p>
<div class="grid">
$items
</div>
<script>window.onload = () => window.print();</script>
</body>
</html>''';
}
