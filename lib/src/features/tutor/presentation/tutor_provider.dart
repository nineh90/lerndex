import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/chat_message.dart';
import '../data/tutor_session_model.dart'; // ✅ NEU: für TutorSession.detectContentFlag()
import '../../auth/presentation/active_child_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../../ai/firebase_ai_service.dart';

class TutorNotifier extends StateNotifier<List<ChatMessage>> {
  TutorNotifier(this._aiService, this._ref, this._childId, this._userId)
    : super([]) {
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
        return;
      }

      _currentSessionId = sessionSnapshot.docs.first.id;

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
        return;
      }

      final messages = messagesSnapshot.docs.map((doc) {
        final data = doc.data();
        return ChatMessage(
          id: doc.id,
          text: data['text'] ?? '',
          isUser: data['isUser'] ?? false,
          timestamp:
              (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
        );
      }).toList();

      if (messages.length > 1) {
        state = messages;
        _hasUserSentMessage = true;
      }
    } catch (e) {
      // ⚠️ Fehler beim Laden der Historie: $e
    } finally {
      _isLoadingHistory = false;
    }
  }

  Future<void> _ensureAIInitialized() async {
    if (_isAIInitialized) return;

    try {
      await _aiService.initialize();
      _isAIInitialized = true;
    } catch (e) {
      // ❌ Fehler bei AI-Initialisierung: $e
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
        // ✅ Aktive Session gefunden: $_currentSessionId
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
        // ✅ Neue Session erstellt: $_currentSessionId
      }

      return _currentSessionId!;
    } catch (e) {
      // ❌ Fehler bei Session-Erstellung: $e
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

      state = [...state.where((m) => !m.isLoading), tutorMessage];

      _saveChatMessage(tutorMessage);
    } catch (e) {
      // ❌ Fehler beim Senden der Nachricht: $e

      final errorMessage = ChatMessage.tutor(
        'Ups, geht dein Internet? 😅 Frag mich nochmal!',
      );

      state = [...state.where((m) => !m.isLoading), errorMessage];

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
          .update({'messageCount': FieldValue.increment(1)});

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
          final contentFlag = TutorSession.detectContentFlag(message.text);

          final updates = <String, dynamic>{
            'firstQuestion': message.text,
            'detectedTopic': topic,
          };

          if (contentFlag != null) {
            updates['contentFlag'] = contentFlag;
            // 🚩 Content-Flag erkannt: $contentFlag (aus: "${message.text}")',
          }

          await _firestore
              .collection('users')
              .doc(_userId)
              .collection('children')
              .doc(_childId)
              .collection('tutor_sessions')
              .doc(sessionId)
              .update(updates);

          // 🎯 Thema erkannt: $topic (aus: "${message.text}")');
        } else {
          // Wenn bisheriges Topic "Allgemein" war, nochmal versuchen mit neuer Nachricht
          final currentTopic =
              sessionData?['detectedTopic'] as String? ?? 'Allgemein';
          if (currentTopic == 'Allgemein') {
            final newTopic = detectTopic(message.text);
            if (newTopic != 'Allgemein') {
              await _firestore
                  .collection('users')
                  .doc(_userId)
                  .collection('children')
                  .doc(_childId)
                  .collection('tutor_sessions')
                  .doc(sessionId)
                  .update({'detectedTopic': newTopic});
              //🎯 Thema nachträglich erkannt: $newTopic (aus: "${message.text}")',
            }
          }
        }
      }
    } catch (e) {
      // ⚠️ Fehler beim Speichern: $e
    }
  }

  /// Erkennt das Schulfach aus dem Text.
  static String detectTopic(String text) {
    final q = text.toLowerCase().trim();

    // ════════════════════════════════════════════════════════════════════════
    // MATHEMATIK
    // ════════════════════════════════════════════════════════════════════════
    if (q.contains('mathe') || q.contains('mathematik')) return 'Mathematik';
    // Rechenoperationen mit Zahlen
    if (RegExp(r'\d+\s*[\+\-\*\/×÷]\s*\d+').hasMatch(q)) return 'Mathematik';
    if (RegExp(r'\d+\s*(mal|durch|plus|minus|geteilt)\s*\d+').hasMatch(q)) {
      return 'Mathematik';
    }
    if (RegExp(r'wie viel[e]? (ist|sind|macht|ergibt|gibt)').hasMatch(q) &&
        RegExp(r'\d').hasMatch(q)) {
      return 'Mathematik';
    }
    // Grundrechenarten & Arithmetik
    if (q.contains('rechnen') ||
        q.contains('berechne') ||
        q.contains('ausrechnen') ||
        q.contains('berechnen')) {
      return 'Mathematik';
    }
    if (q.contains('addition') ||
        q.contains('subtraktion') ||
        q.contains('multiplikation') ||
        q.contains('division')) {
      return 'Mathematik';
    }
    if (q.contains('plus') ||
        q.contains('minus') ||
        q.contains(' mal ') ||
        q.contains('geteilt') ||
        q.contains('dividier') ||
        q.contains('multiplizier')) {
      return 'Mathematik';
    }
    if (q.contains('einmaleins') ||
        q.contains('dreisatz') ||
        q.contains('kopfrechnen') ||
        q.contains('schriftlich')) {
      return 'Mathematik';
    }
    if (q.contains('ergebnis') && RegExp(r'\d').hasMatch(q)) {
      return 'Mathematik';
    }
    // Brüche, Prozente, Dezimalzahlen
    if (q.contains('bruch') ||
        q.contains('nenner') ||
        q.contains('zähler') ||
        q.contains('gemischte zahl')) {
      return 'Mathematik';
    }
    if (q.contains('prozent') ||
        q.contains('dezimal') ||
        q.contains('kommazahl') ||
        q.contains('promille')) {
      return 'Mathematik';
    }
    if (q.contains('kürzen') ||
        q.contains('erweitern') && q.contains('bruch') ||
        q.contains('gleichnamig')) {
      return 'Mathematik';
    }
    // Algebra & Gleichungen
    if (q.contains('gleichung') ||
        q.contains('ungleichung') ||
        q.contains('löse') && RegExp(r'[x-z]').hasMatch(q)) {
      return 'Mathematik';
    }
    if (q.contains('variable') && !q.contains('programmier') ||
        q.contains('term') &&
            (q.contains('vereinfach') || q.contains('lösung'))) {
      return 'Mathematik';
    }
    if (q.contains('lineares') ||
        q.contains('quadratische gleichung') ||
        q.contains('lgs') ||
        q.contains('gleichungssystem')) {
      return 'Mathematik';
    }
    // Geometrie
    if (q.contains('geometrie') || q.contains('geometrisch')) {
      return 'Mathematik';
    }
    if (q.contains('dreieck') ||
        q.contains('viereck') ||
        q.contains('quadrat') ||
        q.contains('rechteck') ||
        q.contains('raute')) {
      return 'Mathematik';
    }
    if (q.contains('kreis') &&
        (q.contains('fläche') ||
            q.contains('umfang') ||
            q.contains('radius') ||
            q.contains('durchmesser'))) {
      return 'Mathematik';
    }
    if (q.contains('fläche') ||
        q.contains('umfang') ||
        q.contains('flächeninhalt') ||
        q.contains('volumen')) {
      return 'Mathematik';
    }
    if (q.contains('trapez') ||
        q.contains('parallelogramm') ||
        q.contains('rhombus') ||
        q.contains('polygon') ||
        q.contains('sechseck')) {
      return 'Mathematik';
    }
    if (q.contains('kegel') ||
        q.contains('zylinder') ||
        q.contains('kugel') &&
            (q.contains('volumen') || q.contains('oberfläche')) ||
        q.contains('prisma') ||
        q.contains('pyramide') && !q.contains('ägypten')) {
      return 'Mathematik';
    }
    if (q.contains('koordinatensystem') ||
        q.contains('x-achse') ||
        q.contains('y-achse') ||
        q.contains('achse') && q.contains('punkt')) {
      return 'Mathematik';
    }
    if (q.contains('winkel') ||
        q.contains('grad') &&
            (q.contains('winkel') ||
                q.contains('kreis') ||
                q.contains('dreieck'))) {
      return 'Mathematik';
    }
    if (q.contains('symmetrie') ||
        q.contains('spiegelachse') ||
        q.contains('kongruenz') ||
        q.contains('ähnlichkeit')) {
      return 'Mathematik';
    }
    // Potenzen & Wurzeln
    if (q.contains('wurzel') ||
        q.contains('quadratwurzel') ||
        q.contains('kubikwurzel')) {
      return 'Mathematik';
    }
    if (q.contains('potenz') ||
        q.contains('hoch ') ||
        q.contains('quadriert') ||
        q.contains('kubiert')) {
      return 'Mathematik';
    }
    // Pythagoras & Trigonometrie
    if (q.contains('pythagoras') ||
        q.contains('hypotenuse') ||
        q.contains('kathete')) {
      return 'Mathematik';
    }
    if (q.contains('trigonometrie') ||
        q.contains('sinus') ||
        q.contains('kosinus') ||
        q.contains('tangens') ||
        q.contains('sin(') ||
        q.contains('cos(')) {
      return 'Mathematik';
    }
    // Statistik & Wahrscheinlichkeit
    if (q.contains('wahrscheinlichkeit') ||
        q.contains('stochastik') ||
        q.contains('zufallsexperiment') ||
        q.contains('laplace')) {
      return 'Mathematik';
    }
    if (q.contains('statistik') ||
        q.contains('diagramm') ||
        q.contains('balkendiagramm') ||
        q.contains('kreisdiagramm') ||
        q.contains('histogramm')) {
      return 'Mathematik';
    }
    if (q.contains('mittelwert') ||
        q.contains('median') ||
        q.contains('modus') ||
        q.contains('durchschnitt') && RegExp(r'\d').hasMatch(q)) {
      return 'Mathematik';
    }
    if (q.contains('kombinatorik') ||
        q.contains('permutation') ||
        q.contains('binomialkoeffizient') ||
        q.contains('fakultät') && RegExp(r'\d').hasMatch(q)) {
      return 'Mathematik';
    }
    // Analysis (Oberstufe)
    if (q.contains('integral') ||
        q.contains('integrieren') ||
        q.contains('integration') ||
        q.contains('stammfunktion')) {
      return 'Mathematik';
    }
    if (q.contains('ableitung') ||
        q.contains('ableiten') ||
        q.contains('differenzieren') ||
        q.contains('differentialrechnung')) {
      return 'Mathematik';
    }
    if (q.contains('differential') &&
        !q.contains('gleichung') &&
        !q.contains('diagnose')) {
      return 'Mathematik';
    }
    if (q.contains('grenzwert') ||
        q.contains('limes') ||
        q.contains('stetigkeit') ||
        q.contains('konvergenz')) {
      return 'Mathematik';
    }
    if (q.contains('kurvendiskussion') ||
        q.contains('extrempunkt') ||
        q.contains('wendepunkt') ||
        q.contains('nullstelle')) {
      return 'Mathematik';
    }
    if (q.contains('monoton') ||
        q.contains('krümmung') ||
        q.contains('tangente') && q.contains('funktion')) {
      return 'Mathematik';
    }
    if (q.contains('funktion') &&
        (q.contains('steigung') ||
            q.contains('graph') ||
            q.contains('ableitung') ||
            q.contains('wert') ||
            q.contains('definitionsbereich') ||
            q.contains('wertebereich'))) {
      return 'Mathematik';
    }
    if (q.contains('logarithmus') ||
        q.contains('log ') ||
        q.contains('ln ') ||
        q.contains('log(')) {
      return 'Mathematik';
    }
    if (q.contains('exponential') ||
        q.contains('e-funktion') ||
        q.contains('e^') ||
        q.contains('e hoch')) {
      return 'Mathematik';
    }
    if (q.contains('wachstumsfunktion') ||
        q.contains('zerfallsfunktion') ||
        q.contains('exponentielles wachstum')) {
      return 'Mathematik';
    }
    // Vektoren & Lineare Algebra
    if (q.contains('vektor') ||
        q.contains('skalarprodukt') ||
        q.contains('kreuzprodukt')) {
      return 'Mathematik';
    }
    if (q.contains('matrix') ||
        q.contains('determinante') ||
        q.contains('lineare algebra') ||
        q.contains('gauss')) {
      return 'Mathematik';
    }
    // Folgen & Reihen
    if (q.contains('folge') &&
        (q.contains('arithmetisch') ||
            q.contains('geometrisch') ||
            q.contains('rekursiv') ||
            q.contains('glied'))) {
      return 'Mathematik';
    }
    if (q.contains('reihe') &&
        (q.contains('konvergenz') ||
            q.contains('summe') ||
            q.contains('geometrisch'))) {
      return 'Mathematik';
    }
    // Polynome & Kurven
    if (q.contains('polynom') ||
        q.contains('parabel') ||
        q.contains('hyperbel') ||
        q.contains('ellipse')) {
      return 'Mathematik';
    }
    // Mengenlehre
    if (q.contains('menge') &&
        (q.contains('schnitt') ||
            q.contains('vereinigung') ||
            q.contains('teilmenge') ||
            q.contains('element'))) {
      return 'Mathematik';
    }
    // Finanzmathematik
    if (q.contains('zinsrechnung') ||
        q.contains('zinsen') && !q.contains('stadt') ||
        q.contains('zinseszins') ||
        q.contains('rendite')) {
      return 'Mathematik';
    }
    if (q.contains('rabatt') ||
        q.contains('mehrwertsteuer') ||
        q.contains('mwst') ||
        q.contains('grundwert') && q.contains('prozent')) {
      return 'Mathematik';
    }

    // ════════════════════════════════════════════════════════════════════════
    // PHYSIK
    // ════════════════════════════════════════════════════════════════════════
    if (q.contains('physik')) return 'Physik';
    // Mechanik
    if (q.contains('kraft') &&
        (q.contains('newton') ||
            q.contains('masse') ||
            q.contains('beschleunig') ||
            q.contains('gewicht'))) {
      return 'Physik';
    }
    if (q.contains('geschwindigkeit') ||
        q.contains('beschleunigung') ||
        q.contains('trägheit') ||
        q.contains('reibung')) {
      return 'Physik';
    }
    if (q.contains('gravitation') ||
        q.contains('gravitationsgesetz') ||
        q.contains('schwerkraft') ||
        q.contains('freier fall')) {
      return 'Physik';
    }
    if (q.contains('hebelgesetz') ||
        q.contains('hebel') && q.contains('kraft') ||
        q.contains('drehmoment')) {
      return 'Physik';
    }
    if (q.contains('druck') &&
        (q.contains('pascal') ||
            q.contains('gas') ||
            q.contains('flüssig') ||
            q.contains('atmo') ||
            q.contains('luftdruck'))) {
      return 'Physik';
    }
    if (q.contains('auftrieb') ||
        q.contains('archimedisches') ||
        q.contains('dichte') &&
            (q.contains('stoff') ||
                q.contains('körper') ||
                q.contains('wasser'))) {
      return 'Physik';
    }
    if (q.contains('impuls') ||
        q.contains('stoß') &&
            (q.contains('elastisch') || q.contains('unelastisch')) ||
        q.contains('impulserhaltung')) {
      return 'Physik';
    }
    // Energie & Arbeit
    if (q.contains('energie') &&
        (q.contains('kinetisch') ||
            q.contains('potenziel') ||
            q.contains('arbeit') ||
            q.contains('leistung') ||
            q.contains('joule') ||
            q.contains('erhalten'))) {
      return 'Physik';
    }
    if (q.contains('arbeit') &&
        (q.contains('joule') || q.contains('kraft') || q.contains('weg'))) {
      return 'Physik';
    }
    if (q.contains('leistung') &&
        (q.contains('watt') || q.contains('energie') || q.contains('zeit'))) {
      return 'Physik';
    }
    if (q.contains('wirkungsgrad') || q.contains('energieerhaltung')) {
      return 'Physik';
    }
    // Elektrizität
    if (q.contains('elektrizität') ||
        q.contains('elektrisch') ||
        q.contains('elektro')) {
      return 'Physik';
    }
    if (q.contains('strom') &&
        (q.contains('volt') ||
            q.contains('ampere') ||
            q.contains('widerstand') ||
            q.contains('spannung') ||
            q.contains('schaltkreis'))) {
      return 'Physik';
    }
    if (q.contains('widerstand') &&
        (q.contains('ohm') ||
            q.contains('schaltung') ||
            q.contains('reihenschaltung') ||
            q.contains('parallelschaltung'))) {
      return 'Physik';
    }
    if (q.contains('kondensator') ||
        q.contains('spule') ||
        q.contains('transformator') ||
        q.contains('generator') && q.contains('strom')) {
      return 'Physik';
    }
    if (q.contains('ohmsches gesetz') || q.contains('kirchhoff')) {
      return 'Physik';
    }
    // Magnetismus
    if (q.contains('magnetismus') ||
        q.contains('magnetfeld') ||
        q.contains('elektromagnet') ||
        q.contains('permanentmagnet')) {
      return 'Physik';
    }
    if (q.contains('induktion') &&
        (q.contains('strom') ||
            q.contains('magnetfeld') ||
            q.contains('spule'))) {
      return 'Physik';
    }
    // Wärmelehre
    if (q.contains('wärme') &&
        (q.contains('temperatur') ||
            q.contains('ausdehnung') ||
            q.contains('leitung') ||
            q.contains('strahlung') ||
            q.contains('konvektion'))) {
      return 'Physik';
    }
    if (q.contains('thermodynamik') ||
        q.contains('wärmekapazität') ||
        q.contains('spezifische wärme') ||
        q.contains('schmelzwärme')) {
      return 'Physik';
    }
    if (q.contains('aggregatzustand') &&
        (q.contains('physik') ||
            q.contains('wärme') ||
            q.contains('temperatur'))) {
      return 'Physik';
    }
    // Optik
    if (q.contains('optik') ||
        q.contains('linse') ||
        q.contains('prisma') && q.contains('licht')) {
      return 'Physik';
    }
    if (q.contains('licht') &&
        (q.contains('brechung') ||
            q.contains('reflexion') ||
            q.contains('welle') ||
            q.contains('spektrum') ||
            q.contains('geschwindigkeit'))) {
      return 'Physik';
    }
    if (q.contains('spiegel') &&
        (q.contains('licht') ||
            q.contains('bild') ||
            q.contains('brennpunkt'))) {
      return 'Physik';
    }
    // Akustik & Schwingungen
    if (q.contains('schall') ||
        q.contains('schallwelle') ||
        q.contains('schallgeschwindigkeit')) {
      return 'Physik';
    }
    if (q.contains('frequenz') &&
        (q.contains('schwingung') ||
            q.contains('welle') ||
            q.contains('hertz') ||
            q.contains('ton'))) {
      return 'Physik';
    }
    if (q.contains('schwingung') ||
        q.contains('pendel') ||
        q.contains('amplitude') ||
        q.contains('wellenlänge')) {
      return 'Physik';
    }
    // Atomphysik & Kernphysik
    if (q.contains('atom') &&
        (q.contains('kern') ||
            q.contains('elektron') ||
            q.contains('proton') ||
            q.contains('neutron') ||
            q.contains('bohr'))) {
      return 'Physik';
    }
    if (q.contains('radioaktiv') ||
        q.contains('kernspaltung') ||
        q.contains('kernfusion') ||
        q.contains('halbwertszeit')) {
      return 'Physik';
    }
    if (q.contains('strahlung') &&
        (q.contains('alpha') ||
            q.contains('beta') ||
            q.contains('gamma') ||
            q.contains('radioaktiv'))) {
      return 'Physik';
    }
    // Einheiten typisch Physik
    if (q.contains('newton') &&
            !q.contains('isaac newton') &&
            !q.contains('geschichte') ||
        q.contains('joule') && !q.contains('chemie') ||
        q.contains('watt') && q.contains('einheit')) {
      return 'Physik';
    }

    // ════════════════════════════════════════════════════════════════════════
    // CHEMIE
    // ════════════════════════════════════════════════════════════════════════
    if (q.contains('chemie') ||
        q.contains('chemisch') ||
        q.contains('chemiker')) {
      return 'Chemie';
    }
    // Atome & Moleküle
    if (q.contains('atom') &&
        (q.contains('bindung') ||
            q.contains('molekül') ||
            q.contains('reaktion') ||
            q.contains('orbital') ||
            q.contains('schale'))) {
      return 'Chemie';
    }
    if (q.contains('molekül') ||
        q.contains('verbindung') && q.contains('stoff') ||
        q.contains('formel') && q.contains('stoff')) {
      return 'Chemie';
    }
    // Periodensystem
    if (q.contains('periodensystem') || q.contains('pse')) return 'Chemie';
    if (q.contains('element') &&
        (q.contains('periodensystem') ||
            q.contains('symbol') ||
            q.contains('metall') ||
            q.contains('nichtmetall'))) {
      return 'Chemie';
    }
    // Reaktionen
    if (q.contains('chemische reaktion') ||
        q.contains('reaktionsgleichung') ||
        q.contains('stöchiometrie')) {
      return 'Chemie';
    }
    if (q.contains('reaktion') &&
        (q.contains('exotherm') ||
            q.contains('endotherm') ||
            q.contains('aktivierungsenergie'))) {
      return 'Chemie';
    }
    if (q.contains('oxidation') ||
        q.contains('reduktion') ||
        q.contains('redoxreaktion') ||
        q.contains('redox')) {
      return 'Chemie';
    }
    if (q.contains('verbrennung') &&
        (q.contains('sauerstoff') ||
            q.contains('reaktion') ||
            q.contains('kohlenstoff'))) {
      return 'Chemie';
    }
    if (q.contains('katalysator') ||
        q.contains('enzym') && q.contains('reaktion')) {
      return 'Chemie';
    }
    // Säuren & Basen
    if (q.contains('säure') ||
        q.contains('ph-wert') ||
        q.contains('ph ') && q.contains('messung')) {
      return 'Chemie';
    }
    if (q.contains('base') &&
        (q.contains('ph') || q.contains('lauge') || q.contains('hydroxid'))) {
      return 'Chemie';
    }
    if (q.contains('neutralisation') ||
        q.contains('titration') ||
        q.contains('indikator') && q.contains('säure')) {
      return 'Chemie';
    }
    // Aggregatzustände & Stoffe
    if (q.contains('aggregatzustand') && !q.contains('physik') ||
        q.contains('siedepunkt') ||
        q.contains('schmelzpunkt')) {
      return 'Chemie';
    }
    if (q.contains('gemisch') ||
        q.contains('löslichkeit') ||
        q.contains('lösung') && q.contains('stoff')) {
      return 'Chemie';
    }
    if (q.contains('destillation') ||
        q.contains('filtration') ||
        q.contains('chromatographie') ||
        q.contains('kristallisation')) {
      return 'Chemie';
    }
    // Elemente
    if (q.contains('kohlenstoff') ||
        q.contains('sauerstoff') ||
        q.contains('wasserstoff') ||
        q.contains('stickstoff')) {
      return 'Chemie';
    }
    if (q.contains('chlor') ||
        q.contains('natrium') ||
        q.contains('kalium') ||
        q.contains('calcium') ||
        q.contains('eisen') && q.contains('chemie')) {
      return 'Chemie';
    }
    if (q.contains('kupfer') &&
            (q.contains('ion') ||
                q.contains('reaktion') ||
                q.contains('oxid')) ||
        q.contains('schwefel') && q.contains('chemie')) {
      return 'Chemie';
    }
    // Bindungen
    if (q.contains('ionen') ||
        q.contains('ionenbindung') ||
        q.contains('ionengitter')) {
      return 'Chemie';
    }
    if (q.contains('kovalente') ||
        q.contains('elektronenpaarbindung') ||
        q.contains('atombindung')) {
      return 'Chemie';
    }
    if (q.contains('metallbindung') ||
        q.contains('van-der-waals') ||
        q.contains('wasserstoffbrücke')) {
      return 'Chemie';
    }
    // Organische Chemie
    if (q.contains('organisch') ||
        q.contains('kohlenwasserstoff') ||
        q.contains('alkohol') && q.contains('stoff')) {
      return 'Chemie';
    }
    if (q.contains('alkan') ||
        q.contains('alken') ||
        q.contains('alkin') ||
        q.contains('aromat') ||
        q.contains('benzol')) {
      return 'Chemie';
    }
    if (q.contains('polymer') ||
        q.contains('kunststoff') && q.contains('chemie') ||
        q.contains('polymerisation')) {
      return 'Chemie';
    }

    // ════════════════════════════════════════════════════════════════════════
    // BIOLOGIE
    // ════════════════════════════════════════════════════════════════════════
    if (q.contains('biologie') || q.contains('biologisch')) return 'Biologie';
    // Zellen & Genetik
    if (q.contains('zelle') &&
        (q.contains('kern') ||
            q.contains('membran') ||
            q.contains('teilung') ||
            q.contains('organell') ||
            q.contains('chloroplast') ||
            q.contains('mitochondr'))) {
      return 'Biologie';
    }
    if (q.contains('dna') ||
        q.contains('rna') ||
        q.contains('erbgut') ||
        q.contains('chromosom') ||
        q.contains('genetik') ||
        q.contains('gen') && q.contains('vererbung')) {
      return 'Biologie';
    }
    if (q.contains('mitose') ||
        q.contains('meiose') ||
        q.contains('zellteilung') ||
        q.contains('zellzyklus')) {
      return 'Biologie';
    }
    if (q.contains('erbgang') ||
        q.contains('dominant') && q.contains('rezessiv') ||
        q.contains('mendel') ||
        q.contains('mutation') && q.contains('gen')) {
      return 'Biologie';
    }
    if (q.contains('genotyp') ||
        q.contains('phänotyp') ||
        q.contains('allel') ||
        q.contains('homozygot') ||
        q.contains('heterozygot')) {
      return 'Biologie';
    }
    // Evolution
    if (q.contains('evolution') ||
        q.contains('darwin') ||
        q.contains('natürliche selektion') ||
        q.contains('artbildung')) {
      return 'Biologie';
    }
    if (q.contains('anpassung') &&
        (q.contains('art') ||
            q.contains('tier') ||
            q.contains('pflanze') ||
            q.contains('lebewesen'))) {
      return 'Biologie';
    }
    // Ökologie
    if (q.contains('ökosystem') ||
        q.contains('nahrungskette') ||
        q.contains('nahrungsnetz') ||
        q.contains('ökologie')) {
      return 'Biologie';
    }
    if (q.contains('lebensraum') ||
        q.contains('biotop') ||
        q.contains('biozönose') ||
        q.contains('population') && q.contains('tier')) {
      return 'Biologie';
    }
    if (q.contains('räuber') && q.contains('beute') ||
        q.contains('parasit') ||
        q.contains('symbiose') ||
        q.contains('konkurrenz') && q.contains('art')) {
      return 'Biologie';
    }
    if (q.contains('artenschutz') ||
        q.contains('aussterben') && q.contains('art') ||
        q.contains('biodiversität')) {
      return 'Biologie';
    }
    // Photosynthese & Stoffwechsel
    if (q.contains('fotosynthese') ||
        q.contains('photosynthese') ||
        q.contains('chlorophyll') ||
        q.contains('chloroplast')) {
      return 'Biologie';
    }
    if (q.contains('zellatmung') ||
        q.contains('atmung') &&
            (q.contains('zelle') ||
                q.contains('sauerstoff') ||
                q.contains('atp'))) {
      return 'Biologie';
    }
    if (q.contains('stoffwechsel') ||
        q.contains('metabolismus') ||
        q.contains('atp') && q.contains('energie')) {
      return 'Biologie';
    }
    // Mikroorganismen
    if (q.contains('virus') ||
        q.contains('bakterie') ||
        q.contains('mikroorganism')) {
      return 'Biologie';
    }
    if (q.contains('pilz') &&
        (q.contains('lebewesen') ||
            q.contains('art') ||
            q.contains('schimmel') ||
            q.contains('spore'))) {
      return 'Biologie';
    }
    // Immunsystem
    if (q.contains('immunsystem') ||
        q.contains('antikörper') ||
        q.contains('antigen') ||
        q.contains('lymphozyt')) {
      return 'Biologie';
    }
    if (q.contains('impfung') &&
        (q.contains('körper') ||
            q.contains('immunsystem') ||
            q.contains('schutz'))) {
      return 'Biologie';
    }
    // Organe & Körper
    if (q.contains('organ') &&
        (q.contains('leber') ||
            q.contains('niere') ||
            q.contains('herz') ||
            q.contains('lunge') ||
            q.contains('magen') ||
            q.contains('darm') ||
            q.contains('milz'))) {
      return 'Biologie';
    }
    if (q.contains('nervensystem') ||
        q.contains('neuron') ||
        q.contains('synapse') ||
        q.contains('gehirn') &&
            (q.contains('funktion') || q.contains('aufbau'))) {
      return 'Biologie';
    }
    if (q.contains('hormon') &&
        (q.contains('drüse') ||
            q.contains('körper') ||
            q.contains('regulation') ||
            q.contains('insulin'))) {
      return 'Biologie';
    }
    if (q.contains('blut') &&
        (q.contains('zelle') ||
            q.contains('kreislauf') ||
            q.contains('sauerstoff') ||
            q.contains('gefäß') ||
            q.contains('plasma'))) {
      return 'Biologie';
    }
    if (q.contains('verdauung') ||
        q.contains('darm') &&
            (q.contains('funktion') || q.contains('aufbau')) ||
        q.contains('nährstoffaufnahme')) {
      return 'Biologie';
    }
    if (q.contains('muskel') &&
        (q.contains('funktion') ||
            q.contains('aufbau') ||
            q.contains('kontraktion'))) {
      return 'Biologie';
    }
    if (q.contains('knochen') &&
        (q.contains('aufbau') ||
            q.contains('funktion') ||
            q.contains('skelett'))) {
      return 'Biologie';
    }
    if (q.contains('skelett') || q.contains('gelenk') && q.contains('körper')) {
      return 'Biologie';
    }
    // Pflanzen
    if (q.contains('blüte') ||
        q.contains('bestäubung') ||
        q.contains('pollen') ||
        q.contains('keimung')) {
      return 'Biologie';
    }
    if (q.contains('pflanze') &&
        (q.contains('wächst') ||
            q.contains('blatt') ||
            q.contains('wurzel') ||
            q.contains('stengel') ||
            q.contains('fotosynthese') ||
            q.contains('nährstoff') ||
            q.contains('art') ||
            q.contains('warum') ||
            q.contains('wie') ||
            q.contains('aufbau'))) {
      return 'Biologie';
    }
    if (q.contains('samen') &&
        (q.contains('pflanze') ||
            q.contains('keimung') ||
            q.contains('frucht'))) {
      return 'Biologie';
    }
    if (q.contains('monokoltyled') ||
        q.contains('dikotylede') ||
        q.contains('angiosperm') ||
        q.contains('gymnosperm')) {
      return 'Biologie';
    }
    // Tiere (Biologie)
    if (q.contains('wirbeltier') ||
        q.contains('wirbellos') ||
        q.contains('reptil') ||
        q.contains('amphibie')) {
      return 'Biologie';
    }
    if (q.contains('säugetier') &&
        (q.contains('merkmal') || q.contains('klasse') || q.contains('art'))) {
      return 'Biologie';
    }
    if (q.contains('tier') &&
        (q.contains('art') ||
            q.contains('klasse') ||
            q.contains('wirbel') ||
            q.contains('merkmal') ||
            q.contains('warum') ||
            q.contains('wie') ||
            q.contains('aufbau'))) {
      return 'Biologie';
    }
    if (q.contains('insekt') &&
        (q.contains('aufbau') ||
            q.contains('metamorphose') ||
            q.contains('art') ||
            q.contains('merkmal'))) {
      return 'Biologie';
    }
    // Proteine & Enzyme
    if (q.contains('protein') &&
        (q.contains('körper') ||
            q.contains('funktion') ||
            q.contains('struktur') ||
            q.contains('aminosäure'))) {
      return 'Biologie';
    }
    if (q.contains('enzym') &&
        (q.contains('reaktion') ||
            q.contains('substrat') ||
            q.contains('katalysator') ||
            q.contains('verdauung'))) {
      return 'Biologie';
    }

    // ════════════════════════════════════════════════════════════════════════
    // ENGLISCH
    // ════════════════════════════════════════════════════════════════════════
    if (q.contains('englisch') || q.contains('english')) return 'Englisch';
    if (q.contains('übersetze') ||
        q.contains('übersetzung') ||
        q.contains('auf englisch') ||
        q.contains('ins englische')) {
      return 'Englisch';
    }
    // Grammatik (englisch)
    if (q.contains('past tense') ||
        q.contains('present tense') ||
        q.contains('future tense')) {
      return 'Englisch';
    }
    if (q.contains('simple past') ||
        q.contains('present perfect') ||
        q.contains('past perfect') ||
        q.contains('past continuous')) {
      return 'Englisch';
    }
    if (q.contains('present simple') ||
        q.contains('present continuous') ||
        q.contains('will future') ||
        q.contains('going to')) {
      return 'Englisch';
    }
    if (q.contains('conditional') ||
        q.contains('if clause') ||
        q.contains('reported speech') ||
        q.contains('passive voice')) {
      return 'Englisch';
    }
    if (q.contains('irregular verb') ||
        q.contains('irregular') && q.contains('verb')) {
      return 'Englisch';
    }
    if (q.contains('gerund') ||
        q.contains('infinitive') ||
        q.contains('participle') ||
        q.contains('relative clause')) {
      return 'Englisch';
    }
    if (q.contains('adjective') ||
        q.contains('adverb') ||
        q.contains('preposition') ||
        q.contains('conjunction') ||
        q.contains('pronoun')) {
      return 'Englisch';
    }
    // Vokabeln
    if (q.contains('vokabel') ||
        q.contains('vokabeln') ||
        q.contains('vocabulary') ||
        q.contains('word') && q.contains('bedeutung')) {
      return 'Englisch';
    }
    if (q.contains('was bedeutet') &&
        (q.contains('englisch') ||
            RegExp(
              r'\b[a-z]{3,}\b',
            ).hasMatch(q.replaceAll(RegExp(r'[äöüß\s]'), '')))) {
      return 'Englisch';
    }
    // Englischsprachige Fragen erkennen
    if (q.split(' ').length >= 4 &&
        RegExp(
          r'\b(what|how|why|when|where|who|which|the |is |are |was |were |have |has |had |will |would |can |could |should |do |does |did )\b',
        ).hasMatch(q)) {
      return 'Englisch';
    }
    // Typisch englische Themen
    if (q.contains('essay') && q.contains('english') ||
        q.contains('text') && q.contains('english')) {
      return 'Englisch';
    }
    if (q.contains('listening') ||
        q.contains('reading comprehension') ||
        q.contains('writing') && q.contains('english'))
      return 'Englisch';

    // ════════════════════════════════════════════════════════════════════════
    // DEUTSCH
    // ════════════════════════════════════════════════════════════════════════
    if (q.contains('deutschstunde') ||
        q.contains('im deutschen') ||
        q.contains('auf deutsch')) {
      return 'Deutsch';
    }
    if (q.contains('grammatik') ||
        q.contains('rechtschreibung') ||
        q.contains('zeichensetzung')) {
      return 'Deutsch';
    }
    // Wortarten
    if (q.contains('nomen') ||
        q.contains('substantiv') ||
        q.contains('adjektiv') ||
        q.contains('adverb')) {
      return 'Deutsch';
    }
    if (q.contains('pronomen') ||
        q.contains('präposition') ||
        q.contains('konjunktion') ||
        q.contains('artikel') && q.contains('deutsch')) {
      return 'Deutsch';
    }
    if (q.contains('verb') &&
        !q.contains('englisch') &&
        !q.contains('english') &&
        !q.contains('tense') &&
        !q.contains('irregular') &&
        !q.contains('latein')) {
      return 'Deutsch';
    }
    if (q.contains('wortart') ||
        q.contains('interjektion') ||
        q.contains('partikel') && q.contains('wort')) {
      return 'Deutsch';
    }
    // Grammatikformen
    if (q.contains('konjugier') ||
        q.contains('konjugation') ||
        q.contains('zeitform') ||
        q.contains('tempus')) {
      return 'Deutsch';
    }
    if (q.contains('präteritum') ||
        q.contains('plusquamperfekt') ||
        q.contains('perfekt') && !q.contains('present perfect') ||
        q.contains('futur') && !q.contains('future')) {
      return 'Deutsch';
    }
    if (q.contains('nominativ') ||
        q.contains('genitiv') ||
        q.contains('dativ') ||
        q.contains('akkusativ')) {
      return 'Deutsch';
    }
    if (q.contains('kasus') ||
        q.contains('fall') &&
            (q.contains('wessen') || q.contains('wem') || q.contains('wen'))) {
      return 'Deutsch';
    }
    if (q.contains('komparativ') ||
        q.contains('superlativ') ||
        q.contains('steigerung') && q.contains('adjektiv')) {
      return 'Deutsch';
    }
    if (q.contains('aktiv') &&
        (q.contains('passiv') || q.contains('umwandeln')) &&
        !q.contains('sport')) {
      return 'Deutsch';
    }
    if (q.contains('konjunktiv') ||
        q.contains('indikativ') ||
        q.contains('imperativ') && q.contains('verb')) {
      return 'Deutsch';
    }
    // Satzlehre
    if (q.contains('hauptsatz') ||
        q.contains('nebensatz') ||
        q.contains('satzgefüge') ||
        q.contains('satzreihe')) {
      return 'Deutsch';
    }
    if (q.contains('satzzeichen') ||
        q.contains('interpunktion') ||
        q.contains('komma') && (q.contains('satz') || q.contains('regel'))) {
      return 'Deutsch';
    }
    if (q.contains(' satz') &&
        !q.contains('dreisatz') &&
        !q.contains('pythagoras') &&
        !q.contains('physik')) {
      return 'Deutsch';
    }
    if (q.contains('subjekt') ||
        q.contains('prädikat') ||
        q.contains('objekt') && !q.contains('programmier')) {
      return 'Deutsch';
    }
    // Rechtschreibung
    if (q.contains('großschreib') ||
        q.contains('kleinschreib') ||
        q.contains('getrenntschreib') ||
        q.contains('zusammenschreib')) {
      return 'Deutsch';
    }
    if (q.contains('silbe') ||
        q.contains('vorsilbe') ||
        q.contains('nachsilbe') ||
        q.contains('wortstamm')) {
      return 'Deutsch';
    }
    if (q.contains('dehnung') &&
            (q.contains('vokal') || q.contains('ie') || q.contains('ee')) ||
        q.contains('schärfung') && q.contains('konsonant')) {
      return 'Deutsch';
    }
    // Textsorten & Literatur
    if (q.contains('aufsatz') ||
        q.contains('erörterung') ||
        q.contains('inhaltsangabe') ||
        q.contains('charakterisierung')) {
      return 'Deutsch';
    }
    if (q.contains('gedicht') ||
        q.contains('strophe') ||
        q.contains('reim') ||
        q.contains('vers') && !q.contains('versuch')) {
      return 'Deutsch';
    }
    if (q.contains('metapher') ||
        q.contains('vergleich') && q.contains('stilmittel') ||
        q.contains('stilmittel') ||
        q.contains('rhetorisch')) {
      return 'Deutsch';
    }
    if (q.contains('erzählung') ||
        q.contains('roman') &&
            (q.contains('analyse') || q.contains('deutsch')) ||
        q.contains('kurzgeschichte') && !q.contains('englisch')) {
      return 'Deutsch';
    }
    if (q.contains('literatur') &&
        !q.contains('englisch') &&
        !q.contains('french') &&
        !q.contains('spanisch')) {
      return 'Deutsch';
    }
    if (q.contains('fabel') ||
        q.contains('märchen') &&
            (q.contains('merkmale') || q.contains('aufbau')) ||
        q.contains('ballade')) {
      return 'Deutsch';
    }
    if (q.contains('textanalyse') ||
        q.contains('interpretation') &&
            (q.contains('text') || q.contains('gedicht'))) {
      return 'Deutsch';
    }

    // ════════════════════════════════════════════════════════════════════════
    // GESCHICHTE
    // ════════════════════════════════════════════════════════════════════════
    if (q.contains('geschichte') &&
        !q.contains('lebensgeschichte') &&
        !q.contains('eigengeschichte')) {
      return 'Geschichte';
    }
    // Weltkriege
    if (q.contains('weltkrieg') ||
        q.contains('erster weltkrieg') ||
        q.contains('zweiter weltkrieg') ||
        q.contains('ww1') ||
        q.contains('ww2')) {
      return 'Geschichte';
    }
    if (q.contains('nationalsozialismu') ||
        q.contains('ns-zeit') ||
        q.contains('nazi') ||
        q.contains('hitler') ||
        q.contains('drittes reich')) {
      return 'Geschichte';
    }
    if (q.contains('holocaust') ||
        q.contains('konzentrationslager') ||
        q.contains('weimarer republik')) {
      return 'Geschichte';
    }
    // Antike
    if (q.contains('römer') ||
        q.contains('römisch') ||
        q.contains('römisches reich') ||
        q.contains('antike')) {
      return 'Geschichte';
    }
    if (q.contains('julius caesar') ||
        q.contains('kolosseum') ||
        q.contains('senator') && q.contains('rom')) {
      return 'Geschichte';
    }
    if (q.contains('griechisch') &&
        (q.contains('antik') ||
            q.contains('polis') ||
            q.contains('demokratie') ||
            q.contains('sparta') ||
            q.contains('athen'))) {
      return 'Geschichte';
    }
    if (q.contains('olympia') && q.contains('antike') ||
        q.contains('sokrates') ||
        q.contains('aristoteles') ||
        q.contains('platon') && q.contains('geschichte')) {
      return 'Geschichte';
    }
    if (q.contains('pharao') ||
        q.contains('altes ägypten') ||
        q.contains('hieroglyphe') ||
        q.contains('pyramide') && q.contains('ägypten')) {
      return 'Geschichte';
    }
    if (q.contains('mesopotamien') ||
        q.contains('babylon') ||
        q.contains('sumer') ||
        q.contains('alexander der große')) {
      return 'Geschichte';
    }
    // Mittelalter
    if (q.contains('mittelalter') ||
        q.contains('kreuzzug') ||
        q.contains('ritter') &&
            (q.contains('burg') ||
                q.contains('mittelalter') ||
                q.contains('historisch'))) {
      return 'Geschichte';
    }
    if (q.contains('feudalsystem') ||
        q.contains('lehnswesen') ||
        q.contains('leibeigenschaft') ||
        q.contains('minnesänger')) {
      return 'Geschichte';
    }
    if (q.contains('schwarzer tod') ||
        q.contains('pest') && q.contains('mittelalter') ||
        q.contains('kreuzzug')) {
      return 'Geschichte';
    }
    // Frühe Neuzeit
    if (q.contains('reformation') ||
        q.contains('luther') && q.contains('kirch') ||
        q.contains('ablasshandel')) {
      return 'Geschichte';
    }
    if (q.contains('französische revolution') ||
        q.contains('französisch') && q.contains('revolution') ||
        q.contains('bastille')) {
      return 'Geschichte';
    }
    if (q.contains('kolonie') ||
        q.contains('kolonialismus') ||
        q.contains('imperialismus') && q.contains('historisch')) {
      return 'Geschichte';
    }
    if (q.contains('industrie') && q.contains('revolution') ||
        q.contains('industrialisierung')) {
      return 'Geschichte';
    }
    // Neuere Geschichte
    if (q.contains('bismarck') ||
        q.contains('wilhelmin') ||
        q.contains('kaiserreich') && q.contains('deutsch')) {
      return 'Geschichte';
    }
    if (q.contains('kalter krieg') ||
        q.contains('mauerfall') ||
        q.contains('deutsche teilung') ||
        q.contains('wiedervereinigung') && q.contains('deutsch')) {
      return 'Geschichte';
    }
    if (q.contains('ddr') ||
        q.contains('brd') ||
        q.contains('berliner mauer') ||
        q.contains('ostblock')) {
      return 'Geschichte';
    }
    if (q.contains('amerikanische revolution') ||
        q.contains('unabhängigkeit') &&
            q.contains('usa') &&
            q.contains('historisch')) {
      return 'Geschichte';
    }
    if (q.contains('french revolution') ||
        q.contains('napoleon') ||
        q.contains('napoleon') && q.contains('krieg')) {
      return 'Geschichte';
    }
    if (q.contains('historisch') &&
        (q.contains('wann') ||
            q.contains('warum') ||
            q.contains('ursache') ||
            q.contains('folge'))) {
      return 'Geschichte';
    }
    if (q.contains('wann wurde') ||
        q.contains('wann war') ||
        q.contains('wann fand') &&
            (q.contains('krieg') ||
                q.contains('revolution') ||
                q.contains('ereignis'))) {
      return 'Geschichte';
    }

    // ════════════════════════════════════════════════════════════════════════
    // SACHKUNDE (Grundschule)
    // ════════════════════════════════════════════════════════════════════════
    if (q.contains('sachkunde') || q.contains('sachunterricht')) {
      return 'Sachkunde';
    }
    // Pflanzen & Tiere (einfach, Grundschulniveau)
    if (q.contains('pflanze') ||
        q.contains('blume') ||
        q.contains('baum') ||
        q.contains('strauch')) {
      return 'Biologie';
    }
    if (q.contains('tier') ||
        q.contains('tiere') ||
        q.contains('tierart') ||
        q.contains('haustier') ||
        q.contains('wildtier')) {
      return 'Biologie';
    }
    if (q.contains('insekt') ||
        q.contains('schmetterling') ||
        q.contains('biene') ||
        q.contains('käfer') ||
        q.contains('ameise')) {
      return 'Biologie';
    }
    if (q.contains('vogel') ||
        q.contains('fisch') ||
        q.contains('frosch') ||
        q.contains('schlange') && !q.contains('spiel')) {
      return 'Biologie';
    }
    // Sachkunde-spezifisch
    if (q.contains('jahreszeit') ||
        q.contains('frühling') ||
        q.contains('herbst') && !q.contains('olymp') ||
        q.contains('winter') && !q.contains('sport')) {
      return 'Sachkunde';
    }
    if (q.contains('körper') &&
        (q.contains('organ') ||
            q.contains('wie funktioniert') ||
            q.contains('herzschlag') ||
            q.contains('knochen'))) {
      return 'Sachkunde';
    }
    if (q.contains('blutkreislauf') ||
        q.contains('verdauung') && !q.contains('biologie')) {
      return 'Sachkunde';
    }
    if (q.contains('umwelt') ||
        q.contains('recycling') ||
        q.contains('naturschutz') ||
        q.contains('mülltrennung')) {
      return 'Sachkunde';
    }
    if (q.contains('planet') ||
        q.contains('sonnensystem') ||
        q.contains('weltall') ||
        q.contains('galaxie') ||
        q.contains('sterne') && q.contains('astronomie')) {
      return 'Sachkunde';
    }
    if (q.contains('magnet') ||
        q.contains('elektrizität') &&
            !q.contains('physik') &&
            !q.contains('chemie')) {
      return 'Sachkunde';
    }
    if (q.contains('verkehr') ||
        q.contains('ampel') ||
        q.contains('verkehrszeichen') ||
        q.contains('straßenverkehr')) {
      return 'Sachkunde';
    }
    if (q.contains('gesund') && !q.contains('rechnung') ||
        q.contains('ernährung') ||
        q.contains('vitamin') ||
        q.contains('nährstoff') && !q.contains('biologie')) {
      return 'Sachkunde';
    }
    if (q.contains('beruf') ||
        q.contains('feuerwehr') ||
        q.contains('polizei') && q.contains('beruf') ||
        q.contains('arzt') && q.contains('beruf')) {
      return 'Sachkunde';
    }
    if (q.contains('wasser') &&
        (q.contains('kreislauf') ||
            q.contains('regen') ||
            q.contains('fluss') && !q.contains('geographie'))) {
      return 'Sachkunde';
    }
    if (q.contains('luft') &&
        (q.contains('bestandteil') ||
            q.contains('sauerstoff') ||
            q.contains('stickstoff') ||
            q.contains('zusammensetzung'))) {
      return 'Sachkunde';
    }

    return 'Allgemein';
  }

  Future<void> completeCurrentSession() async {
    if (_currentSessionId == null) return;

    try {
      if (!_hasUserSentMessage) {
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
    } catch (e) {
      // ❌ Fehler beim Abschließen der Session: $e');
    }
  }

  Future<void> clearChat() async {
    final child = _ref.read(activeChildProvider);
    if (child == null) return;

    try {
      await completeCurrentSession();

      _hasUserSentMessage = false;

      final welcomeMessage = ChatMessage.tutor(
        'Hallo ${child.name}! 👋 Ich bin **Lerndex**, dein persönlicher Lernbegleiter! 🎓 Ich helfe dir bei allen Fragen zu Mathe, Deutsch, Englisch und anderen Schulfächern. Was möchtest du heute lernen? 📚✨',
      );

      state = [welcomeMessage];
    } catch (e) {
      // ❌ Fehler beim Session-Reset: $e');
    }
  }
}

// ============================================================================
// PROVIDER
// ============================================================================

/// Provider für den Firebase AI Service (Singleton)
final firebaseAIServiceProvider = Provider<FirebaseAIService>((ref) {
  return FirebaseAIService();
});

/// 🎯 FAMILY PROVIDER - Ein Chat pro Kind!
final tutorProviderFamily =
    StateNotifierProvider.family<TutorNotifier, List<ChatMessage>, String>((
      ref,
      childId,
    ) {
      final service = ref.watch(firebaseAIServiceProvider);
      final user = ref.watch(authStateChangesProvider).value;

      if (user == null) {
        throw Exception('User nicht eingeloggt');
      }

      return TutorNotifier(service, ref, childId, user.uid);
    });

/// 🎯 CONVENIENCE PROVIDER - Automatisch für aktives Kind
final tutorProvider =
    Provider<StateNotifierProvider<TutorNotifier, List<ChatMessage>>?>((ref) {
      final activeChild = ref.watch(activeChildProvider);

      if (activeChild == null) {
        return null;
      }

      return tutorProviderFamily(activeChild.id);
    });
