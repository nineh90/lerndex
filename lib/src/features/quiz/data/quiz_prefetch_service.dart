import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex/src/ai/vertex_ai_service.dart';
import 'package:lerndex/src/features/auth/domain/child_model.dart';
import 'package:lerndex/src/features/quiz/data/ai_question_cache_repository.dart';
import 'package:lerndex/src/features/student_dashboard/presentation/subject_config.dart';

/// Pre-Fetch Service für Quiz-Fragen.
///
/// Wird aufgerufen beim App-Start (Splash-Screen):
///   → Alle Kinder parallel
///   → Pro Kind: alle Fächer parallel (mit Concurrency-Limit)
///
/// Auch aufgerufen bei:
///   1. Kind-Erstellung  → sofort alle Fächer vorbereiten
///   2. Dashboard-Laden  → Sicherheitsnetz für existierende Kinder
///
/// Guard-Logik (verhindert unnötige KI-Calls):
///   - prefillIfEmpty() in AiQuestionCacheRepository prüft ob >= 5 Fragen
///     für das aktuelle Level vorhanden sind → kein Firestore-Write nötig
///   - _sessionPrefetchDone (In-Memory): merkt sich pro childId+subject ob
///     dieser App-Start bereits einen erfolgreichen Prefetch abgeschlossen hat
///     → verhindert Doppel-Calls wenn Dashboard + Splash beide prefetchen
class QuizPrefetchService {
  // Maximale parallele Vertex-AI-Anfragen pro Kind.
  static const int _subjectConcurrency = 3;

  /// In-Memory: welche "childId|subject"-Kombinationen wurden in dieser
  /// App-Session bereits erfolgreich geprefetcht.
  /// Wird NIE persistiert — reset bei App-Neustart ist gewünscht, da
  /// ein Neustart oft bedeutet dass Zeit vergangen ist.
  static final Set<String> _sessionPrefetchDone = {};

  // ============================================================
  // HILFSMETHODEN
  // ============================================================

  /// Anzahl der Quiz-Fächer für ein Kind (für Splash-Fortschrittsanzeige).
  static int subjectCountForChild(ChildModel child) {
    return getSubjectsForChild(child).length;
  }

  /// Fächer-Reihenfolge: Prioritäts-Fächer zuerst laden.
  static List<SubjectConfig> _prioritized(List<SubjectConfig> subjects) {
    const priority = ['Mathe', 'Deutsch', 'Zahlen', 'Buchstaben'];
    final sorted = List<SubjectConfig>.from(subjects);
    sorted.sort((a, b) {
      final aIdx = priority.indexOf(a.subject);
      final bIdx = priority.indexOf(b.subject);
      return (aIdx >= 0 ? aIdx : 99).compareTo(bIdx >= 0 ? bIdx : 99);
    });
    return sorted;
  }

  // ============================================================
  // ALLE KINDER PREFETCHEN (für Splash-Screen)
  // ============================================================

  /// Lädt für ALLE übergebenen Kinder alle Fächer vor.
  ///
  /// Strategie:
  ///   - Kinder parallel (Future.wait)
  ///   - Pro Kind: bis zu [_subjectConcurrency] Fächer gleichzeitig
  ///   - Session-Guard: bereits geprefetchte Fächer werden übersprungen
  ///   - Fehler eines Kindes/Fachs brechen nicht die anderen ab
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

    debugPrint(
      '🚀 Splash-Prefetch: Starte für ${children.length} Kinder parallel...',
    );

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

    debugPrint('✅ Splash-Prefetch abgeschlossen');
  }

  /// Prefetch für ein einzelnes Kind.
  static Future<void> _prefetchChildParallel({
    required String userId,
    required ChildModel child,
    required AiQuestionCacheRepository cache,
    void Function(String childName, String subject)? onSubjectDone,
  }) async {
    final subjects = _prioritized(getSubjectsForChild(child));

    // Quiz-Fächer in Concurrency-Batches laden
    for (int i = 0; i < subjects.length; i += _subjectConcurrency) {
      final batch = subjects.skip(i).take(_subjectConcurrency).toList();
      await Future.wait(
        batch.map((subjectConfig) async {
          final guardKey = '${child.id}|${subjectConfig.subject}';

          // Session-Guard: Schon mal gemacht? Überspringen.
          if (_sessionPrefetchDone.contains(guardKey)) {
            onSubjectDone?.call(child.name, subjectConfig.subject);
            return;
          }

          try {
            await cache.prefillIfEmpty(
              userId: userId,
              childId: child.id,
              child: child,
              subject: subjectConfig.subject,
            );
            _sessionPrefetchDone.add(guardKey);
            onSubjectDone?.call(child.name, subjectConfig.subject);
          } catch (e) {
            debugPrint('⚠️ ${child.name} / ${subjectConfig.title}: $e');
          }
        }),
      );
    }

    debugPrint('✅ ${child.name}: Quiz-Fächer bereit');
  }

  // ============================================================
  // EINZELNES KIND (für Dashboard-Fallback und Kind-Erstellung)
  // ============================================================

  /// Prefetch für ein einzelnes Kind.
  /// Nutzt denselben Session-Guard wie prefetchAllChildren.
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

    await _prefetchChildParallel(
      userId: userId,
      child: child,
      cache: effectiveCache,
    );
  }

  /// Session-Guard manuell zurücksetzen — z.B. nach einem Level-Up damit
  /// die neuen Level-Fragen sofort nachgeladen werden.
  static void invalidateSessionGuard(String childId, [String? subject]) {
    if (subject != null) {
      _sessionPrefetchDone.removeWhere(
        (k) => k.startsWith('$childId|$subject'),
      );
    } else {
      _sessionPrefetchDone.removeWhere((k) => k.startsWith('$childId|'));
    }
    debugPrint(
      '🔄 Session-Guard invalidiert: $childId ${subject ?? "(alle Fächer)"}',
    );
  }
}

final quizPrefetchServiceProvider = Provider<QuizPrefetchService>((ref) {
  return QuizPrefetchService();
});
