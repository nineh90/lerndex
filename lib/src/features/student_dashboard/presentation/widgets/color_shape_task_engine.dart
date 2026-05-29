import 'dart:math';

// ============================================================================
// COLOR SHAPE TASK ENGINE – Algorithmischer Generator für Klasse 1 & 2
//
// Kein KI, kein Firebase, keine Duplikate.
// Aufgaben skalieren mit dem Level des Kindes.
//
// 5 feste Slots je Runde (immer alle 5 Typen, zufällig gemischt):
//
// Stufe 1 (Lvl  1– 3): farbeNennen | formNennen | gleicheFarbe | farbMuster | oddOneOutFarbe
// Stufe 2 (Lvl  4– 7): farbeNennen | formNennen | gleicheFarbe | farbeZuordnen | oddOneOutForm
// Stufe 3 (Lvl  8–12): farbeNennen | formNennen | gleicheForm  | wieVieleEcken | farbeZuordnen
// Stufe 4 (Lvl 13–20): farbeNennen | formNennen | gleicheForm  | wieVieleEcken | formZeichnen
// Stufe 5 (Lvl 21+  ): farbeNennen | formNennen | gleicheForm  | wieVieleEcken | formZeichnen
//
// Aufgabentypen:
//   farbeNennen    – 🔴 → Rot / Blau / Gelb / Grün
//   formNennen     – ⬛ → Quadrat / Kreis / Dreieck / Rechteck
//   gleicheFarbe   – Was ist auch rot? → 🍓/🌳/☀️/🐸
//   gleicheForm    – Was hat die gleiche Form wie ○? → 🌕/📦/🔺/💎
//   farbMuster     – 🔴🔵🔴__ → welche Farbe kommt?
//   formMuster     – ○□○__ → welche Form kommt?
//   oddOneOutFarbe – Was ist nicht rot? (3 rote + 1 andere)
//   oddOneOutForm  – Was ist nicht rund? (3 runde + 1 eckige)
//   farbeZuordnen  – Welche Farbe hat dieses Objekt?
//   wieVieleEcken  – ▲ hat wie viele Ecken? → 3/4/5/6
//   formZeichnen   – Male einen Kreis (Vertex AI prüft)
// ============================================================================

enum ColorShapeTaskType {
  farbeNennen, // Farb-Emoji → Farbe benennen
  formNennen, // Form-Emoji → Form benennen
  gleicheFarbe, // Welches Objekt hat die gleiche Farbe?
  gleicheForm, // Welches Objekt hat die gleiche Form?
  farbMuster, // Farbmuster ergänzen
  formMuster, // Formmuster ergänzen (ab Stufe 2)
  oddOneOutFarbe, // Was passt farblich nicht dazu?
  oddOneOutForm, // Was passt formal nicht dazu?
  farbeZuordnen, // Welche Farbe hat dieses Objekt?
  wieVieleEcken, // Wie viele Ecken hat diese Form?
  formZeichnen, // Form malen (Vertex AI prüft)
}

// ── Aufgaben-Modell ───────────────────────────────────────────────────────────

class ColorShapeTask {
  final ColorShapeTaskType type;
  final String questionText;

  /// Haupt-Emoji/Symbol der Frage
  final String? questionEmoji;

  /// Antwortoptionen (Text oder Emoji)
  final List<String> options;
  final String correctAnswer;
  final String feedbackCorrect;
  final String feedbackWrong;
  final int difficultyLevel;

  /// Für farbMuster / formMuster: die vollständige Sequenz
  final List<String>? sequence;

  /// Für farbMischung (nicht mehr aktiv genutzt, bleibt für Kompatibilität)
  final String? mixColor1;
  final String? mixColor2;

  /// Für formZeichnen: die zu zeichnende Form
  final String? shapeToDraw;

  const ColorShapeTask({
    required this.type,
    required this.questionText,
    required this.options,
    required this.correctAnswer,
    required this.feedbackCorrect,
    required this.feedbackWrong,
    required this.difficultyLevel,
    this.questionEmoji,
    this.sequence,
    this.mixColor1,
    this.mixColor2,
    this.shapeToDraw,
  });
}

// ── Farb-Daten ────────────────────────────────────────────────────────────────

class _ColorData {
  final String name; // z.B. "Rot"
  final String emoji; // z.B. "🔴"
  final List<String> objects; // rote Objekte als Emojis
  const _ColorData({
    required this.name,
    required this.emoji,
    required this.objects,
  });
}

