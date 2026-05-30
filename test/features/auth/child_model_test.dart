import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/auth/domain/child_model.dart';

void main() {
  group('fromMap Defaults', () {
    test('leere Map liefert sinnvolle Standardwerte', () {
      final child = ChildModel.fromMap({}, 'abc');
      expect(child.id, 'abc');
      expect(child.name, '');
      expect(child.level, 1);
      expect(child.grade, 1);
      expect(child.schoolType, 'Grundschule');
      expect(child.age, 6);
      expect(child.xp, 0);
      expect(child.xpToNextLevel, 25);
      expect(child.isActive, isTrue); // null → aktiv
      expect(child.unlockedAvatars, isEmpty);
      expect(child.hiddenSubjects, isEmpty);
    });

    test('isActive == false wird respektiert', () {
      final child = ChildModel.fromMap({'isActive': false}, 'id');
      expect(child.isActive, isFalse);
    });

    test('Listenfelder werden korrekt geladen', () {
      final child = ChildModel.fromMap({
        'unlockedAvatars': ['a', 'b'],
        'hiddenSubjects': ['Englisch'],
      }, 'id');
      expect(child.unlockedAvatars, ['a', 'b']);
      expect(child.hiddenSubjects, ['Englisch']);
    });

    test('Timestamp-Felder werden zu DateTime', () {
      final date = DateTime(2026, 1, 15, 10, 30);
      final child = ChildModel.fromMap({
        'lastLearningDate': Timestamp.fromDate(date),
      }, 'id');
      expect(child.lastLearningDate, date);
    });
  });

  group('xpProgress', () {
    test('berechnet Anteil korrekt', () {
      const child = ChildModel(
        id: 'x',
        name: 'Test',
        grade: 1,
        schoolType: 'Grundschule',
        age: 6,
        xp: 10,
        xpToNextLevel: 25,
      );
      expect(child.xpProgress, closeTo(0.4, 0.0001));
    });

    test('vermeidet Division durch Null', () {
      const child = ChildModel(
        id: 'x',
        name: 'Test',
        grade: 1,
        schoolType: 'Grundschule',
        age: 6,
        xp: 10,
        xpToNextLevel: 0,
      );
      expect(child.xpProgress, 0.0);
    });
  });

  group('canLevelUp', () {
    test('true wenn xp >= xpToNextLevel', () {
      const child = ChildModel(
        id: 'x',
        name: 'Test',
        grade: 1,
        schoolType: 'Grundschule',
        age: 6,
        xp: 25,
        xpToNextLevel: 25,
      );
      expect(child.canLevelUp, isTrue);
    });

    test('false wenn xp < xpToNextLevel', () {
      const child = ChildModel(
        id: 'x',
        name: 'Test',
        grade: 1,
        schoolType: 'Grundschule',
        age: 6,
        xp: 24,
        xpToNextLevel: 25,
      );
      expect(child.canLevelUp, isFalse);
    });
  });

  group('formattedLearningTime', () {
    ChildModel withSeconds(int s) => ChildModel(
          id: 'x',
          name: 'Test',
          grade: 1,
          schoolType: 'Grundschule',
          age: 6,
          totalLearningSeconds: s,
        );

    test('0 Sekunden → 0min', () {
      expect(withSeconds(0).formattedLearningTime, '0min');
    });
    test('90 Sekunden → 1min', () {
      expect(withSeconds(90).formattedLearningTime, '1min');
    });
    test('3600 Sekunden → 1h 0min', () {
      expect(withSeconds(3600).formattedLearningTime, '1h 0min');
    });
    test('3661 Sekunden → 1h 1min', () {
      expect(withSeconds(3661).formattedLearningTime, '1h 1min');
    });
  });

  group('toMap / Roundtrip', () {
    test('toMap lässt unbelegte Optionalfelder weg', () {
      const child = ChildModel(
        id: 'x',
        name: 'Lina',
        grade: 2,
        schoolType: 'Grundschule',
        age: 7,
      );
      final map = child.toMap();
      expect(map['name'], 'Lina');
      expect(map.containsKey('streak'), isFalse);
      expect(map.containsKey('lastLearningDate'), isFalse);
      expect(map['isActive'], isTrue);
    });

    test('fromMap(toMap()) erhält die Kernfelder', () {
      final original = ChildModel(
        id: 'kid1',
        name: 'Max',
        level: 5,
        grade: 3,
        schoolType: 'Gymnasium',
        age: 9,
        xp: 120,
        xpToNextLevel: 200,
        streak: 4,
        totalQuizzes: 12,
        perfectQuizzes: 3,
        lastLearningDate: DateTime(2026, 5, 1, 8, 0),
        unlockedAvatars: const ['avatar-rare'],
        hiddenSubjects: const ['Englisch'],
      );
      final restored = ChildModel.fromMap(original.toMap(), 'kid1');
      expect(restored.name, 'Max');
      expect(restored.level, 5);
      expect(restored.grade, 3);
      expect(restored.schoolType, 'Gymnasium');
      expect(restored.xp, 120);
      expect(restored.xpToNextLevel, 200);
      expect(restored.streak, 4);
      expect(restored.totalQuizzes, 12);
      expect(restored.perfectQuizzes, 3);
      expect(restored.lastLearningDate, DateTime(2026, 5, 1, 8, 0));
      expect(restored.unlockedAvatars, ['avatar-rare']);
      expect(restored.hiddenSubjects, ['Englisch']);
    });
  });

  group('copyWith', () {
    const base = ChildModel(
      id: 'x',
      name: 'Test',
      grade: 1,
      schoolType: 'Grundschule',
      age: 6,
      level: 1,
      xp: 0,
    );

    test('ändert nur die angegebenen Felder', () {
      final updated = base.copyWith(xp: 50, level: 2);
      expect(updated.xp, 50);
      expect(updated.level, 2);
      expect(updated.name, 'Test'); // unverändert
      expect(updated.id, 'x');
    });

    test('ohne Argumente bleibt alles gleich', () {
      final clone = base.copyWith();
      expect(clone.name, base.name);
      expect(clone.xp, base.xp);
      expect(clone.grade, base.grade);
    });
  });
}
