import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/chat_message.dart';
import '../../auth/presentation/active_child_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../../ai/firebase_ai_service.dart';

class TutorNotifier extends StateNotifier<List<ChatMessage>> {
  TutorNotifier(
      this._aiService,
      this._ref,
      this._childId,
      this._userId,
      ) : super([]) {
    _initializeWithWelcome();
  }

  final FirebaseAIService _aiService;
  final Ref _ref;
  final String _childId;
  final String _userId;
  bool _isAIInitialized = false;
  bool _isLoadingHistory = false;
  String? _currentSessionId;
  bool _hasUserSentMessage = false;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  void _initializeWithWelcome() {
    final child = _ref.read(activeChildProvider);
    if (child == null) return;

    final welcomeMessage = ChatMessage.tutor(
      'Hallo ${child.name}! 👋 Ich bin **Lerndex**, dein persönlicher Lernbegleiter! 🎓 Ich helfe dir bei allen Fragen zu Mathe, Deutsch, Englisch und anderen Schulfächern. Was möchtest du heute lernen? 📚✨',
    );

    state = [welcomeMessage];
    _loadChatHistoryInBackground();
  }

  Future<void> _loadChatHistoryInBackground() async {
    if (_isLoadingHistory) return;
    _isLoadingHistory = true;

    try {
      print('📚 Lade Chat-Historie für Kind $_childId im Hintergrund...');

      final sessionSnapshot = await _firestore
          .collection('users')
          .doc(_userId)
          .collection('children')
          .doc(_childId)
          .collection('tutor_sessions')
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (sessionSnapshot.docs.isEmpty) {
        print('   → Keine aktive Session, warte auf erste User-Nachricht');
        return;
      }

      _currentSessionId = sessionSnapshot.docs.first.id;
      print('   → Aktive Session gefunden: $_currentSessionId');

      final messagesSnapshot = await _firestore
          .collection('users')
          .doc(_userId)
          .collection('children')
          .doc(_childId)
          .collection('tutor_sessions')
          .doc(_currentSessionId)
          .collection('messages')
          .orderBy('timestamp', descending: false)
          .limit(50)
          .get();

      if (messagesSnapshot.docs.isEmpty) {
        print('   → Keine Nachrichten in Session, behalte Begrüßung');
        return;
      }

      print('   → ${messagesSnapshot.docs.length} Nachrichten gefunden');

      final messages = messagesSnapshot.docs.map((doc) {
        final data = doc.data();
        return ChatMessage(
          id: doc.id,
          text: data['text'] ?? '',
          isUser: data['isUser'] ?? false,
          timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
        );
      }).toList();

      if (messages.length > 1) {
        state = messages;
        _hasUserSentMessage = true;
        print('✅ Chat-Historie geladen und angezeigt');
      }
    } catch (e) {
      print('⚠️ Fehler beim Laden der Historie: $e');
    } finally {
      _isLoadingHistory = false;
    }
  }

  Future<void> _ensureAIInitialized() async {
    if (_isAIInitialized) return;

    try {
      print('🚀 Initialisiere AI Service...');
      await _aiService.initialize();
      _isAIInitialized = true;
      print('✅ AI Service bereit');
    } catch (e) {
      print('❌ Fehler bei AI-Initialisierung: $e');
      rethrow;
    }
  }

