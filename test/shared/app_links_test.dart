import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/shared/app_links.dart';

void main() {
  group('lerndexLinkPath', () {
    test('erkennt Koppel-Link, Karten, Elternbrief und Schul-Einladung', () {
      expect(lerndexLinkPath('https://app.lerndex.de/k/K7MX-Q2PA'),
          '/k/K7MX-Q2PA');
      expect(lerndexLinkPath('https://app.lerndex.de/s/abcdefghijklmnop1234'),
          '/s/abcdefghijklmnop1234');
      expect(lerndexLinkPath('https://app.lerndex.de/l/abcdefghijklmnop1234'),
          '/l/abcdefghijklmnop1234');
      expect(lerndexLinkPath('https://app.lerndex.de/e/AB12-CD34'),
          '/e/AB12-CD34');
      expect(lerndexLinkPath('https://app.lerndex.de/schule/AB12CD34'),
          '/schule/AB12CD34');
    });

    test('nimmt alte Links auf web.app und Text ohne https://', () {
      expect(lerndexLinkPath('https://lerndex-3775f.web.app/k/K7MXQ2PA'),
          '/k/K7MXQ2PA');
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
}
