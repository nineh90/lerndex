import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../../domain/chat_message.dart';

// ============================================================================
// MATH-AWARE MESSAGE BUBBLE
// Rendert Text mit eingebetteten LaTeX-Formeln ($...$) korrekt.
// Brüche, Wurzeln, Potenzen etc. werden als echte Formeln dargestellt.
// ============================================================================

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final String childName;
  final String? childSelectedAvatar;

  const MessageBubble({
    super.key,
    required this.message,
    required this.childName,
    this.childSelectedAvatar,
  });

  @override
  Widget build(BuildContext context) {
    // Lade-Zustand
    if (message.isLoading) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildTutorAvatar(),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(18),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.deepPurple,
                      ),
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Tutor denkt nach...',
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Colors.black54,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[_buildTutorAvatar(), const SizedBox(width: 8)],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              decoration: BoxDecoration(
                color: isUser ? Colors.deepPurple : Colors.grey.shade100,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: isUser
                    ? Text(
                        message.text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                      )
                    : _MathAwareContent(
                        text: message.text,
                        textColor: Colors.black87,
                      ),
              ),
            ),
          ),
          if (isUser) ...[const SizedBox(width: 8), _buildChildAvatar()],
        ],
      ),
    );
  }

  Widget _buildTutorAvatar() {
    return CircleAvatar(
      radius: 18,
      backgroundColor: Colors.deepPurple.shade100,
      child: ClipOval(
        child: Image.asset(
          'assets/images/lerndex_logo.png',
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.school, size: 20, color: Colors.deepPurple),
        ),
      ),
    );
  }

  Widget _buildChildAvatar() {
    final initial = childName.isNotEmpty ? childName[0].toUpperCase() : '?';
    if (childSelectedAvatar != null) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: Colors.deepPurple.shade100,
        backgroundImage: AssetImage('assets/images/$childSelectedAvatar.png'),
        onBackgroundImageError: (_, __) {},
        child: null,
      );
    }
    return CircleAvatar(
      radius: 18,
      backgroundColor: Colors.deepPurple,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }
}

// ============================================================================
// MATH-AWARE CONTENT WIDGET
// Teilt den Text in normale Markdown-Blöcke und LaTeX-Blöcke auf.
// Inline-Formeln: $...$
// Block-Formeln:  $$...$$
// ============================================================================

class _MathAwareContent extends StatelessWidget {
  final String text;
  final Color textColor;

  const _MathAwareContent({required this.text, required this.textColor});