  Future<String> _getOrCreateSession() async {
    if (_currentSessionId != null) {
      return _currentSessionId!;
    }

    try {
      final sessionSnapshot = await _firestore
          .collection('users')
          .doc(_userId)
          .collection('children')
          .doc(_childId)
          .collection('tutor_sessions')
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (sessionSnapshot.docs.isNotEmpty) {
        _currentSessionId = sessionSnapshot.docs.first.id;
        print('✅ Aktive Session gefunden: $_currentSessionId');
      } else {
        final sessionDoc = await _firestore
            .collection('users')
            .doc(_userId)
            .collection('children')
            .doc(_childId)
            .collection('tutor_sessions')
            .add({
          'childId': _childId,
          'startedAt': Timestamp.fromDate(DateTime.now()),
          'status': 'active',
          'messageCount': 0,
        });
        _currentSessionId = sessionDoc.id;
        print('✅ Neue Session erstellt: $_currentSessionId');
      }

      return _currentSessionId!;
    } catch (e) {
      print('❌ Fehler bei Session-Erstellung: $e');
      rethrow;
    }
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final child = _ref.read(activeChildProvider);
    if (child == null) return;

    if (!_isAIInitialized) {
      try {
        await _ensureAIInitialized();
      } catch (e) {
        final errorMessage = ChatMessage.tutor(
          'Entschuldigung, ich hatte Probleme beim Starten. Versuch es gleich nochmal! 😊',
        );
        state = [...state, errorMessage];
        return;
      }
    }

    _hasUserSentMessage = true;

    final userMessage = ChatMessage.user(text);
    state = [...state, userMessage];
    _saveChatMessage(userMessage);

    state = [...state, ChatMessage.loading()];

    try {
      final response = await _aiService.sendTutorMessage(
        child: child,
        userMessage: text,
        conversationHistory: state.where((m) => !m.isLoading).toList(),
      );

      final tutorMessage = ChatMessage.tutor(response);

      state = [
        ...state.where((m) => !m.isLoading),
        tutorMessage,
      ];

      _saveChatMessage(tutorMessage);
    } catch (e) {
      print('❌ Fehler beim Senden der Nachricht: $e');

      final errorMessage = ChatMessage.tutor(
        'Ups, da ist etwas schiefgelaufen. Versuch es nochmal! 😅',
      );

      state = [
        ...state.where((m) => !m.isLoading),
        errorMessage,
      ];

      _saveChatMessage(errorMessage);
    }
  }

  Future<void> _saveChatMessage(ChatMessage message) async {
    if (message.isLoading) return;

    try {
      final messageData = {
        'text': message.text,
        'isUser': message.isUser,
        'timestamp': Timestamp.fromDate(DateTime.now()),
      };

      final sessionId = await _getOrCreateSession();

      await _firestore
          .collection('users')
          .doc(_userId)
          .collection('children')
          .doc(_childId)
          .collection('tutor_sessions')
          .doc(sessionId)
          .collection('messages')
          .add(messageData);

      await _firestore
          .collection('users')
          .doc(_userId)
          .collection('children')
          .doc(_childId)
          .collection('tutor_sessions')
          .doc(sessionId)
          .update({
        'messageCount': FieldValue.increment(1),
      });

      if (message.isUser) {
        final sessionDoc = await _firestore
            .collection('users')
            .doc(_userId)
            .collection('children')
            .doc(_childId)
            .collection('tutor_sessions')
            .doc(sessionId)
            .get();

        final sessionData = sessionDoc.data();
        final hasFirstQuestion = sessionData?['firstQuestion'] != null;

        if (!hasFirstQuestion) {
          final topic = detectTopic(message.text);
          await _firestore
              .collection('users')
              .doc(_userId)
              .collection('children')
              .doc(_childId)
              .collection('tutor_sessions')
              .doc(sessionId)
              .update({
            'firstQuestion': message.text,
            'detectedTopic': topic,
          });
          print('🎯 Thema erkannt: $topic (aus: "${message.text}")');
        }
      }
    } catch (e) {
      print('⚠️ Fehler beim Speichern: $e');
    }
  }