const _colors = [
  _ColorData(
    name: 'Rot',
    emoji: '🔴',
    objects: ['🍎', '🍓', '🌹', '❤️', '🎈', '🚒', '🍒'],
  ),
  _ColorData(
    name: 'Blau',
    emoji: '🔵',
    objects: ['🫐', '🌊', '💙', '🧢', '🐳', '💎', '🫐'],
  ),
  _ColorData(
    name: 'Gelb',
    emoji: '🟡',
    objects: ['🍋', '🌻', '⭐', '🌟', '🍌', '🌕', '🌼'],
  ),
  _ColorData(
    name: 'Grün',
    emoji: '🟢',
    objects: ['🌿', '🍀', '🐸', '🥦', '🌲', '🍃', '🥝'],
  ),
  _ColorData(
    name: 'Orange',
    emoji: '🟠',
    objects: ['🍊', '🥕', '🎃', '🍑', '🦊', '🏵️', '🍁'],
  ),
  _ColorData(
    name: 'Lila',
    emoji: '🟣',
    objects: ['🍇', '💜', '🦄', '🌸', '🔮', '🌷', '🫙'],
  ),
  _ColorData(
    name: 'Weiß',
    emoji: '⬜',
    objects: ['☁️', '🐑', '❄️', '🥛', '🕊️', '🌨️', '🧻'],
  ),
  _ColorData(
    name: 'Schwarz',
    emoji: '⬛',
    objects: ['🦇', '🎱', '🖤', '🐦‍⬛', '🕶️', '♠️', '🦝'],
  ),
];

// ── Form-Daten ────────────────────────────────────────────────────────────────

class _ShapeData {
  final String name; // z.B. "Kreis"
  final String emoji; // z.B. "⭕"
  final int ecken; // Anzahl Ecken (0 = rund)
  final List<String> objects; // runde Objekte als Emojis
  final String description; // für TTS

  const _ShapeData({
    required this.name,
    required this.emoji,
    required this.ecken,
    required this.objects,
    required this.description,
  });
}

const _shapes = [
  _ShapeData(
    name: 'Kreis',
    emoji: '⭕',
    ecken: 0,
    objects: ['🌕', '🍕', '🎱', '🌍', '🍩', '⚽', '🌶️'],
    description: 'runde Form ohne Ecken',
  ),
  _ShapeData(
    name: 'Dreieck',
    emoji: '🔺',
    ecken: 3,
    objects: ['⛰️', '🔔', '🏔️', '📐', '⚠️', '🎄', '🍕'],
    description: 'Form mit 3 Ecken',
  ),
  _ShapeData(
    name: 'Quadrat',
    emoji: '🟦',
    ecken: 4,
    objects: ['📦', '🧊', '🪟', '🎲', '📱', '🖥️', '🎁'],
    description: 'Form mit 4 gleichen Seiten',
  ),
  _ShapeData(
    name: 'Rechteck',
    emoji: '▬',
    ecken: 4,
    objects: ['📄', '🚪', '🖼️', '📺', '🏠', '📏', '📋'],
    description: 'Form mit 4 Seiten, zwei länger',
  ),
  _ShapeData(
    name: 'Stern',
    emoji: '⭐',
    ecken: 5,
    objects: ['🌟', '✨', '💫', '🌠', '⭐', '🌃', '🎇'],
    description: 'Form mit 5 Zacken',
  ),
  _ShapeData(
    name: 'Raute',
    emoji: '🔷',
    ecken: 4,
    objects: ['💎', '♦️', '🃏', '🔷', '🔹', '🎯', '🃏'],
    description: 'Form mit 4 gleichen Seiten, spitz',
  ),
];

// ── Farbe-Zuordnen-Daten ─────────────────────────────────────────────────────

