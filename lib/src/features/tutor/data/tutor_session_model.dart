import 'package:cloud_firestore/cloud_firestore.dart';

/// 💬 TUTOR SESSION MODEL
/// Repräsentiert eine zusammenhängende Tutor-Session
class TutorSession {
  final String id;
  final String childId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String status; // 'active' | 'completed'
  final int messageCount;
  final int durationSeconds;
  final String? detectedTopic; // 'Mathematik', 'Deutsch', etc.
  final String? firstQuestion; // Erste Frage des Schülers
  final String? contentFlag; // null | 'off_topic' | 'critical'

  // Zukünftig für Belohnungen
  final int? xpEarned;
  final int? starsEarned;

  const TutorSession({
    required this.id,
    required this.childId,
    required this.startedAt,
    this.endedAt,
    required this.status,
    this.messageCount = 0,
    this.durationSeconds = 0,
    this.detectedTopic,
    this.firstQuestion,
    this.contentFlag,
    this.xpEarned,
    this.starsEarned,
  });

  /// Erstellt Session aus Firestore
  factory TutorSession.fromFirestore(Map<String, dynamic> data, String id) {
    return TutorSession(
      id: id,
      childId: data['childId'] ?? '',
      startedAt: (data['startedAt'] as Timestamp).toDate(),
      endedAt: data['endedAt'] != null
          ? (data['endedAt'] as Timestamp).toDate()
          : null,
      status: data['status'] ?? 'active',
      messageCount: data['messageCount'] ?? 0,
      durationSeconds: data['durationSeconds'] ?? 0,
      detectedTopic: data['detectedTopic'],
      firstQuestion: data['firstQuestion'],
      contentFlag: data['contentFlag'],
      xpEarned: data['xpEarned'],
      starsEarned: data['starsEarned'],
    );
  }

  /// Konvertiert zu Firestore Map
  Map<String, dynamic> toMap() {
    return {
      'childId': childId,
      'startedAt': Timestamp.fromDate(startedAt),
      if (endedAt != null) 'endedAt': Timestamp.fromDate(endedAt!),
      'status': status,
      'messageCount': messageCount,
      'durationSeconds': durationSeconds,
      if (detectedTopic != null) 'detectedTopic': detectedTopic,
      if (firstQuestion != null) 'firstQuestion': firstQuestion,
      if (contentFlag != null) 'contentFlag': contentFlag,
      if (xpEarned != null) 'xpEarned': xpEarned,
      if (starsEarned != null) 'starsEarned': starsEarned,
    };
  }

  /// Kopie mit geänderten Werten
  TutorSession copyWith({
    String? id,
    String? childId,
    DateTime? startedAt,
    DateTime? endedAt,
    String? status,
    int? messageCount,
    int? durationSeconds,
    String? detectedTopic,
    String? firstQuestion,
    String? contentFlag,
    int? xpEarned,
    int? starsEarned,
  }) {
    return TutorSession(
      id: id ?? this.id,
      childId: childId ?? this.childId,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      status: status ?? this.status,
      messageCount: messageCount ?? this.messageCount,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      detectedTopic: detectedTopic ?? this.detectedTopic,
      firstQuestion: firstQuestion ?? this.firstQuestion,
      contentFlag: contentFlag ?? this.contentFlag,
      xpEarned: xpEarned ?? this.xpEarned,
      starsEarned: starsEarned ?? this.starsEarned,
    );
  }

  /// Prüft ob Session aktiv ist
  bool get isActive => status == 'active';

  /// Prüft ob Session abgeschlossen ist
  bool get isCompleted => status == 'completed';

  /// Berechnet Dauer basierend auf Start/Ende
  Duration get duration {
    final end = endedAt ?? DateTime.now();
    return end.difference(startedAt);
  }

