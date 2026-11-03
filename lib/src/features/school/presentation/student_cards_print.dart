import 'package:qr/qr.dart';

import '../data/parent_link_repository.dart';
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

/// Druckseite für die QR-Karte einer Lehrkraft: Karte zum Ausschneiden und
/// darunter die Anleitung (PIN beim ersten Scannen).
String teacherCardHtml(TeacherCard card) => '''<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lerndex – Lehrer-Karte ${_escape(card.name)}</title>
<style>
  * { box-sizing: border-box; }
  body { margin: 0; font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
         color: #222; background: #F5F3FF; }
  main { max-width: 520px; margin: 0 auto; padding: 24px 16px; }
  .card { display: flex; align-items: center; justify-content: space-between; gap: 16px;
          background: #fff; padding: 20px; border: 2px dashed #C4B5FD; border-radius: 14px; }
  .school { font-size: 12px; color: #6B21A8; font-weight: 600; }
  .title { font-size: 12px; text-transform: uppercase; letter-spacing: .08em; color: #666; margin-top: 8px; }
  .name { font-size: 22px; font-weight: 700; margin: 2px 0; }
  .qr svg { width: 150px; height: 150px; display: block; }
  .steps { background: #fff; border-radius: 14px; padding: 16px 20px; margin-top: 16px;
           font-size: 14px; line-height: 1.5; }
  .steps ol { margin: 8px 0 0; padding-left: 20px; }
  button { margin-top: 16px; width: 100%; background: #6B21A8; color: #fff; border: 0;
           border-radius: 10px; padding: 12px; font-size: 16px; font-weight: 600; cursor: pointer; }
  @media print {
    @page { size: A4; margin: 15mm; }
    body { background: #fff; }
    main { padding: 0; max-width: 120mm; }
    .card { padding: 5mm; border: 0.4mm dashed #999; border-radius: 3mm; }
    .qr svg { width: 34mm; height: 34mm; }
    .steps { padding: 4mm 0; font-size: 10pt; }
    button { display: none; }
  }
</style>
</head>
<body>
<main>
  <div class="card">
    <div>
      <div class="school">${_escape(card.schoolName)}</div>
      <div class="title">Lehrer-Karte</div>
      <div class="name">${_escape(card.name)}</div>
    </div>
    <div class="qr">${qrSvg(card.link.toString())}</div>
  </div>
  <div class="steps">
    <strong>So melden Sie sich bei Lerndex an</strong>
    <ol>
      <li>QR-Code mit der Kamera des Handys, Tablets oder Laptops scannen.</li>
      <li>Beim ersten Mal eine eigene PIN festlegen (4 bis 6 Ziffern).</li>
      <li>Danach immer: Karte scannen und PIN eingeben.</li>
    </ol>
    <p>Die Karte bitte nicht weitergeben. Verloren oder PIN vergessen? Die Schulleitung stellt eine neue Karte aus, die alte gilt dann nicht mehr.</p>
  </div>
  <button onclick="window.print()">Drucken</button>
</main>
</body>
</html>''';

/// Elternbriefe: eine A4-Seite pro Kind mit zwei QR-Codes – „Eltern
/// verbinden“ (Elternkonto, Statistik, Belohnungen) und „Zu Hause lernen“
/// (Anmeldung des Kindes auf dem eigenen Gerät).
String parentLettersHtml(List<ParentLetter> letters) {
  final pages = letters
      .map(
        (l) =>
            '''
<section class="letter">
  <div class="school">${_escape(l.schoolName)}</div>
  <h1>Lerndex für ${_escape(l.studentName)}</h1>
  <p class="meta">Klasse ${_escape(l.className)}</p>
  <p>Liebe Eltern,</p>
  <p>in der Schule lernt ${_escape(l.studentName)} mit Lerndex. Mit diesem Brief können Sie
  zu Hause dabei sein. Beides ist für Sie kostenlos.</p>
  <div class="boxes">
    <div class="box">
      <h2>1. Eltern verbinden</h2>
      <div class="qr">${qrSvg(l.parentLink.toString())}</div>
      <p>Mit der Kamera Ihres Handys scannen und mit Ihrem Lerndex-Konto anmelden
      (oder kostenlos eins anlegen). Danach sehen Sie, was Ihr Kind gelernt hat, und
      können Belohnungen festlegen.</p>
      <p class="code">Oder in der App unter „Kind aus der Schule verbinden“:<br><b>${l.displayCode}</b></p>
    </div>
    <div class="box">
      <h2>2. Zu Hause lernen</h2>
      <div class="qr">${qrSvg(l.homeLink.toString())}</div>
      <p>Mit dem Handy oder Tablet scannen, auf dem Ihr Kind lernen soll. Dann ist
      ${_escape(l.studentName)} dort angemeldet und lernt mit demselben Fortschritt wie in der Schule.</p>
    </div>
  </div>
  <p class="small">Bitte geben Sie diesen Brief nicht weiter. Die Codes gehören nur zu Ihrem
  Kind. Ist er verloren gegangen, stellt die Lehrkraft einen neuen aus, der alte gilt dann nicht mehr.</p>
</section>''',
      )
      .join('\n');

  return '''<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lerndex – Elternbriefe ${letters.isEmpty ? '' : _escape(letters.first.className)}</title>
<style>
  * { box-sizing: border-box; }
  body { margin: 0; font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
         color: #222; background: #F5F3FF; line-height: 1.45; }
  .bar { background: #6B21A8; color: #fff; padding: 14px 20px; display: flex;
         justify-content: space-between; align-items: center; gap: 12px; flex-wrap: wrap; }
  .bar button { background: #fff; color: #6B21A8; border: 0; border-radius: 10px;
                padding: 10px 18px; font-size: 15px; font-weight: 600; cursor: pointer; }
  .letter { background: #fff; max-width: 760px; margin: 20px auto; padding: 28px 32px;
            border-radius: 14px; }
  .school { color: #6B21A8; font-weight: 600; font-size: 13px; }
  h1 { margin: 6px 0 0; font-size: 24px; }
  .meta { margin: 0 0 16px; color: #555; }
  .boxes { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin: 18px 0; }
  .box { border: 2px dashed #C4B5FD; border-radius: 12px; padding: 14px; font-size: 14px; }
  .box h2 { margin: 0 0 8px; font-size: 17px; color: #4C1D95; }
  .qr svg { width: 150px; height: 150px; display: block; margin: 0 auto 8px; }
  .code b { font-family: monospace; font-size: 18px; letter-spacing: 2px; }
  .small { font-size: 12px; color: #666; }
  @media (max-width: 560px) { .boxes { grid-template-columns: 1fr; } .letter { padding: 20px; } }
  @media print {
    @page { size: A4; margin: 15mm; }
    body { background: #fff; }
    .bar { display: none; }
    .letter { margin: 0; padding: 0; max-width: none; border-radius: 0; break-after: page; }
    .qr svg { width: 40mm; height: 40mm; }
  }
</style>
</head>
<body>
<div class="bar"><span>Elternbriefe · ${letters.length} ${letters.length == 1 ? 'Kind' : 'Kinder'}</span>
<button onclick="window.print()">Drucken</button></div>
$pages
</body>
</html>''';
}
