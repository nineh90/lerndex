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
    if (sportEntertainmentKeywords.any((k) => q.contains(k))) {
      return 'off_topic';
    }

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
}