/// Objekt → seine bekannte Farbe (für Erstklässler eindeutig erkennbar)
const _farbeZuordnenPool = [
  // Gelbe Objekte
  {
    'emoji': '🍌',
    'farbe': 'Gelb',
    'falsch': ['Rot', 'Blau', 'Grün'],
  },
  {
    'emoji': '⭐',
    'farbe': 'Gelb',
    'falsch': ['Rot', 'Blau', 'Grün'],
  },
  {
    'emoji': '🌻',
    'farbe': 'Gelb',
    'falsch': ['Rot', 'Grün', 'Lila'],
  },
  {
    'emoji': '🍋',
    'farbe': 'Gelb',
    'falsch': ['Grün', 'Rot', 'Orange'],
  },
  {
    'emoji': '🌕',
    'farbe': 'Gelb',
    'falsch': ['Weiß', 'Blau', 'Grün'],
  },
  // Rote Objekte
  {
    'emoji': '🍎',
    'farbe': 'Rot',
    'falsch': ['Gelb', 'Blau', 'Grün'],
  },
  {
    'emoji': '🍓',
    'farbe': 'Rot',
    'falsch': ['Gelb', 'Blau', 'Orange'],
  },
  {
    'emoji': '🌹',
    'farbe': 'Rot',
    'falsch': ['Gelb', 'Blau', 'Grün'],
  },
  {
    'emoji': '❤️',
    'farbe': 'Rot',
    'falsch': ['Blau', 'Gelb', 'Grün'],
  },
  {
    'emoji': '🍒',
    'farbe': 'Rot',
    'falsch': ['Gelb', 'Grün', 'Blau'],
  },
  // Grüne Objekte
  {
    'emoji': '🌿',
    'farbe': 'Grün',
    'falsch': ['Gelb', 'Blau', 'Rot'],
  },
  {
    'emoji': '🍀',
    'farbe': 'Grün',
    'falsch': ['Gelb', 'Rot', 'Blau'],
  },
  {
    'emoji': '🐸',
    'farbe': 'Grün',
    'falsch': ['Gelb', 'Blau', 'Rot'],
  },
  {
    'emoji': '🥦',
    'farbe': 'Grün',
    'falsch': ['Gelb', 'Rot', 'Orange'],
  },
  {
    'emoji': '🌲',
    'farbe': 'Grün',
    'falsch': ['Gelb', 'Blau', 'Braun'],
  },
  // Blaue Objekte
  {
    'emoji': '🌊',
    'farbe': 'Blau',
    'falsch': ['Grün', 'Gelb', 'Rot'],
  },
  {
    'emoji': '💙',
    'farbe': 'Blau',
    'falsch': ['Rot', 'Gelb', 'Grün'],
  },
  {
    'emoji': '🐳',
    'farbe': 'Blau',
    'falsch': ['Grün', 'Gelb', 'Grau'],
  },
  {
    'emoji': '🧢',
    'farbe': 'Blau',
    'falsch': ['Rot', 'Gelb', 'Grün'],
  },
  {
    'emoji': '🫐',
    'farbe': 'Blau',
    'falsch': ['Rot', 'Gelb', 'Grün'],
  },
  // Orange Objekte
  {
    'emoji': '🍊',
    'farbe': 'Orange',
    'falsch': ['Gelb', 'Rot', 'Blau'],
  },
  {
    'emoji': '🥕',
    'farbe': 'Orange',
    'falsch': ['Gelb', 'Rot', 'Grün'],
  },
  {
    'emoji': '🎃',
    'farbe': 'Orange',
    'falsch': ['Gelb', 'Rot', 'Grün'],
  },
  {
    'emoji': '🦊',
    'farbe': 'Orange',
    'falsch': ['Gelb', 'Rot', 'Braun'],
  },
  {
    'emoji': '🍑',
    'farbe': 'Orange',
    'falsch': ['Gelb', 'Rot', 'Grün'],
  },
  // Lila Objekte
  {
    'emoji': '🍇',
    'farbe': 'Lila',
    'falsch': ['Blau', 'Rot', 'Grün'],
  },
  {
    'emoji': '💜',
    'farbe': 'Lila',
    'falsch': ['Blau', 'Rot', 'Gelb'],
  },
  {
    'emoji': '🔮',
    'farbe': 'Lila',
    'falsch': ['Blau', 'Grün', 'Gelb'],
  },
  // Weiße Objekte
  {
    'emoji': '☁️',
    'farbe': 'Weiß',
    'falsch': ['Gelb', 'Blau', 'Grau'],
  },
  {
    'emoji': '🐑',
    'farbe': 'Weiß',
    'falsch': ['Gelb', 'Grau', 'Blau'],
  },
  {
    'emoji': '❄️',
    'farbe': 'Weiß',
    'falsch': ['Blau', 'Grau', 'Gelb'],
  },
  // Schwarze Objekte
  {
    'emoji': '🦇',
    'farbe': 'Schwarz',
    'falsch': ['Grau', 'Blau', 'Grün'],
  },
  {
    'emoji': '🎱',
    'farbe': 'Schwarz',
    'falsch': ['Grau', 'Blau', 'Rot'],
  },
  {
    'emoji': '🖤',
    'farbe': 'Schwarz',
    'falsch': ['Grau', 'Blau', 'Lila'],
  },
];

// ── Farbmuster-Daten ──────────────────────────────────────────────────────────

