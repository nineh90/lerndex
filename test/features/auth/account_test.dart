import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/auth/domain/account.dart';

void main() {
  test('Eltern: Daten liegen unter der eigenen UID', () {
    expect(
      ownerUidFor('pXJrpb9HUUN5QsIVOHQesrPPnD62'),
      'pXJrpb9HUUN5QsIVOHQesrPPnD62',
    );
    expect(pairedChildIdFor('pXJrpb9HUUN5QsIVOHQesrPPnD62'), isNull);
  });

  test('Kindergerät: Daten liegen bei den Eltern', () {
    final uid = kidUid('parent1', 'child1');
    expect(uid, 'kid:parent1:child1');
    expect(ownerUidFor(uid), 'parent1');
    expect(pairedChildIdFor(uid), 'child1');
  });

  test('kaputte Kind-UIDs werden nicht als Kindergerät erkannt', () {
    for (final uid in ['kid:', 'kid::c', 'kid:p:', 'kid:p:c:x', 'kids:p:c']) {
      expect(pairedChildIdFor(uid), isNull, reason: uid);
      expect(ownerUidFor(uid), uid, reason: uid);
    }
  });
}
