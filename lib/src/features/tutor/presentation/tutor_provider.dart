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
  static String detectTopic(String text) {
    final q = text.toLowerCase().trim();

    // ── MATHEMATIK ───────────────────────────────────────────────────────────
    if (q.contains('mathe') || q.contains('mathematik')) return 'Mathematik';
    if (RegExp(r'\d+\s*[\+\-\*\/×÷]\s*\d+').hasMatch(q)) return 'Mathematik';
    if (RegExp(r'\d+\s*(mal|durch|plus|minus|geteilt)\s*\d+').hasMatch(q)) return 'Mathematik';
    if (RegExp(r'wie viel[e]? (ist|sind|macht|ergibt|gibt)').hasMatch(q) && RegExp(r'\d').hasMatch(q)) return 'Mathematik';
    if (q.contains('rechnen') || q.contains('berechne') || q.contains('ausrechnen') || q.contains('berechnen')) return 'Mathematik';
    if (q.contains('plus') || q.contains('minus') || q.contains(' mal ') || q.contains('geteilt') || q.contains('dividier') || q.contains('multiplizier')) return 'Mathematik';
    if (q.contains('bruch') || q.contains('nenner') || q.contains('zähler') || q.contains('prozent') || q.contains('dezimal') || q.contains('kommazahl')) return 'Mathematik';
    if (q.contains('gleichung') || q.contains('variable') || q.contains('ungleichung')) return 'Mathematik';
    if (q.contains('dreieck') || q.contains('kreis') || q.contains('quadrat') || q.contains('rechteck') || q.contains('fläche') || q.contains('umfang') || q.contains('volumen') || q.contains('geometrie')) return 'Mathematik';
    if (q.contains('wurzel') || q.contains('potenz') || q.contains('hoch ') || q.contains('quadriert')) return 'Mathematik';
    if (q.contains('einmaleins') || q.contains('dreisatz') || q.contains('kopfrechnen')) return 'Mathematik';
    if (q.contains('addition') || q.contains('subtraktion') || q.contains('multiplikation') || q.contains('division')) return 'Mathematik';
    if (q.contains('wahrscheinlichkeit') || q.contains('statistik') || q.contains('diagramm') || q.contains('stochastik')) return 'Mathematik';
    if (q.contains('funktion') && (q.contains('график') || q.contains('steigung') || q.contains('achse') || q.contains('x-wert') || q.contains('y-wert'))) return 'Mathematik';
    if (q.contains('pythagoras') || q.contains('trigonometrie') || q.contains('sinus') || q.contains('kosinus') || q.contains('tangens')) return 'Mathematik';

    // ── PHYSIK ───────────────────────────────────────────────────────────────
    if (q.contains('physik')) return 'Physik';
    if (q.contains('kraft') && (q.contains('newt') || q.contains('masse') || q.contains('beschleunig'))) return 'Physik';
    if (q.contains('geschwindigkeit') || q.contains('beschleunigung') || q.contains('trägheit')) return 'Physik';
    if (q.contains('elektrizität') || q.contains('elektrisch') || q.contains('strom') && (q.contains('volt') || q.contains('ampere') || q.contains('widerstand') || q.contains('spannung'))) return 'Physik';
    if (q.contains('magnetismus') || q.contains('magnetfeld') || q.contains('elektromagnet')) return 'Physik';
    if (q.contains('licht') && (q.contains('brechung') || q.contains('reflex') || q.contains('welle') || q.contains('spektrum'))) return 'Physik';
    if (q.contains('schall') || q.contains('schallwelle') || q.contains('frequenz') || q.contains('lautstärke') || q.contains('dezibel')) return 'Physik';
    if (q.contains('wärme') && (q.contains('temperatur') || q.contains('ausdehnung') || q.contains('leitung'))) return 'Physik';
    if (q.contains('energie') && (q.contains('kinetisch') || q.contains('potenziel') || q.contains('arbeit') || q.contains('leistung') || q.contains('joule'))) return 'Physik';
    if (q.contains('hebelgesetz') || q.contains('hebel') && q.contains('kraft')) return 'Physik';
    if (q.contains('druck') && (q.contains('pascal') || q.contains('gas') || q.contains('flüssig') || q.contains('atmo'))) return 'Physik';
    if (q.contains('atom') && (q.contains('kern') || q.contains('elektron') || q.contains('proton') || q.contains('neutron'))) return 'Physik';
    if (q.contains('radioaktiv') || q.contains('strahlung') && (q.contains('alpha') || q.contains('beta') || q.contains('gamma'))) return 'Physik';
    if (q.contains('newton') || q.contains('joule') || q.contains('watt') && q.contains('einheit')) return 'Physik';
    if (q.contains('optik') || q.contains('linse') || q.contains('spiegel') && q.contains('licht')) return 'Physik';
    if (q.contains('schwingung') || q.contains('pendel') || q.contains('welle') && (q.contains('länge') || q.contains('amplitude'))) return 'Physik';
    if (q.contains('auftrieb') || q.contains('schwimmen') && q.contains('sinken') && q.contains('physik')) return 'Physik';
    if (q.contains('gravitationsgesetz') || q.contains('gravitation') || q.contains('schwerkraft')) return 'Physik';

    // ── CHEMIE ───────────────────────────────────────────────────────────────
    if (q.contains('chemie') || q.contains('chemisch')) return 'Chemie';
    if (q.contains('atom') && (q.contains('bindung') || q.contains('molekül') || q.contains('reaktion'))) return 'Chemie';
    if (q.contains('molekül') || q.contains('verbindung') && q.contains('stoff')) return 'Chemie';
    if (q.contains('element') && (q.contains('periodensystem') || q.contains('symbol') || q.contains('stoff'))) return 'Chemie';
    if (q.contains('periodensystem') || q.contains('periode') && q.contains('gruppe') && q.contains('element')) return 'Chemie';
    if (q.contains('säure') || q.contains('base') && q.contains('ph') || q.contains('ph-wert')) return 'Chemie';
    if (q.contains('oxidation') || q.contains('reduktion') || q.contains('redox')) return 'Chemie';
    if (q.contains('reaktion') && (q.contains('verbrennungsreaktion') || q.contains('exotherm') || q.contains('endotherm'))) return 'Chemie';
    if (q.contains('aggregatzustand') || q.contains('schmelzen') && (q.contains('stoff') || q.contains('punkte')) || q.contains('siedepunkt')) return 'Chemie';
    if (q.contains('gemisch') || q.contains('lösung') && q.contains('stoff') || q.contains('löslich')) return 'Chemie';
    if (q.contains('kohlenstoff') || q.contains('sauerstoff') || q.contains('wasserstoff') || q.contains('stickstoff') || q.contains('chlor') || q.contains('natrium')) return 'Chemie';
    if (q.contains('verbrennung') && (q.contains('sauerstoff') || q.contains('reaktion'))) return 'Chemie';
    if (q.contains('ionen') || q.contains('ionenbindung') || q.contains('kovalente')) return 'Chemie';
    if (q.contains('organisch') || q.contains('kohlenwasserstoff') || q.contains('alkohol') && q.contains('stoff')) return 'Chemie';

    // ── BIOLOGIE ─────────────────────────────────────────────────────────────
    if (q.contains('biologie') || q.contains('biologisch')) return 'Biologie';
    if (q.contains('zelle') && (q.contains('kern') || q.contains('membran') || q.contains('teilung') || q.contains('organell'))) return 'Biologie';
    if (q.contains('dna') || q.contains('gen') && (q.contains('erbgut') || q.contains('chromosom') || q.contains('vererbung')) || q.contains('genetik')) return 'Biologie';
    if (q.contains('evolution') || q.contains('darw') || q.contains('artbildung') || q.contains('mutation')) return 'Biologie';
    if (q.contains('ökosystem') || q.contains('nahrungskette') || q.contains('ökologie') || q.contains('lebensraum')) return 'Biologie';
    if (q.contains('fotosynthese') || q.contains('photosynthese') || q.contains('chlorophyll') || q.contains('chloroplast')) return 'Biologie';
    if (q.contains('atmung') && (q.contains('zelle') || q.contains('pflanze') || q.contains('sauerstoff'))) return 'Biologie';
    if (q.contains('mitose') || q.contains('meiose') || q.contains('zellteilung')) return 'Biologie';
    if (q.contains('virus') || q.contains('bakterie') || q.contains('pilz') && q.contains('lebewesen')) return 'Biologie';
    if (q.contains('immunsystem') || q.contains('antikörper') || q.contains('impfung') && q.contains('körper')) return 'Biologie';

    // ── ENGLISCH ─────────────────────────────────────────────────────────────
    if (q.contains('englisch') || q.contains('english')) return 'Englisch';
    if (q.contains('übersetze') || q.contains('übersetzung') || q.contains('auf englisch')) return 'Englisch';
    if (q.contains('past tense') || q.contains('present tense') || q.contains('future tense') || q.contains('simple past') || q.contains('present perfect') || q.contains('past perfect') || q.contains('present simple') || q.contains('present continuous')) return 'Englisch';
    if (q.contains('irregular') || q.contains('unregelmäßig') && q.contains('verb')) return 'Englisch';
    if (q.contains('vokabel') || q.contains('vokabeln') || q.contains('vocabulary')) return 'Englisch';
    if (q.split(' ').length >= 4 && RegExp(r'\b(what|how|why|when|where|who|which|the |is |are |was |were |have |has |had |will |would |can |could |should |do |does |did )\b').hasMatch(q)) return 'Englisch';

    // ── DEUTSCH ──────────────────────────────────────────────────────────────
    if (q.contains('deutschstunde') || q.contains('im deutschen')) return 'Deutsch';
    if (q.contains('grammatik') || q.contains('rechtschreibung')) return 'Deutsch';
    if (q.contains('nomen') || q.contains('substantiv') || q.contains('adjektiv') || q.contains('adverb') || q.contains('pronomen') || q.contains('präposition') || q.contains('konjunktion')) return 'Deutsch';
    if (q.contains('konjugier') || q.contains('konjugation') || q.contains('zeitform') || q.contains('präteritum') || q.contains('plusquamperfekt') || q.contains('futur') && !q.contains('future')) return 'Deutsch';
    if (q.contains('nominativ') || q.contains('genitiv') || q.contains('dativ') || q.contains('akkusativ')) return 'Deutsch';
    if (q.contains('hauptsatz') || q.contains('nebensatz') || q.contains('satzzeichen') || q.contains('interpunktion')) return 'Deutsch';
    if (q.contains('komma') && (q.contains('satz') || q.contains('regel'))) return 'Deutsch';
    if (q.contains('großschreib') || q.contains('kleinschreib')) return 'Deutsch';
    if (q.contains('aufsatz') || q.contains('gedicht') || q.contains('strophe') || q.contains('reim')) return 'Deutsch';
    if (q.contains('silbe') || q.contains('wortart') || q.contains('vorsilbe') || q.contains('nachsilbe')) return 'Deutsch';
    if (q.contains('komparativ') || q.contains('superlativ')) return 'Deutsch';
    if (q.contains('verb') && !q.contains('englisch') && !q.contains('english') && !q.contains('tense') && !q.contains('irregular')) return 'Deutsch';
    if (q.contains(' satz') && !q.contains('dreisatz') && !q.contains('pythagoras')) return 'Deutsch';

    // ── GESCHICHTE ───────────────────────────────────────────────────────────
    if (q.contains('geschichte') && !q.contains('lebens')) return 'Geschichte';
    if (q.contains('weltkrieg') || q.contains('erster krieg') || q.contains('zweiter krieg')) return 'Geschichte';
    if (q.contains('römer') || q.contains('römisch') || q.contains('römisches reich') || q.contains('antike')) return 'Geschichte';
    if (q.contains('mittelalter') || q.contains('ritter') && (q.contains('burg') || q.contains('historisch')) || q.contains('kreuzzug')) return 'Geschichte';
    if (q.contains('französisch') && q.contains('revolution') || q.contains('französische revolution')) return 'Geschichte';
    if (q.contains('nationalsozialismu') || q.contains('nazi') || q.contains('hitler') || q.contains('drittes reich') || q.contains('holocaust') || q.contains('weimarer republik')) return 'Geschichte';
    if (q.contains('kalter krieg') || q.contains('mauerfall') || q.contains('deutsche teilung') || q.contains('wiedervereinigung') && q.contains('deutsch')) return 'Geschichte';
    if (q.contains('pharao') || q.contains('ägypten') && (q.contains('alt') || q.contains('hieroglyphe') || q.contains('pyramide')) || q.contains('altes ägypten')) return 'Geschichte';
    if (q.contains('griechisch') && (q.contains('antik') || q.contains('polis') || q.contains('demokratie') && q.contains('athen'))) return 'Geschichte';
    if (q.contains('french revolution') || q.contains('historisch') && (q.contains('wann') || q.contains('warum'))) return 'Geschichte';
    if (q.contains('kolonie') || q.contains('kolonialismus') || q.contains('imperialismus') && q.contains('historisch')) return 'Geschichte';
    if (q.contains('reformation') || q.contains('luther') && q.contains('kirch')) return 'Geschichte';
    if (q.contains('industrie') && q.contains('revolution') && !q.contains('physik')) return 'Geschichte';
    if (q.contains('bismarck') || q.contains('wilhelmin') || q.contains('kaiserreich') && q.contains('deutsch')) return 'Geschichte';

    // ── GEOGRAPHIE / ERDKUNDE ────────────────────────────────────────────────
    if (q.contains('geographie') || q.contains('erdkunde') || q.contains('geografie')) return 'Geographie';
    if (q.contains('kontinent') || q.contains('weltkarte') || q.contains('atlas') && q.contains('karte')) return 'Geographie';
    if (q.contains('hauptstadt') || q.contains('land') && (q.contains('grenzt') || q.contains('liegt in') || q.contains('wo liegt'))) return 'Geographie';
    if (q.contains('fluss') && (q.contains('länge') || q.contains('mündet') || q.contains('quelle') || q.contains('verlauf')) || q.contains('rhein') || q.contains('donau') || q.contains('nil') || q.contains('amazon') && q.contains('fluss')) return 'Geographie';
    if (q.contains('gebirge') || q.contains('berg') && (q.contains('hoch') || q.contains('alpen') || q.contains('höhe')) || q.contains('himalaya') || q.contains('everest')) return 'Geographie';
    if (q.contains('klimazone') || q.contains('klima') && (q.contains('tropen') || q.contains('wüste') || q.contains('polar') || q.contains('gemäßigt'))) return 'Geographie';
    if (q.contains('vulkan') || q.contains('erdbeben') && !q.contains('physik') || q.contains('plattentektonik') || q.contains('erdplatten')) return 'Geographie';
    if (q.contains('bevölkerung') && (q.contains('dicht') || q.contains('wachstum') || q.contains('land')) || q.contains('einwohner') && q.contains('land')) return 'Geographie';
    if (q.contains('tropen') || q.contains('wüste') && (q.contains('sahara') || q.contains('entsteht') || q.contains('klima'))) return 'Geographie';

    // ── SACHKUNDE ────────────────────────────────────────────────────────────
    if (q.contains('sachkunde') || q.contains('sachunterricht')) return 'Sachkunde';
    if (q.contains('pflanze') || q.contains('blume') || q.contains('baum') && q.contains('wächst')) return 'Sachkunde';
    if (q.contains('tier ') || q.contains('tiere') || q.contains('tierart')) return 'Sachkunde';
    if (q.contains('insekt') || q.contains('schmetterling') || q.contains('biene') || q.contains('käfer') || q.contains('vogel') || q.contains('säugetier')) return 'Sachkunde';
    if (q.contains('jahreszeit') || q.contains('frühling') || q.contains('herbst') && !q.contains('olymp')) return 'Sachkunde';
    if (q.contains('körper') && (q.contains('organ') || q.contains('wie funktioniert')) || q.contains('herzschlag') || q.contains('blutkreislauf') || q.contains('lunge') || q.contains('knochen')) return 'Sachkunde';
    if (q.contains('umwelt') || q.contains('recycling') || q.contains('naturschutz') || q.contains('klimawandel') && !q.contains('geographie')) return 'Sachkunde';
    if (q.contains('planet') || q.contains('sonnensystem') || q.contains('weltall') || q.contains('galaxie')) return 'Sachkunde';
    if (q.contains('magnet') || q.contains('elektrizität') && !q.contains('physik')) return 'Sachkunde';
    if (q.contains('verkehr') || q.contains('ampel') || q.contains('verkehrszeichen')) return 'Sachkunde';
    if (q.contains('gesund') && !q.contains('rechnung') || q.contains('ernährung') || q.contains('vitamin') || q.contains('nährstoff')) return 'Sachkunde';

    // ── INFORMATIK ───────────────────────────────────────────────────────────
    if (q.contains('informatik') || q.contains('programmier') || q.contains('coding') || q.contains('code') && q.contains('schul')) return 'Informatik';
    if (q.contains('algorithmus') || q.contains('schleife') && q.contains('programmier') || q.contains('variable') && q.contains('programmier')) return 'Informatik';

    // ── MUSIK ────────────────────────────────────────────────────────────────
    if (q.contains('musik') && (q.contains('note') || q.contains('takt') || q.contains('rhythmus') || q.contains('instrument') || q.contains('tonleiter'))) return 'Musik';
    if (q.contains('tonleiter') || q.contains('dur') && q.contains('moll') || q.contains('akkord') && q.contains('musik')) return 'Musik';

    // ── KUNST ────────────────────────────────────────────────────────────────
    if (q.contains('kunst') && (q.contains('farb') || q.contains('mal') || q.contains('zeichn') || q.contains('perspektive') || q.contains('schatt'))) return 'Kunst';
    if (q.contains('farblehre') || q.contains('primärfarbe') || q.contains('komplementärfarbe')) return 'Kunst';

    // ── LATEIN ───────────────────────────────────────────────────────────────
    if (q.contains('latein') || q.contains('lateinisch') || q.contains('dekliniere') || q.contains('konjugiere') && q.contains('latein')) return 'Latein';
    if (q.contains('nominativ') && q.contains('latein') || q.contains('ablativ') || q.contains('akkusativ') && q.contains('latein')) return 'Latein';

    // ── FRANZÖSISCH ──────────────────────────────────────────────────────────
    if (q.contains('französisch') && !q.contains('revolution') || q.contains('français') || q.contains('bonjour') && q.contains('lern')) return 'Französisch';

    // ── SPANISCH ─────────────────────────────────────────────────────────────
    if (q.contains('spanisch') || q.contains('español') || q.contains('hola') && q.contains('lern')) return 'Spanisch';

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