// Muster: Liste der Emojis + korrekte Fortsetzung
const _farbMuster = [
  {
    'seq': ['🔴', '🔵', '🔴', '🔵', '🔴'],
    'next': '🔵',
    'name': 'Rot-Blau',
  },
  {
    'seq': ['🟡', '🟢', '🟡', '🟢', '🟡'],
    'next': '🟢',
    'name': 'Gelb-Grün',
  },
  {
    'seq': ['🔴', '🟡', '🔴', '🟡', '🔴'],
    'next': '🟡',
    'name': 'Rot-Gelb',
  },
  {
    'seq': ['🔵', '🟠', '🔵', '🟠', '🔵'],
    'next': '🟠',
    'name': 'Blau-Orange',
  },
  {
    'seq': ['🟢', '🟣', '🟢', '🟣', '🟢'],
    'next': '🟣',
    'name': 'Grün-Lila',
  },
  {
    'seq': ['🔴', '🔵', '🟡', '🔴', '🔵'],
    'next': '🟡',
    'name': 'Rot-Blau-Gelb',
  },
  {
    'seq': ['🟡', '🟠', '🔴', '🟡', '🟠'],
    'next': '🔴',
    'name': 'Gelb-Orange-Rot',
  },
  {
    'seq': ['🔵', '🟢', '🔵', '🟢', '🔵'],
    'next': '🟢',
    'name': 'Blau-Grün',
  },
  {
    'seq': ['⬛', '⬜', '⬛', '⬜', '⬛'],
    'next': '⬜',
    'name': 'Schwarz-Weiß',
  },
  {
    'seq': ['🔴', '🔴', '🔵', '🔴', '🔴'],
    'next': '🔵',
    'name': 'Rot-Rot-Blau',
  },
  {
    'seq': ['🟡', '🟡', '🟡', '🔴', '🟡'],
    'next': '🟡',
    'name': 'Dreimal Gelb',
  },
  {
    'seq': ['🔵', '🟡', '🟢', '🔵', '🟡'],
    'next': '🟢',
    'name': 'Blau-Gelb-Grün',
  },
];

// ── Formmuster-Daten ──────────────────────────────────────────────────────────

const _formMuster = [
  {
    'seq': ['⭕', '🔺', '⭕', '🔺', '⭕'],
    'next': '🔺',
    'falsch': ['🟦', '⭐', '🔷'],
  },
  {
    'seq': ['🟦', '⭕', '🟦', '⭕', '🟦'],
    'next': '⭕',
    'falsch': ['🔺', '⭐', '🔷'],
  },
  {
    'seq': ['🔺', '🔺', '🟦', '🔺', '🔺'],
    'next': '🟦',
    'falsch': ['⭕', '⭐', '🔷'],
  },
  {
    'seq': ['⭕', '⭐', '⭕', '⭐', '⭕'],
    'next': '⭐',
    'falsch': ['🟦', '🔺', '🔷'],
  },
  {
    'seq': ['🔷', '🔺', '🔷', '🔺', '🔷'],
    'next': '🔺',
    'falsch': ['⭕', '🟦', '⭐'],
  },
  {
    'seq': ['⭐', '⭕', '🔺', '⭐', '⭕'],
    'next': '🔺',
    'falsch': ['🟦', '🔷', '⭐'],
  },
];

// ── Feedback-Texte ────────────────────────────────────────────────────────────

const _feedbacksCorrect = [
  '🌟 Super gemacht!',
  '🎉 Richtig!',
  '🏆 Toll!',
  '✨ Klasse!',
  '🎊 Wunderbar!',
  '🥳 Genau richtig!',
  '💪 Stark!',
];


// ── Engine ────────────────────────────────────────────────────────────────────

class ColorShapeTaskEngine {
  final int grade;
  final int level;
  final Random _rng;

  ColorShapeTaskEngine({required this.grade, required this.level, int? seed})
    : _rng = Random(seed);

  int get _diffStage {
    if (level <= 3) return 1;
    if (level <= 7) return 2;
    if (level <= 12) return 3;
    if (level <= 20) return 4;
    return 5;
  }

  // ── Slots ─────────────────────────────────────────────────────────────────

