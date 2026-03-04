import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex/src/ai/vertex_ai_service.dart';
import 'package:lerndex/src/features/auth/domain/child_model.dart';
import 'package:lerndex/src/features/quiz/data/ai_question_cache_repository.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/subject_config.dart';

/// Pre-Fetch Service fuer Quiz-Fragen.
///
/// Wird aufgerufen bei:
///   1. Kind-Erstellung -> Mathe + Deutsch sofort, Rest im Hintergrund
///   2. Dashboard-Laden -> Sicherheitsnetz fuer existierende Kinder
///
/// Nutzt prefillIfEmpty() statt getQuestions():
///   - Generiert NUR wenn Cache leer ist
///   - Markiert keine Fragen als gespielt
///   - Kein Schnell-Batch noetig (hat ja Zeit)
class QuizPrefetchService {
  /// Faecher-Reihenfolge: Mathe und Deutsch zuerst,
  /// weil Kinder diese am ehesten zuerst antippen.
  static List<SubjectConfig> _prioritized(List<SubjectConfig> subjects) {
    final priority = ['Mathe', 'Deutsch', 'Englisch'];
    final sorted = List<SubjectConfig>.from(subjects);
    sorted.sort((a, b) {
      final aIdx = priority.indexOf(a.subject);
      final bIdx = priority.indexOf(b.subject);
      final aPrio = aIdx >= 0 ? aIdx : 99;
      final bPrio = bIdx >= 0 ? bIdx : 99;
      return aPrio.compareTo(bPrio);
    });
    return sorted;
  }

  /// Generiert Fragen fuer alle Faecher eines Kindes.
  /// Priorisiert Mathe > Deutsch > Englisch > Rest.
  /// Ueberspringt Faecher die schon genug Fragen im Cache haben.
  static Future<void> prefetchAllSubjects({
    required String userId,
    required ChildModel child,
    AiQuestionCacheRepository? cache,
  }) async {
    try {
      final effectiveCache =
          cache ??
          AiQuestionCacheRepository(
            FirebaseFirestore.instance,
            VertexAIService(),
          );

      final subjects = _prioritized(getSubjectsForChild(child));

      print(
        '🔮 Pre-Fetch: Starte fuer ${child.name} '
        '(${subjects.length} Faecher: ${subjects.map((s) => s.title).join(", ")})',
      );

      for (final subject in subjects) {
        try {
          await effectiveCache.prefillIfEmpty(
            userId: userId,
            childId: child.id,
            child: child,
            subject: subject.subject,
          );
        } catch (e) {
          print('⚠️ Pre-Fetch: ${subject.title} fehlgeschlagen: $e');
        }
      }

      print('🔮 Pre-Fetch abgeschlossen fuer ${child.name}');
    } catch (e) {
      print('⚠️ Pre-Fetch Gesamtfehler: $e');
    }
  }
}

final quizPrefetchServiceProvider = Provider<QuizPrefetchService>((ref) {
  return QuizPrefetchService();
});
