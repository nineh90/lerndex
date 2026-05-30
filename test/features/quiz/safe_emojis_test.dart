import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/quiz/domain/safe_emojis.dart';

void main() {
  group('SafeEmojis.sanitize', () {
    test('null bleibt null', () {
      expect(SafeEmojis.sanitize(null), isNull);
    });

    test('leerer / Whitespace-String → null', () {
      expect(SafeEmojis.sanitize(''), isNull);
      expect(SafeEmojis.sanitize('   '), isNull);
    });

    test('einzelnes Whitelist-Emoji wird durchgereicht', () {
      expect(SafeEmojis.sanitize('🍎'), '🍎');
    });

    test('Emoji wird getrimmt', () {
      expect(SafeEmojis.sanitize('  🍌  '), '🍌');
    });

    test('mehrteiliges Emoji (Variation Selector) wird erkannt', () {
      expect(SafeEmojis.sanitize('☀️'), '☀️');
    });

    test('mehrere gleiche Whitelist-Emojis werden akzeptiert', () {
      expect(SafeEmojis.sanitize('🍎🍎🍎'), '🍎🍎🍎');
    });

    test('nicht-gelistetes Emoji → null', () {
      expect(SafeEmojis.sanitize('😀'), isNull);
    });

    test('Mischung aus erlaubt und unerlaubt → null', () {
      expect(SafeEmojis.sanitize('🍎😀'), isNull);
    });

    test('Buchstaben/Text → null', () {
      expect(SafeEmojis.sanitize('Apfel'), isNull);
    });

    test('mehr als 5 Emojis (Spam-Schutz) → null', () {
      expect(SafeEmojis.sanitize('🍎🍎🍎🍎🍎🍎'), isNull);
    });

    test('genau 5 Emojis sind noch erlaubt', () {
      expect(SafeEmojis.sanitize('🍎🍎🍎🍎🍎'), '🍎🍎🍎🍎🍎');
    });
  });

  group('SafeEmojis.promptList', () {
    test('enthält Whitelist-Emojis', () {
      expect(SafeEmojis.promptList, contains('🍎'));
      expect(SafeEmojis.promptList.isNotEmpty, isTrue);
    });
  });
}
