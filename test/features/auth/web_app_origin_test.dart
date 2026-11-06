import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/auth/data/child_device_repository.dart';

void main() {
  test('Links zeigen immer auf app.lerndex.de, auch vom alten Hosting', () {
    expect(
      webAppOriginFor(
        configured: '',
        emulatorInBrowser: false,
        currentOrigin: 'https://lerndex-3775f.web.app',
      ),
      'https://app.lerndex.de',
    );
    expect(
      webAppOriginFor(
        configured: '',
        emulatorInBrowser: false,
        currentOrigin: '',
      ),
      'https://app.lerndex.de',
    );
  });

  test('Emulator im Browser: die laufende Test-Seite', () {
    expect(
      webAppOriginFor(
        configured: '',
        emulatorInBrowser: true,
        currentOrigin: 'http://localhost:5000',
      ),
      'http://localhost:5000',
    );
  });

  test('WEB_APP_URL hat Vorrang', () {
    expect(
      webAppOriginFor(
        configured: 'https://test.lerndex.de',
        emulatorInBrowser: true,
        currentOrigin: 'http://localhost:5000',
      ),
      'https://test.lerndex.de',
    );
  });

  test('PairingCode-Link nutzt die feste Adresse', () {
    final code = PairingCode(code: 'K7MXQ2PA', expiresAt: DateTime(2026));
    expect(code.link.toString(), 'https://app.lerndex.de/k/K7MXQ2PA');
  });
}
