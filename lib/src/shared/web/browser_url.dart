// Browser-Hilfen (Adresszeile, Druck-Tab). In den Apps ohne
// Wirkung (package:web gibt es dort nicht, daher der bedingte Export).
export 'browser_url_stub.dart'
    if (dart.library.js_interop) 'browser_url_web.dart';
