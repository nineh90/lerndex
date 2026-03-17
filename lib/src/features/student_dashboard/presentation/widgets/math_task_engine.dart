import 'dart:math';

// ============================================================================
// MATH TASK ENGINE – Algorithmischer Generator für Klasse 1 & 2
//
// Kein KI, kein Firebase, keine Duplikate.
// Aufgaben skalieren mit dem Level des Kindes.
//
// Klasse 1: Zahlen bis 20  |  Klasse 2: Zahlen bis 100
//
// Schwierigkeitsstufen nach Level:
//   Stufe 1 (Level  1– 3) Starter      – Zahlen bis  5/15, nur +, viel countDots
//   Stufe 2 (Level  4– 7) Einsteiger   – Zahlen bis 10/30, erste -
//   Stufe 3 (Level  8–12) Fortgeschrtt – Zahlen bis 15/50, alle Typen
//   Stufe 4 (Level 13–20) Profi        – Voller Bereich,   enge Distraktoren
//   Stufe 5 (Level 21+  ) Meister      – Maximum-Modus,    sehr enge Optionen
//
// Aufgabentypen:
//   multipleChoice – Ergebnis aus 4 Antworten wählen
//   fillBlank      – „3 + __ = 7" → Zahl tippen (4 Antworten)
//   comparison     – „5 __ 8" → < = > wählen
//   countDots      – Emojis zählen → Zahl wählen
//   numberOrder    – Zahlen in richtige Reihenfolge bringen
// ============================================================================

enum MathTaskType {
  multipleChoice,
  fillBlank,
  comparison,
  countDots,
  numberOrder,
  numberLine, // Zahlenstrahl: Slider auf richtige Position ziehen
  balanceScale, // Waage: fehlende Zahl finden die die Waage ausgleicht
  drawAnswer, // Antwort malen: Kind zeichnet Zahl, KI prüft sie
  missingNumber, // Zahlenfolge mit Lücke: 2, 4, __, 8
  wordProblem, // Emoji-Textaufgabe: 🍎🍎🍎 + 🍎🍎 = ?
}

// ── Aufgaben-Modell ───────────────────────────────────────────────────────────

class MathTask {
  final MathTaskType type;
  final String questionText;
  final String? countEmoji;
  final int? countAmount;
  final List<int>? orderNumbers;
  final int? compareLeft;
  final int? compareRight;
  final List<String> options;
  final String correctAnswer;
  final String feedbackCorrect;
  final String feedbackWrong;

  /// Schwierigkeitsstufe (1–5) – für optionales Badge im Header
  final int difficultyLevel;

  /// Für numberLine: Minimum, Maximum und Zielwert auf dem Strahl
  final int? lineMin;
  final int? lineMax;
  final int? lineTarget;

  /// Für balanceScale: linke Seite (bekannt), rechte Seite (gesamt),
  /// Operator (+/-) und gesuchter Wert
  final int? scaleLeft;
  final int? scaleRight;
  final String? scaleOp; // '+' oder '-'
  final int? scaleTarget; // = correctAnswer als int

  /// Für missingNumber: komplette Folge und Position der Lücke
  final List<int>? sequence;
  final int? blankIndex;

  /// Für wordProblem: Emoji, linke Menge, rechte Menge, Operator
  final String? wpEmoji;
  final int? wpLeft;
  final int? wpRight;
  final String? wpOp;

  const MathTask({
    required this.type,
    required this.questionText,
    required this.options,
    required this.correctAnswer,
    required this.feedbackCorrect,
    required this.feedbackWrong,
    required this.difficultyLevel,
    this.countEmoji,
    this.countAmount,
    this.orderNumbers,
    this.compareLeft,
    this.compareRight,
    this.lineMin,
    this.lineMax,
    this.lineTarget,
    this.scaleLeft,
    this.scaleRight,
    this.scaleOp,
    this.scaleTarget,
    this.sequence,
    this.blankIndex,
    this.wpEmoji,
    this.wpLeft,
    this.wpRight,
    this.wpOp,
  });
}

