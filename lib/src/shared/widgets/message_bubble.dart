import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import '../../features/tutor/domain/chat_message.dart';
import 'picked_image.dart';

import 'package:lerndex/src/shared/theme/app_theme.dart';
// ============================================================================
// UNIFIED MESSAGE BUBBLE
//
// Zwei Darstellungs-Modi:
//   - topicColor == null → Tutor-Chat-Style (Avatare, LaTeX, Loading-Animation)
//   - topicColor != null → Parent-Review-Style (Topic-Farbe, Name-Label, Border)
// ============================================================================

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final String childName;
  final String? childSelectedAvatar;

  /// Wenn gesetzt: Parent-Review-Style.
  /// Wenn null: Tutor-Chat-Style.
  final Color? topicColor;

  /// Lautsprecher-Knopf neben Lexis Nachricht (nur Tutor-Chat-Style).
  /// null = kein Knopf.
  final VoidCallback? onSpeak;

  /// Diese Nachricht wird gerade vorgelesen → Stopp-Knopf statt Lautsprecher.
  final bool isSpeaking;

  const MessageBubble({
    super.key,
    required this.message,
    required this.childName,
    this.childSelectedAvatar,
    this.topicColor,
    this.onSpeak,
    this.isSpeaking = false,
  });

  bool get _isParentReviewMode => topicColor != null;

  @override
  Widget build(BuildContext context) {
    if (_isParentReviewMode) {
      return _buildParentReviewBubble(context);
    }
    return _buildTutorChatBubble(context);
  }

  // --------------------------------------------------------------------------
  // TUTOR-CHAT-STYLE
  // Avatare, deepPurple für User, grau für Tutor, LaTeX, Loading-Animation
  // --------------------------------------------------------------------------

  Widget _buildTutorChatBubble(BuildContext context) {
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
                        AppColors.purple,
                      ),
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Tutor denkt nach…',
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
                color: isUser ? AppColors.purple : Colors.grey.shade100,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
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
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (message.hasImage) _buildMessageImage(),
                          if (message.text.trim().isNotEmpty) ...[
                            if (message.hasImage) const SizedBox(height: 6),
                            Text(
                              message.text,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ],
                      )
                    : _MathAwareContent(
                        text: message.text,
                        textColor: Colors.black87,
                      ),
              ),
            ),
          ),
          if (isUser) ...[const SizedBox(width: 8), _buildChildAvatar()],
          if (!isUser && onSpeak != null) _buildSpeakButton(),
        ],
      ),
    );
  }

  Widget _buildSpeakButton() {
    return IconButton(
      onPressed: onSpeak,
      tooltip: isSpeaking ? 'Vorlesen stoppen' : 'Vorlesen',
      // Volle 48 × 48 dp Trefferfläche (Kinderhände, Barrierefreiheit)
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      iconSize: 22,
      color: AppColors.purple,
      icon: Icon(
        isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
      ),
    );
  }

  Widget _buildTutorAvatar() {
    return CircleAvatar(
      radius: 18,
      backgroundColor: AppColors.purple.shade100,
      child: ClipOval(
        child: Image.asset(
          'assets/images/lerndex_logo.webp',
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              const Icon(Icons.school, size: 20, color: AppColors.purple),
        ),
      ),
    );
  }

  Widget _buildChildAvatar() {
    final initial = childName.isNotEmpty ? childName[0].toUpperCase() : '?';
    if (childSelectedAvatar != null) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: AppColors.purple.shade100,
        backgroundImage: AssetImage('assets/images/$childSelectedAvatar.webp'),
        onBackgroundImageError: (_, _) {},
        child: null,
      );
    }
    return CircleAvatar(
      radius: 18,
      backgroundColor: AppColors.purple,
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

  /// Rendert das Aufgabenblatt-Foto einer Nachricht.
  /// Bevorzugt die lokale Datei (sofortige Vorschau), sonst die Remote-URL.
  Widget _buildMessageImage() {
    final local = message.localImagePath;
    final url = message.imageUrl;

    Widget img;
    // Im Browser ist der lokale Pfad eine blob:-URL, die es nur in dieser
    // Sitzung gibt.
    if (local != null &&
        local.isNotEmpty &&
        (kIsWeb || File(local).existsSync())) {
      img = pickedImage(local, fit: BoxFit.cover);
    } else if (url != null && url.isNotEmpty) {
      img = Image.network(
        url,
        // Firebase Storage erlaubt keinen Abruf per Script (CORS) – im
        // Browser dann als <img>-Element anzeigen.
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        fit: BoxFit.cover,
        loadingBuilder: (c, child, progress) => progress == null
            ? child
            : const SizedBox(
                width: 180,
                height: 120,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
        errorBuilder: (_, _, _) => const SizedBox(
          width: 180,
          height: 120,
          child: Icon(Icons.broken_image, color: Colors.white70),
        ),
      );
    } else {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220, maxHeight: 220),
        child: img,
      ),
    );
  }

  // --------------------------------------------------------------------------
  // PARENT-REVIEW-STYLE
  // Topic-Farbe, Name-Label, Border, kein Avatar, Timestamp
  // --------------------------------------------------------------------------

  Widget _buildParentReviewBubble(BuildContext context) {
    final color = topicColor!;
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                isUser ? childName : 'Lerndex',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isUser ? color : AppColors.purple,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? color.withValues(alpha: 0.1) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isUser
                      ? const Radius.circular(16)
                      : const Radius.circular(4),
                  bottomRight: isUser
                      ? const Radius.circular(4)
                      : const Radius.circular(16),
                ),
                border: Border.all(
                  color: isUser
                      ? color.withValues(alpha: 0.2)
                      : Colors.grey.shade200,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.hasImage) _buildMessageImage(),
                  if (message.text.trim().isNotEmpty) ...[
                    if (message.hasImage) const SizedBox(height: 6),
                    _MathAwareContent(
                      text: message.text,
                      textColor: Colors.black87,
                      fontSize: 14,
                    ),
                  ],
                ],
              ),
            ),
            if (message.timestamp != DateTime(0))
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                  // grey[700] auf Weiß: Kontrast über 4,5 : 1
                  style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// MATH-AWARE CONTENT WIDGET
