import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/rewards/domain/xp_result.dart';

void main() {
  test('XPResult hält die übergebenen Werte', () {
    final result = XPResult(
      newXP: 120,
      newLevel: 3,
      leveledUp: true,
      xpGained: 5,
      xpToNextLevel: 80,
    );
    expect(result.newXP, 120);
    expect(result.newLevel, 3);
    expect(result.leveledUp, isTrue);
    expect(result.xpGained, 5);
    expect(result.xpToNextLevel, 80);
  });

  test('toString enthält die wichtigsten Werte', () {
    final result = XPResult(
      newXP: 10,
      newLevel: 1,
      leveledUp: false,
      xpGained: 5,
      xpToNextLevel: 50,
    );
    expect(result.toString(), contains('newXP: 10'));
    expect(result.toString(), contains('leveledUp: false'));
  });
}