// ── Schwierigkeits-Konfiguration ──────────────────────────────────────────────

class _Difficulty {
  final int maxNumber;
  final int maxCount;
  final bool allowSubtraction;
  final int distractorDelta; // max Abstand der Distraktoren – klein = schwerer

  const _Difficulty({
    required this.maxNumber,
    required this.maxCount,
    required this.allowSubtraction,
    required this.distractorDelta,
  });
}

// ── Emoji-Pools für countDots und wordProblem ────────────────────────────────

/// Großer Pool für countDots – viel Abwechslung beim Zählen
const _countEmojis = [
  // Tiere
  '🐶', '🐱', '🐸', '🐭', '🐰', '🐻', '🐼', '🦊', '🐯', '🦁',
  '🐮', '🐷', '🦆', '🐧', '🐝', '🐢', '🦕', '🐬', '🐳', '🦓',
  // Essen
  '🍎', '🍌', '🍓', '🍕', '🍦', '🍩', '🍪', '🌽', '🍉', '🍒',
  // Natur / Objekte
  '⭐', '🌸', '🌈', '🍀', '🌙', '🌻', '🍄', '🌲',
  // Spaß
  '🎈', '🚀', '🏆', '🎯', '⚽', '🎪', '🎀', '💎',
  // Früchte
  '🍇', '🍐', '🫐', '🍊', '🍋',
];

