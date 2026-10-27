import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/tts/speakable_text.dart';

void main() {
  group('speakableText', () {
    test('entfernt Markdown und Emojis', () {
      expect(
        speakableText('**Super!** 🌟 Das ist *richtig* gut.'),
        'Super! Das ist richtig gut.',
      );
    });

    test('Aufzählungen werden zu Sätzen mit Pause', () {
      expect(
        speakableText('Überlege mal:\n- erst die Zehner\n- dann die Einer'),
        'Überlege mal: erst die Zehner. dann die Einer',
      );
    });

    test('Überschriften und Links', () {
      expect(
        speakableText('## Tipp\nSchau [hier](https://example.org) nach.'),
        'Tipp. Schau hier nach.',
      );
    });

    test('versteckte Steuer-Tags fallen weg', () {
      expect(
        speakableText('Genau so! [FACH:Mathe] [KORREKT:ja]'),
        'Genau so!',
      );
    });

    test('einfache Rechnung', () {
      expect(speakableText(r'Was ist $3 + 4 = 7$?'), 'Was ist 3 plus 4 gleich 7?');
    });

    test('Bruch, Mal und Minus', () {
      expect(
        speakableText(r'$\frac{1}{2} \cdot 4 - 1$'),
        '1 geteilt durch 2 mal 4 minus 1',
      );
    });

    test('Potenzen und Wurzeln', () {
      expect(
        speakableText(r'$$a^2 + b^2 = c^2$$ und $\sqrt{16}$'),
        'a hoch zwei plus b hoch zwei gleich c hoch zwei und Wurzel aus 16',
      );
    });

    test('Vergleich mit \\leq wird nicht als \\le gelesen', () {
      expect(speakableText(r'$x \leq 5$'), 'x kleiner oder gleich 5');
    });

    test('Bindestriche in Wörtern bleiben', () {
      expect(speakableText('Das Lern-Spiel'), 'Das Lern-Spiel');
    });
  });

  test('stripEmojis', () {
    expect(stripEmojis('🌟 Ja, 3 Äpfel! 🍎'), 'Ja, 3 Äpfel!');
  });
}
