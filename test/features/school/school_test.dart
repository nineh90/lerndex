import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/auth/data/child_device_repository.dart';
import 'package:lerndex/src/features/auth/domain/account.dart';
import 'package:lerndex/src/features/school/data/school_repository.dart';
import 'package:lerndex/src/features/school/domain/school_models.dart';
import 'package:lerndex/src/features/school/presentation/school_class_screen.dart';
import 'package:lerndex/src/features/school/presentation/student_cards_print.dart';

void main() {
  test('Einladungslink der Schule und Lehrer-Karte', () {
    expect(schoolSignupFromPath('/schule/K7MXQ2PA'), 'K7MXQ2PA');
    expect(schoolSignupFromPath('/schule/K7MX-Q2PA/'), 'K7MX-Q2PA');
    expect(schoolSignupFromPath('/lehrer/K7MXQ2PA'), isNull);
    expect(schoolSignupFromPath('/schule/'), isNull);
    expect(
      teacherCardFromPath('/l/ABCDEFGHJKLMNPQRSTUV'),
      'ABCDEFGHJKLMNPQRSTUV',
    );
    expect(teacherCardFromPath('/l/kurz'), isNull);
    expect(teacherCardFromPath('/s/ABCDEFGHJKLMNPQRSTUV'), isNull);
    expect(studentCardFromPath('/l/ABCDEFGHJKLMNPQRSTUV'), isNull);
    // Andere Links sind davon nicht betroffen
    expect(pairingCodeFromPath('/schule/K7MXQ2PA'), isNull);
    expect(studentCardFromPath('/lehrer/K7MXQ2PA'), isNull);
  });

  test('Namensliste: eine Zeile pro Kind, aufgeräumt', () {
    expect(parseStudentNames('Mia K.\r\n\n  Ben   S. \nLeonie W.\n'), [
      'Mia K.',
      'Ben S.',
      'Leonie W.',
    ]);
    expect(parseStudentNames('   \n'), isEmpty);
    expect(parseStudentNames('A' * 60).single.length, 40);
  });

  test('Schülergerät wird als Schul-Tablet erkannt', () {
    final schoolKid = kidUid(schoolOwnerUid('abc'), 's1');
    expect(schoolKid, 'kid:school_abc:s1');
    expect(ownerUidFor(schoolKid), 'school_abc');
    expect(pairedChildIdFor(schoolKid), 's1');
  });

  test('Links von QR-Code und Schülerkarte', () {
    expect(pairingCodeFromPath('/k/K7MXQ2PA'), 'K7MXQ2PA');
    expect(pairingCodeFromPath('/s/K7MXQ2PA'), isNull);
    expect(studentCardFromPath('/s/ABCDEFGHJKLMNPQRSTUV'), 'ABCDEFGHJKLMNPQRSTUV');
    expect(studentCardFromPath('/s/kurz'), isNull);
    expect(studentCardFromPath('/k/ABCDEFGHJKLMNPQRSTUV'), isNull);
  });

  test('Druckseite: Namen werden maskiert, QR als SVG', () {
    final html = studentCardsHtml([
      StudentCard(
        studentId: 's1',
        name: '<script>alert(1)</script>',
        className: '5b',
        link: Uri.parse('https://app.lerndex.de/s/ABCDEFGHJKLMNPQRSTUV'),
      ),
    ], schoolName: 'Schule & Co');
    expect(html, isNot(contains('<script>alert')));
    expect(html, contains('&lt;script&gt;'));
    expect(html, contains('Schule &amp; Co'));
    expect(html, contains('<svg'));
    expect(html, contains('Klasse 5b'));
  });

  test('QR-SVG hat Ruhezone und quadratische Module', () {
    final svg = qrSvg('https://app.lerndex.de/s/ABCDEFGHJKLMNPQRSTUV');
    expect(svg, startsWith('<svg'));
    expect(RegExp(r'viewBox="0 0 (\d+) \1"').hasMatch(svg), isTrue);
    expect(svg, contains('h1v1h-1z'));
  });
}
