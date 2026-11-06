import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/shared/app_links.dart';

void main() {
  group('lerndexLinkPath', () {
    test('erkennt Koppel-Link, Karten, Elternbrief und Schul-Einladung', () {
      expect(
        lerndexLinkPath('https://app.lerndex.de/k/K7MX-Q2PA'),
        '/k/K7MX-Q2PA',
      );
      expect(
        lerndexLinkPath('https://app.lerndex.de/s/abcdefghijklmnop1234'),
        '/s/abcdefghijklmnop1234',
      );
      expect(
        lerndexLinkPath('https://app.lerndex.de/l/abcdefghijklmnop1234'),
        '/l/abcdefghijklmnop1234',
      );
      expect(
        lerndexLinkPath('https://app.lerndex.de/e/AB12-CD34'),
        '/e/AB12-CD34',
      );
      expect(
        lerndexLinkPath('https://app.lerndex.de/schule/AB12CD34'),
        '/schule/AB12CD34',
      );
    });

    test('nimmt alte Links auf web.app und Text ohne https://', () {
      expect(
        lerndexLinkPath('https://lerndex-3775f.web.app/k/K7MXQ2PA'),
        '/k/K7MXQ2PA',
      );
      expect(lerndexLinkPath('  app.lerndex.de/k/K7MX-Q2PA '), '/k/K7MX-Q2PA');
    });

    test('lehnt fremde Seiten und unbekannte Pfade ab', () {
      expect(lerndexLinkPath('https://example.com/k/K7MX-Q2PA'), isNull);
      expect(lerndexLinkPath('https://app.lerndex.de/'), isNull);
      expect(lerndexLinkPath('https://app.lerndex.de/k/zu-kurz'), isNull);
      expect(lerndexLinkPath('K7MX-Q2PA'), isNull);
      expect(lerndexLinkPath('irgendwas'), isNull);
    });
  });

  group('knownLinkPath', () {
    test('nur Pfade, die der Startbildschirm versteht', () {
      expect(knownLinkPath('/k/K7MX-Q2PA'), '/k/K7MX-Q2PA');
      expect(
        knownLinkPath('/s/abcdefghijklmnop1234'),
        '/s/abcdefghijklmnop1234',
      );
      expect(knownLinkPath('/'), isNull);
      expect(knownLinkPath('/k/zu-kurz'), isNull);
      expect(knownLinkPath('/irgendwas/AB12CD34'), isNull);
    });
  });

  // web/index.html nimmt Links mit Codes vor dem Start aus der Adresszeile.
  // Das Muster dort muss alle Pfade abdecken, die die App versteht – sonst
  // bliebe der Code im Verlauf.
  test('web/index.html fängt alle Link-Pfade ab', () {
    final html = File('web/index.html').readAsStringSync();
    final match = RegExp(r'if \(!/(.+?)/\.test\(path\)\)').firstMatch(html);
    expect(match, isNotNull, reason: 'Muster in web/index.html nicht gefunden');
    final jsPattern = RegExp(match!.group(1)!.replaceAll(r'\/', '/'));
    for (final path in [
      '/k/K7MX-Q2PA',
      '/k/K7MXQ2PA',
      '/s/abcdefghijklmnop1234',
      '/s/${'a' * 64}',
      '/l/abcdefghijklmnop1234/',
      '/e/AB12-CD34',
      '/schule/AB12CD34',
    ]) {
      expect(knownLinkPath(path), path, reason: path);
      expect(jsPattern.hasMatch(path), isTrue, reason: path);
    }
    expect(jsPattern.hasMatch('/'), isFalse);
    expect(jsPattern.hasMatch('/datenschutz'), isFalse);
  });
}