  List<ColorShapeTask> generate(int count) {
    final List<ColorShapeTaskType> slots;
    switch (_diffStage) {
      case 1:
        slots = [
          ColorShapeTaskType.farbeNennen,
          ColorShapeTaskType.formNennen,
          ColorShapeTaskType.gleicheFarbe,
          ColorShapeTaskType.farbMuster,
          ColorShapeTaskType.oddOneOutFarbe,
        ];
        break;
      case 2:
        slots = [
          ColorShapeTaskType.farbeNennen,
          ColorShapeTaskType.formNennen,
          ColorShapeTaskType.gleicheFarbe,
          ColorShapeTaskType.farbeZuordnen,
          ColorShapeTaskType.oddOneOutForm,
        ];
        break;
      case 3:
        slots = [
          ColorShapeTaskType.farbeNennen,
          ColorShapeTaskType.formNennen,
          ColorShapeTaskType.gleicheForm,
          ColorShapeTaskType.wieVieleEcken,
          ColorShapeTaskType.farbeZuordnen,
        ];
        break;
      default: // Stufe 4–5
        slots = [
          ColorShapeTaskType.farbeNennen,
          ColorShapeTaskType.formNennen,
          ColorShapeTaskType.gleicheForm,
          ColorShapeTaskType.wieVieleEcken,
          ColorShapeTaskType.formZeichnen,
        ];
    }

    final usedSlots = List<ColorShapeTaskType>.from(slots.take(count))
      ..shuffle(_rng);

    // Tracking damit nicht zweimal dieselbe Farbe/Form in einer Runde
    final usedColors = <String>{};
    final usedShapes = <String>{};

    final tasks = <ColorShapeTask>[];
    for (final type in usedSlots) {
      final task = _generate(type, usedColors, usedShapes);
      if (task != null) {
        tasks.add(task);
        if (task.mixColor1 != null) {
          usedColors.add(task.mixColor1!);
          usedColors.add(task.mixColor2!);
        }
        if (task.questionEmoji != null) {
          // Farb-Emoji tracken
          for (final c in _colors) {
            if (c.emoji == task.questionEmoji) usedColors.add(c.name);
          }
          // Form-Emoji tracken
          for (final s in _shapes) {
            if (s.emoji == task.questionEmoji) usedShapes.add(s.name);
          }
        }
      }
    }
    return tasks;
  }

  // ── Dispatcher ────────────────────────────────────────────────────────────

  ColorShapeTask? _generate(
    ColorShapeTaskType type,
    Set<String> usedColors,
    Set<String> usedShapes,
  ) {
    switch (type) {
      case ColorShapeTaskType.farbeNennen:
        return _genFarbeNennen(usedColors);
      case ColorShapeTaskType.formNennen:
        return _genFormNennen(usedShapes);
      case ColorShapeTaskType.gleicheFarbe:
        return _genGleicheFarbe(usedColors);
      case ColorShapeTaskType.gleicheForm:
        return _genGleicheForm(usedShapes);
      case ColorShapeTaskType.farbMuster:
        return _genFarbMuster();
      case ColorShapeTaskType.formMuster:
        return _genFormMuster();
      case ColorShapeTaskType.oddOneOutFarbe:
        return _genOddOneOutFarbe(usedColors);
      case ColorShapeTaskType.oddOneOutForm:
        return _genOddOneOutForm(usedShapes);
      case ColorShapeTaskType.farbeZuordnen:
        return _genFarbeZuordnen();
      case ColorShapeTaskType.wieVieleEcken:
        return _genWieVieleEcken(usedShapes);
      case ColorShapeTaskType.formZeichnen:
        return _genFormZeichnen(usedShapes);
    }
  }

  // ── Farbe nennen ──────────────────────────────────────────────────────────

  ColorShapeTask _genFarbeNennen(Set<String> used) {
    final pool = _colors.where((c) => !used.contains(c.name)).toList();
    final color = pool.isEmpty
        ? _colors[_rng.nextInt(_colors.length)]
        : pool[_rng.nextInt(pool.length)];

    // Stufe 1–2: nur 4 Grundfarben als Optionen
    // Stufe 3+: alle 8 Farben als mögliche Distraktoren
    final List<_ColorData> distractorPool = _diffStage <= 2
        ? _colors
              .where(
                (c) =>
                    c.name != color.name &&
                    ['Rot', 'Blau', 'Gelb', 'Grün'].contains(c.name),
              )
              .toList()
        : _colors.where((c) => c.name != color.name).toList();

    distractorPool.shuffle(_rng);
    final opts = [color.name, ...distractorPool.take(3).map((c) => c.name)]
      ..shuffle(_rng);

    return ColorShapeTask(
      type: ColorShapeTaskType.farbeNennen,
      questionText: 'Welche Farbe siehst du?',
      questionEmoji: color.emoji,
      options: opts,
      correctAnswer: color.name,
      feedbackCorrect:
          '${_pickRandom(_feedbacksCorrect)} ${color.emoji} ist ${color.name}!',
      feedbackWrong: '💪 Das ist ${color.name}!',
      difficultyLevel: _diffStage,
    );
  }

