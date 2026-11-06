import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Eine Stimme der Sprachausgabe im Browser.
typedef WebVoice = ({String name, String lang, bool localService});

/// Alle Stimmen des Browsers mit `localService` (true = spricht auf dem
/// Gerät, false = schickt den Text an einen Server, z.B. „Google Deutsch“ in
/// Chrome). Chrome lädt die Liste erst nach dem Start – bis zu 2 s warten.
Future<List<WebVoice>> browserVoices() async {
  final synth = web.window.speechSynthesis;
  var voices = synth.getVoices().toDart;
  if (voices.isEmpty) {
    final loaded = Completer<void>();
    synth.onvoiceschanged = ((web.Event _) {
      if (!loaded.isCompleted) loaded.complete();
    }).toJS;
    await loaded.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    synth.onvoiceschanged = null;
    voices = synth.getVoices().toDart;
  }
  return [
    for (final v in voices)
      (name: v.name, lang: v.lang, localService: v.localService),
  ];
}
