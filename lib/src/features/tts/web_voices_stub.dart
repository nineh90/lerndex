/// Eine Stimme der Sprachausgabe im Browser.
typedef WebVoice = ({String name, String lang, bool localService});

/// Alle Stimmen des Browsers (nur im Browser, sonst leer).
Future<List<WebVoice>> browserVoices() async => const [];