  /// Formatierte Dauer
  String get formattedDuration {
    final d = duration;
    if (d.inMinutes < 1) {
      return '< 1 Min';
    } else if (d.inMinutes < 60) {
      return '${d.inMinutes} Min';
    } else {
      final hours = d.inHours;
      final minutes = d.inMinutes % 60;
      return '${hours}h ${minutes}min';
    }
  }

  // =========================================================================
  // TOPIC & FLAG DETECTION
  // =========================================================================

  /// Gibt den Content-Flag für eine Nachricht zurück.
  ///
  /// Rückgabewerte:
  ///   null         → normales Schulthema, kein Flag
  ///   'off_topic'  → Nicht-Schulthema (Alltag, Freizeit, …)
  ///   'critical'   → potenziell bedenklicher Inhalt
  ///
  // TODO: Refactor – ähnliche Prüfung existiert in FirebaseAIService
  // (_isAppropriateQuestion / _isNonSchoolQuestion). Beim nächsten Review
  // in eine gemeinsame ContentAnalyzer-Klasse konsolidieren.
  static String? detectContentFlag(String text) {
    final q = text.toLowerCase().trim();
    // ── 🚨 CRITICAL: Bedenkliche Inhalte ─────────────────────────────────────
    // Gewalt
    if (q.contains('töten') ||
        q.contains('umbringen') ||
        q.contains('ermorden') ||
        q.contains('morden') ||
        q.contains('angreifen') ||
        q.contains('schlagen') ||
        q.contains('prügeln') ||
        (q.contains('verletzen') && q.contains('absicht')) ||
        q.contains('waffe') ||
        (q.contains('messer') && q.contains('person')) ||
        q.contains('pistole') ||
        q.contains('schuss') ||
        q.contains('bombe') ||
        q.contains('sprengen')) {
      return 'critical';
    }

    // Selbstverletzung / Suizid
    if (q.contains('selbstmord') ||
        q.contains('suizid') ||
        q.contains('sich umbringen') ||
        q.contains('sterben wollen') ||
        q.contains('nicht mehr leben') ||
        q.contains('selbst verletzen') ||
        q.contains('ritzen')) {
      return 'critical';
    }

    // Sexueller Inhalt
    if (q.contains('sex') ||
        q.contains('nackt') ||
        q.contains('pornо') ||
        q.contains('erotik') ||
        q.contains('intim') && (q.contains('bild') || q.contains('video')) ||
        q.contains('vergewaltigung')) {
      return 'critical';
    }

    // Drogen / gefährliche Substanzen
    if (q.contains('drogen') ||
        q.contains('kokain') ||
        q.contains('heroin') ||
        q.contains('crystal') ||
        (q.contains('cannabis') && q.contains('kaufen')) ||
        (q.contains('kiffen') && q.contains('wie')) ||
        (q.contains('alkohol') &&
            q.contains('trinken') &&
            q.contains('wie viel'))) {
      return 'critical';
    }

    // Mobbing / Beleidigungen
    if (q.contains('mobbing') && q.contains('wie') ||
        q.contains('jemanden fertig machen') ||
        q.contains('demütigen') ||
        q.contains('erniedrigen') ||
        q.contains('hassen') && q.contains('person')) {
      return 'critical';
    }

    // Persönliche Daten
    if (q.contains('passwort') ||
        q.contains('hacken') ||
        q.contains('konto knacken') ||
        q.contains('daten stehlen')) {
      return 'critical';
    }

    // ── ⚠️ OFF_TOPIC: Nicht-Schulthemen ──────────────────────────────────────

    // Gaming – einzelne Spielnamen reichen
    const gameKeywords = [
      'minecraft',
      'fortnite',
      'roblox',
      'fifa',
      'gta',
      'cod',
      'call of duty',
      'among us',
      'brawl stars',
      'clash',
      'pokemon go',
      'zelda',
      'mario',
      'league of legends',
      'valorant',
      'apex',
      'gaming',
      'zocken',
      'videospiel',
      'computerspiel',
      'cheat',
      'cheaten',
      'skin kaufen',
      'v-bucks',
      'robux',
      'level freischalten',
    ];
    if (gameKeywords.any((k) => q.contains(k))) return 'off_topic';

    // Social Media & Streaming
    const socialKeywords = [
      'tiktok',
      'instagram',
      'snapchat',
      'youtube',
      'twitch',
      'netflix',
      'disney+',
      'amazon prime',
      'spotify',
      'likes',
      'follower',
      'subscriber',
      'reel',
      'story posten',
      'livestream',
      'streamer',
    ];
    if (socialKeywords.any((k) => q.contains(k))) return 'off_topic';

    // Kochen & Essen
    const foodKeywords = [
      'rezept',
      'kochen',
      'zubereiten',
      'pizza',
      'burger',
      'nuggets',
      'pasta',
      'spaghetti',
      'kuchen backen',
      'pfannkuchen',
      'smoothie',
      'was soll ich essen',
      'was kann ich kochen',
      'hunger',
    ];
    if (foodKeywords.any((k) => q.contains(k))) return 'off_topic';

    // Freizeit, Party, Soziales
    const leisureKeywords = [
      'party',
      'feiern',
      'treffen',
      'schlafen gehen',
      'schlafen',
      'langweilig',
      'langeweile',
      'nichts zu tun',
      'was soll ich machen',
      'was kann ich heute',
      'urlaub',
      'ferien',
      'ausflug',
      'kino',
      'zoo',
      'freizeitpark',
      'konzert',
    ];
    if (leisureKeywords.any((k) => q.contains(k))) return 'off_topic';

    // Shopping & Konsum
    const shoppingKeywords = [
      'kaufen',
      'bestellen',
      'amazon',
      'ebay',
      'zalando',
      'handy',
      'smartphone',
      'iphone',
      'samsung',
      'airpods',
      'schuhe',
      'kleidung',
      'outfit',
      'sneaker',
      'hoodie',
      'geschenk',
      'wunschliste',
      'rabatt',
      'angebot',
    ];
    if (shoppingKeywords.any((k) => q.contains(k))) return 'off_topic';

    // Sport (Unterhaltung, nicht Schulfach)
    const sportEntertainmentKeywords = [
      'bundesliga',
      'champions league',
      'premier league',
      'transfermarkt',
      'welcher spieler',
      'welches team',
      'bester fußballer',
      'tore geschossen',
      'fc bayern',
      'bvb',
      'real madrid',
      'nba',
      'nfl',
    ];
    if (sportEntertainmentKeywords.any((k) => q.contains(k)))
      return 'off_topic';

    // Haustiere (Alltag, nicht Biologie)
    if ((q.contains('hund') ||
            q.contains('katze') ||
            q.contains('hamster') ||
            q.contains('haustier')) &&
        (q.contains('mein') ||
            q.contains('unser') ||
            q.contains('füttern') ||
            q.contains('spielen') ||
            q.contains('gassi'))) {
      return 'off_topic';
    }

    // Allgemeine "Was soll ich"-Fragen (kein Schulbezug)
    if ((q.contains('was soll ich') ||
            q.contains('was kann ich') ||
            q.contains('was mache ich') ||
            q.contains('ich bin gelangweilt') ||
            q.contains('ich langweile') ||
            q.contains('hast du lust')) &&
        !q.contains('aufgabe') &&
        !q.contains('rechnen') &&
        !q.contains('lernen') &&
        !q.contains('hausaufgabe')) {
      return 'off_topic';
    }

    return null; // ✅ Kein Flag – normales Schulthema
  }

