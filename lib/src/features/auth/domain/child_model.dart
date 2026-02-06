import 'package:cloud_firestore/cloud_firestore.dart';

/// Repräsentiert ein Kind in der App
/// Enthält alle wichtigen Daten: Level, XP, Sterne, Lernzeit
class ChildModel {
  final String id;              // Eindeutige ID aus Firestore
  final String name;            // Name des Kindes
  final int level;              // Aktuelles Level (startet bei 1)
  final int grade;              // Schulklasse (1-13)
  final String schoolType;      // Schulform (Grundschule, Gymnasium, etc.)
  final int age;                // Alter des Kindes
  final int stars;              // Gesammelte Sterne
  final int totalLearningSeconds; // Gesamte Lernzeit in Sekunden
  final int xp;                 // Experience Points (für Level-System)
  final int xpToNextLevel;      // XP benötigt für nächstes Level

  // NEU: Zusätzliche Tracking-Felder
  final int? streak;            // Lern-Streak (Tage am Stück)
  final int? totalQuizzes;      // Anzahl abgeschlossener Quizze
  final int? perfectQuizzes;    // Anzahl perfekter Quizze (10/10)
  final DateTime? lastLearningDate;  // Letztes Lerndatum
  final DateTime? lastQuizDate;      // Letztes Quiz-Datum
  final DateTime? lastXPGain;        // Letzter XP-Gewinn

  const ChildModel({
    required this.id,
    required this.name,
    this.level = 1,
    required this.grade,
    required this.schoolType,
    required this.age,
    this.stars = 0,
    this.totalLearningSeconds = 0,
    this.xp = 0,
    this.xpToNextLevel = 25,    // Standard: 25 XP für Level 2
    // NEU: Optional parameters
    this.streak,
    this.totalQuizzes,
    this.perfectQuizzes,
    this.lastLearningDate,
    this.lastQuizDate,
    this.lastXPGain,
  });

  /// Berechnet den XP-Fortschritt als Prozentwert (0.0 - 1.0)
  /// Wird für den Fortschrittsbalken/Ring verwendet
  double get xpProgress => xpToNextLevel > 0 ? xp / xpToNextLevel : 0.0;

  /// Prüft, ob genug XP für ein Level-Up vorhanden sind
  bool get canLevelUp => xp >= xpToNextLevel;

  /// Gibt die Lernzeit formatiert zurück (z.B. "1h 23min" oder "45min")
  String get formattedLearningTime {
    final hours = totalLearningSeconds ~/ 3600;
    final minutes = (totalLearningSeconds % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${minutes}min';
    return '${minutes}min';
  }

  /// Erstellt ein ChildModel aus Firestore-Daten
  /// Wird beim Laden der Kinder aus der Datenbank verwendet
  factory ChildModel.fromMap(Map<String, dynamic> data, String id) {
    return ChildModel(
      id: id,
      name: data['name'] ?? '',
      level: data['level'] ?? 1,
      grade: data['grade'] ?? 1,
      schoolType: data['schoolType'] ?? 'Grundschule',
      age: data['age'] ?? 6,
      stars: data['stars'] ?? 0,
      totalLearningSeconds: data['totalLearningSeconds'] ?? 0,
      xp: data['xp'] ?? 0,
      xpToNextLevel: data['xpToNextLevel'] ?? 25,
      // NEU: Lade zusätzliche Felder
      streak: data['streak'],
      totalQuizzes: data['totalQuizzes'],
      perfectQuizzes: data['perfectQuizzes'],
      lastLearningDate: (data['lastLearningDate'] as Timestamp?)?.toDate(),
      lastQuizDate: (data['lastQuizDate'] as Timestamp?)?.toDate(),
      lastXPGain: (data['lastXPGain'] as Timestamp?)?.toDate(),
    );
  }

  /// Alias für fromMap (für Kompatibilität mit xp_service.dart)
  factory ChildModel.fromFirestore(Map<String, dynamic> data, String id) {
    return ChildModel.fromMap(data, id);
  }

  /// Konvertiert das Modell in eine Map für Firestore
  /// Wird beim Speichern in der Datenbank verwendet
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'level': level,
      'grade': grade,
      'schoolType': schoolType,
      'age': age,
      'stars': stars,
      'totalLearningSeconds': totalLearningSeconds,
      'xp': xp,
      'xpToNextLevel': xpToNextLevel,
      // NEU: Speichere zusätzliche Felder (wenn vorhanden)
      if (streak != null) 'streak': streak,
      if (totalQuizzes != null) 'totalQuizzes': totalQuizzes,
      if (perfectQuizzes != null) 'perfectQuizzes': perfectQuizzes,
      if (lastLearningDate != null) 'lastLearningDate': Timestamp.fromDate(lastLearningDate!),
      if (lastQuizDate != null) 'lastQuizDate': Timestamp.fromDate(lastQuizDate!),
      if (lastXPGain != null) 'lastXPGain': Timestamp.fromDate(lastXPGain!),
    };
  }

  /// Erstellt eine Kopie mit geänderten Werten
  /// Nützlich für State-Updates ohne das Original zu ändern
  ChildModel copyWith({
    String? id,
    String? name,
    int? level,
    int? grade,
    String? schoolType,
    int? age,
    int? stars,
    int? totalLearningSeconds,
    int? xp,
    int? xpToNextLevel,
    int? streak,
    int? totalQuizzes,
    int? perfectQuizzes,
    DateTime? lastLearningDate,
    DateTime? lastQuizDate,
    DateTime? lastXPGain,
  }) {
    return ChildModel(
      id: id ?? this.id,
      name: name ?? this.name,
      level: level ?? this.level,
      grade: grade ?? this.grade,
      schoolType: schoolType ?? this.schoolType,
      age: age ?? this.age,
      stars: stars ?? this.stars,
      totalLearningSeconds: totalLearningSeconds ?? this.totalLearningSeconds,
      xp: xp ?? this.xp,
      xpToNextLevel: xpToNextLevel ?? this.xpToNextLevel,
      // NEU: Kopiere zusätzliche Felder
      streak: streak ?? this.streak,
      totalQuizzes: totalQuizzes ?? this.totalQuizzes,
      perfectQuizzes: perfectQuizzes ?? this.perfectQuizzes,
      lastLearningDate: lastLearningDate ?? this.lastLearningDate,
      lastQuizDate: lastQuizDate ?? this.lastQuizDate,
      lastXPGain: lastXPGain ?? this.lastXPGain,
    );
  }
}
