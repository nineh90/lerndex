import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

// Die Web-Version soll beim Start keine fremden Server kontaktieren
// (Kinder, Schulen, DSGVO). Diese Tests passen auf die Stellen auf, die
// bei Paket-Updates still kaputtgehen würden.
void main() {
  test(
    'Import-Map blendet das RevenueCat-Skript der aktuellen Version aus',
    () {
      // Paketpfad aus der package_config (Isolate.resolvePackageUri geht in
      // Flutter-Tests nicht)
      final config = File('.dart_tool/package_config.json');
      final packages =
          (jsonDecode(config.readAsStringSync())['packages'] as List)
              .cast<Map<String, dynamic>>();
      final root =
          packages.firstWhere(
                (p) => p['name'] == 'purchases_flutter',
              )['rootUri']
              as String;
      final pluginFile = config.uri
          .resolve('$root/')
          .resolve('lib/web/purchases_flutter_web.dart');
      final source = File.fromUri(pluginFile).readAsStringSync();
      final version = RegExp(
        r"_purchasesHybridMappingsVersion = '([^']+)'",
      ).firstMatch(source)?.group(1);
      expect(version, isNotNull, reason: 'Konstante im Plugin nicht gefunden');

      final url =
          'https://cdn.jsdelivr.net/npm/@revenuecat/'
          'purchases-js-hybrid-mappings@$version/dist/index.umd.js';
      final indexHtml = File('web/index.html').readAsStringSync();
      expect(
        indexHtml,
        contains('"$url": "./revenuecat-disabled.js"'),
        reason:
            'purchases_flutter lädt jetzt Version $version – die Import-Map in '
            'web/index.html anpassen, sonst lädt die Web-Version Stripe.js.',
      );
    },
  );

  test('Ersatzschriften kommen aus web/fonts', () {
    final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();
    expect(bootstrap, contains('fontFallbackBaseUrl: "fonts/"'));
    expect(bootstrap, contains('initializeEngine(config)'));
    expect(
      File(
        'web/fonts/roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2',
      ).existsSync(),
      isTrue,
    );
  });
}
