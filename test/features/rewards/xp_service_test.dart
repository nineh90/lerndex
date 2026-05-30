import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/rewards/data/xp_service.dart';

void main() {
  group('calculateXPForLevel', () {
    test('Level <= 0 ergibt 0', () {
      expect(XPService.calculateXPForLevel(0), 0);
      expect(XPService.calculateXPForLevel(-3), 0);
    });

    test('Level 1 benötigt 60 XP', () {
      expect(XPService.calculateXPForLevel(1), 60);
    });

    test('Ergebnis ist immer ein Vielfaches von 10', () {
      for (var level = 1; level <= 50; level++) {
        expect(
          XPService.calculateXPForLevel(level) % 10,
          0,
          reason: 'Level $level sollte glatt auf 10er gerundet sein',
        );
      }
    });

    test('Kurve ist streng monoton steigend von Level 1 bis 50', () {
      for (var level = 1; level < 50; level++) {
        expect(
          XPService.calculateXPForLevel(level + 1) >
              XPService.calculateXPForLevel(level),
          isTrue,
          reason: 'Level ${level + 1} muss mehr XP kosten als Level $level',
        );
      }
    });

    test('über maxLevel wird auf maxLevel begrenzt', () {
      final atMax = XPService.calculateXPForLevel(XPService.maxLevel);
      expect(XPService.calculateXPForLevel(51), atMax);
      expect(XPService.calculateXPForLevel(100), atMax);
    });
  });

  group('calculateLevelFromXP', () {
    test('0 XP entspricht Level 1', () {
      expect(XPService.calculateLevelFromXP(0), 1);
    });

    test('knapp unter der ersten Schwelle bleibt Level 1', () {
      expect(XPService.calculateLevelFromXP(59), 1);
    });

    test('genau die erste Schwelle (60) erreicht Level 2', () {
      expect(XPService.calculateLevelFromXP(60), 2);
    });

    test('wird bei maxLevel gedeckelt', () {
      expect(XPService.calculateLevelFromXP(99999999), XPService.maxLevel);
    });

    test('Level steigt monoton mit der XP', () {
      var lastLevel = 1;
      for (var xp = 0; xp <= 5000; xp += 50) {
        final level = XPService.calculateLevelFromXP(xp);
        expect(level >= lastLevel, isTrue);
        lastLevel = level;
      }
    });
  });

  group('calculateXPInCurrentLevel', () {
    test('genau an der Levelgrenze sind 0 XP im neuen Level', () {
      // 60 XP = exakte Schwelle für Level 2 → 0 XP im Level 2 gesammelt
      expect(XPService.calculateXPInCurrentLevel(60, 2), 0);
    });

    test('Rest oberhalb der Grenze zählt im aktuellen Level', () {
      expect(XPService.calculateXPInCurrentLevel(100, 2), 40);
    });

    test('auf Level 1 zählt die gesamte XP', () {
      expect(XPService.calculateXPInCurrentLevel(45, 1), 45);
    });
  });

  group('calculateXPToNextLevel', () {
    test('frisches Level 2 braucht volle Level-2-XP', () {
      expect(
        XPService.calculateXPToNextLevel(60, 2),
        XPService.calculateXPForLevel(2),
      );
    });

    test('auf Level 1 ohne XP fehlt die volle erste Schwelle', () {
      expect(XPService.calculateXPToNextLevel(0, 1), 60);
    });

    test('auf maxLevel sind keine weiteren XP nötig', () {
      expect(XPService.calculateXPToNextLevel(99999, XPService.maxLevel), 0);
    });

    test('Konsistenz: inLevel + toNext == benötigte XP des Levels', () {
      const totalXP = 137;
      final level = XPService.calculateLevelFromXP(totalXP);
      final inLevel = XPService.calculateXPInCurrentLevel(totalXP, level);
      final toNext = XPService.calculateXPToNextLevel(totalXP, level);
      expect(inLevel + toNext, XPService.calculateXPForLevel(level));
    });
  });

  group('getRankForLevel', () {
    test('Level 1–10 → Lernling', () {
      expect(XPService.getRankForLevel(1).title, 'Lernling');
      expect(XPService.getRankForLevel(10).title, 'Lernling');
      expect(XPService.getRankForLevel(10).emoji, '📚');
    });

    test('Level 11–20 → Entdecker', () {
      expect(XPService.getRankForLevel(11).title, 'Entdecker');
      expect(XPService.getRankForLevel(20).title, 'Entdecker');
    });

    test('Level 21–30 → Forscher', () {
      expect(XPService.getRankForLevel(21).title, 'Forscher');
      expect(XPService.getRankForLevel(30).title, 'Forscher');
    });

    test('Level 31–40 → Experte', () {
      expect(XPService.getRankForLevel(31).title, 'Experte');
      expect(XPService.getRankForLevel(40).title, 'Experte');
    });

    test('Level 41–50 → Meister', () {
      expect(XPService.getRankForLevel(41).title, 'Meister');
      expect(XPService.getRankForLevel(50).title, 'Meister');
      expect(XPService.getRankForLevel(99).title, 'Meister');
    });
  });
}
