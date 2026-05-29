import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'tutorial_provider.dart';

// ============================================================================
// TUTORIAL OVERLAY
//
// Legt sich als Stack über die gesamte App-Oberfläche.
// Zeichnet ein dunkles Overlay mit einem „Spotlight"-Ausschnitt
// an der Position des aktuell hervorgehobenen Widgets.
//
// Verwendung:
//   Stack(children: [
//     MeinScreen(),
//     TutorialOverlay(
//       highlightKey: _myButtonKey,       // optional – kein Key = kein Spotlight
//       onAction: () { ... },             // Primär-Button Callback
//     ),
//   ])
// ============================================================================

class TutorialOverlay extends ConsumerStatefulWidget {
  /// GlobalKey des hervorgehobenen Widgets (null = kein Spotlight)
  final GlobalKey? highlightKey;

  /// Callback wenn der Primär-Button gedrückt wird
  final VoidCallback? onAction;

  /// Callback für „Überspringen"
  final VoidCallback? onSkip;

  /// Wo soll der Tooltip erscheinen – above oder below dem Spotlight?
  final TooltipPosition tooltipPosition;

  const TutorialOverlay({
    super.key,
    this.highlightKey,
    this.onAction,
    this.onSkip,
    this.tooltipPosition = TooltipPosition.above,
  });

  @override
  ConsumerState<TutorialOverlay> createState() => _TutorialOverlayState();
}

enum TooltipPosition { above, below, center }

class _TutorialOverlayState extends ConsumerState<TutorialOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  Rect? _highlightRect;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(
      begin: 0.92,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack));
    _animCtrl.forward();

    // Highlight-Position nach erstem Frame ermitteln
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateHighlight());
  }

  @override
  void didUpdateWidget(TutorialOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlightKey != widget.highlightKey) {
      _animCtrl.forward(from: 0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateHighlight());
    }
  }

  // Wird aufgerufen wenn tutState.isVisible von false → true wechselt
  // (z.B. nach Rückkehr vom ParentDashboard)
  void _onVisibilityRestored() {
    _animCtrl.forward(from: 0);
    // Zwei Frames warten: erster für Navigation, zweiter für ListView-Aufbau
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateHighlight());
    });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _updateHighlight() {
    if (!mounted) return;
    final key = widget.highlightKey;
    if (key == null) {
      setState(() => _highlightRect = null);
      return;
    }
    final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    setState(() {
      _highlightRect = Rect.fromLTWH(
        offset.dx - 12,
        offset.dy - 12,
        size.width + 24,
        size.height + 24,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final tutState = ref.watch(tutorialProvider);

    // Wenn Overlay gerade wieder sichtbar gemacht wurde → Highlight neu berechnen
    if (tutState.isVisible &&
        _highlightRect == null &&
        widget.highlightKey != null) {
      _onVisibilityRestored();
    }

    if (!tutState.isActive || !tutState.isVisible) {
      return const SizedBox.shrink();
    }

    final content = tutorialContent[tutState.step];
    if (content == null) return const SizedBox.shrink();

    final size = MediaQuery.of(context).size;

    return FadeTransition(
      opacity: _fadeAnim,
      child: Stack(
        children: [
          // ── Dunkles Overlay mit Spotlight-Ausschnitt ──────────────────────
          CustomPaint(
            size: size,
            painter: _SpotlightPainter(
              highlightRect: _highlightRect,
              progress: _fadeAnim.value,
            ),
          ),

          // ── Tooltip-Karte ─────────────────────────────────────────────────
          _buildTooltip(context, content, size),
        ],
      ),
    );
  }

  Widget _buildTooltip(
    BuildContext context,
    TutorialContent content,
    Size screenSize,
  ) {
    // Immer vertikal zentriert – funktioniert auf allen Bildschirmgrößen
    // und verhindert zuverlässig das Abschneiden am unteren Rand.
    const cardMaxHeight = 240.0;
    final top = (screenSize.height - cardMaxHeight) / 2;

    return Positioned(
      left: 20,
      right: 20,
      top: top,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6B21A8).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          content.icon,
                          color: const Color(0xFF6B21A8),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          content.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                      ),
                      // Überspringen
                      GestureDetector(
                        onTap:
                            widget.onSkip ??
                            () => ref.read(tutorialProvider.notifier).skip(),
                        child: Text(
                          'Überspringen',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Body
                  Text(
                    content.body,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF4A4A6A),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Schritt-Indikator + Button
                  Row(
                    children: [
                      _buildStepDots(),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: widget.onAction,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6B21A8),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                        ),
                        child: Text(
                          content.buttonLabel,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepDots() {
    final tutState = ref.watch(tutorialProvider);
    const steps = [
      TutorialStep.familyDashboardIntro,
      TutorialStep.tapParentButton,
      TutorialStep.enterPin,
      TutorialStep.tapAddChild,
      TutorialStep.addChild,
      TutorialStep.showChildCard,
      TutorialStep.parentDashboardOverview,
    ];
    final currentIndex = steps.indexOf(tutState.step);

    return Row(
      children: List.generate(steps.length, (i) {
        final isActive = i == currentIndex;
        final isDone = i < currentIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.only(right: 5),
          width: isActive ? 18 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: isDone || isActive
                ? const Color(0xFF6B21A8)
                : Colors.grey[300],
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

// ── Spotlight Painter ─────────────────────────────────────────────────────────

class _SpotlightPainter extends CustomPainter {
  final Rect? highlightRect;
  final double progress;

  _SpotlightPainter({this.highlightRect, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()
      ..color = Colors.black.withOpacity(0.65 * progress);

    if (highlightRect == null) {
      canvas.drawRect(Offset.zero & size, overlayPaint);
      return;
    }

    // Overlay mit Loch für den Spotlight
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(
        RRect.fromRectAndRadius(highlightRect!, const Radius.circular(16)),
      );
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, overlayPaint);

    // Leuchtender Rand um den Spotlight
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.5 * progress)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(highlightRect!, const Radius.circular(16)),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.highlightRect != highlightRect || old.progress != progress;
}
