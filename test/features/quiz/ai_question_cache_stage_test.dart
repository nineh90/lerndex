import 'package:flutter_test/flutter_test.dart';
import 'package:lerndex/src/features/auth/domain/child_model.dart';
import 'package:lerndex/src/features/quiz/data/ai_question_cache_repository.dart';
import 'package:lerndex/src/features/quiz/data/curriculum_data.dart';

void main() {
  const child = ChildModel(
    id: 'c1',
    name: 'Mia',
    grade: 7,
    schoolType: 'Realschule',
    age: 12,
    level: 5,
  );

  String stage(ChildModel c) => CurriculumData.curriculumStage(
    schoolType: c.schoolType,
    grade: c.grade,
    level: c.level,
  );

  group('CacheAction', () {
    test('kein Meta-Dokument → behalten', () {
      expect(
        AiQuestionCacheRepository.cacheActionFor(null, child),
        CacheAction.keep,
      );
    });

    test('altes Schema → alles löschen', () {
      expect(
        AiQuestionCacheRepository.cacheActionFor({
          'generatedForLevel': 5,
        }, child),
        CacheAction.clearAll,
      );
    });

    test('Levelaufstieg in derselben Stufe → behalten', () {
      // Level 5 und 6 sind beide Kompetenzstufe III (Regelstandard)
      final meta = {'schemaVersion': 2, 'curriculumStage': stage(child)};
      expect(
        AiQuestionCacheRepository.cacheActionFor(
          meta,
          child.copyWith(level: 6),
        ),
        CacheAction.keep,
      );
    });

    test('neue Kompetenzstufe → ungespielte verwerfen', () {
      final meta = {'schemaVersion': 2, 'curriculumStage': stage(child)};
      expect(
        AiQuestionCacheRepository.cacheActionFor(
          meta,
          child.copyWith(level: 8),
        ),
        CacheAction.discardUnplayed,
      );
    });

    test('neue Klasse → ungespielte verwerfen', () {
      final meta = {'schemaVersion': 2, 'curriculumStage': stage(child)};
      expect(
        AiQuestionCacheRepository.cacheActionFor(
          meta,
          child.copyWith(grade: 8),
        ),
        CacheAction.discardUnplayed,
      );
    });

    test(
      'altes Meta nur mit generatedForLevel wird über das Level verglichen',
      () {
        expect(
          AiQuestionCacheRepository.cacheActionFor({
            'schemaVersion': 2,
            'generatedForLevel': 5,
          }, child.copyWith(level: 7)),
          CacheAction.keep,
        );
        expect(
          AiQuestionCacheRepository.cacheActionFor({
            'schemaVersion': 2,
            'generatedForLevel': 4,
          }, child),
          CacheAction.discardUnplayed,
        );
      },
    );

    test('Gesamtschule: Kurswechsel (G → E) ist eine neue Stufe', () {
      const gs = ChildModel(
        id: 'c2',
        name: 'Ben',
        grade: 7,
        schoolType: 'Gesamtschule',
        age: 12,
        level: 4,
      );
      expect(stage(gs), isNot(stage(gs.copyWith(level: 5))));
    });
  });
}
