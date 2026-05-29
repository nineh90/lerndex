import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../../features/tutor/domain/chat_message.dart';

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

  const MessageBubble({
    super.key,
    required this.message,
    required this.childName,
    this.childSelectedAvatar,
    this.topicColor,
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
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
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

  /// Rendert das Aufgabenblatt-Foto einer Nachricht.
  /// Bevorzugt die lokale Datei (sofortige Vorschau), sonst die Remote-URL.
  Widget _buildMessageImage() {
    final local = message.localImagePath;
    final url = message.imageUrl;

    Widget img;
    if (local != null && local.isNotEmpty && File(local).existsSync()) {
      img = Image.file(File(local), fit: BoxFit.cover);
    } else if (url != null && url.isNotEmpty) {
      img = Image.network(
        url,
        fit: BoxFit.cover,
        loadingBuilder: (c, child, progress) => progress == null
            ? child
            : const SizedBox(
                width: 180,
                height: 120,
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
        errorBuilder: (_, __, ___) => const SizedBox(
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
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                isUser ? childName : 'Lerndex',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isUser ? color : Colors.deepPurple,
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
                  color: isUser ? color.withValues(alpha: 0.2) : Colors.grey.shade200,
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
                  style: TextStyle(fontSize: 10, color: Colors.grey[400]),
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
// Teilt den Text in normale Markdown-Blöcke und LaTeX-Blöcke auf.
// Inline-Formeln: $...$
// Block-Formeln:  $$...$$
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
            child: Center(child: _safeMath(seg.content, fontSize: fontSize + 3)),
          );
        } else if (seg.isInlineMath) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: _safeMath(seg.content, fontSize: fontSize),
          );
        } else {
          if (seg.content.trim().isEmpty) return const SizedBox.shrink();
          return MarkdownBody(
            data: seg.content,
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
        }
      }).toList(),
    );
  }

  Widget _safeMath(String latex, {double? fontSize}) {
    final size = fontSize ?? this.fontSize;
    try {
      return Math.tex(
        latex,
        textStyle: TextStyle(fontSize: size, color: Colors.black87),
        onErrorFallback: (err) => Text(
          latex,
          style: TextStyle(
            fontSize: size,
            color: Colors.red.shade700,
            fontFamily: 'monospace',
          ),
        ),
      );
    } catch (_) {
      return Text(
        latex,
        style: TextStyle(fontSize: size, fontFamily: 'monospace'),
      );
    }
  }

  List<_TextSegment> _parseSegments(String input) {
    final segments = <_TextSegment>[];
    int pos = 0;

    while (pos < input.length) {
      final blockStart = input.indexOf(r'$$', pos);
      final inlineStart = _findInlineDollar(input, pos);

      final nextBlock = blockStart == -1 ? input.length + 1 : blockStart;
      final nextInline = inlineStart == -1 ? input.length + 1 : inlineStart;

      if (nextBlock == input.length + 1 && nextInline == input.length + 1) {
        if (pos < input.length) {
          segments.add(_TextSegment.text(input.substring(pos)));
        }
        break;
      }

      if (nextBlock <= nextInline) {
        if (pos < nextBlock) {
          segments.add(_TextSegment.text(input.substring(pos, nextBlock)));
        }
        final endBlock = input.indexOf(r'$$', nextBlock + 2);
        if (endBlock == -1) {
          segments.add(_TextSegment.text(input.substring(nextBlock)));
          break;
        }
        final mathContent = input.substring(nextBlock + 2, endBlock).trim();
        segments.add(_TextSegment.blockMath(mathContent));
        pos = endBlock + 2;
      } else {
        if (pos < nextInline) {
          segments.add(_TextSegment.text(input.substring(pos, nextInline)));
        }
        final endInline = _findClosingDollar(input, nextInline + 1);
        if (endInline == -1) {
          segments.add(_TextSegment.text(input.substring(nextInline)));
          break;
        }
        final mathContent =
            input.substring(nextInline + 1, endInline).trim();
        segments.add(_TextSegment.inlineMath(mathContent));
        pos = endInline + 1;
      }
    }

    return segments;
  }

  int _findInlineDollar(String text, int start) {
    for (int i = start; i < text.length; i++) {
      if (text[i] == r'$') {
        if (i + 1 < text.length && text[i + 1] == r'$') {
          i++;
          continue;
        }
        return i;
      }
    }
    return -1;
  }

  int _findClosingDollar(String text, int start) {
    for (int i = start; i < text.length; i++) {
      if (text[i] == r'$') {
        if (i + 1 < text.length && text[i + 1] == r'$') {
          return -1;
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
