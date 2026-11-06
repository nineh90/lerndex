import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/quiz/presentation/quiz_screen.dart';

double contrastWithWhite(Color c) => 1.05 / (c.computeLuminance() + 0.05);

void main() {
  test('Fachfarben werden für weiße Schrift ausreichend dunkel', () {
    for (final color in [
      Colors.green,
      Colors.blue,
      Colors.redAccent,
      Colors.amber,
      const Color(0xFF26A69A),
      Colors.white,
    ]) {
      expect(
        contrastWithWhite(readableOnWhiteText(color)),
        greaterThanOrEqualTo(4.5),
        reason: '$color',
      );
    }
  });

  test('dunkle Farben bleiben unverändert', () {
    expect(readableOnWhiteText(Colors.deepPurple), Colors.deepPurple);
  });
}
