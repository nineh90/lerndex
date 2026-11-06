import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/tts/tts_provider.dart';

void main() {
  group('pickLocalWebVoice', () {
    test('nimmt nie eine Netzwerkstimme', () {
      final voice = TtsController.pickLocalWebVoice([
        (name: 'Google Deutsch', lang: 'de-DE', localService: false),
        (name: 'Microsoft Katja', lang: 'de-DE', localService: true),
      ]);
      expect(voice?.name, 'Microsoft Katja');
    });

    test('nur Netzwerkstimmen → keine Stimme (Vorlesen aus)', () {
      expect(
        TtsController.pickLocalWebVoice([
          (name: 'Google Deutsch', lang: 'de-DE', localService: false),
          (name: 'Samantha', lang: 'en-US', localService: true),
        ]),
        isNull,
      );
    });

    test('de-DE vor anderen deutschen Stimmen', () {
      final voice = TtsController.pickLocalWebVoice([
        (name: 'Anna (CH)', lang: 'de-CH', localService: true),
        (name: 'Anna', lang: 'de-DE', localService: true),
      ]);
      expect(voice?.name, 'Anna');
    });
  });
}