  @override
  Widget build(BuildContext context) {
    final segments = _parseSegments(text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: segments.map((seg) {
        if (seg.isBlockMath) {
          // Block-Formel: zentriert, etwas größer
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Center(child: _safeMath(seg.content, fontSize: 18)),
          );
        } else if (seg.isInlineMath) {
          // Inline-Formel: in einer Zeile mit Text
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: _safeMath(seg.content, fontSize: 15),
          );
        } else {
          // Normaler Markdown-Text
          if (seg.content.trim().isEmpty) return const SizedBox.shrink();
          return MarkdownBody(
            data: seg.content,
            styleSheet: MarkdownStyleSheet(
              p: TextStyle(fontSize: 15, color: textColor),
              strong: const TextStyle(fontWeight: FontWeight.bold),
              em: const TextStyle(fontStyle: FontStyle.italic),
              code: TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                backgroundColor: Colors.grey.shade200,
              ),
            ),
          );
        }
      }).toList(),
    );
  }

  /// Rendert LaTeX sicher – zeigt Fehler-Text statt Crash
  Widget _safeMath(String latex, {double fontSize = 15}) {
    try {
      return Math.tex(
        latex,
        textStyle: TextStyle(fontSize: fontSize, color: Colors.black87),
        onErrorFallback: (err) => Text(
          latex,
          style: TextStyle(
            fontSize: fontSize,
            color: Colors.red.shade700,
            fontFamily: 'monospace',
          ),
        ),
      );
    } catch (_) {
      return Text(
        latex,
        style: TextStyle(fontSize: fontSize, fontFamily: 'monospace'),
      );
    }
  }

  /// Parst den Text und trennt Markdown von LaTeX-Formeln.
  /// Reihenfolge: erst $$ (Block), dann $ (Inline) suchen.
  List<_TextSegment> _parseSegments(String input) {
    final segments = <_TextSegment>[];
    int pos = 0;

    while (pos < input.length) {
      // Block-Formel $$...$$
      final blockStart = input.indexOf(r'$$', pos);
      // Inline-Formel $...$  (nicht $$)
      final inlineStart = _findInlineDollar(input, pos);

      final nextBlock = blockStart == -1 ? input.length + 1 : blockStart;
      final nextInline = inlineStart == -1 ? input.length + 1 : inlineStart;

      if (nextBlock == input.length + 1 && nextInline == input.length + 1) {
        // Kein weiteres $ mehr → Rest als normaler Text
        if (pos < input.length) {
          segments.add(_TextSegment.text(input.substring(pos)));
        }
        break;
      }

      if (nextBlock <= nextInline) {
        // Block-Formel zuerst
        if (pos < nextBlock) {
          segments.add(_TextSegment.text(input.substring(pos, nextBlock)));
        }
        final endBlock = input.indexOf(r'$$', nextBlock + 2);
        if (endBlock == -1) {
          // Kein schließendes $$ → als Text behandeln
          segments.add(_TextSegment.text(input.substring(nextBlock)));
          break;
        }
        final mathContent = input.substring(nextBlock + 2, endBlock).trim();
        segments.add(_TextSegment.blockMath(mathContent));
        pos = endBlock + 2;
      } else {
        // Inline-Formel zuerst
        if (pos < nextInline) {
          segments.add(_TextSegment.text(input.substring(pos, nextInline)));
        }
        final endInline = _findClosingDollar(input, nextInline + 1);
        if (endInline == -1) {
          // Kein schließendes $ → als Text behandeln
          segments.add(_TextSegment.text(input.substring(nextInline)));
          break;
        }
        final mathContent = input.substring(nextInline + 1, endInline).trim();
        segments.add(_TextSegment.inlineMath(mathContent));
        pos = endInline + 1;
      }
    }

    return segments;
  }

  /// Findet das nächste einzelne $ (nicht $$) ab [start].
  int _findInlineDollar(String text, int start) {
    for (int i = start; i < text.length; i++) {
      if (text[i] == r'$') {
        // Sicherstellen dass es kein $$ ist
        if (i + 1 < text.length && text[i + 1] == r'$') {
          i++; // $$ überspringen
          continue;
        }
        return i;
      }
    }
    return -1;
  }

  /// Findet das schließende einzelne $ ab [start].
  int _findClosingDollar(String text, int start) {
    for (int i = start; i < text.length; i++) {
      if (text[i] == r'$') {
        if (i + 1 < text.length && text[i + 1] == r'$') {
          return -1; // Unerwartetes $$, Inline-Formel ungültig
        }
        return i;
      }
    }
    return -1;
  }
}

// ============================================================================
// TEXT SEGMENT MODEL
// ============================================================================

class _TextSegment {
  final String content;
  final _SegmentType type;

  const _TextSegment._(this.content, this.type);

  factory _TextSegment.text(String content) =>
      _TextSegment._(content, _SegmentType.text);
  factory _TextSegment.inlineMath(String content) =>
      _TextSegment._(content, _SegmentType.inlineMath);
  factory _TextSegment.blockMath(String content) =>
      _TextSegment._(content, _SegmentType.blockMath);

  bool get isInlineMath => type == _SegmentType.inlineMath;
  bool get isBlockMath => type == _SegmentType.blockMath;
}

enum _SegmentType { text, inlineMath, blockMath }