  /// Erkennt das Schulfach aus dem Text.
  /// Deutlich erweitert – erkennt auch implizite Fragen ohne Fachnennung.
  /// Static damit es auch aus tutor_session_model.dart aufrufbar ist.
  static String detectTopic(String text) {
    final q = text.toLowerCase().trim();

    // ── MATHEMATIK ───────────────────────────────────────────────────────────
    if (q.contains('mathe') || q.contains('mathematik')) return 'Mathematik';
    // Rechenzeichen oder Zahlen mit Operatoren
    if (RegExp(r'\d+\s*[\+\-\*\/×÷]\s*\d+').hasMatch(q)) return 'Mathematik';
    if (RegExp(r'\d+\s*(mal|durch|plus|minus|geteilt)\s*\d+').hasMatch(q)) return 'Mathematik';
    // Typische Kinderfragen mit Zahl + Fragepartikel
    if (RegExp(r'wie viel[e]? (ist|sind|macht|ergibt|gibt)').hasMatch(q) &&
        RegExp(r'\d').hasMatch(q)) return 'Mathematik';
    if (q.contains('rechnen') || q.contains('berechne') || q.contains('ausrechnen') ||
        q.contains('berechnen')) return 'Mathematik';
    if (q.contains('plus') || q.contains('minus') || q.contains(' mal ') ||
        q.contains('geteilt') || q.contains('dividier') || q.contains('multiplizier')) return 'Mathematik';
    if (q.contains('bruch') || q.contains('nenner') || q.contains('zähler') ||
        q.contains('prozent') || q.contains('dezimal') || q.contains('kommazahl')) return 'Mathematik';
    if (q.contains('gleichung') || q.contains('variable') || q.contains('löse ') ||
        q.contains('ungleichung')) return 'Mathematik';
    if (q.contains('dreieck') || q.contains('kreis') || q.contains('quadrat') ||
        q.contains('rechteck') || q.contains('fläche') || q.contains('umfang') ||
        q.contains('volumen') || q.contains('geometrie')) return 'Mathematik';
    if (q.contains('wurzel') || q.contains('potenz') || q.contains('hoch ') ||
        q.contains('quadriert')) return 'Mathematik';
    if (q.contains('einmaleins') || q.contains('einmal eins') ||
        q.contains('kopfrechnen') || q.contains('dreisatz')) return 'Mathematik';
    if (q.contains('addition') || q.contains('subtraktion') ||
        q.contains('multiplikation') || q.contains('division')) return 'Mathematik';
    if (q.contains('zahl') && (q.contains('größ') || q.contains('klein') ||
        q.contains('ordne') || q.contains('runde'))) return 'Mathematik';

    // ── ENGLISCH ─────────────────────────────────────────────────────────────
    if (q.contains('englisch') || q.contains('english')) return 'Englisch';
    if (q.contains('übersetze') || q.contains('übersetzung') ||
        q.contains('auf englisch') || q.contains('auf deutsch') &&
        q.contains('englisch')) return 'Englisch';
    if (q.contains('past tense') || q.contains('present tense') ||
        q.contains('future tense') || q.contains('simple past') ||
        q.contains('present perfect') || q.contains('past perfect') ||
        q.contains('present simple') || q.contains('present continuous')) return 'Englisch';
    if (q.contains('irregular') || q.contains('irregular verb') ||
        q.contains('unregelmäßig') && q.contains('verb')) return 'Englisch';
    if (q.contains('vokabel') || q.contains('vokabeln') ||
        q.contains('vocabulary') || q.contains('word')) return 'Englisch';
    if (q.contains('plural') && (q.contains('english') || q.contains('englisch') ||
        q.contains('wort'))) return 'Englisch';
    // Englische Schlüsselwörter in der Frage (mind. 4 Wörter damit kein Zufall)
    if (q.split(' ').length >= 4 &&
        RegExp(r'\b(what|how|why|when|where|who|which|the |is |are |was |were |have |has |had |will |would |can |could |should |do |does |did )\b').hasMatch(q)) return 'Englisch';

    // ── DEUTSCH ──────────────────────────────────────────────────────────────
    if (q.contains('deutschstunde') || q.contains('im deutschen')) return 'Deutsch';
    if (q.contains('grammatik') || q.contains('rechtschreibung') ||
        q.contains('rechtschreib')) return 'Deutsch';
    if (q.contains('nomen') || q.contains('substantiv') || q.contains('adjektiv') ||
        q.contains('adverb') || q.contains('pronomen') || q.contains('präposition') ||
        q.contains('konjunktion') || q.contains('artikel') && q.contains('wort')) return 'Deutsch';
    if (q.contains('konjugier') || q.contains('konjugation') ||
        q.contains('zeitform') || q.contains('präteritum') || q.contains('perfekt') &&
        !q.contains('present perfect') || q.contains('plusquamperfekt') ||
        q.contains('futur') && !q.contains('future')) return 'Deutsch';
    if (q.contains('nominativ') || q.contains('genitiv') || q.contains('dativ') ||
        q.contains('akkusativ') || q.contains('fall') && q.contains('wort')) return 'Deutsch';
    if (q.contains('hauptsatz') || q.contains('nebensatz') ||
        q.contains('satzzeichen') || q.contains('interpunktion')) return 'Deutsch';
    if (q.contains('komma') && (q.contains('satz') || q.contains('regel') ||
        q.contains('wann') || q.contains('wo'))) return 'Deutsch';
    if (q.contains('großschreib') || q.contains('kleinschreib') ||
        q.contains('groß schreib') || q.contains('klein schreib')) return 'Deutsch';
    if (q.contains('aufsatz') || q.contains('gedicht') || q.contains('strophe') ||
        q.contains('reim')) return 'Deutsch';
    if (q.contains('silbe') || q.contains('wortart') || q.contains('stamm') &&
        q.contains('wort') || q.contains('vorsilbe') || q.contains('nachsilbe')) return 'Deutsch';
    if (q.contains('umlaut') || q.contains('dehnung') || q.contains('schärfung') ||
        q.contains('dehnungs')) return 'Deutsch';
    if (q.contains('buchstabe') && (q.contains('schreib') || q.contains('welch') ||
        q.contains('groß') || q.contains('klein'))) return 'Deutsch';
    if (q.contains('steigerung') || q.contains('komparativ') ||
        q.contains('superlativ')) return 'Deutsch';
    // "Verb" allein ohne Englisch-Kontext → Deutsch
    if (q.contains('verb') && !q.contains('englisch') && !q.contains('english') &&
        !q.contains('tense') && !q.contains('irregular')) return 'Deutsch';
    // "Satz" allein ohne Mathe-Kontext → Deutsch
    if (q.contains(' satz') && !q.contains('dreisatz') && !q.contains('pythagoras')) return 'Deutsch';
    // "Wort" allein ohne Mathe/Englisch-Kontext
    if (q.contains('wort') && !q.contains('vokab') && !q.contains('englisch') &&
        !q.contains('mathe') && q.contains('welch')) return 'Deutsch';

    // ── SACHKUNDE ────────────────────────────────────────────────────────────
    if (q.contains('sachkunde') || q.contains('sachunterricht')) return 'Sachkunde';
    if (q.contains('pflanze') || q.contains('pflanzen') ||
        q.contains('blume') || q.contains('baum') || q.contains('blatt') &&
        q.contains('pflanz')) return 'Sachkunde';
    if (q.contains('tier ') || q.contains(' tier') || q.contains('tiere') ||
        q.contains('das tier') || q.contains('tierart')) return 'Sachkunde';
    if (q.contains('insekt') || q.contains('schmetterling') || q.contains('biene') ||
        q.contains('käfer') || q.contains('vogel') || q.contains('säugetier') ||
        q.contains('reptil') || q.contains('amphibi') || q.contains('fisch') &&
        q.contains('lebewesen')) return 'Sachkunde';
    if (q.contains('wetter') || q.contains('regen') || q.contains('schnee') &&
        !q.contains('spiel') || q.contains('wolke') || q.contains('gewitter') ||
        q.contains('temperatur') && !q.contains('grad') && !q.contains('rechnung')) return 'Sachkunde';
    if (q.contains('jahreszeit') || q.contains('frühling') || q.contains('herbst') &&
        !q.contains('olymp')) return 'Sachkunde';
    if (q.contains('körper') && (q.contains('organ') || q.contains('wie funktioniert') ||
        q.contains('mensch')) || q.contains('herzschlag') || q.contains('blutkreislauf') ||
        q.contains('lunge') || q.contains('knochen') || q.contains('muskel')) return 'Sachkunde';
    if (q.contains('gesund') && !q.contains('rechnung') || q.contains('ernährung') ||
        q.contains('vitamin') || q.contains('nährstoff')) return 'Sachkunde';
    if (q.contains('umwelt') || q.contains('recycling') || q.contains('mülltrennung') ||
        q.contains('naturschutz') || q.contains('klimawandel')) return 'Sachkunde';
    if (q.contains('wasser') && (q.contains('kreislauf') || q.contains('wie') ||
        q.contains('warum') || q.contains('woher'))) return 'Sachkunde';
    if (q.contains('planet') || q.contains('sonnensystem') || q.contains('weltall') ||
        q.contains('mond') && q.contains('erde') || q.contains('asteroid') ||
        q.contains('galaxie')) return 'Sachkunde';
    if (q.contains('magnet') || q.contains('elektrizität') && !q.contains('rechnung') ||
        q.contains('aggregatzustand') || q.contains('verdunstung') ||
        q.contains('kondensation')) return 'Sachkunde';
    if (q.contains('wald') || q.contains('wiese') || q.contains('ökosystem') ||
        q.contains('nahrungskette')) return 'Sachkunde';

    return 'Allgemein';
  }