  // ── Form nennen ───────────────────────────────────────────────────────────

  ColorShapeTask _genFormNennen(Set<String> used) {
    // Stufe 1–2: nur Kreis, Dreieck, Quadrat
    // Stufe 3+: alle Formen
    final pool = _diffStage <= 2
        ? _shapes
              .where(
                (s) =>
                    ['Kreis', 'Dreieck', 'Quadrat'].contains(s.name) &&
                    !used.contains(s.name),
              )
              .toList()
        : _shapes.where((s) => !used.contains(s.name)).toList();

    final shape = pool.isEmpty
        ? _shapes[_rng.nextInt(_shapes.length)]
        : pool[_rng.nextInt(pool.length)];

    final distractorPool = _shapes.where((s) => s.name != shape.name).toList()
      ..shuffle(_rng);
    final opts = [shape.name, ...distractorPool.take(3).map((s) => s.name)]
      ..shuffle(_rng);

    return ColorShapeTask(
      type: ColorShapeTaskType.formNennen,
      questionText: 'Welche Form siehst du?',
      questionEmoji: shape.emoji,
      options: opts,
      correctAnswer: shape.name,
      feedbackCorrect:
          '${_pickRandom(_feedbacksCorrect)} Das ist ein ${shape.name}!',
      feedbackWrong: '💪 Das ist ein ${shape.name}!',
      difficultyLevel: _diffStage,
    );
  }

  // ── Gleiche Farbe ─────────────────────────────────────────────────────────

  ColorShapeTask _genGleicheFarbe(Set<String> used) {
    final pool = _colors.where((c) => c.objects.length >= 3).toList();
    final color = pool[_rng.nextInt(pool.length)];

    final correctObjs = List<String>.from(color.objects)..shuffle(_rng);
    final correct = correctObjs.first;

    // Distraktoren: bekannte Objekte anderer Farben
    // Wichtig: nur Objekte verwenden die NICHT in color.objects sind
    final wrongPool =
        _colors
            .where((c) => c.name != color.name)
            .expand((c) => c.objects)
            .toSet()
            .where((o) => !color.objects.contains(o))
            .toList()
          ..shuffle(_rng);

    // Fallback falls nicht genug Distraktoren
    final opts = [correct, ...wrongPool.take(3)]..shuffle(_rng);

    return ColorShapeTask(
      type: ColorShapeTaskType.gleicheFarbe,
      questionText: 'Was ist auch ${color.name}?',
      questionEmoji: color.emoji,
      options: opts,
      correctAnswer: correct,
      feedbackCorrect:
          '${_pickRandom(_feedbacksCorrect)} Das ist auch ${color.name}!',
      feedbackWrong: '💪 Suche etwas ${color.name}es!',
      difficultyLevel: _diffStage,
    );
  }

  // ── Gleiche Form ──────────────────────────────────────────────────────────

  ColorShapeTask _genGleicheForm(Set<String> used) {
    final pool = _shapes
        .where((s) => s.objects.length >= 3 && !used.contains(s.name))
        .toList();
    final shape = pool.isEmpty
        ? _shapes[_rng.nextInt(_shapes.length)]
        : pool[_rng.nextInt(pool.length)];

    final correctObjs = List<String>.from(shape.objects)..shuffle(_rng);
    final correct = correctObjs.first;

    // Distraktoren aus anderen Formen
    final wrongPool =
        _shapes
            .where((s) => s.name != shape.name)
            .expand((s) => s.objects)
            .toSet()
            .where((o) => !shape.objects.contains(o))
            .toList()
          ..shuffle(_rng);

    final opts = [correct, ...wrongPool.take(3)]..shuffle(_rng);

    return ColorShapeTask(
      type: ColorShapeTaskType.gleicheForm,
      questionText: 'Was hat die gleiche Form wie ein ${shape.name}?',
      questionEmoji: shape.emoji,
      options: opts,
      correctAnswer: correct,
      feedbackCorrect:
          '${_pickRandom(_feedbacksCorrect)} Das ist auch ein ${shape.name}!',
      feedbackWrong: '💪 Suche die Form ${shape.name}!',
      difficultyLevel: _diffStage,
    );
  }

  // ── Farbmuster ────────────────────────────────────────────────────────────