/// Pool für wordProblem (gleiche Emojis für linke und rechte Gruppe)
const _wordProblemEmojis = [
  '🍎',
  '🍌',
  '🍓',
  '🍕',
  '⭐',
  '🎈',
  '🐶',
  '🐱',
  '🐸',
  '🐰',
  '🍩',
  '🍪',
  '🌸',
  '🍦',
  '🐼',
  '🎯',
  '🍉',
  '🌻',
  '🐝',
  '🦋',
  '🍒',
  '🌽',
  '🍇',
  '⚽',
  '🐧',
  '🦊',
  '🐯',
  '🐻',
  '🍊',
  '🌙',
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

const _feedbacksWrong = [
  '💪 Versuch es nochmal!',
  '🤔 Fast – nochmal!',
  '💡 Du schaffst das!',
  '🧠 Denk nochmal nach!',
];

// ── Engine ────────────────────────────────────────────────────────────────────

class MathTaskEngine {
  final int grade;
  final int level; // Kind-Level (1–50)
  final Random _rng;

  MathTaskEngine({required this.grade, required this.level, int? seed})
    : _rng = Random(seed);

  // ── Schwierigkeitsstufe ───────────────────────────────────────────────────

  int get _diffStage {
    if (level <= 3) return 1;
    if (level <= 7) return 2;
    if (level <= 12) return 3;
    if (level <= 20) return 4;
    return 5;
  }

  int get _classMax => grade <= 1 ? 20 : 100;

  _Difficulty get _difficulty {
    switch (_diffStage) {
      case 1:
        return _Difficulty(
          maxNumber: grade <= 1 ? 5 : 15,
          maxCount: grade <= 1 ? 5 : 10,
          allowSubtraction: false,
          distractorDelta: 3,
        );
      case 2:
        return _Difficulty(
          maxNumber: grade <= 1 ? 10 : 30,
          maxCount: grade <= 1 ? 8 : 12,
          allowSubtraction: true,
          distractorDelta: 4,
        );
      case 3:
        return _Difficulty(
          maxNumber: grade <= 1 ? 15 : 50,
          maxCount: grade <= 1 ? 10 : 15,
          allowSubtraction: true,
          distractorDelta: 4,
        );
      case 4:
        return _Difficulty(
          maxNumber: grade <= 1 ? 20 : 80,
          maxCount: grade <= 1 ? 12 : 18,
          allowSubtraction: true,
          distractorDelta: 3,
        );
      default: // Stufe 5
        return _Difficulty(
          maxNumber: _classMax,
          maxCount: grade <= 1 ? 15 : 20,
          allowSubtraction: true,
          distractorDelta: 2,
        );
    }
  }

  // ── Öffentliche API ───────────────────────────────────────────────────────

  /// Generiert genau 5 Aufgaben – je eine pro Slot.
  /// Jeder Slot hat einen festen Typ (nach Schwierigkeitsstufe),
  /// aber die Zahlen sind jedes Mal zufällig → immer frisch, nie doppelt.
  ///
  /// Stufe 1 (Lvl 1–3):  countDots | multipleChoice | comparison | fillBlank     | missingNumber
  /// Stufe 2 (Lvl 4–7):  countDots | multipleChoice | comparison | numberLine    | fillBlank
  /// Stufe 3 (Lvl 8–12): countDots | multipleChoice | comparison | numberLine    | drawAnswer
  /// Stufe 4 (Lvl 13–20):countDots | multipleChoice | comparison | wordProblem   | drawAnswer
  /// Stufe 5 (Lvl 21+):  countDots | multipleChoice | comparison | wordProblem   | drawAnswer
  List<MathTask> generate(int count) {
    final diff = _difficulty;

    // Feste Slot-Reihenfolge je Stufe
    final List<MathTaskType> slots;
    switch (_diffStage) {
      case 1:
        slots = [
          MathTaskType.countDots,
          MathTaskType.multipleChoice,
          MathTaskType.comparison,
          MathTaskType.fillBlank,
          MathTaskType.missingNumber,
        ];
        break;
      case 2:
        slots = [
          MathTaskType.countDots,
          MathTaskType.multipleChoice,
          MathTaskType.comparison,
          MathTaskType.numberLine,
          MathTaskType.drawAnswer, // auch ab Stufe 2 testen
        ];
        break;
      case 3:
        slots = [
          MathTaskType.countDots,
          MathTaskType.multipleChoice,
          MathTaskType.comparison,
          MathTaskType.numberLine,
          MathTaskType.drawAnswer,
        ];
        break;
      case 4:
        slots = [
          MathTaskType.countDots,
          MathTaskType.multipleChoice,
          MathTaskType.comparison,
          MathTaskType.wordProblem,
          MathTaskType.drawAnswer,
        ];
        break;
      default: // Stufe 5
        slots = [
          MathTaskType.countDots,
          MathTaskType.multipleChoice,
          MathTaskType.comparison,
          MathTaskType.wordProblem,
          MathTaskType.drawAnswer,
        ];
    }

    // Slots auf gewünschte Anzahl anpassen (normalerweise 5)
    final usedSlots = slots.take(count).toList();
    if (usedSlots.length < count) {
      // Mehr gefragt als Slots → mit multipleChoice auffüllen
      while (usedSlots.length < count) {
        usedSlots.add(MathTaskType.multipleChoice);
      }
    }

    // Reihenfolge mischen damit das Kind nicht immer dieselbe Reihenfolge hat
    usedSlots.shuffle(_rng);

    // Aufgaben generieren
    final tasks = <MathTask>[];
    for (final type in usedSlots) {
      final task = _generate(type, diff);
      if (task != null) tasks.add(task);
    }
    return tasks;
  }

  // ── Generatoren ───────────────────────────────────────────────────────────

  MathTask? _generate(MathTaskType type, _Difficulty diff) {
    switch (type) {
      case MathTaskType.multipleChoice:
        return _genMultipleChoice(diff);
      case MathTaskType.fillBlank:
        return _genFillBlank(diff);
      case MathTaskType.comparison:
        return _genComparison(diff);
      case MathTaskType.countDots:
        return _genCountDots(diff);
      case MathTaskType.numberOrder:
        return _genNumberOrder(diff);
      case MathTaskType.numberLine:
        return _genNumberLine(diff);
      case MathTaskType.balanceScale:
        return _genBalanceScale(diff);
      case MathTaskType.drawAnswer:
        return _genDrawAnswer(diff);
      case MathTaskType.missingNumber:
        return _genMissingNumber(diff);
      case MathTaskType.wordProblem:
        return _genWordProblem(diff);
    }
  }

  // ── Multiple Choice ───────────────────────────────────────────────────────

  MathTask _genMultipleChoice(_Difficulty diff) {
    final isAddition = !diff.allowSubtraction || _rng.nextBool();
    int a, b, result;

    if (isAddition) {
      a = _rng.nextInt(diff.maxNumber ~/ 2) + 1;
      b = _rng.nextInt(diff.maxNumber - a) + 1;
      result = a + b;
    } else {
      result = _rng.nextInt(diff.maxNumber ~/ 2) + 1;
      b = _rng.nextInt(result) + 1;
      a = result + b;
    }

    final op = isAddition ? '+' : '-';
    return MathTask(
      type: MathTaskType.multipleChoice,
      questionText: '$a $op $b = ?',
      options: _buildNumericOptions(
        result,
        1,
        diff.maxNumber + result + 1,
        diff,
      ),
      correctAnswer: '$result',
      feedbackCorrect: _pickRandom(_feedbacksCorrect),
      feedbackWrong: _pickRandom(_feedbacksWrong),
      difficultyLevel: _diffStage,
    );
  }

  // ── Fill Blank ────────────────────────────────────────────────────────────

  MathTask _genFillBlank(_Difficulty diff) {
    final isAddition = !diff.allowSubtraction || _rng.nextBool();
    int a, b, total;

    if (isAddition) {
      a = _rng.nextInt(diff.maxNumber ~/ 2) + 1;
      b = _rng.nextInt(diff.maxNumber - a) + 1;
      total = a + b;
    } else {
      total = _rng.nextInt(diff.maxNumber ~/ 2) + 2;
      b = _rng.nextInt(total - 1) + 1;
      a = total - b;
    }

    // Lücken-Position: ab Stufe 3 auch das Ergebnis als Lücke möglich
    final blankVariant = _diffStage >= 3 ? _rng.nextInt(3) : _rng.nextInt(2);

    final String question;
    final int blank;

    if (isAddition) {
      switch (blankVariant) {
        case 0:
          question = '[?] + $b = $total';
          blank = a;
          break;
        case 2:
          question = '$a + $b = [?]';
          blank = total;
          break;
        default:
          question = '$a + [?] = $total';
          blank = b;
      }
    } else {
      switch (blankVariant) {
        case 0:
          question = '[?] - $b = $a';
          blank = total;
          break;
        case 2:
          question = '$total - $b = [?]';
          blank = a;
          break;
        default:
          question = '$total - [?] = $a';
          blank = b;
      }
    }

    return MathTask(
      type: MathTaskType.fillBlank,
      questionText: question,
      options: _buildNumericOptions(blank, 1, diff.maxNumber + 1, diff),
      correctAnswer: '$blank',
      feedbackCorrect: _pickRandom(_feedbacksCorrect),
      feedbackWrong: _pickRandom(_feedbacksWrong),
      difficultyLevel: _diffStage,
    );
  }

  // ── Comparison ────────────────────────────────────────────────────────────

  MathTask _genComparison(_Difficulty diff) {
    int left, right;
    String correct;

    final equalChance = _diffStage >= 3 ? 4 : 3;
    final variant = _rng.nextInt(equalChance);

    if (variant == 0) {
      left = _rng.nextInt(diff.maxNumber) + 1;
      right = left;
      correct = '=';
    } else if (variant == 1) {
      left = _rng.nextInt(diff.maxNumber - 1) + 1;
      right = left + _rng.nextInt(diff.maxNumber - left) + 1;
      correct = '<';
    } else {
      right = _rng.nextInt(diff.maxNumber - 1) + 1;
      left = right + _rng.nextInt(diff.maxNumber - right) + 1;
      correct = '>';
    }

    return MathTask(
      type: MathTaskType.comparison,
      questionText: '$left  ?  $right',
      options: const ['<', '=', '>'],
      correctAnswer: correct,
      compareLeft: left,
      compareRight: right,
      feedbackCorrect: _pickRandom(_feedbacksCorrect),
      feedbackWrong: _pickRandom(_feedbacksWrong),
      difficultyLevel: _diffStage,
    );
  }

  // ── Count Dots ────────────────────────────────────────────────────────────

  MathTask _genCountDots(_Difficulty diff) {
    final count = _rng.nextInt(diff.maxCount) + 1;

    // Ab Stufe 3: manchmal zwei verschiedene Emoji-Gruppen (MIXED-Format)
    // Screen zeigt: 🍎🍎 + 🍌🍌🍌 → Kind muss beide Gruppen zusammenzählen
    final String emoji;
    final String questionText;
    if (_diffStage >= 3 && count >= 3 && _rng.nextBool()) {
      final pool = List<String>.from(_countEmojis)..shuffle(_rng);
      final e1 = pool[0];
      final e2 = pool[1];
      final n1 = 1 + _rng.nextInt(count - 1);
      final n2 = count - n1;
      emoji = 'MIXED:$e1:$n1:$e2:$n2';
      questionText = 'Wie viele sind es zusammen?';
    } else {
      emoji = _countEmojis[_rng.nextInt(_countEmojis.length)];
      questionText = 'Wie viele siehst du?';
    }

    return MathTask(
      type: MathTaskType.countDots,
      questionText: questionText,
      countEmoji: emoji,
      countAmount: count,
      options: _buildNumericOptions(count, 1, diff.maxCount + 2, diff),
      correctAnswer: '$count',
      feedbackCorrect: _pickRandom(_feedbacksCorrect),
      feedbackWrong: '💪 Zähl nochmal!',
      difficultyLevel: _diffStage,
    );
  }

  // ── Number Order ──────────────────────────────────────────────────────────

  MathTask _genNumberOrder(_Difficulty diff) {
    // Ab Stufe 4: 4 Zahlen sortieren statt 3
    final numCount = _diffStage >= 4 ? 4 : 3;

    // Ab Stufe 4 mit großem Zahlenbereich: Zahlen aus verschiedenen
    // Segmenten wählen damit nicht immer kleine nahe Zahlen kommen
    final Set<int> nums = {};
    if (_diffStage >= 4 && diff.maxNumber >= 20) {
      final segSize = diff.maxNumber ~/ numCount;
      for (int i = 0; i < numCount; i++) {
        final segMin = i * segSize + 1;
        final segMax = (i + 1) * segSize;
        nums.add(segMin + _rng.nextInt(segMax - segMin + 1));
      }
    } else {
      while (nums.length < numCount) {
        nums.add(_rng.nextInt(diff.maxNumber) + 1);
      }
    }

    final list = nums.toList()..shuffle(_rng);

    // Ab Stufe 3 manchmal absteigend sortieren lassen (1/4 Chance)
    final askDescending = _diffStage >= 3 && _rng.nextInt(4) == 0;
    final sorted = List<int>.from(list)
      ..sort((a, b) => askDescending ? b.compareTo(a) : a.compareTo(b));

    return MathTask(
      type: MathTaskType.numberOrder,
      questionText: askDescending
          ? 'Sortiere von groß nach klein!'
          : 'Sortiere von klein nach groß!',
      orderNumbers: list,
      options: list.map((n) => '$n').toList(),
      correctAnswer: sorted.map((n) => '$n').join(','),
      feedbackCorrect: _pickRandom(_feedbacksCorrect),
      feedbackWrong: '💪 Nochmal sortieren!',
      difficultyLevel: _diffStage,
    );
  }

  // ── Number Line ───────────────────────────────────────────────────────────

  MathTask _genNumberLine(_Difficulty diff) {
    // Ziel-Zahl zufällig im erlaubten Bereich
    final target = _rng.nextInt(diff.maxNumber) + 1;

    // Strahl-Bereich: startet immer bei 0, endet bei einem runden Wert
    // der etwas größer als der Zielwert ist (für sinnvolle Darstellung)
    final lineMax = ((target / 5).ceil() * 5).clamp(5, diff.maxNumber);
    const lineMin = 0;

    final options = _buildNumericOptions(target, lineMin, lineMax + 1, diff);

    return MathTask(
      type: MathTaskType.numberLine,
      questionText: 'Wo ist die $target?',
      options: options,
      correctAnswer: '$target',
      lineMin: lineMin,
      lineMax: lineMax,
      lineTarget: target,
      feedbackCorrect: _pickRandom(_feedbacksCorrect),
      feedbackWrong: '💪 Schau nochmal auf den Strahl!',
      difficultyLevel: _diffStage,
    );
  }

  // ── Balance Scale ─────────────────────────────────────────────────────────

  MathTask _genBalanceScale(_Difficulty diff) {
    final isAddition = !diff.allowSubtraction || _rng.nextBool();
    int left, right, target;

    if (isAddition) {
      // left + target = right
      left = _rng.nextInt(diff.maxNumber ~/ 2) + 1;
      target = _rng.nextInt(diff.maxNumber - left) + 1;
      right = left + target;
    } else {
      // left - target = right  →  left = right + target
      right = _rng.nextInt(diff.maxNumber ~/ 2) + 1;
      target = _rng.nextInt(right) + 1;
      left = right + target;
    }

    final op = isAddition ? '+' : '-';
    // Frage: „X + ? = Y" oder „X - ? = Y"
    final question = isAddition ? '$left + ? = $right' : '$left - ? = $right';

    final options = _buildNumericOptions(target, 1, diff.maxNumber + 1, diff);

    return MathTask(
      type: MathTaskType.balanceScale,
      questionText: question,
      options: options,
      correctAnswer: '$target',
      scaleLeft: left,
      scaleRight: right,
      scaleOp: op,
      scaleTarget: target,
      feedbackCorrect: _pickRandom(_feedbacksCorrect),
      feedbackWrong: '💪 Die Waage stimmt noch nicht!',
      difficultyLevel: _diffStage,
    );
  }

  // ── Draw Answer ───────────────────────────────────────────────────────────

  /// Einfache Rechenaufgabe deren Ergebnis das Kind als Zahl malt.
  /// Der correctAnswer-String ist die erwartete Zahl (z.B. "7").
  /// Der Screen zeigt einen freien Canvas + schickt das Bild an Vertex AI.
  MathTask _genDrawAnswer(_Difficulty diff) {
    final isAddition = !diff.allowSubtraction || _rng.nextBool();
    int a, b, result;

    if (isAddition) {
      a = _rng.nextInt(diff.maxNumber ~/ 2) + 1;
      b = _rng.nextInt(diff.maxNumber - a) + 1;
      result = a + b;
    } else {
      result = _rng.nextInt(diff.maxNumber ~/ 3) + 1;
      b = _rng.nextInt(result) + 1;
      a = result + b;
    }

    final op = isAddition ? '+' : '-';
    return MathTask(
      type: MathTaskType.drawAnswer,
      questionText: '$a $op $b = ?',
      options: [], // Kein Multiple Choice – Antwort wird gemalt
      correctAnswer: '$result',
      feedbackCorrect: _pickRandom(_feedbacksCorrect),
      feedbackWrong: '💪 Versuch es nochmal!',
      difficultyLevel: _diffStage,
    );
  }

  // ── Missing Number: Zahlenfolge mit Lücke ────────────────────────────────

  MathTask _genMissingNumber(_Difficulty diff) {
    // Schrittweiten je Stufe
    final List<int> stepPool;
    final bool descending;
    switch (_diffStage) {
      case 1:
        stepPool = [1];
        descending = false;
        break;
      case 2:
        stepPool = [1, 1, 2];
        descending = false;
        break;
      case 3:
        stepPool = [1, 2, 2, 5];
        descending = false;
        break;
      default: // Stufe 4+
        stepPool = [1, 2, 3, 5, 10];
        descending = _rng.nextInt(3) == 0; // 1/3 chance absteigend
    }
    final step = stepPool[_rng.nextInt(stepPool.length)];

    // Startpunkt
    final maxStart = (diff.maxNumber - step * 4).clamp(1, diff.maxNumber ~/ 2);
    final start = _rng.nextInt(maxStart) + 1;

    final List<int> seq;
    if (descending) {
      final highStart = start + step * 4;
      seq = List.generate(5, (i) => highStart - i * step);
    } else {
      seq = List.generate(5, (i) => start + i * step);
    }

    // Lücke: Stufe 1 nur Mitte, sonst Index 1-3
    final blankIdx = _diffStage <= 1 ? 2 : 1 + _rng.nextInt(3);
    final correct = seq[blankIdx];

    final display = seq
        .asMap()
        .entries
        .map((e) => e.key == blankIdx ? '__' : '${e.value}')
        .join(', ');

    final options = _buildNumericOptions(
      correct,
      descending ? 0 : 1,
      diff.maxNumber + step * 2,
      diff,
    );

    return MathTask(
      type: MathTaskType.missingNumber,
      questionText: display,
      options: options,
      correctAnswer: '$correct',
      sequence: seq,
      blankIndex: blankIdx,
      feedbackCorrect: _pickRandom(_feedbacksCorrect),
      feedbackWrong: descending
          ? '💪 Diese Reihe wird kleiner!'
          : '💪 Schau auf die Reihe!',
      difficultyLevel: _diffStage,
    );
  }

  // ── Word Problem: Emoji-Textaufgabe ──────────────────────────────────────

  MathTask _genWordProblem(_Difficulty diff) {
    final isAddition = !diff.allowSubtraction || _rng.nextBool();
    final emoji = _wordProblemEmojis[_rng.nextInt(_wordProblemEmojis.length)];

    // Mengen klein halten damit die Emojis noch auf den Screen passen
    final maxSingle = diff.maxCount.clamp(1, 10);
    int left, right, result;

    if (isAddition) {
      left = _rng.nextInt(maxSingle ~/ 2) + 1;
      right = _rng.nextInt(maxSingle - left) + 1;
      result = left + right;
    } else {
      result = _rng.nextInt(maxSingle ~/ 2) + 1;
      right = _rng.nextInt(result) + 1;
      left = result + right;
    }

    final op = isAddition ? '+' : '-';
    // questionText wird für TTS genutzt – mit ausgeschriebenem Operator
    final ttsText = isAddition
        ? '$left plus $right gleich wie viele?'
        : '$left minus $right gleich wie viele?';

    final options = _buildNumericOptions(result, 1, diff.maxNumber + 1, diff);

    return MathTask(
      type: MathTaskType.wordProblem,
      questionText: ttsText,
      options: options,
      correctAnswer: '$result',
      wpEmoji: emoji,
      wpLeft: left,
      wpRight: right,
      wpOp: op,
      feedbackCorrect: _pickRandom(_feedbacksCorrect),
      feedbackWrong: '💪 Zähl die ${emoji}s!',
      difficultyLevel: _diffStage,
    );
  }

  // ── Hilfsmethoden ─────────────────────────────────────────────────────────

  /// Baut 4 Antwort-Optionen.
  /// Bei kleinen Ergebnissen (≤5) wird ein größerer Abstand erzwungen
  /// damit nicht immer triviale 1,2,3,4 Optionen erscheinen.
  List<String> _buildNumericOptions(
    int correct,
    int rangeMin,
    int rangeMax,
    _Difficulty diff,
  ) {
    final opts = <int>{correct};

    // Bei sehr kleinen Zahlen etwas mehr Abstand für interessantere Optionen
    final effectiveDelta = correct <= 5
        ? (diff.distractorDelta + 2).clamp(2, 6)
        : diff.distractorDelta;

    int attempts = 0;
    while (opts.length < 4 && attempts < 80) {
      attempts++;
      final delta = 1 + _rng.nextInt(effectiveDelta);
      final candidate = _rng.nextBool() ? correct + delta : correct - delta;
      if (candidate >= rangeMin && candidate != correct) {
        opts.add(candidate.abs());
      }
    }
    // Fallback: sequenziell auffüllen
    for (int i = rangeMin; opts.length < 4 && i < rangeMax + 10; i++) {
      if (i != correct) opts.add(i);
    }
    final list = opts.toList()..shuffle(_rng);
    return list.take(4).map((n) => '$n').toList();
  }

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
