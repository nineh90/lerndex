import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/ai/ai_response_parser.dart';

void main() {
  group('extractSubjectTag', () {
    test('extrahiert Fach aus [FACH:...]', () {
      expect(
        AiResponseParser.extractSubjectTag('Antwort [FACH:Mathematik] Ende'),
        'Mathematik',
      );
    });

    test('trimmt Whitespace im Tag', () {
      expect(
        AiResponseParser.extractSubjectTag('[FACH:  Deutsch  ]'),
        'Deutsch',
      );
    });

    test('gibt kein_schulfach zurück wenn kein Tag vorhanden', () {
      expect(
        AiResponseParser.extractSubjectTag('Nur normaler Text'),
        'kein_schulfach',
      );
    });

    test('nimmt das erste Vorkommen', () {
      expect(
        AiResponseParser.extractSubjectTag('[FACH:Englisch] [FACH:Physik]'),
        'Englisch',
      );
    });
  });

  group('extractCorrectTag', () {
    test('expliziter Tag [KORREKT:ja] → true', () {
      expect(AiResponseParser.extractCorrectTag('Toll! [KORREKT:ja]'), isTrue);
    });

    test('expliziter Tag [KORREKT:nein] → false', () {
      expect(
        AiResponseParser.extractCorrectTag('Hm... [KORREKT:nein]'),
        isFalse,
      );
    });

    test('expliziter Tag ist case-insensitive', () {
      expect(AiResponseParser.extractCorrectTag('[korrekt:JA]'), isTrue);
      expect(AiResponseParser.extractCorrectTag('[Korrekt:Nein]'), isFalse);
    });

    test('expliziter Tag hat Vorrang vor widersprüchlichem Text', () {
      // Text klingt falsch, Tag sagt aber korrekt → Tag gewinnt
      expect(
        AiResponseParser.extractCorrectTag('Das ist leider [KORREKT:ja]'),
        isTrue,
      );
    });

    test('Heuristik erkennt eindeutig falsche Antwort', () {
      expect(
        AiResponseParser.extractCorrectTag('Das ist leider falsch, versuch es nochmal.'),
        isFalse,
      );
      expect(
        AiResponseParser.extractCorrectTag('Not quite, try again.'),
        isFalse,
      );
    });

    test('Heuristik erkennt eindeutig richtige Antwort', () {
      expect(
        AiResponseParser.extractCorrectTag('Super, das ist genau richtig!'),
        isTrue,
      );
      expect(AiResponseParser.extractCorrectTag('Perfect, well done!'), isTrue);
    });

    test('falsch wird vor richtig geprüft (sicher ist sicher)', () {
      // "nicht ganz richtig" enthält sowohl "nicht ganz" als auch "richtig"
      expect(
        AiResponseParser.extractCorrectTag('Das ist nicht ganz richtig'),
        isFalse,
      );
    });

    test('kein klares Signal → false', () {
      expect(
        AiResponseParser.extractCorrectTag('Erzähl mir mehr darüber.'),
        isFalse,
      );
    });
  });

  group('stripTutorTags', () {
    test('entfernt nackten FACH-Tag', () {
      expect(
        AiResponseParser.stripTutorTags('Hallo [FACH:Mathematik] Welt'),
        'Hallo Welt',
      );
    });

    test('entfernt FACH-Tag mit Label-Präfix', () {
      expect(
        AiResponseParser.stripTutorTags('Erkanntes Schulfach: [FACH:Deutsch]'),
        '',
      );
    });

    test('entfernt nackten KORREKT-Tag', () {
      expect(
        AiResponseParser.stripTutorTags('Gut gemacht! [KORREKT:ja]'),
        'Gut gemacht!',
      );
    });

    test('entfernt KORREKT mit Leerzeichen vor Klammer', () {
      expect(
        AiResponseParser.stripTutorTags('Antwort KORREKT: [nein]'),
        'Antwort',
      );
    });

    test('entfernt FACH und KORREKT gemeinsam', () {
      final result = AiResponseParser.stripTutorTags(
        'Richtig so! [FACH:Mathematik][KORREKT:ja]',
      );
      expect(result, 'Richtig so!');
    });

    test('kollabiert dreifache Leerzeilen zu doppelten', () {
      expect(
        AiResponseParser.stripTutorTags('A\n\n\nB'),
        'A\n\nB',
      );
    });

    test('lässt normalen Text unverändert', () {
      expect(
        AiResponseParser.stripTutorTags('Ganz normaler Satz.'),
        'Ganz normaler Satz.',
      );
    });
  });

  group('stripImagePlaceholders', () {
    test('entfernt (Bild ...)-Platzhalter', () {
      expect(
        AiResponseParser.stripImagePlaceholders(
          'Wie viele Äpfel siehst du? (Bild eines Apfels)',
        ),
        'Wie viele Äpfel siehst du?',
      );
    });

    test('entfernt [Bild: ...]-Platzhalter', () {
      expect(
        AiResponseParser.stripImagePlaceholders('Was ist das? [Bild: Hund]'),
        'Was ist das?',
      );
    });

    test('entfernt (siehe Bild)', () {
      expect(
        AiResponseParser.stripImagePlaceholders('Zähle die Tiere (siehe Bild).'),
        'Zähle die Tiere .',
      );
    });

    test('entfernt englische Image-Platzhalter', () {
      expect(
        AiResponseParser.stripImagePlaceholders('Count them (Image of apples)'),
        'Count them',
      );
      expect(
        AiResponseParser.stripImagePlaceholders('Look [Image: dog] here'),
        'Look here',
      );
    });

    test('ist case-insensitive', () {
      expect(
        AiResponseParser.stripImagePlaceholders('Test (BILD eines Balls)'),
        'Test',
      );
    });

    test('kollabiert doppelte Leerzeichen', () {
      expect(
        AiResponseParser.stripImagePlaceholders('A  B   C'),
        'A B C',
      );
    });

    test('lässt Text ohne Platzhalter unverändert', () {
      expect(
        AiResponseParser.stripImagePlaceholders('Wie viel ist 2 + 2?'),
        'Wie viel ist 2 + 2?',
      );
    });
  });

  group('quoteBareEmoji', () {
    test('umschließt nacktes einzelnes Emoji mit Quotes', () {
      expect(
        AiResponseParser.quoteBareEmoji('{"emoji": ☀️, "x": 1}'),
        '{"emoji": "☀️", "x": 1}',
      );
    });

    test('umschließt mehrere nackte Emojis', () {
      expect(
        AiResponseParser.quoteBareEmoji('{"emoji": 🍎🍎🍎}'),
        '{"emoji": "🍎🍎🍎"}',
      );
    });

    test('lässt bereits gequotete Emojis unverändert', () {
      const valid = '{"emoji": "🍎"}';
      expect(AiResponseParser.quoteBareEmoji(valid), valid);
    });

    test('lässt null unverändert', () {
      const withNull = '{"emoji": null}';
      expect(AiResponseParser.quoteBareEmoji(withNull), withNull);
    });
  });

  group('fixJsonNewlines', () {
    test('escaped Newlines innerhalb von Strings', () {
      expect(
        AiResponseParser.fixJsonNewlines('{"a": "Zeile1\nZeile2"}'),
        '{"a": "Zeile1\\nZeile2"}',
      );
    });

    test('lässt Newlines außerhalb von Strings unangetastet', () {
      expect(
        AiResponseParser.fixJsonNewlines('{\n"a": "b"\n}'),
        '{\n"a": "b"\n}',
      );
    });

    test('verwirft Carriage Returns in Strings', () {
      expect(
        AiResponseParser.fixJsonNewlines('{"a": "x\ry"}'),
        '{"a": "xy"}',
      );
    });

    test('behandelt escaped Quotes korrekt', () {
      const input = r'{"a": "er sagte \"hi\""}';
      expect(AiResponseParser.fixJsonNewlines(input), input);
    });
  });

  group('cleanJson (Integration)', () {
    test('entfernt ```json Fences', () {
      const raw = '```json\n[{"a": 1}]\n```';
      expect(AiResponseParser.cleanJson(raw), '[{"a": 1}]');
    });

    test('entfernt nackte ``` Fences', () {
      const raw = '```\n{"a": 1}\n```';
      expect(AiResponseParser.cleanJson(raw), '{"a": 1}');
    });

    test('produziert parsebares JSON aus fehlerhaftem KI-Output', () {
      const raw = '```json\n[{"emoji": 🍎, "q": "Zeile1\nZeile2"}]\n```';
      final cleaned = AiResponseParser.cleanJson(raw);
      final decoded = jsonDecode(cleaned) as List;
      expect(decoded.first['emoji'], '🍎');
      expect(decoded.first['q'], 'Zeile1\nZeile2');
    });
  });
}