  ColorShapeTask _genFarbMuster() {
    final muster = _farbMuster[_rng.nextInt(_farbMuster.length)];
    final seq = List<String>.from(muster['seq'] as List);
    final next = muster['next'] as String;

    // 3 falsche Farb-Emojis die NICHT richtig sind
    final allColorEmojis = _colors.map((c) => c.emoji).toList();
    final wrongPool = allColorEmojis.where((e) => e != next).toList()
      ..shuffle(_rng);
    final opts = [next, ...wrongPool.take(3)]..shuffle(_rng);

    return ColorShapeTask(
      type: ColorShapeTaskType.farbMuster,
      questionText: '${seq.join(' ')} ?',
      options: opts,
      correctAnswer: next,
      sequence: seq,
      feedbackCorrect: _pickRandom(_feedbacksCorrect),
      feedbackWrong: '💪 Schau auf das Muster!',
      difficultyLevel: _diffStage,
    );
  }

  // ── Formmuster ────────────────────────────────────────────────────────────

  ColorShapeTask _genFormMuster() {
    final muster = _formMuster[_rng.nextInt(_formMuster.length)];
    final seq = List<String>.from(muster['seq'] as List);
    final next = muster['next'] as String;
    final falsch = List<String>.from(muster['falsch'] as List)..shuffle(_rng);

    final opts = [next, ...falsch.take(3)]..shuffle(_rng);

    return ColorShapeTask(
      type: ColorShapeTaskType.formMuster,
      questionText: '${seq.join(' ')} ?',
      options: opts,
      correctAnswer: next,
      sequence: seq,
      feedbackCorrect: _pickRandom(_feedbacksCorrect),
      feedbackWrong: '💪 Schau auf das Muster!',
      difficultyLevel: _diffStage,
    );
  }

  // ── Odd One Out Farbe ────────────────────────────────────────────────────

  ColorShapeTask _genOddOneOutFarbe(Set<String> used) {
    // Eine Farbe wählen, 3 Objekte dieser Farbe + 1 Objekt einer anderen Farbe
    final pool = _colors.where((c) => c.objects.length >= 3).toList();
    final color = pool[_rng.nextInt(pool.length)];

    final colorObjs = List<String>.from(color.objects)..shuffle(_rng);
    final three = colorObjs.take(3).toList();

    // Das "odd one out": ein Objekt einer anderen Farbe das NICHT in color.objects ist
    final otherColors = _colors.where((c) => c.name != color.name).toList()
      ..shuffle(_rng);
    final otherColor = otherColors.first;
    final oddPool = otherColor.objects
        .where((o) => !color.objects.contains(o))
        .toList();
    final odd = oddPool.isNotEmpty
        ? oddPool[_rng.nextInt(oddPool.length)]
        : otherColor.objects[_rng.nextInt(otherColor.objects.length)];

    final opts = [...three, odd]..shuffle(_rng);

    return ColorShapeTask(
      type: ColorShapeTaskType.oddOneOutFarbe,
      questionText: 'Was ist NICHT ${color.name}?',
      questionEmoji: color.emoji,
      options: opts,
      correctAnswer: odd,
      feedbackCorrect:
          '${_pickRandom(_feedbacksCorrect)} Das ist nicht ${color.name}!',
      feedbackWrong: '💪 3 davon sind ${color.name}!',
      difficultyLevel: _diffStage,
    );
  }

  // ── Odd One Out Form ─────────────────────────────────────────────────────

  ColorShapeTask _genOddOneOutForm(Set<String> used) {
    final pool = _shapes.where((s) => s.objects.length >= 3).toList();
    final shape = pool[_rng.nextInt(pool.length)];

    final shapeObjs = List<String>.from(shape.objects)..shuffle(_rng);
    final three = shapeObjs.take(3).toList();

    // Das "odd one out": Objekt einer anderen Form
    final otherShape = _shapes.firstWhere((s) => s.name != shape.name);
    final odd = otherShape.objects[_rng.nextInt(otherShape.objects.length)];

    final opts = [...three, odd]..shuffle(_rng);

    return ColorShapeTask(
      type: ColorShapeTaskType.oddOneOutForm,
      questionText: 'Was ist KEIN ${shape.name}?',
      questionEmoji: shape.emoji,
      options: opts,
      correctAnswer: odd,
      feedbackCorrect:
          '${_pickRandom(_feedbacksCorrect)} Das ist kein ${shape.name}!',
      feedbackWrong: '💪 3 davon haben die Form ${shape.name}!',
      difficultyLevel: _diffStage,
    );
  }

  // ── Farbe zuordnen ──────────────────────────────────────────────────────────

