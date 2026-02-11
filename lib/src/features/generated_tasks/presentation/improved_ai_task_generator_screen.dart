import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../auth/domain/child_model.dart';
import '../../auth/data/auth_repository.dart';
import '../data/generated_task_models.dart';
import '../data/generated_task_repository.dart';
import '../data/firebase_ai_service_improved.dart';

/// 📸 VERBESSERTER KI-AUFGABENGENERATOR FÜR ELTERN
///
/// Features:
/// - Fach-Auswahl (Mathe, Deutsch, Englisch, Sachkunde)
/// - Foto-Upload von Schulaufgaben
/// - KI-Generierung von ähnlichen Übungen
/// - Vorschau vor Speicherung
/// - Automatisches Speichern mit pending-Status

class ImprovedAITaskGeneratorScreen extends ConsumerStatefulWidget {
  final ChildModel child;

  const ImprovedAITaskGeneratorScreen({super.key, required this.child});

  @override
  ConsumerState<ImprovedAITaskGeneratorScreen> createState() =>
      _ImprovedAITaskGeneratorScreenState();
}

class _ImprovedAITaskGeneratorScreenState
    extends ConsumerState<ImprovedAITaskGeneratorScreen> {

  Subject? _selectedSubject;
  File? _selectedImage;
  bool _isGenerating = false;
  bool _isSaving = false;
  List<GeneratedQuestion>? _generatedQuestions;
  String? _imageUrl;
  int _numberOfTasks = 5;

  final ImagePicker _picker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text('KI-Aufgaben für ${widget.child.name}'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoCard(),
            const SizedBox(height: 24),

            // Schritt 1: Fach auswählen
            _buildSubjectSelector(),

            if (_selectedSubject != null) ...[
              const SizedBox(height: 24),

              // Schritt 2: Bild auswählen/aufnehmen
              if (_selectedImage == null)
                _buildImagePicker()
              else
                _buildImagePreview(),

              if (_selectedImage != null && _generatedQuestions == null) ...[
                const SizedBox(height: 16),
                _buildTaskCountSelector(),
                const SizedBox(height: 24),
                _buildGenerateButton(),
              ],
            ],

            // Schritt 3: Ergebnisse
            if (_generatedQuestions != null) ...[
              const SizedBox(height: 32),
              _buildResults(),
              const SizedBox(height: 24),
              _buildSaveButton(),
            ],
          ],
        ),
      ),
    );
  }

  // ========================================================================
  // UI KOMPONENTEN
  // ========================================================================

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepPurple.shade50, Colors.purple.shade50],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.deepPurple.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.deepPurple,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.auto_awesome, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'KI-Aufgabengenerator',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Schulstoff aus der Schule direkt in die App',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.subject,
            text: 'Fach auswählen',
            number: '1',
          ),
          const SizedBox(height: 8),
          _InfoRow(
            icon: Icons.photo_camera,
            text: 'Foto von Hausaufgaben/Arbeitsblättern machen',
            number: '2',
          ),
          const SizedBox(height: 8),
          _InfoRow(
            icon: Icons.psychology,
            text: 'KI erstellt ähnliche Übungen',
            number: '3',
          ),
          const SizedBox(height: 8),
          _InfoRow(
            icon: Icons.check_circle,
            text: 'Aufgaben prüfen und freigeben',
            number: '4',
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.deepPurple,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  '1',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Fach auswählen',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.5,
          children: Subject.values.map((subject) {
            final isSelected = _selectedSubject == subject;
            return InkWell(
              onTap: () {
                setState(() {
                  _selectedSubject = subject;
                  // Reset wenn Fach gewechselt wird
                  _selectedImage = null;
                  _generatedQuestions = null;
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? Colors.deepPurple : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? Colors.deepPurple : Colors.grey.shade300,
                    width: 2,
                  ),
                  boxShadow: isSelected
                      ? [
                    BoxShadow(
                      color: Colors.deepPurple.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                      : [],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _getSubjectIcon(subject),
                      color: isSelected ? Colors.white : Colors.grey.shade700,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      subject.displayName,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  IconData _getSubjectIcon(Subject subject) {
    switch (subject) {
      case Subject.mathe:
        return Icons.calculate;
      case Subject.deutsch:
        return Icons.menu_book;
      case Subject.englisch:
        return Icons.language;
      case Subject.sachkunde:
        return Icons.science;
    }
  }

  Widget _buildImagePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.deepPurple,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  '2',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Aufgabe fotografieren',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Kamera-Button
        SizedBox(
          width: double.infinity,
          height: 140,
          child: InkWell(
            onTap: () => _pickImage(ImageSource.camera),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.deepPurple.shade200,
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.camera_alt,
                    size: 48,
                    color: Colors.deepPurple.shade300,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Foto aufnehmen',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Galerie-Button
        SizedBox(
          width: double.infinity,
          height: 100,
          child: InkWell(
            onTap: () => _pickImage(ImageSource.gallery),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.blue.shade200,
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_library, size: 32, color: Colors.blue.shade400),
                  const SizedBox(width: 12),
                  Text(
                    'Aus Galerie wählen',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImagePreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Foto ausgewählt',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _selectedImage = null;
                  _generatedQuestions = null;
                });
              },
              icon: const Icon(Icons.close, size: 20),
              label: const Text('Ändern'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.file(
            _selectedImage!,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
      ],
    );
  }

  Widget _buildTaskCountSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Anzahl der Aufgaben',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [3, 5, 8, 10].map((count) {
            final isSelected = _numberOfTasks == count;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: InkWell(
                  onTap: () => setState(() => _numberOfTasks = count),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.deepPurple : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? Colors.deepPurple : Colors.grey.shade300,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$count',
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildGenerateButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isGenerating ? null : _generateTasks,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: _isGenerating ? 0 : 4,
        ),
        child: _isGenerating
            ? const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(width: 12),
            Text(
              'KI generiert Aufgaben...',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        )
            : const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome, size: 24),
            SizedBox(width: 8),
            Text(
              'Aufgaben generieren',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_generatedQuestions == null || _generatedQuestions!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade700, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_generatedQuestions!.length} Aufgaben generiert!',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Prüfe die Aufgaben und gib sie dann frei',
                      style: TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ..._generatedQuestions!.asMap().entries.map((entry) {
          return _TaskPreviewCard(
            question: entry.value,
            index: entry.key + 1,
          );
        }),
      ],
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveTasks,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: _isSaving ? 0 : 4,
        ),
        child: _isSaving
            ? const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Wird gespeichert...',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        )
            : const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.save, size: 24),
            SizedBox(width: 8),
            Text(
              'Zur Freigabe speichern',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  // ========================================================================
  // LOGIK
  // ========================================================================

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Laden des Bildes: $e')),
        );
      }
    }
  }

  Future<void> _generateTasks() async {
    if (_selectedImage == null || _selectedSubject == null) return;

    setState(() => _isGenerating = true);

    try {
      final aiService = ref.read(improvedFirebaseAIServiceProvider);
      final authRepo = ref.read(authRepositoryProvider);
      final userId = authRepo.currentUser?.uid;

      if (userId == null) throw Exception('Nicht angemeldet');

      final result = await aiService.generateTasksFromImage(
        imageFile: _selectedImage!,
        child: widget.child,
        userId: userId,
        subject: _selectedSubject!,
        numberOfTasks: _numberOfTasks,
      );

      if (result.success && result.questions.isNotEmpty) {
        setState(() {
          _generatedQuestions = result.questions;
          _imageUrl = result.imageUrl;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Aufgaben erfolgreich generiert!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception(result.errorMessage ?? 'Generierung fehlgeschlagen');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _saveTasks() async {
    if (_generatedQuestions == null || _imageUrl == null || _selectedSubject == null) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      final repository = ref.read(generatedTaskRepositoryProvider);
      final authRepo = ref.read(authRepositoryProvider);
      final userId = authRepo.currentUser?.uid;

      if (userId == null) throw Exception('Nicht angemeldet');

      await repository.saveGeneratedBatch(
        userId: userId,
        childId: widget.child.id,
        childName: widget.child.name,
        subject: _selectedSubject!,
        imageUrl: _imageUrl!,
        questions: _generatedQuestions!,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Aufgaben gespeichert! Jetzt in der Freigabe-Liste.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );

        // Zurück zum Dashboard
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Speichern: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }
}

// ========================================================================
// HILFSKOMPONENTEN
// ========================================================================

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? number;

  const _InfoRow({
    required this.icon,
    required this.text,
    this.number,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (number != null) ...[
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade100,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple.shade700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Icon(icon, size: 20, color: Colors.deepPurple.shade400),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}

class _TaskPreviewCard extends StatefulWidget {
  final GeneratedQuestion question;
  final int index;

  const _TaskPreviewCard({
    required this.question,
    required this.index,
  });

  @override
  State<_TaskPreviewCard> createState() => _TaskPreviewCardState();
}

class _TaskPreviewCardState extends State<_TaskPreviewCard> {
  bool _showSolution = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Colors.deepPurple,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${widget.index}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.question.topic,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                _DifficultyChip(difficulty: widget.question.difficulty),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),

            // Frage
            Text(
              widget.question.question,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),

            const SizedBox(height: 16),

            // Antwortmöglichkeiten
            ...widget.question.options.asMap().entries.map((entry) {
              final isCorrect = entry.value == widget.question.correctAnswer;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isCorrect ? Colors.green.shade50 : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isCorrect ? Colors.green.shade300 : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    if (isCorrect)
                      Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                    if (isCorrect) const SizedBox(width: 8),
                    Expanded(child: Text(entry.value)),
                  ],
                ),
              );
            }),

            // Lösung (falls vorhanden)
            if (widget.question.solution != null) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () => setState(() => _showSolution = !_showSolution),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: _showSolution ? Colors.blue.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _showSolution ? Icons.visibility_off : Icons.visibility,
                        size: 18,
                        color: _showSolution ? Colors.blue.shade700 : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _showSolution ? 'Erklärung ausblenden' : 'Erklärung anzeigen',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _showSolution ? Colors.blue.shade700 : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_showSolution) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Text(
                    widget.question.solution!,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _DifficultyChip extends StatelessWidget {
  final String difficulty;

  const _DifficultyChip({required this.difficulty});

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    final text = _getText();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Color _getColor() {
    switch (difficulty.toLowerCase()) {
      case 'easy':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'hard':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  String _getText() {
    switch (difficulty.toLowerCase()) {
      case 'easy':
        return 'Leicht';
      case 'medium':
        return 'Mittel';
      case 'hard':
        return 'Schwer';
      default:
        return 'Normal';
    }
  }
}