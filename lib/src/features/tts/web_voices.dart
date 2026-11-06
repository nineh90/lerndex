// Stimmen des Browsers (Web Speech API). In den Apps ohne Wirkung
// (package:web gibt es dort nicht, daher der bedingte Export).
export 'web_voices_stub.dart'
    if (dart.library.js_interop) 'web_voices_web.dart';
