import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex/src/ai/vertex_ai_service.dart';
import 'package:lerndex/src/features/auth/domain/child_model.dart';
import 'package:lerndex/src/features/parent_dashboard/presentation/widgets/early_learner_question_repository.dart';
import 'package:lerndex/src/features/quiz/data/ai_question_cache_repository.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/subject_config.dart';

/// Pre-Fetch Service fuer Quiz-Fragen.
///
/// Wird aufgerufen beim App-Start (Splash-Screen):
///   → Alle Kinder parallel
///   → Pro Kind: alle Faecher parallel (mit Concurrency-Limit)
///
/// Auch aufgerufen bei:
///   1. Kind-Erstellung -> sofort alle Faecher vorbereiten
///   2. Dashboard-Laden -> Sicherheitsnetz fuer existierende Kinder
///
/// Nutzt prefillIfEmpty():
///   - Generiert NUR wenn Cache leer ist (< 5 Fragen)
///   - Markiert keine Fragen als gespielt
class QuizPrefetchService {
  // Maximale parallele Vertex-AI-Anfragen pro Kind.
  // Zu viele parallele Requests koennen Rate-Limits triggern.
  static const int _subjectConcurrency = 3;

  /// Gibt die Anzahl der Fächer für ein Kind zurück.
  /// Wird im Splash verwendet um den Gesamtfortschritt zu berechnen.
  /// Für Klasse 1–2 werden auch die Early-Learner-Fächer mitgezählt.
  static int subjectCountForChild(ChildModel child) {
    return getSubjectsForChild(child).length + earlyLearnerSubjectCount(child);
  }

  /// Faecher-Reihenfolge: Mathe und Deutsch zuerst.
  static List<SubjectConfig> _prioritized(List<SubjectConfig> subjects) {
    const priority = ['Mathe', 'Deutsch', 'FarbenFormen'];
    final sorted = List<SubjectConfig>.from(subjects);
    sorted.sort((a, b) {
      final aIdx = priority.indexOf(a.subject);
      final bIdx = priority.indexOf(b.subject);
      return (aIdx >= 0 ? aIdx : 99).compareTo(bIdx >= 0 ? bIdx : 99);
    });
    return sorted;
  }

  // ============================================================
  // NEU: Alle Kinder parallel prefetchen (fuer Splash-Screen)
  // ============================================================

  /// Laed fuer ALLE uebergebenen Kinder alle Faecher vor.
  ///
  /// Strategie:
  /// - Kinder werden parallel gestartet (Future.wait)
  /// - Pro Kind laufen bis zu [_subjectConcurrency] Faecher gleichzeitig
  /// - Fehler eines Kindes/Fachs brechen nicht die anderen ab
  static Future<void> prefetchAllChildren({
    required String userId,
    required List<ChildModel> children,
    AiQuestionCacheRepository? cache,
    void Function(String childName, String subject)? onSubjectDone,
  }) async {
    if (children.isEmpty) return;

    final effectiveCache =
        cache ??
        AiQuestionCacheRepository(
          FirebaseFirestore.instance,
          VertexAIService(),
        );

    print(
      '🚀 Splash-Prefetch: Starte fuer ${children.length} Kinder parallel...',
    );

    // Alle Kinder gleichzeitig starten
    await Future.wait(
      children.map(
        (child) => _prefetchChildParallel(
          userId: userId,
          child: child,
          cache: effectiveCache,
          onSubjectDone: onSubjectDone,
        ),
      ),
    );

    print('✅ Splash-Prefetch abgeschlossen fuer alle Kinder');
  }