  ColorShapeTask _genFarbeZuordnen() {
    final item = _farbeZuordnenPool[_rng.nextInt(_farbeZuordnenPool.length)];
    final emoji = item['emoji'] as String;
    final farbe = item['farbe'] as String;
    final falsch = List<String>.from(item['falsch'] as List)..shuffle(_rng);
    final opts = [farbe, ...falsch.take(3)]..shuffle(_rng);

    return ColorShapeTask(
      type: ColorShapeTaskType.farbeZuordnen,
      questionText: 'Welche Farbe hat das?',
      questionEmoji: emoji,
      options: opts,
      correctAnswer: farbe,
      feedbackCorrect: '${_pickRandom(_feedbacksCorrect)} Das ist $farbe!',
      feedbackWrong: '💪 Das ist $farbe!',
      difficultyLevel: _diffStage,
    );
  }

  // ── Wie viele Ecken ───────────────────────────────────────────────────────
  // ── Wie viele Ecken ───────────────────────────────────────────────────────

  ColorShapeTask _genWieVieleEcken(Set<String> used) {
    // Alle Formen inkl. Kreis (0 Ecken) sind valide
    final pool = _shapes.where((s) => !used.contains(s.name)).toList();
    final shape = pool.isEmpty
        ? _shapes[_rng.nextInt(_shapes.length)]
        : pool[_rng.nextInt(pool.length)];

    final correct = shape.ecken;
    // Distraktoren: andere Eckenanzahlen
    final allEcken = {0, 3, 4, 5, 6};
    final wrongPool = allEcken.where((e) => e != correct).toList()
      ..shuffle(_rng);
    final opts = ['$correct', ...wrongPool.take(3).map((e) => '$e')]
      ..shuffle(_rng);

    final question = correct == 0
        ? 'Wie viele Ecken hat ein ${shape.name}?'
        : 'Wie viele Ecken hat ein ${shape.name}?';

    return ColorShapeTask(
      type: ColorShapeTaskType.wieVieleEcken,
      questionText: question,
      questionEmoji: shape.emoji,
      options: opts,
      correctAnswer: '$correct',
      feedbackCorrect: correct == 0
          ? '${_pickRandom(_feedbacksCorrect)} Ein ${shape.name} hat keine Ecken!'
          : '${_pickRandom(_feedbacksCorrect)} Ein ${shape.name} hat $correct Ecken!',
      feedbackWrong: correct == 0
          ? '💪 Ein ${shape.name} ist rund – keine Ecken!'
          : '💪 Zähl die Ecken: ein ${shape.name} hat $correct!',
      difficultyLevel: _diffStage,
    );
  }

  // ── Form zeichnen ─────────────────────────────────────────────────────────

  ColorShapeTask _genFormZeichnen(Set<String> used) {
    // Stufe 4: nur einfache Formen
    final pool = _diffStage <= 4
        ? _shapes
              .where(
                (s) =>
                    ['Kreis', 'Dreieck', 'Quadrat'].contains(s.name) &&
                    !used.contains(s.name),
              )
              .toList()
        : _shapes.where((s) => !used.contains(s.name)).toList();

    final shape = pool.isEmpty
        ? _shapes[_rng.nextInt(3)] // nur erste 3 (einfache)
        : pool[_rng.nextInt(pool.length)];

    return ColorShapeTask(
      type: ColorShapeTaskType.formZeichnen,
      questionText: 'Male einen ${shape.name}!',
      questionEmoji: shape.emoji,
      options: [], // kein Multiple Choice
      correctAnswer: shape.name,
      shapeToDraw: shape.name,
      feedbackCorrect: _pickRandom(_feedbacksCorrect),
      feedbackWrong: '💪 Versuch es nochmal!',
      difficultyLevel: _diffStage,
    );
  }

  // ── Hilfsmethoden ─────────────────────────────────────────────────────────

  String _pickRandom(List<String> list) => list[_rng.nextInt(list.length)];

  // ── Statische UI-Helfer ───────────────────────────────────────────────────

  static String stageName(int stage) {
    switch (stage) {
      case 1:
        return 'Starter';
      case 2:
        return 'Einsteiger';
      case 3:
        return 'Fortgeschritten';
      case 4:
        return 'Profi';
      default:
        return 'Meister';
    }
  }

  static String stageEmoji(int stage) {
    switch (stage) {
      case 1:
        return '🌱';
      case 2:
        return '🌿';
      case 3:
        return '🌳';
      case 4:
        return '⚡';
      default:
        return '🔥';
    }
  }
}
