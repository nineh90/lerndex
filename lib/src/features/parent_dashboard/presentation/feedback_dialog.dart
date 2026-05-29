import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../data/feedback_repository.dart';

class FeedbackDialog extends ConsumerStatefulWidget {
  const FeedbackDialog({super.key});

  @override
  ConsumerState<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends ConsumerState<FeedbackDialog> {
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  bool _isSending = false;
  File? _screenshot;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickScreenshot() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (picked != null) {
        setState(() => _screenshot = File(picked.path));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bild konnte nicht geladen werden.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() => _isSending = true);

    try {
      await ref.read(feedbackRepositoryProvider).sendFeedback(
            subject: _subjectCtrl.text,
            message: _messageCtrl.text,
            screenshot: _screenshot,
          );

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vielen Dank für dein Feedback!'),
          backgroundColor: Colors.green,
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      final msg = e.code == 'permission-denied'
          ? 'Bitte gib mindestens 10 Zeichen ein.'
          : 'Senden fehlgeschlagen. Bitte versuch es später erneut.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Senden fehlgeschlagen. Bitte versuch es später erneut.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.feedback_outlined, color: Colors.deepPurple),
          SizedBox(width: 8),
          Expanded(child: Text('Feedback senden')),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Schreib uns, was dir gefällt oder was wir verbessern können.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _subjectCtrl,
                enabled: !_isSending,
                textInputAction: TextInputAction.next,
                // 190 + Präfix "Feedback: " (10) = 200, passt zur Firestore-Rule.
                maxLength: 190,
                decoration: _inputDecoration(
                  label: 'Betreff (optional)',
                  hint: 'Worum geht’s?',
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _messageCtrl,
                enabled: !_isSending,
                minLines: 4,
                maxLines: 8,
                maxLength: 2000,
                textInputAction: TextInputAction.newline,
                decoration: _inputDecoration(
                  label: 'Deine Nachricht',
                  hint: 'Mindestens 10 Zeichen…',
                ),
                validator: (value) {
                  final v = (value ?? '').trim();
                  if (v.isEmpty) return 'Bitte gib eine Nachricht ein.';
                  if (v.length < 10) {
                    return 'Mindestens 10 Zeichen, damit wir dir helfen können.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.privacy_tip_outlined,
                    size: 16,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Deine E-Mail-Adresse wird mitgesendet, damit wir dir antworten können.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildAttachmentSection(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton.icon(
          onPressed: _isSending ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.deepPurple.withValues(alpha: 0.4),
          ),
          icon: _isSending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.send, size: 18),
          label: Text(_isSending ? 'Senden…' : 'Absenden'),
        ),
      ],
    );
  }

  Widget _buildAttachmentSection() {
    if (_screenshot == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _isSending ? null : _pickScreenshot,
          icon: const Icon(Icons.image_outlined, size: 18),
          label: const Text('Screenshot anhängen (optional)'),
          style: TextButton.styleFrom(foregroundColor: Colors.deepPurple),
        ),
      );
    }
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            _screenshot!,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Screenshot angehängt',
            style: TextStyle(fontSize: 13),
          ),
        ),
        IconButton(
          onPressed: _isSending ? null : () => setState(() => _screenshot = null),
          icon: const Icon(Icons.close, size: 20),
          tooltip: 'Entfernen',
          color: Colors.grey.shade700,
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({required String label, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.deepPurple, width: 1.5),
      ),
    );
  }
}

Future<void> showFeedbackDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const FeedbackDialog(),
  );
}
