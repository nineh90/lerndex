import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Schickt [batch] ab und wartet höchstens [wait] auf die Bestätigung vom
/// Server.
///
/// Firestore übernimmt Schreibvorgänge sofort in den lokalen Cache; das
/// Future von `commit()` endet aber erst, wenn der Server bestätigt hat –
/// offline also erst Minuten oder Stunden später. Wer darauf wartet, hängt.
/// Deshalb: kurz warten (online kommen so Fehler wie fehlende Rechte noch
/// beim Aufrufer an), danach gilt der Batch als lokal übernommen.
///
/// Scheitert der Batch erst nach dem Warten, wird [onLateError] aufgerufen.
Future<void> commitOfflineTolerant(
  WriteBatch batch, {
  Duration wait = const Duration(seconds: 3),
  void Function(Object error)? onLateError,
}) async {
  final commit = batch.commit();
  var timedOut = false;
  try {
    await commit.timeout(wait);
  } on TimeoutException {
    timedOut = true;
  }
  if (timedOut) {
    debugPrint('📴 Firestore: Batch lokal gespeichert, wird nachgereicht');
    unawaited(
      commit.catchError((Object e) {
        debugPrint('❌ Firestore: Batch später abgelehnt: $e');
        onLateError?.call(e);
      }),
    );
  }
}