  Future<void> completeCurrentSession() async {
    if (_currentSessionId == null) return;

    print('🏁 Schließe Session ab: $_currentSessionId');

    try {
      if (!_hasUserSentMessage) {
        print('🗑️ Session war leer (nur Begrüßung) → wird gelöscht');
        await _firestore
            .collection('users')
            .doc(_userId)
            .collection('children')
            .doc(_childId)
            .collection('tutor_sessions')
            .doc(_currentSessionId)
            .delete();
        _currentSessionId = null;
        return;
      }

      await _firestore
          .collection('users')
          .doc(_userId)
          .collection('children')
          .doc(_childId)
          .collection('tutor_sessions')
          .doc(_currentSessionId)
          .update({
        'status': 'completed',
        'endedAt': Timestamp.fromDate(DateTime.now()),
      });

      _currentSessionId = null;
      print('✅ Session abgeschlossen');
    } catch (e) {
      print('❌ Fehler beim Abschließen der Session: $e');
    }
  }

  Future<void> clearChat() async {
    final child = _ref.read(activeChildProvider);
    if (child == null) return;

    print('🔄 Starte neue Chat-Session für ${child.name}...');

    try {
      await completeCurrentSession();

      _hasUserSentMessage = false;

      final welcomeMessage = ChatMessage.tutor(
        'Hallo ${child.name}! 👋 Ich bin **Lerndex**, dein persönlicher Lernbegleiter! 🎓 Ich helfe dir bei allen Fragen zu Mathe, Deutsch, Englisch und anderen Schulfächern. Was möchtest du heute lernen? 📚✨',
      );

      state = [welcomeMessage];
      print('✅ Neue Session bereit (wird bei erster Nachricht erstellt)');
    } catch (e) {
      print('❌ Fehler beim Session-Reset: $e');
    }
  }
}

/// Provider für den Firebase AI Service (Singleton)
final firebaseAIServiceProvider = Provider<FirebaseAIService>((ref) {
  return FirebaseAIService();
});

/// 🎯 FAMILY PROVIDER - Ein Chat pro Kind!
final tutorProviderFamily = StateNotifierProvider.family<TutorNotifier, List<ChatMessage>, String>(
      (ref, childId) {
    final service = ref.watch(firebaseAIServiceProvider);
    final user = ref.watch(authStateChangesProvider).value;

    if (user == null) {
      throw Exception('User nicht eingeloggt');
    }

    return TutorNotifier(service, ref, childId, user.uid);
  },
);

/// 🎯 CONVENIENCE PROVIDER - Automatisch für aktives Kind
final tutorProvider = Provider<StateNotifierProvider<TutorNotifier, List<ChatMessage>>?>((ref) {
  final activeChild = ref.watch(activeChildProvider);

  if (activeChild == null) {
    return null;
  }

  return tutorProviderFamily(activeChild.id);
});