import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:cross_file/cross_file.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lerndex/src/ai/vertex_ai_service.dart';
import '../domain/chat_message.dart';
import '../data/chat_message_firestore.dart';
import '../data/tutor_session_model.dart';
import '../../auth/presentation/active_child_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/child_model.dart';
import '../../rewards/data/xp_service.dart';
import '../../quiz/data/ai_question_cache_repository.dart';
import '../../generated_tasks/data/generated_task_models.dart'
    show Subject, SubjectExtension;
import 'package:lerndex/src/features/auth/domain/account.dart';

/// Chat mit Lexi für ein Kind.
///
/// Firestore: `users/{uid}/children/{childId}/tutor_sessions/{sessionId}`
/// mit Unterkollektion `messages`. Werte der Session (Fach, erste Frage,
/// Inhalts-Flag) und die Tages-XP hält der Notifier selbst, statt sie bei
/// jeder Nachricht neu zu lesen.
class TutorNotifier extends StateNotifier<List<ChatMessage>> {
  TutorNotifier(this._aiService, this._ref, this._childId, this._userId)
    : super([]) {
    _ready = _initialize();
  }

  final VertexAIService _aiService;
  final Ref _ref;
  final String _childId;
  final String _userId;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Läuft beim Öffnen: Verlauf laden bzw. alte Sessions schließen. Senden
  /// und Session-Anlage warten darauf.
  late final Future<void> _ready;

  bool _isAIInitialized = false;
  bool _hasUserSentMessage = false;

  /// Solange eine Nachricht auf Lexis Antwort wartet: kein zweites Senden.
  bool _sending = false;

  /// Aktuelle Session. [_sessionFuture] ist gesetzt, sobald sie angelegt
  /// wird – so entsteht bei schnellen Nachrichten keine zweite Session.
  String? _currentSessionId;
  Future<String>? _sessionFuture;

  /// Zählt hoch, wenn die Session abgeschlossen wird. Eine danach fertig
  /// werdende Anlage wird nicht mehr zur aktuellen Session.
  int _sessionGeneration = 0;

  // Werte der aktuellen Session (statt sie bei jeder Nachricht zu lesen)
  String? _sessionTopic;
  bool _sessionHasFirstQuestion = false;
  String? _sessionContentFlag;

  /// Verhindert, dass pro Tutor-Session mehr als einmal Quiz-Aufgaben aus dem
  /// Gespräch generiert werden (ein zusätzlicher KI-Aufruf reicht pro Session).
  bool _quizInjectedThisSession = false;

  // Heute verdiente Tutor-XP (Vorprüfung; das Limit prüft die Transaktion)
  int _dailyXp = 0;
  DateTime? _dailyXpDay;

  static const int maxXpPerDay = 50;

  /// True, solange Lexi an einer Antwort arbeitet.
  bool get isWaitingForAnswer => _sending;

  CollectionReference<Map<String, dynamic>> get _sessions => _firestore
      .collection('users')
      .doc(_userId)
      .collection('children')
      .doc(_childId)
      .collection('tutor_sessions');

  // --------------------------------------------------------------------------
  // START
  // --------------------------------------------------------------------------

  Future<void> _initialize() async {
    final child = _ref.read(activeChildProvider);
    if (child == null) return;

    // Wenn eine Session reaktiviert werden soll, KEINE Welcome-Message setzen –
    // der State bleibt leer bis die Nachrichten geladen sind (verhindert Flash).
    final resumeId = _ref.read(tutorResumeSessionIdProvider);
    final isFreshChat = _ref.read(tutorFreshChatProvider);
    if (resumeId == null) state = [_welcome(child)];

    // Andere Provider erst nach dem Aufbau dieses Providers ändern.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    if (resumeId != null) {
      _ref.read(tutorResumeSessionIdProvider.notifier).state = null;
    }
    if (isFreshChat) _ref.read(tutorFreshChatProvider.notifier).state = false;

    unawaited(_loadDailyXp());

