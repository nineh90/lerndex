import 'package:qr/qr.dart';

import '../domain/school_models.dart';

// ============================================================================
// DRUCKBARE SCHÜLERKARTEN
//
// Eine schlichte HTML-Seite (beim Drucken A4, 8 Karten pro Seite) mit den QR-Codes als
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

/// Komplette Druckseite für die Karten einer Klasse. Am Bildschirm mit
/// Kopfzeile, Erklärung und Drucken-Knopf (auch auf dem Handy lesbar), beim
/// Drucken nur die Karten (A4, zwei Spalten).
String studentCardsHtml(List<StudentCard> cards, {required String schoolName}) {
  final className = cards.isEmpty ? '' : cards.first.className;
  final items = cards
      .map(
        (c) =>
            '''
<div class="card">
  <div class="text">
    <div class="school">${_escape(schoolName)}</div>
    <div class="name">${_escape(c.name)}</div>
    <div class="class">Klasse ${_escape(c.className)}</div>
    <div class="hint">QR-Code mit der Kamera scannen, dann bist du in Lerndex angemeldet.</div>
  </div>
  <div class="qr">${qrSvg(c.link.toString())}</div>
</div>''',
      )
      .join('\n');

  return '''<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lerndex – Anmeldekarten ${_escape(className)}</title>
<style>
  * { box-sizing: border-box; }
  body { margin: 0; font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
         color: #222; background: #F5F3FF; }
  header { background: #6B21A8; color: #fff; padding: 20px 24px; }
  header .inner, main { max-width: 860px; margin: 0 auto; }
  header h1 { margin: 0; font-size: 22px; }
  header p { margin: 4px 0 0; opacity: .85; font-size: 15px; }
  .info { background: #fff; border-radius: 14px; padding: 16px 20px; margin: 20px 0;
          display: flex; gap: 16px; align-items: center; justify-content: space-between;
          flex-wrap: wrap; box-shadow: 0 1px 4px rgba(0,0,0,.06); }
  .info p { margin: 0; flex: 1 1 320px; font-size: 14px; line-height: 1.5; color: #444; }
  .info button { background: #6B21A8; color: #fff; border: 0; border-radius: 10px;
                 padding: 12px 22px; font-size: 16px; font-weight: 600; cursor: pointer; }
  main { padding: 0 16px 32px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(340px, 1fr)); gap: 16px; }
  .card { display: flex; align-items: center; justify-content: space-between; gap: 16px;
          background: #fff; padding: 18px; border: 2px dashed #C4B5FD; border-radius: 14px;
          break-inside: avoid; }
  .school { font-size: 12px; color: #6B21A8; font-weight: 600; }
  .name { font-size: 22px; font-weight: 700; margin: 6px 0 2px; }
  .class { font-size: 14px; }
  .hint { font-size: 12px; color: #666; margin-top: 10px; }
  .qr svg { width: 150px; height: 150px; display: block; }
  @media (max-width: 420px) {
    .grid { grid-template-columns: 1fr; }
    .card { flex-direction: column-reverse; text-align: center; }
    .qr svg { width: 220px; height: 220px; }
  }
  @media print {
    @page { size: A4; margin: 12mm; }
    body { background: #fff; }
    header, .info { display: none; }
    main { max-width: none; padding: 0; }
    .grid { grid-template-columns: 1fr 1fr; gap: 6mm; }
    .card { flex-direction: row; text-align: left; height: 58mm; padding: 5mm;
            border: 0.4mm dashed #999; border-radius: 3mm; }
    .school { font-size: 8pt; }
    .name { font-size: 16pt; margin: 2mm 0 1mm; }
    .class { font-size: 10pt; }
    .hint { font-size: 7.5pt; margin-top: 3mm; }
    .qr svg { width: 34mm; height: 34mm; }
  }
</style>
</head>
<body>
<header><div class="inner">
  <h1>Anmeldekarten${className.isEmpty ? '' : ' · Klasse ${_escape(className)}'}</h1>
  <p>${_escape(schoolName)} · ${cards.length} ${cards.length == 1 ? 'Karte' : 'Karten'}</p>
</div></header>
<main>
  <div class="info">
    <p>Ausdrucken, ausschneiden, austeilen. Jede Karte meldet genau dieses Kind an, auf dem
    Schul-Tablet oder dem eigenen Handy. Geht eine Karte verloren, in Lerndex beim Kind
    „Anmelde-Code (QR)“ wählen. Die alte Karte gilt dann nicht mehr.</p>
    <button onclick="window.print()">Drucken</button>
  </div>
  <div class="grid">
$items
  </div>
</main>
</body>
</html>''';
}
