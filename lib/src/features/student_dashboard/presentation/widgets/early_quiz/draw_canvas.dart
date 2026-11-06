import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

// ============================================================================
// ZEICHENFLÄCHE für die Malaufgaben (Zahl, Buchstabe, Form malen)
//
// Die Striche liegen in einem [DrawingController] (ChangeNotifier). Nur das
// CustomPaint und die beiden Knöpfe hören darauf – ein Pinselstrich baut
// nicht mehr den ganzen Quiz-Bildschirm neu.
// ============================================================================

/// Hält die gemalten Striche und kann das Bild als PNG liefern.
class DrawingController extends ChangeNotifier {
  final List<List<Offset>> _strokes = [];

  /// Für [capturePng]: liegt auf dem RepaintBoundary der Zeichenfläche.
  final GlobalKey boundaryKey = GlobalKey();

  List<List<Offset>> get strokes => _strokes;
  bool get isEmpty => _strokes.isEmpty;
  bool get isNotEmpty => _strokes.isNotEmpty;

  void startStroke(Offset point) {
    _strokes.add([point]);
    notifyListeners();
  }

  void extendStroke(Offset point) {
    if (_strokes.isEmpty) return;
    _strokes.last.add(point);
    notifyListeners();
  }

  void clear() {
    if (_strokes.isEmpty) return;
    _strokes.clear();
    notifyListeners();
  }

  /// Bild der Zeichenfläche als PNG (für die KI-Prüfung), sonst `null`.
  Future<Uint8List?> capturePng({double pixelRatio = 2.0}) async {
    try {
      final boundary =
          boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('DrawCanvas: Bild nicht erzeugt: $e');
      return null;
    }
  }
}

/// Zeichenfläche mit „Löschen“ und „Prüfen“, optional „Weiter“
/// (wenn die Prüfung gerade nicht erreichbar ist).
class DrawCanvas extends StatelessWidget {
  const DrawCanvas({
    super.key,
    required this.controller,
    required this.accentColor,
    required this.enabled,
    required this.isEvaluating,
    required this.onSubmit,
    this.onSkip,
  });

  final DrawingController controller;
  final Color accentColor;

  /// Malen und Knöpfe aktiv (nicht während Feedback/Prüfung).
  final bool enabled;
  final bool isEvaluating;
  final VoidCallback onSubmit;

  /// Gesetzt → zusätzlicher „Weiter“-Knopf zum Überspringen.
  final VoidCallback? onSkip;

  static const _inkColor = Color(0xFF1A1A2E);

  @override
  Widget build(BuildContext context) {
    final canDraw = enabled && !isEvaluating;
    return Column(
      children: [
        RepaintBoundary(
          key: controller.boundaryKey,
          child: GestureDetector(
            onPanStart: canDraw
                ? (d) => controller.startStroke(d.localPosition)
                : null,
            onPanUpdate: canDraw
                ? (d) => controller.extendStroke(d.localPosition)
                : null,
            child: Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.35),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Stack(
                  children: [
                    CustomPaint(
                      painter: _StrokesPainter(controller, _inkColor),
                      child: const SizedBox.expand(),
                    ),
                    if (isEvaluating)
                      Container(
                        color: Colors.white.withValues(alpha: 0.8),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                color: accentColor,
                                strokeWidth: 3,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Ich schaue nach...',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: accentColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) => _buildButtons(controller.isNotEmpty),
        ),
        if (onSkip != null) ...[
          const SizedBox(height: 12),
          Semantics(
            button: true,
            label: 'Weiter zur nächsten Aufgabe',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: canDraw
                  ? () {
                      HapticFeedback.mediumImpact();
                      onSkip!();
                    }
                  : null,
              child: Container(
                height: 56,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Center(
                  child: Text(
                    'Weiter ➡️',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildButtons(bool hasDrawing) {
    final active = enabled && !isEvaluating;
    return Row(
      children: [
        // Löschen
        Semantics(
          button: true,
          label: 'Zeichnung löschen',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: active
                ? () {
                    HapticFeedback.lightImpact();
                    controller.clear();
                  }
                : null,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300, width: 2),
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                color: Color(0xFF888888),
                size: 26,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Prüfen
        Expanded(
          child: Semantics(
            button: true,
            enabled: hasDrawing && active,
            child: GestureDetector(
              onTap: hasDrawing && active ? onSubmit : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 56,
                decoration: BoxDecoration(
                  color: hasDrawing
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: hasDrawing
                        ? accentColor
                        : Colors.white.withValues(alpha: 0.3),
                    width: 2,
                  ),
                  boxShadow: hasDrawing
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    '✓ Prüfen',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: hasDrawing
                          ? accentColor
                          : Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Malt die Striche. Zeichnet neu, wenn der Controller sich meldet
/// (`repaint:`) – ohne Rebuild des Widget-Baums.
class _StrokesPainter extends CustomPainter {
  _StrokesPainter(this.controller, this.color) : super(repaint: controller);

  final DrawingController controller;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in controller.strokes) {
      if (stroke.isEmpty) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_StrokesPainter old) =>
      old.controller != controller || old.color != color;
}