  /// Prefetch fuer ein einzelnes Kind mit parallelen Fach-Requests.
  static Future<void> _prefetchChildParallel({
    required String userId,
    required ChildModel child,
    required AiQuestionCacheRepository cache,
    void Function(String childName, String subject)? onSubjectDone,
  }) async {
    final subjects = _prioritized(getSubjectsForChild(child));

    print(
      '🔮 ${child.name}: ${subjects.length} Faecher werden geladen '
      '(max $_subjectConcurrency parallel)...',
    );

    // Faecher in Gruppen aufteilen fuer kontrollierten Parallelismus
    for (int i = 0; i < subjects.length; i += _subjectConcurrency) {
      final batch = subjects.skip(i).take(_subjectConcurrency).toList();

      await Future.wait(
        batch.map((subjectConfig) async {
          try {
            await cache.prefillIfEmpty(
              userId: userId,
              childId: child.id,
              child: child,
              subject: subjectConfig.subject,
            );
            onSubjectDone?.call(child.name, subjectConfig.subject);
          } catch (e) {
            print('⚠️ ${child.name} / ${subjectConfig.title}: $e');
          }
        }),
      );
    }

    print('✅ ${child.name}: alle Faecher bereit');

    // Extra: Für Klasse 1–2 auch Early-Learner-Fragen vorladen
    // WICHTIG: await damit der Splash-Screen darauf wartet!
    if (child.grade <= 2) {
      await _prefetchEarlyLearnerQuestions(
        userId: userId,
        child: child,
        onSubjectDone: onSubjectDone,
      );
    }
  }

  // ============================================================
  // EARLY LEARNER: KI-Fragen für Klasse 1–2 vorladen
  //
  // Generiert pro Fach GENUG Fragen damit nach dem Client-Filter
  // mindestens 5 gute Fragen für ein Quiz übrig bleiben.
  // Ziel: 20 Fragen pro Fach im Cache (bei ~50% Filterrate → 10 gute)
  // ============================================================

  /// Anzahl der Early-Learner-Fächer (für Fortschrittsberechnung im Splash)
  static int earlyLearnerSubjectCount(ChildModel child) {
    return child.grade <= 2 ? 3 : 0; // Mathe, Deutsch, FarbenFormen
  }

  static Future<void> _prefetchEarlyLearnerQuestions({
    required String userId,
    required ChildModel child,
    void Function(String childName, String subject)? onSubjectDone,
  }) async {
    const earlySubjects = ['Mathe', 'Deutsch', 'FarbenFormen'];
    final repo = EarlyLearnerQuestionRepository(FirebaseFirestore.instance);
    print(
      '🧒 ${child.name} (Klasse ${child.grade}): Early-Learner-Fragen vorladen...',
    );
    for (final subject in earlySubjects) {
      try {
        // prefillForQuiz generiert genug Fragen damit nach dem Filter
        // mindestens 15 übrig bleiben (= 3 volle Quiz-Runden)
        await repo.prefillForQuiz(
          userId: userId,
          childId: child.id,
          child: child,
          subject: subject,
          targetCount: 20, // 20 Fragen → nach ~50% Filter bleiben ~10
        );
        onSubjectDone?.call(child.name, '$subject 🧒');
      } catch (e) {
        print('⚠️ Early-Prefill Fehler $subject: $e');
      }
    }
    print('✅ ${child.name}: Early-Learner-Fragen bereit');
  }

  // ============================================================
  // BESTEHEND: Ein Kind prefetchen (sequenziell, fuer Fallback)
  // ============================================================

  /// Generiert Fragen fuer alle Faecher eines einzelnen Kindes.
  /// Fuer Rueckwaertskompatibilitaet und den StudentDashboard-Fallback.
  static Future<void> prefetchAllSubjects({
    required String userId,
    required ChildModel child,
    AiQuestionCacheRepository? cache,
  }) async {
    final effectiveCache =
        cache ??
        AiQuestionCacheRepository(
          FirebaseFirestore.instance,
          VertexAIService(),
        );

    // Direkt die parallele Variante nutzen
    await _prefetchChildParallel(
      userId: userId,
      child: child,
      cache: effectiveCache,
    );
  }
}

final quizPrefetchServiceProvider = Provider<QuizPrefetchService>((ref) {
  return QuizPrefetchService();
});
