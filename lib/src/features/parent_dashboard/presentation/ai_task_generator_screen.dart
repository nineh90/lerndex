import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../auth/domain/child_model.dart';
import '../../auth/data/auth_repository.dart';
import '../../generated_tasks/data/generated_task_models.dart';
import '../../generated_tasks/data/generated_task_repository.dart';
import '../../generated_tasks/data/firebase_ai_service_improved.dart';
import '../../student_dashboard/presentation/subject_config.dart'
    show getSubjectsForChild;
import 'widgets/info_row.dart';
import 'widgets/question_card.dart';

/// 📸 KI-AUFGABENGENERATOR FÜR ELTERN
///
/// - Dynamische Fächer basierend auf Kind (Klasse + Schulform)
/// - Foto von Schulaufgabe → KI generiert Multiple-Choice-Übungen
/// - Auto-Save direkt nach Generierung → sofort in "Freigeben" sichtbar

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
  List<GeneratedQuestion>? _generatedQuestions;
  String? _errorMessage;
  int _numberOfTasks = 5;

  final ImagePicker _picker = ImagePicker();

  // ---------------------------------------------------------------------------
  // Dynamische Fächerliste – identisch zu getSubjectsForChild im Schüler-Dashboard
  // ---------------------------------------------------------------------------

  List<Subject> _getAvailableSubjects() {
    final configs = getSubjectsForChild(widget.child);

    const stringToSubject = {
      'Mathe': Subject.mathe,
      'Deutsch': Subject.deutsch,
      'Englisch': Subject.englisch,
      'Sachkunde': Subject.sachkunde,
      'Biologie': Subject.biologie,
      'Chemie': Subject.chemie,
      'Physik': Subject.physik,
      'Geschichte': Subject.geschichte,
    };

    final result = <Subject>[];
    final seen = <Subject>{};

    for (final config in configs) {
      final s = stringToSubject[config.subject];
      if (s != null && !seen.contains(s)) {
        result.add(s);
        seen.add(s);
      }
    }

    // Fallback: nach Klasse filtern wenn Mapping leer
    return result.isEmpty
        ? Subject.values
              .where((s) => s.isAvailableForGrade(widget.child.grade))
              .toList()
        : result;
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

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
            // Info-Card
            _buildInfoCard(),
            const SizedBox(height: 24),

            // Schritt 1: Fach auswählen (dynamisch)
            _buildSubjectSelector(),
            const SizedBox(height: 24),

            // Schritt 2: Bild (nur wenn Fach gewählt)
            if (_selectedSubject != null) ...[
              if (_selectedImage == null) ...[
                _buildImagePicker(),
              ] else ...[
                _buildImagePreview(),
                const SizedBox(height: 16),
                _buildTaskCountSelector(),
                const SizedBox(height: 24),
                _buildGenerateButton(),
              ],
            ],

            // Ergebnis
            if (_generatedQuestions != null) ...[
              const SizedBox(height: 32),
              _buildResults(),
            ],

            // Fehler
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              _buildErrorCard(),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // INFO CARD
  // ---------------------------------------------------------------------------

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
                child: const Icon(
                  Icons.auto_awesome,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'KI-Aufgabengenerator',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Klasse ${widget.child.grade} · ${widget.child.schoolType}',
                      style: const TextStyle(
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
          const InfoRow(icon: Icons.subject, text: 'Passendes Fach auswählen'),
          const SizedBox(height: 8),
          const InfoRow(
            icon: Icons.photo_camera,
            text: 'Foto von Hausaufgaben/Arbeitsblättern machen',
          ),
          const SizedBox(height: 8),
          const InfoRow(
            icon: Icons.psychology,
            text: 'KI erstellt ähnliche Multiple-Choice-Übungen',
          ),
          const SizedBox(height: 8),
          const InfoRow(
            icon: Icons.check_circle,
            text: 'Aufgaben sofort in "Freigeben" sichtbar',
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FACH-SELEKTOR (dynamisch, passend zum Kind)
  // ---------------------------------------------------------------------------

  Widget _buildSubjectSelector() {
    final availableSubjects = _getAvailableSubjects();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Fach auswählen',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: availableSubjects.map((subject) {
            final isSelected = _selectedSubject == subject;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedSubject = subject;
                  _selectedImage = null;
                  _generatedQuestions = null;
                  _errorMessage = null;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.deepPurple : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? Colors.deepPurple
                        : Colors.grey.shade300,
                    width: 2,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.deepPurple.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getSubjectIcon(subject),
                      size: 20,
                      color: isSelected ? Colors.white : Colors.grey.shade700,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      subject.displayName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : Colors.grey.shade800,
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

  // ---------------------------------------------------------------------------
  // BILD-AUSWAHL
  // ---------------------------------------------------------------------------

  Widget _buildImagePicker() {
    return Column(
      children: [
        const SizedBox(height: 8),

        // Kamera-Button
        SizedBox(
          width: double.infinity,
          height: 180,
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
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.camera_alt,
                    size: 64,
                    color: Colors.deepPurple.shade300,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Foto aufnehmen',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Schulaufgabe fotografieren',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.deepPurple.shade400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Galerie-Button
        SizedBox(
          width: double.infinity,
          height: 120,
          child: InkWell(
            onTap: () => _pickImage(ImageSource.gallery),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.shade200, width: 2),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.photo_library,
                    size: 40,
                    color: Colors.blue.shade400,
                  ),
                  const SizedBox(width: 16),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Aus Galerie wählen',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                      Text(
                        'Vorhandenes Foto auswählen',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blue.shade400,
                        ),
                      ),
                    ],
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
        const Text(
          'Ausgewähltes Foto',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(
                _selectedImage!,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => setState(() {
                  _selectedImage = null;
                  _generatedQuestions = null;
                  _errorMessage = null;
                }),
                icon: const Icon(Icons.close),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // ANZAHL-SELEKTOR
  // ---------------------------------------------------------------------------

  Widget _buildTaskCountSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Anzahl Aufgaben',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: _numberOfTasks > 3
                    ? () => setState(() => _numberOfTasks--)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
                iconSize: 32,
                color: Colors.deepPurple,
              ),
              Text(
                '$_numberOfTasks Aufgaben',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
              IconButton(
                onPressed: _numberOfTasks < 10
                    ? () => setState(() => _numberOfTasks++)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
                iconSize: 32,
                color: Colors.deepPurple,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Empfohlen: 5 Aufgaben',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // GENERIER-BUTTON
  // ---------------------------------------------------------------------------

  Widget _buildGenerateButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: _isGenerating ? null : _generateAndSave,
        icon: _isGenerating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.auto_awesome, size: 24),
        label: Text(
          _isGenerating ? 'KI generiert Aufgaben...' : 'Aufgaben generieren',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 4,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ERGEBNIS
  // ---------------------------------------------------------------------------

  Widget _buildResults() {
    final questions = _generatedQuestions!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Erfolgs-Header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green.shade400, Colors.green.shade600],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 40),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '✨ Aufgaben generiert & gespeichert!',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '${questions.length} Übungen für ${widget.child.name} · Jetzt in "Freigeben" sichtbar',
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        const Text(
          'Generierte Aufgaben (Vorschau)',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        ...questions.asMap().entries.map(
          (entry) => QuestionCard(question: entry.value, index: entry.key + 1),
        ),

        const SizedBox(height: 24),

        // Aktions-Buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => setState(() {
                  _selectedImage = null;
                  _generatedQuestions = null;
                  _errorMessage = null;
                }),
                icon: const Icon(Icons.refresh),
                label: const Text('Neu generieren'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: Colors.deepPurple, width: 2),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.check),
                label: const Text('Fertig'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fehler beim Generieren',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Laden des Bildes: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Generiert Aufgaben mit KI und speichert sie DIREKT in Firestore.
  /// Ein Schritt – kein separater Speichern-Button nötig.
  Future<void> _generateAndSave() async {
    if (_selectedImage == null || _selectedSubject == null) return;

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final authRepo = ref.read(authRepositoryProvider);
      final userId = authRepo.currentUser?.uid;
      if (userId == null) throw Exception('Nicht angemeldet');

      // 1. KI generiert Multiple-Choice-Aufgaben
      final aiService = ref.read(improvedFirebaseAIServiceProvider);
      final result = await aiService.generateTasksFromImage(
        imageFile: _selectedImage!,
        child: widget.child,
        userId: userId,
        subject: _selectedSubject!,
        numberOfTasks: _numberOfTasks,
      );

      if (!result.success || result.questions.isEmpty) {
        throw Exception(
          result.errorMessage ?? 'KI hat keine Aufgaben generiert',
        );
      }

      // 2. Direkt in Firestore speichern → sofort in Freigabe-Liste
      final repository = ref.read(generatedTaskRepositoryProvider);
      await repository.saveGeneratedBatch(
        userId: userId,
        childId: widget.child.id,
        childName: widget.child.name,
        subject: _selectedSubject!,
        imageUrl: result.imageUrl ?? '',
        questions: result.questions,
      );

      if (mounted) {
        setState(() => _generatedQuestions = result.questions);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Aufgaben generiert & gespeichert!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  // ---------------------------------------------------------------------------
  // HILFSMETHODEN
  // ---------------------------------------------------------------------------

  IconData _getSubjectIcon(Subject subject) {
    switch (subject) {
      case Subject.mathe:
        return Icons.calculate;
      case Subject.deutsch:
        return Icons.menu_book;
      case Subject.englisch:
        return Icons.language;
      case Subject.sachkunde:
        return Icons.park;
      case Subject.biologie:
        return Icons.biotech;
      case Subject.chemie:
        return Icons.science;
      case Subject.physik:
        return Icons.bolt;
      case Subject.geschichte:
        return Icons.history_edu;
    }
  }
}

// =============================================================================
// WIDGETS
// =============================================================================