// Block-Formeln ($$...$$) stehen zentriert auf eigener Zeile. Der Text
// dazwischen geht als Markdown raus; Inline-Formeln ($...$) baut eine eigene
// Markdown-Syntax direkt in den Textfluss ein – sonst stünde jede kleine
// Formel wie „3/4“ auf einer eigenen Zeile.
// ============================================================================

class _MathAwareContent extends StatelessWidget {
  final String text;
  final Color textColor;
  final double fontSize;

  const _MathAwareContent({
    required this.text,
    required this.textColor,
    this.fontSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    final segments = _parseSegments(text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: segments.map((seg) {
        if (seg.isBlockMath) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Center(
              child: _safeMath(seg.content, fontSize: fontSize + 3),
            ),
          );
        }
        if (seg.content.trim().isEmpty) return const SizedBox.shrink();
        return MarkdownBody(
          data: seg.content,
          inlineSyntaxes: [_InlineMathSyntax()],
          builders: {
            'math': _InlineMathBuilder(
              (latex) => _safeMath(latex, fontSize: fontSize),
            ),
          },
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(fontSize: fontSize, color: textColor),
            strong: const TextStyle(fontWeight: FontWeight.bold),
            em: const TextStyle(fontStyle: FontStyle.italic),
            code: TextStyle(
              fontSize: fontSize - 2,
              fontFamily: 'monospace',
              backgroundColor: Colors.grey.shade200,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _safeMath(String latex, {required double fontSize}) {
    try {
      return Math.tex(
        latex,
        textStyle: TextStyle(fontSize: fontSize, color: textColor),
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

  /// Trennt nur Block-Formeln ab, Inline-Formeln bleiben im Text.
  List<_TextSegment> _parseSegments(String input) {
    final segments = <_TextSegment>[];
    int pos = 0;

    while (pos < input.length) {
      final blockStart = input.indexOf(r'$$', pos);
      if (blockStart == -1) {
        segments.add(_TextSegment.text(input.substring(pos)));
        break;
      }
      final blockEnd = input.indexOf(r'$$', blockStart + 2);
      if (blockEnd == -1) {
        segments.add(_TextSegment.text(input.substring(pos)));
        break;
      }
      if (pos < blockStart) {
        segments.add(_TextSegment.text(input.substring(pos, blockStart)));
      }
      segments.add(
        _TextSegment.blockMath(
          input.substring(blockStart + 2, blockEnd).trim(),
        ),
      );
      pos = blockEnd + 2;
    }

    return segments;
  }
}

/// Markdown-Syntax für Inline-Formeln: `$3 + 4$` → Element `math`.
class _InlineMathSyntax extends md.InlineSyntax {
  _InlineMathSyntax() : super(r'\$([^$\n]+?)\$', startCharacter: 0x24);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('math', match[1]!.trim()));
    return true;
  }
}

/// Rendert `math` als WidgetSpan. Als Text.rich verschmilzt flutter_markdown
/// es mit dem umgebenden Text zu einer Zeile.
class _InlineMathBuilder extends MarkdownElementBuilder {
  _InlineMathBuilder(this._buildMath);

  final Widget Function(String latex) _buildMath;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return Text.rich(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _buildMath(element.textContent),
      ),
    );
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
  factory _TextSegment.blockMath(String content) =>
      _TextSegment._(content, _SegmentType.blockMath);

  bool get isBlockMath => type == _SegmentType.blockMath;
}

enum _SegmentType { text, blockMath }
