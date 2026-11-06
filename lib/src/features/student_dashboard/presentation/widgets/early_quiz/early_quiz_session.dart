import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lerndex/src/features/learning_time/learning_time_tracker.dart';
import 'package:lerndex/src/features/quiz/presentation/quiz_finish_service.dart';

// ============================================================================
// EARLY QUIZ SESSION – Wertung und Abschluss der Quizze für Klasse 1–2
// (Zahlen, Buchstaben, Farben & Formen).
// ============================================================================

/// Wertung eines Quiz: zählt nur Aufgaben, die beim ERSTEN Versuch richtig
/// waren. Wer nach „Nochmal“ rät, bis es passt, bekommt kein perfektes Quiz
/// (und damit keine Perfekt-Belohnung), aber trotzdem ein paar XP fürs
/// Dranbleiben.
class EarlyQuizScore {
  EarlyQuizScore(this.taskCount)
    : stepResults = List<bool?>.filled(taskCount, null),
      _attempts = List<int>.filled(taskCount, 0);

  /// XP für eine Aufgabe, die beim ersten Versuch richtig war.
  static const int xpFirstTry = 3;

  /// XP für eine Aufgabe, die erst nach „Nochmal“ richtig war.
  static const int xpLaterTry = 1;

  /// Ab so vielen richtigen Aufgaben gibt es die Schatzkiste.
  static const int treasureThreshold = 4;

  final int taskCount;

  /// Ergebnis je Aufgabe für Fortschrittsbalken und Abschluss-Liste:
  /// `true` = beim ersten Versuch richtig, `false` = mindestens einmal
  /// falsch, `null` = offen bzw. übersprungen.
  final List<bool?> stepResults;

  final List<int> _attempts;
  int _correctCount = 0;
  int _earnedXP = 0;

  /// Beim ersten Versuch richtig gelöste Aufgaben.
  int get correctCount => _correctCount;

  /// Bisher verdiente XP (werden erst beim Abschluss geschrieben).
  int get earnedXP => _earnedXP;

  bool get isPerfect => taskCount > 0 && _correctCount == taskCount;

  bool get earnsTreasure => _correctCount >= treasureThreshold;

  /// Wurde bei Aufgabe [index] schon ein Versuch gewertet?
  bool hasAttempted(int index) => _attempts[index] > 0;

  /// Wertet eine Antwort für Aufgabe [index]. Gibt die XP zurück, die diese
  /// Antwort bringt.
  int record(int index, {required bool correct}) {
    final firstTry = _attempts[index] == 0;
    _attempts[index]++;
    stepResults[index] = correct && firstTry;
    if (!correct) return 0;
    if (firstTry) _correctCount++;
    final xp = firstTry ? xpFirstTry : xpLaterTry;
    _earnedXP += xp;
    return xp;
  }

  /// Ein Fehlversuch, der noch keine Antwort ist (z.B. Zeichnung nicht
  /// erkannt, Kind malt neu). Die Aufgabe zählt danach nicht mehr als
  /// „beim ersten Versuch richtig“.
  void markFailedAttempt(int index) => _attempts[index]++;

  /// „Nochmal“: Aufgabe wieder offen anzeigen. Der Fehlversuch bleibt.
  void retry(int index) => stepResults[index] = null;

  /// Aufgabe ohne Wertung überspringen (z.B. Malprüfung nicht erreichbar).
  void skip(int index) => stepResults[index] = null;
}

/// Abschluss eines Quiz unabhängig vom Widget-Lebenszyklus.
///
/// - [start] sobald die letzte Aufgabe beantwortet ist (noch vor der
///   Schatzkiste): schreibt XP, Streak, Lernzeit, Quiz-Statistik und prüft
///   Belohnungen – auch wenn das Kind danach sofort „Home“ tippt oder per
///   Zurück-Geste geht.
/// - [present], sobald der Abschluss-Bildschirm steht: zeigt Popups.
/// - [onDispose] im `dispose()` des Bildschirms: rettet bei Abbruch XP und
///   Lernzeit; war das Quiz fertig, kommen die Popups notfalls auf dem
///   Bildschirm, auf dem das Kind jetzt ist.
class EarlyQuizFinish {
  EarlyQuizFinish({
    required this.userId,
    required this.childId,
    this.timeTracker,
  });

  final String userId;
  final String childId;
  final LearningTimeTracker? timeTracker;

  Future<QuizFinishResult?>? _future;
  DateTime? _startedAt;
  bool _presented = false;

  bool get started => _future != null;

  /// Startet den Abschluss (nur einmal).
  void start(WidgetRef ref, {required bool isPerfect, required int earnedXP}) {
    if (_future != null) return;
    _startedAt = DateTime.now();
    _future = QuizFinishService.finish(
      ref: ref,
      userId: userId,
      childId: childId,
      isPerfect: isPerfect,
      earnedXP: earnedXP,
      timeTracker: timeTracker,
    );
  }

  /// Zeigt Belohnungs-/Streak-Popups, sobald der Abschluss fertig ist.
  /// [context] liefert den aktuellen Kontext des Bildschirms oder `null`,
  /// wenn der nicht mehr da ist.
  void present(BuildContext? Function() context) {
    final future = _future;
    if (future == null || _presented) return;
    _presented = true;
    final startedAt = _startedAt ?? DateTime.now();
    unawaited(
      future.then((result) {
        if (result == null) return;
        final ctx = context();
        if (ctx != null && !ctx.mounted) return;
        // Ohne eigenen Bildschirm nur, solange das Quiz gerade erst vorbei
        // ist – nicht Minuten später (offline) mitten in etwas anderem.
        if (ctx == null &&
            DateTime.now().difference(startedAt) > const Duration(minutes: 1)) {
          return;
        }
        QuizFinishService.showPopups(ctx, result);
      }),
    );
  }

  /// Aus `dispose()` aufrufen. [pendingXP]: bis zum Abbruch verdiente XP.
  void onDispose({required int pendingXP}) {
    if (_future == null) {
      // Abbruch mitten im Quiz: XP und Lernzeit retten (best effort,
      // offline-tauglich, ohne Streak und ohne Quiz-Zählung).
      final tracker = timeTracker;
      tracker?.stopTracking();
      unawaited(
        QuizProgressWriter(FirebaseFirestore.instance).write(
          userId: userId,
          childId: childId,
          earnedXP: pendingXP,
          countQuiz: false,
          timeTracker: tracker,
        ),
      );
      return;
    }
    present(() => null);
  }
}
