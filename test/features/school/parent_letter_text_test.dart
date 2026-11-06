import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/school/data/parent_link_repository.dart';
import 'package:lerndex/src/features/school/presentation/student_cards_print.dart';

void main() {
  final letter = ParentLetter(
    studentName: 'Mia K.',
    className: '5b',
    schoolName: 'Grundschule am Wald',
    parentCode: 'K7MXQ2PA',
    homeLink: Uri.parse('https://app.lerndex.de/s/abcdefghijklmnop1234'),
  );

  test('Brieftext enthält Eltern-Link, Code und Heim-Link', () {
    final text = parentLetterText(letter);
    expect(text, contains('Mia K.'));
    expect(text, contains('https://app.lerndex.de/e/K7MXQ2PA'));
    expect(text, contains('K7MX-Q2PA'));
    expect(text, contains('https://app.lerndex.de/s/abcdefghijklmnop1234'));
  });

  test('Fehlerseite für den Druck-Tab maskiert HTML', () {
    final html = printErrorHtml('<b>kaputt</b>');
    expect(html, contains('&lt;b&gt;kaputt&lt;/b&gt;'));
    expect(html, isNot(contains('<b>kaputt')));
  });

  test('Druckkarten: Mindesthöhe statt fester Höhe', () {
    final html = studentCardsHtml(const [], schoolName: 'X');
    expect(html, contains('min-height: 58mm'));
    expect(html, isNot(contains(' height: 58mm')));
  });
}