  /// Erkenne Thema aus Text (Heuristik)
  // TODO: Refactor – gleiche Logik existiert in TutorNotifier.detectTopic()
  // in tutor_provider.dart. Beim nächsten Review konsolidieren.
  static String detectTopic(String text) {
    final q = text.toLowerCase().trim();

    // ── MATHEMATIK ───────────────────────────────────────────────────────────
    if (q.contains('mathe') || q.contains('mathematik')) return 'Mathematik';
    if (RegExp(r'\d+\s*[\+\-\*\/×÷]\s*\d+').hasMatch(q)) return 'Mathematik';
    if (RegExp(r'\d+\s*(mal|durch|plus|minus|geteilt)\s*\d+').hasMatch(q))
      return 'Mathematik';
    if (RegExp(r'wie viel[e]? (ist|sind|macht|ergibt|gibt)').hasMatch(q) &&
        RegExp(r'\d').hasMatch(q)) {
      return 'Mathematik';
    }
    if (q.contains('rechnen') ||
        q.contains('berechne') ||
        q.contains('ausrechnen') ||
        q.contains('berechnen')) {
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
    if (q.contains('bruch') ||
        q.contains('nenner') ||
        q.contains('zähler') ||
        q.contains('prozent') ||
        q.contains('dezimal') ||
        q.contains('kommazahl')) {
      return 'Mathematik';
    }
    if (q.contains('gleichung') || q.contains('ungleichung'))
      return 'Mathematik';
    if (q.contains('dreieck') ||
        q.contains('kreis') ||
        q.contains('quadrat') ||
        q.contains('rechteck') ||
        q.contains('fläche') ||
        q.contains('umfang') ||
        q.contains('volumen') ||
        q.contains('geometrie')) {
      return 'Mathematik';
    }
    if (q.contains('wurzel') ||
        q.contains('potenz') ||
        q.contains('hoch ') ||
        q.contains('quadriert')) {
      return 'Mathematik';
    }
    if (q.contains('einmaleins') ||
        q.contains('dreisatz') ||
        q.contains('kopfrechnen')) {
      return 'Mathematik';
    }
    if (q.contains('addition') ||
        q.contains('subtraktion') ||
        q.contains('multiplikation') ||
        q.contains('division')) {
      return 'Mathematik';
    }
    if (q.contains('wahrscheinlichkeit') ||
        q.contains('statistik') ||
        q.contains('stochastik')) {
      return 'Mathematik';
    }
    if (q.contains('pythagoras') ||
        q.contains('trigonometrie') ||
        q.contains('sinus') ||
        q.contains('kosinus') ||
        q.contains('tangens')) {
      return 'Mathematik';
    }

    // ── PHYSIK ───────────────────────────────────────────────────────────────
    if (q.contains('physik')) return 'Physik';
    if (q.contains('geschwindigkeit') ||
        q.contains('beschleunigung') ||
        q.contains('trägheit')) {
      return 'Physik';
    }
    if (q.contains('kraft') &&
        (q.contains('newt') ||
            q.contains('masse') ||
            q.contains('beschleunig'))) {
      return 'Physik';
    }
    if (q.contains('elektrisch') ||
        (q.contains('strom') &&
            (q.contains('volt') ||
                q.contains('ampere') ||
                q.contains('widerstand') ||
                q.contains('spannung')))) {
      return 'Physik';
    }
    if (q.contains('magnetfeld') || q.contains('elektromagnet'))
      return 'Physik';
    if (q.contains('licht') &&
        (q.contains('brechung') ||
            q.contains('reflex') ||
            q.contains('welle') ||
            q.contains('spektrum'))) {
      return 'Physik';
    }
    if (q.contains('schall') ||
        q.contains('schallwelle') ||
        q.contains('frequenz') ||
        q.contains('dezibel')) {
      return 'Physik';
    }
    if (q.contains('wärme') &&
        (q.contains('temperatur') ||
            q.contains('ausdehnung') ||
            q.contains('leitung'))) {
      return 'Physik';
    }
    if (q.contains('energie') &&
        (q.contains('kinetisch') ||
            q.contains('potenziell') ||
            q.contains('joule') ||
            q.contains('leistung'))) {
      return 'Physik';
    }
    if (q.contains('hebelgesetz') ||
        (q.contains('hebel') && q.contains('kraft'))) {
      return 'Physik';
    }
    if (q.contains('druck') &&
        (q.contains('pascal') ||
            q.contains('gas') ||
            q.contains('flüssig') ||
            q.contains('atmo'))) {
      return 'Physik';
    }
    if (q.contains('atom') &&
        (q.contains('kern') ||
            q.contains('elektron') ||
            q.contains('proton') ||
            q.contains('neutron'))) {
      return 'Physik';
    }
    if (q.contains('radioaktiv') ||
        q.contains('gravitation') ||
        q.contains('schwerkraft')) {
      return 'Physik';
    }
    if (q.contains('optik') || (q.contains('linse') && q.contains('licht'))) {
      return 'Physik';
    }
    if (q.contains('pendel') || q.contains('schwingung')) return 'Physik';
    if (q.contains('newton') &&
        (q.contains('gesetz') || q.contains('einheit'))) {
      return 'Physik';
    }

    // ── CHEMIE ───────────────────────────────────────────────────────────────
    if (q.contains('chemie') || q.contains('chemisch')) return 'Chemie';
    if (q.contains('molekül') ||
        (q.contains('verbindung') && q.contains('stoff'))) {
      return 'Chemie';
    }
    if (q.contains('periodensystem') ||
        (q.contains('element') &&
            (q.contains('symbol') || q.contains('stoff')))) {
      return 'Chemie';
    }
    if (q.contains('säure') ||
        (q.contains('base') && q.contains('ph')) ||
        q.contains('ph-wert')) {
      return 'Chemie';
    }
    if (q.contains('oxidation') ||
        q.contains('reduktion') ||
        q.contains('redox')) {
      return 'Chemie';
    }
    if (q.contains('aggregatzustand') ||
        q.contains('siedepunkt') ||
        (q.contains('schmelzen') && q.contains('stoff'))) {
      return 'Chemie';
    }
    if (q.contains('ionen') || q.contains('ionenbindung')) return 'Chemie';
    if (q.contains('kohlenstoff') ||
        q.contains('sauerstoff') && q.contains('stoff')) {
      return 'Chemie';
    }
    if (q.contains('verbrennung') && q.contains('sauerstoff')) return 'Chemie';
    if (q.contains('organisch') || q.contains('kohlenwasserstoff'))
      return 'Chemie';

    // ── BIOLOGIE ─────────────────────────────────────────────────────────────
    if (q.contains('biologie') || q.contains('biologisch')) return 'Biologie';
    if (q.contains('zelle') &&
        (q.contains('kern') ||
            q.contains('membran') ||
            q.contains('teilung') ||
            q.contains('organell'))) {
      return 'Biologie';
    }
    if (q.contains('dna') ||
        q.contains('chromosom') ||
        q.contains('genetik') ||
        q.contains('vererbung')) {
      return 'Biologie';
    }
    if (q.contains('evolution') ||
        q.contains('artbildung') ||
        q.contains('mutation') && q.contains('gen')) {
      return 'Biologie';
    }
    if (q.contains('ökosystem') ||
        q.contains('nahrungskette') ||
        q.contains('ökologie')) {
      return 'Biologie';
    }
    if (q.contains('fotosynthese') ||
        q.contains('photosynthese') ||
        q.contains('chlorophyll') ||
        q.contains('chloroplast')) {
      return 'Biologie';
    }
    if (q.contains('mitose') ||
        q.contains('meiose') ||
        q.contains('zellteilung')) {
      return 'Biologie';
    }
    if (q.contains('virus') || q.contains('bakterie')) return 'Biologie';
    if (q.contains('immunsystem') || q.contains('antikörper'))
      return 'Biologie';

    // ── ENGLISCH ─────────────────────────────────────────────────────────────
    if (q.contains('englisch') || q.contains('english')) return 'Englisch';
    if (q.contains('übersetze') || q.contains('auf englisch'))
      return 'Englisch';
    if (q.contains('past tense') ||
        q.contains('present tense') ||
        q.contains('future tense') ||
        q.contains('simple past') ||
        q.contains('present perfect') ||
        q.contains('past perfect') ||
        q.contains('present simple') ||
        q.contains('present continuous')) {
      return 'Englisch';
    }
    if (q.contains('irregular') ||
        (q.contains('unregelmäßig') && q.contains('verb'))) {
      return 'Englisch';
    }
    if (q.contains('vokabel') ||
        q.contains('vokabeln') ||
        q.contains('vocabulary')) {
      return 'Englisch';
    }
    if (q.split(' ').length >= 4 &&
        RegExp(
          r'\b(what|how|why|when|where|who|which|the |is |are |was |were |have |has |had |will |would |can |could |should |do |does |did )\b',
        ).hasMatch(q)) {
      return 'Englisch';
    }

    // ── DEUTSCH ──────────────────────────────────────────────────────────────
    if (q.contains('grammatik') || q.contains('rechtschreibung'))
      return 'Deutsch';
    if (q.contains('nomen') ||
        q.contains('substantiv') ||
        q.contains('adjektiv') ||
        q.contains('adverb') ||
        q.contains('pronomen') ||
        q.contains('präposition') ||
        q.contains('konjunktion')) {
      return 'Deutsch';
    }
    if (q.contains('konjugier') ||
        q.contains('konjugation') ||
        q.contains('zeitform') ||
        q.contains('präteritum') ||
        q.contains('plusquamperfekt') ||
        (q.contains('futur') && !q.contains('future'))) {
      return 'Deutsch';
    }
    if (q.contains('nominativ') ||
        q.contains('genitiv') ||
        q.contains('dativ') ||
        q.contains('akkusativ')) {
      return 'Deutsch';
    }
    if (q.contains('hauptsatz') ||
        q.contains('nebensatz') ||
        q.contains('satzzeichen') ||
        q.contains('interpunktion')) {
      return 'Deutsch';
    }
    if (q.contains('komma') && (q.contains('satz') || q.contains('regel'))) {
      return 'Deutsch';
    }
    if (q.contains('großschreib') || q.contains('kleinschreib'))
      return 'Deutsch';
    if (q.contains('aufsatz') ||
        q.contains('gedicht') ||
        q.contains('strophe') ||
        q.contains('reim')) {
      return 'Deutsch';
    }
    if (q.contains('silbe') ||
        q.contains('wortart') ||
        q.contains('vorsilbe') ||
        q.contains('nachsilbe')) {
      return 'Deutsch';
    }
    if (q.contains('komparativ') || q.contains('superlativ')) return 'Deutsch';
    if (q.contains('verb') &&
        !q.contains('englisch') &&
        !q.contains('english') &&
        !q.contains('tense') &&
        !q.contains('irregular')) {
      return 'Deutsch';
    }
    if (q.contains(' satz') &&
        !q.contains('dreisatz') &&
        !q.contains('pythagoras')) {
      return 'Deutsch';
    }

    // ── GESCHICHTE ───────────────────────────────────────────────────────────
    if (q.contains('geschichte') && !q.contains('lebens')) return 'Geschichte';
    if (q.contains('weltkrieg')) return 'Geschichte';
    if (q.contains('römer') || q.contains('römisch') || q.contains('antike')) {
      return 'Geschichte';
    }
    if (q.contains('mittelalter') || q.contains('kreuzzug'))
      return 'Geschichte';
    if (q.contains('französische revolution')) return 'Geschichte';
    if (q.contains('nationalsozialismu') ||
        q.contains('holocaust') ||
        q.contains('drittes reich') ||
        q.contains('weimarer republik')) {
      return 'Geschichte';
    }
    if (q.contains('kalter krieg') ||
        q.contains('mauerfall') ||
        q.contains('deutsche teilung')) {
      return 'Geschichte';
    }
    if (q.contains('altes ägypten') ||
        q.contains('pharao') ||
        q.contains('hieroglyphe')) {
      return 'Geschichte';
    }
    if (q.contains('reformation') ||
        (q.contains('luther') && q.contains('kirch'))) {
      return 'Geschichte';
    }
    if (q.contains('industrierevolution')) return 'Geschichte';
    if (q.contains('bismarck') || q.contains('wilhelmin')) return 'Geschichte';

    // ── GEOGRAPHIE ───────────────────────────────────────────────────────────
    if (q.contains('geographie') ||
        q.contains('erdkunde') ||
        q.contains('geografie')) {
      return 'Geographie';
    }
    if (q.contains('kontinent') || q.contains('weltkarte')) return 'Geographie';
    if (q.contains('hauptstadt') ||
        (q.contains('land') && q.contains('grenzt'))) {
      return 'Geographie';
    }
    if (q.contains('fluss') &&
        (q.contains('länge') || q.contains('mündet') || q.contains('quelle'))) {
      return 'Geographie';
    }
    if (q.contains('gebirge') ||
        q.contains('himalaya') ||
        q.contains('everest')) {
      return 'Geographie';
    }
    if (q.contains('klimazone') ||
        (q.contains('klima') && q.contains('tropen'))) {
      return 'Geographie';
    }
    if (q.contains('vulkan') ||
        q.contains('plattentektonik') ||
        q.contains('erdplatten')) {
      return 'Geographie';
    }

    // ── SACHKUNDE ────────────────────────────────────────────────────────────
    if (q.contains('sachkunde') || q.contains('sachunterricht'))
      return 'Sachkunde';
    if (q.contains('pflanze') ||
        q.contains('blume') ||
        (q.contains('baum') && q.contains('wächst'))) {
      return 'Sachkunde';
    }
    if (q.contains('tier ') || q.contains('tiere') || q.contains('tierart')) {
      return 'Sachkunde';
    }
    if (q.contains('insekt') ||
        q.contains('schmetterling') ||
        q.contains('biene') ||
        q.contains('vogel') ||
        q.contains('säugetier')) {
      return 'Sachkunde';
    }
    if (q.contains('jahreszeit') || q.contains('frühling')) return 'Sachkunde';
    if (q.contains('blutkreislauf') ||
        q.contains('herzschlag') ||
        q.contains('lunge') ||
        q.contains('knochen')) {
      return 'Sachkunde';
    }
    if (q.contains('umwelt') ||
        q.contains('recycling') ||
        q.contains('naturschutz') ||
        q.contains('klimawandel')) {
      return 'Sachkunde';
    }
    if (q.contains('sonnensystem') ||
        q.contains('weltall') ||
        q.contains('galaxie')) {
      return 'Sachkunde';
    }
    if (q.contains('verkehr') || q.contains('verkehrszeichen'))
      return 'Sachkunde';
    if (q.contains('ernährung') ||
        q.contains('vitamin') ||
        q.contains('nährstoff')) {
      return 'Sachkunde';
    }

    // ── INFORMATIK ───────────────────────────────────────────────────────────
    if (q.contains('informatik') ||
        (q.contains('programmier') && q.contains('schul'))) {
      return 'Informatik';
    }
    if (q.contains('algorithmus')) return 'Informatik';

    // ── MUSIK ────────────────────────────────────────────────────────────────
    if (q.contains('musik') &&
        (q.contains('note') ||
            q.contains('takt') ||
            q.contains('rhythmus') ||
            q.contains('tonleiter'))) {
      return 'Musik';
    }

    // ── LATEIN ───────────────────────────────────────────────────────────────
    if (q.contains('latein') ||
        q.contains('lateinisch') ||
        q.contains('ablativ')) {
      return 'Latein';
    }

    // ── FRANZÖSISCH ──────────────────────────────────────────────────────────
    if (q.contains('französisch') && !q.contains('revolution'))
      return 'Französisch';

    // ── SPANISCH ─────────────────────────────────────────────────────────────
    if (q.contains('spanisch')) return 'Spanisch';

    return 'Allgemein';
  }
}