    try {
      if (resumeId != null) {
        await _activateSession(resumeId);
      } else if (isFreshChat) {
        await _closeAllActiveSessions();
      } else {
        await _loadActiveSession();
      }
    } catch (e) {
      debugPrint('⚠️ Tutor: Verlauf konnte nicht geladen werden: $e');
    }
  }

  static ChatMessage _welcome(ChildModel child) => ChatMessage.tutor(
    VertexAIService.buildWelcomeMessage(child),
    excludeFromAi: true,
  );

  /// Lädt die heutigen Tutor-XP und befüllt den Banner.
  Future<void> _loadDailyXp() async {
    try {
      final xpToday = await _ref
          .read(xpServiceProvider)
          .getTutorXpToday(userId: _userId, childId: _childId);
      if (!mounted) return;
      _setDailyXp(xpToday);
    } catch (e) {
      debugPrint('⚠️ Tutor: Fehler beim Laden der Tages-XP: $e');
    }
  }

  void _setDailyXp(int xp) {
    _dailyXp = xp;
    _dailyXpDay = _today();
    _ref.read(tutorSessionXpProvider(_childId).notifier).state = xp;
  }

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Gespräch aus dem Verlauf fortsetzen (Schülerdashboard).
  Future<void> _activateSession(String sessionId) async {
    final ref = _sessions.doc(sessionId);
    await ref.update({'status': 'active', 'endedAt': FieldValue.delete()});
    final snapshot = await ref.get();
    final messages = await _loadMessages(sessionId);
    if (!mounted) return;
    _useSession(sessionId, snapshot.data());
    _hasUserSentMessage = true;
    if (messages.isNotEmpty) state = messages;
  }

  /// Normaler Start: eine noch aktive Session weiterführen.
  Future<void> _loadActiveSession() async {
    final snapshot = await _sessions
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty || !mounted) return;

    final doc = snapshot.docs.first;
    final messages = await _loadMessages(doc.id);
    if (!mounted) return;
    _useSession(doc.id, doc.data());
    if (messages.length > 1) {
      state = messages;
      _hasUserSentMessage = true;
    }
  }

  /// Die neuesten 50 Nachrichten einer Session.
  Future<List<ChatMessage>> _loadMessages(String sessionId) async {
    final snapshot = await _sessions
        .doc(sessionId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .limitToLast(50)
        .get();
    return [
      for (final doc in snapshot.docs)
        chatMessageFromFirestore(doc.id, doc.data()),
    ];
  }

  void _useSession(String sessionId, Map<String, dynamic>? data) {
    _currentSessionId = sessionId;
    _sessionFuture = Future.value(sessionId);
    final topic = data?['detectedTopic'] as String?;
    _sessionTopic = topic != null && isSchoolSubject(topic) ? topic : null;
    _sessionHasFirstQuestion = data?['firstQuestion'] != null;
    _sessionContentFlag = data?['contentFlag'] as String?;
    _quizInjectedThisSession = false;
  }

  Future<void> _ensureAIInitialized() async {
    if (_isAIInitialized) return;
    await _aiService.initialize();
    _isAIInitialized = true;
  }

  // --------------------------------------------------------------------------
  // SESSION
  // --------------------------------------------------------------------------

  /// ID der aktuellen Session; legt sie beim ersten Mal an. Mehrere Aufrufe
  /// teilen sich dieselbe Anlage.
  Future<String> _getOrCreateSession() {
    return _sessionFuture ??= _createSession().catchError((Object e) {
      _sessionFuture = null;
      throw e;
    });
  }

  Future<String> _createSession() async {
    // Erst fertig laden: beim frischen Chat schließt _initialize die alten
    // Sessions, beim normalen Start übernimmt es die aktive.
    await _ready;
    final existing = _currentSessionId;
    if (existing != null) return existing;

    final generation = _sessionGeneration;
    final doc = await _sessions.add({
      'childId': _childId,
      'startedAt': Timestamp.fromDate(DateTime.now()),
      'status': 'active',
      'messageCount': 0,
    });
    if (generation == _sessionGeneration) {
      _currentSessionId = doc.id;
      _sessionTopic = null;
      _sessionHasFirstQuestion = false;
      _sessionContentFlag = null;
      _quizInjectedThisSession = false;
    }
    return doc.id;
  }

  // --------------------------------------------------------------------------
  // SENDEN
  // --------------------------------------------------------------------------

  Future<void> sendMessage(String text, {XFile? imageFile}) async {
    // Mit Foto ist ein leerer Begleittext erlaubt.
    if (text.trim().isEmpty && imageFile == null) return;
    // Lexi antwortet noch: parallele KI-Aufrufe würden sich die Ladeanzeige
    // gegenseitig wegnehmen.
    if (_sending) return;

    final child = _ref.read(activeChildProvider);
    if (child == null) return;

    _sending = true;
    try {
      await _send(child, text, imageFile);
    } finally {
      _sending = false;
    }
  }

  Future<void> _send(ChildModel child, String text, XFile? imageFile) async {
    await _ready;
    if (!mounted) return;

    try {
      await _ensureAIInitialized();
    } catch (e) {
      if (mounted) {
        state = [
          ...state,
          ChatMessage.tutor(
            'Entschuldigung, ich hatte Probleme beim Starten. Versuch es gleich nochmal! 😊',
            excludeFromAi: true,
          ),
        ];
      }
      return;
    }
    if (!mounted) return;

    _hasUserSentMessage = true;

    // Verlauf für die KI: alles VOR der neuen Nachricht.
    final history = state.where((m) => !m.isLoading).toList();

    // User-Nachricht sofort anzeigen (mit lokaler Bild-Vorschau falls Foto).
    final userMessage = ChatMessage.user(text, localImagePath: imageFile?.path);
    state = [...state, userMessage, ChatMessage.loading()];

    final sessionFuture = _getOrCreateSession();

    // Foto in Firebase Storage hochladen → URL persistieren (Eltern-Ansicht).
    String? imageUrl;
    if (imageFile != null) {
      try {
        imageUrl = await _aiService.uploadTutorWorksheet(
          imageFile: imageFile,
          userId: _userId,
          childId: _childId,
        );
      } catch (e) {
        debugPrint('⚠️ Tutor-Aufgabenblatt-Upload fehlgeschlagen: $e');
      }
    }

    // Session vom Sendezeitpunkt: die Antwort landet in derselben Session,
    // auch wenn das Kind den Chat schon verlassen hat.
    String? sessionId;
    try {
      sessionId = await sessionFuture;
    } catch (e) {
      debugPrint('⚠️ Tutor: Session konnte nicht angelegt werden: $e');
    }
    final userSaved = sessionId == null
        ? Future<DocumentReference<Map<String, dynamic>>?>.value()
        : _saveChatMessage(sessionId, userMessage.copyWith(imageUrl: imageUrl));

    TutorResponse response;
    try {
      response = await _aiService.sendTutorMessage(
        child: child,
        userMessage: text,
        conversationHistory: history,
        imageFile: imageFile,
      );
    } catch (e) {
      debugPrint('❌ Tutor: Fehler beim Senden: $e');
      response = const TutorResponse.local(
        'Ups, geht dein Internet? 😅 Frag mich nochmal!',
      );
    }

    final tutorMessage = ChatMessage.tutor(
      response.text,
      excludeFromAi: response.isLocal,
    );

    // Erst die Frage, dann die Antwort speichern (Reihenfolge, erste Frage).
    final userRef = await userSaved;
    if (sessionId != null) {
      // Abgewiesene Fragen gehen nicht wieder an die KI (Verlauf).
      if (response.isLocal && userRef != null) {
        unawaited(
          userRef.update({'excludeFromAi': true}).catchError((Object e) {
            debugPrint('⚠️ Tutor: Markierung nicht gespeichert: $e');
          }),
        );
      }
      unawaited(_saveChatMessage(sessionId, tutorMessage));
    }

    // Hat das Kind den Chat verlassen, ist hier Schluss (kein State, keine XP).
    if (!mounted) return;
    state = [
      for (final m in state)
        if (!m.isLoading)
          response.isLocal && identical(m, userMessage)
              ? m.copyWith(excludeFromAi: true)
              : m,
      tutorMessage,
    ];

    // Abweisung, Hilfe-Antwort oder Fehler kamen von der App selbst: keine
    // XP und keine Quiz-Fragen aus diesem Text.
    if (response.isLocal || sessionId == null) return;

    // XP gibt es, sobald über ein Schulthema geredet wird. Fach: Tag der KI,
    // sonst das bereits erkannte Fach der Session. Kein Raten aus dem Text –
    // das brachte XP für Smalltalk.
    final subject =
        response.isSchoolSubject && isSchoolSubject(response.subject)
        ? response.subject
        : _sessionTopic;
    if (subject == null) {
      debugPrint('⛔ Kein XP: Kein Schulfach erkannt (${response.subject})');
      return;
    }

    if (_sessionTopic == null && sessionId == _currentSessionId) {
      // Fach nur beim ersten Mal setzen – kein Überschreiben mit falschem Fach
      _sessionTopic = subject;
      unawaited(_setSessionTopic(sessionId, subject));
    }

    // Korrekte Antworten geben Bonus.
    await _awardTutorXP(sessionId, isCorrect: response.isCorrect);
    if (!mounted) return;

    // Einmal pro Session: passende Quiz-Aufgaben aus dem Gespräch ableiten
    // und in den Quiz-Cache des Fachs einspeisen (Hintergrund).
    _maybeInjectQuizQuestions(child, subject, text);
  }

  /// Speichert eine Nachricht samt Zähler (und bei der Frage des Kindes
  /// erste Frage und Inhalts-Flag) in einem Schreibvorgang.
  Future<DocumentReference<Map<String, dynamic>>?> _saveChatMessage(
    String sessionId,
    ChatMessage message,
  ) async {
    if (message.isLoading) return null;

    try {
      final sessionRef = _sessions.doc(sessionId);
      final messageRef = sessionRef.collection('messages').doc();
      final updates = <String, dynamic>{
        'messageCount': FieldValue.increment(1),
      };

      if (message.isUser && sessionId == _currentSessionId) {
        // firstQuestion + detectedTopic nur beim ersten Mal setzen
        if (!_sessionHasFirstQuestion) {
          updates['firstQuestion'] = message.text;
          if (_sessionTopic == null) updates['detectedTopic'] = 'Allgemein';
          _sessionHasFirstQuestion = true;
        }
        // contentFlag bei JEDER Nachricht prüfen – aber 'critical' nie durch
        // ein schwächeres Flag überschreiben
        if (_sessionContentFlag != 'critical') {
          final flag = TutorSession.detectContentFlag(message.text);
          if (flag != null && flag != _sessionContentFlag) {
            updates['contentFlag'] = flag;
            _sessionContentFlag = flag;
          }
        }
      }

      final batch = _firestore.batch()
        ..set(messageRef, chatMessageToFirestore(message))
        ..update(sessionRef, updates);
      await batch.commit();
      return messageRef;
    } on FirebaseException catch (e) {
      debugPrint('⚠️ Tutor: Nachricht nicht gespeichert: $e');
      // Session wurde gelöscht (z.B. von den Eltern): nächste Nachricht
      // beginnt eine neue.
      if (e.code == 'not-found' && sessionId == _currentSessionId) {
        _currentSessionId = null;
        _sessionFuture = null;
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ Tutor: Nachricht nicht gespeichert: $e');
      return null;
    }
  }

  /// Prüft ob ein erkanntes Topic ein echtes Schulfach ist.
  /// XP darf nur bei echten Schulfächern vergeben werden – NIEMALS bei 'Allgemein'.
  static bool isSchoolSubject(String topic) {
    const schoolSubjects = {
      'Mathematik',
      'Deutsch',
      'Englisch',
      'Biologie',
      'Chemie',
      'Physik',
      'Geschichte',
      'Sachkunde',
      'Geographie',
      'Informatik',
      'Latein',
      'Französisch',
      'Spanisch',
      'Ethik',
      'Philosophie',
      'Musik',
      'Kunst',
      'Sport',
      'Wirtschaft',
      'Politik',
    };
    return schoolSubjects.contains(topic);
  }

  /// Vergibt XP via XPService und aktualisiert den Tages-XP-Banner.
  /// Beschäftigung mit einem Schulthema gibt Basis-XP; eine korrekt
  /// beantwortete Aufgabe gibt einen kleinen Bonus. Den Tagesstand hält der
  /// Notifier; die Transaktion in addTutorXP liest ihn ohnehin frisch und
  /// begrenzt auf das Tageslimit.
  Future<void> _awardTutorXP(String sessionId, {bool isCorrect = false}) async {
    if (_dailyXpDay != _today()) _dailyXp = 0; // neuer Tag
    if (_dailyXp >= maxXpPerDay) {
      debugPrint('⏸️ Tutor XP: Tageslimit erreicht ($_dailyXp/$maxXpPerDay)');
      return;
    }

    try {
      final result = await _ref
          .read(xpServiceProvider)
          .addTutorXP(
            userId: _userId,
            childId: _childId,
            dailyXpSoFar: _dailyXp,
            xpPerMessage: isCorrect ? 5 : 2,
          );

      if (result != null && result.xpGained > 0) {
        // xpEarned der Session → im Elterndashboard pro Tag summiert
        unawaited(
          _sessions
              .doc(sessionId)
              .update({'xpEarned': FieldValue.increment(result.xpGained)})
              .catchError((Object e) {
                debugPrint('⚠️ Konnte xpEarned nicht speichern: $e');
              }),
        );
        if (!mounted) return;
        _setDailyXp(_dailyXp + result.xpGained);
        _ref.read(tutorXpGainProvider(_childId).notifier).state =
            result.xpGained;
      } else if (mounted) {
        // Laut Transaktion ist das Tageslimit schon erreicht.
        _setDailyXp(maxXpPerDay);
      }
    } catch (e) {
      debugPrint('❌ _awardTutorXP: Netzwerkfehler, XP nicht vergeben: $e');
    }
  }

  /// Speist – einmal pro Session – passende Quiz-Aufgaben aus dem Tutor-
  /// Gespräch in den Quiz-Cache des erkannten Fachs ein (Hintergrund).
  void _maybeInjectQuizQuestions(
    ChildModel child,
    String germanSubject,
    String focusText,
  ) {
    if (_quizInjectedThisSession) return;

    final subject = _quizSubjectFor(germanSubject, child.grade);
    if (subject == null) {
      debugPrint(
        'ℹ️ Quiz-Einspeisung übersprungen: "$germanSubject" ist für Klasse '
        '${child.grade} kein verfügbares Quiz-Fach',
      );
      return;
    }

    _quizInjectedThisSession = true;
    final hint = focusText.trim().isNotEmpty ? focusText.trim() : germanSubject;
    final repo = _ref.read(aiQuestionCacheRepositoryProvider);
    unawaited(
      repo.injectTutorQuestions(
        userId: _userId,
        childId: _childId,
        child: child,
        subject: subject.value,
        focusHint: hint,
      ),
    );
  }

  /// Mappt den vom Tutor erkannten deutschen Fachnamen auf das passende
  /// Quiz-[Subject] – aber nur, wenn das Fach für die Klasse verfügbar ist.
  /// Gibt null zurück, wenn es kein Quiz-Fach dafür gibt.
  static Subject? _quizSubjectFor(String germanSubject, int grade) {
    Subject? s;
    switch (germanSubject) {
      case 'Mathematik':
        s = Subject.mathe;
        break;
      case 'Deutsch':
        s = Subject.deutsch;
        break;
      case 'Englisch':
        s = Subject.englisch;
        break;
      case 'Sachkunde':
        s = Subject.sachkunde;
        break;
      case 'Biologie':
        s = Subject.biologie;
        break;
      case 'Chemie':
        s = Subject.chemie;
        break;
      case 'Physik':
        s = Subject.physik;
        break;
      case 'Geschichte':
        s = Subject.geschichte;
        break;
      default:
        // Fächer ohne eigenes Quiz (z.B. Geographie, Latein, Musik) → kein Quiz.
        return null;
    }

    if (s.isAvailableForGrade(grade)) return s;

    // Die KI ordnet bei Grundschülern Pflanzen/Tiere manchmal 'Biologie' zu,
    // wo im Lehrplan 'Sachkunde' das passende Fach ist.
    if (s == Subject.biologie && Subject.sachkunde.isAvailableForGrade(grade)) {
      return Subject.sachkunde;
    }
    return null;
  }

  /// Setzt das Session-Topic einmalig auf das von der KI erkannte Schulfach.
  Future<void> _setSessionTopic(String sessionId, String subject) async {
    try {
      await _sessions.doc(sessionId).update({'detectedTopic': subject});
    } catch (e) {
      debugPrint('⚠️ Fehler beim Topic-Setzen: $e');
    }
  }

  // --------------------------------------------------------------------------
  // ABSCHLIESSEN
  // --------------------------------------------------------------------------

  /// Löscht eine Session samt Nachrichten (leere Sessions).
  Future<void> _deleteSessionWithMessages(
    DocumentReference<Map<String, dynamic>> sessionRef,
  ) async {
    final messages = await sessionRef.collection('messages').limit(450).get();
    final batch = _firestore.batch();
    for (final m in messages.docs) {
      batch.delete(m.reference);
    }
    batch.delete(sessionRef);
    await batch.commit();
  }

  /// Schließt alle noch offenen aktiven Sessions (frischer Chat-Start).
  /// Sessions ohne Gespräch (höchstens eine Nachricht, kein Inhalts-Flag)
  /// werden samt Nachrichten gelöscht.
  Future<void> _closeAllActiveSessions() async {
    final snapshot = await _sessions.where('status', isEqualTo: 'active').get();
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final msgCount = (data['messageCount'] as int?) ?? 0;
      try {
        if (msgCount <= 1 && data['contentFlag'] == null) {
          await _deleteSessionWithMessages(doc.reference);
        } else {
          await doc.reference.update({
            'status': 'completed',
            'endedAt': Timestamp.fromDate(DateTime.now()),
          });
        }
      } catch (e) {
        debugPrint('⚠️ Session ${doc.id} nicht geschlossen: $e');
      }
    }
  }

  /// Schließt die aktuelle Session ab (Chat verlassen). Ohne Nachricht des
  /// Kindes und ohne Inhalts-Flag wird sie gelöscht. Läuft auch, wenn der
  /// Notifier schon entsorgt ist (keine State-Änderung).
  Future<void> completeCurrentSession() async {
    final pending = _sessionFuture;
    var sessionId = _currentSessionId;
    final hadMessage = _hasUserSentMessage;
    final flagged = _sessionContentFlag != null;

    _sessionGeneration++;
    _currentSessionId = null;
    _sessionFuture = null;
    _hasUserSentMessage = false;
    _sessionTopic = null;
    _sessionHasFirstQuestion = false;
    _sessionContentFlag = null;
    _quizInjectedThisSession = false;

    if (sessionId == null && pending != null) {
      try {
        sessionId = await pending;
      } catch (_) {
        return;
      }
    }
    if (sessionId == null) return;

    try {
      final ref = _sessions.doc(sessionId);
      if (!hadMessage && !flagged) {
        await _deleteSessionWithMessages(ref);
        return;
      }
      await ref.update({
        'status': 'completed',
        'endedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      debugPrint('❌ Fehler beim Abschließen der Session: $e');
    }
  }
}

// ============================================================================
// XP STATE PROVIDER – reaktiv, per childId
// ============================================================================

/// Gesammelte Session-XP – reaktiv, wird im Banner angezeigt
final tutorSessionXpProvider = StateProvider.family<int, String>(
  (ref, childId) => 0,
);

/// XP-Gain Event für +XP Animation – wird kurz auf >0 gesetzt, dann zurück auf 0
final tutorXpGainProvider = StateProvider.family<int, String>(
  (ref, childId) => 0,
);

/// Session-ID die beim nächsten TutorScreen-Öffnen reaktiviert werden soll
/// Wird von TutorHistoryTab gesetzt, von TutorNotifier einmalig konsumiert
final tutorResumeSessionIdProvider = StateProvider<String?>((ref) => null);

/// Flag: nächster TutorScreen-Aufruf soll frischen Chat starten (keine aktive Session laden)
/// Wird von StudentDashboard gesetzt, von TutorNotifier einmalig konsumiert
final tutorFreshChatProvider = StateProvider<bool>((ref) => false);

// ============================================================================
// PROVIDER
// ============================================================================

/// Ein Chat pro Kind. autoDispose: Verlässt das Kind den Tutor, schließt der
/// Bildschirm die Session ab und der Notifier wird entsorgt. Beim nächsten
/// Öffnen lädt ein neuer Notifier den passenden Stand – kein alter Verlauf
/// über einer neuen Session.
final tutorProviderFamily = StateNotifierProvider.autoDispose
    .family<TutorNotifier, List<ChatMessage>, String>((ref, childId) {
      final service = ref.watch(vertexAIServiceProvider);
      final user = ref.watch(authStateChangesProvider).value;

      if (user == null) {
        throw Exception('User nicht eingeloggt');
      }

      return TutorNotifier(service, ref, childId, user.ownerUid);
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
