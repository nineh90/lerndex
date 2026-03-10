import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lerndex/src/features/generated_tasks/presentation/widgets/info_row.dart';
import '../../auth/domain/child_model.dart';
import '../../auth/data/auth_repository.dart';
import '../../generated_tasks/data/generated_task_models.dart';
import '../../generated_tasks/data/generated_task_repository.dart';
import '../../generated_tasks/presentation/task_approval_screen.dart';
import '../../../ai/vertex_ai_service.dart';
import '../../student_dashboard/presentation/subject_config.dart'
    show getSubjectsForChild;

/// 📸 KI-AUFGABENGENERATOR FÜR ELTERN
///
/// Foto von Schulaufgabe → Vertex AI generiert Multiple-Choice-Übungen
/// Nach Generierung direkt Weiterleitung zum Freigabe-Screen (passendem Batch)
class TaskGeneratorScreen extends ConsumerStatefulWidget {
  final ChildModel child;

  const TaskGeneratorScreen({super.key, required this.child});

  @override
  ConsumerState<TaskGeneratorScreen> createState() =>
      _TaskGeneratorScreenState();
}

class _TaskGeneratorScreenState extends ConsumerState<TaskGeneratorScreen> {
  Subject? _selectedSubject;

  /// Für Klasse 1–2: gewähltes Unter-Thema (Zahlen/Buchstaben/Farben/Formen)
  String? _earlyLearnerTopic;
  File? _selectedImage;
  bool _isGenerating = false;
  String? _errorMessage;
  int _numberOfTasks = 5;

  final ImagePicker _picker = ImagePicker();

  // ---------------------------------------------------------------------------
  // FÄCHERLISTE — dynamisch passend zum Kind
  // ---------------------------------------------------------------------------

  /// Gibt die verfügbaren Fächer zurück die zur Klasse des Kindes passen.
  ///
  /// Klasse 1–2: farbenFormen (wird als 4 visuelle Karten dargestellt:
  ///              Zahlen, Buchstaben, Farben, Formen)
  /// Klasse 3+:  die normalen Schulfächer passend zur Klassenstufe
  List<Subject> _getAvailableSubjects() {
    // Klasse 1–2: nur Early-Learner-Fach
    if (widget.child.grade <= 2) {
      return [Subject.farbenFormen];
    }

    // Klasse 3+: aus SubjectConfig ableiten (bleibt die Single Source of Truth)
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

    // Fallback: alle Fächer die für diese Klasse eingetragen sind
    return result.isEmpty
        ? SubjectExtension.forGrade(widget.child.grade)
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoCard(),
            const SizedBox(height: 24),
            _buildSubjectSelector(),
            const SizedBox(height: 24),

            if (_selectedSubject != null) ...[
              if (_selectedImage == null)
                _buildImagePicker()
              else ...[
                _buildImagePreview(),
                const SizedBox(height: 16),
                _buildTaskCountSelector(),
                const SizedBox(height: 24),
                _buildGenerateButton(),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                _buildErrorCard(),
              ],
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
                    Text(
                      'KI-Aufgabengenerator',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple.shade800,
                      ),
                    ),
                    Text(
                      'Für ${widget.child.name} · ${widget.child.schoolType} · Klasse ${widget.child.grade}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.deepPurple.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const InfoRow(
            icon: Icons.camera_alt,
            text: 'Fotografiere eine Schulaufgabe',
          ),
          const SizedBox(height: 8),
          const InfoRow(
            icon: Icons.psychology,
            text: 'KI analysiert das Foto und erstellt ähnliche Übungen',
          ),
          const SizedBox(height: 8),
          const InfoRow(
            icon: Icons.check_circle,
            text: 'Du wirst direkt zur Freigabe weitergeleitet',
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FACH-SELEKTOR
  // ---------------------------------------------------------------------------

  Widget _buildSubjectSelector() {
    // Klasse 1–2: kindgerechte 4-Kachel-Ansicht statt Text-Chips
    if (widget.child.grade <= 2) {
      return _buildEarlyLearnerTopicSelector();
    }

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
              onTap: () => setState(() {
                _selectedSubject = subject;
                _selectedImage = null;
                _errorMessage = null;
              }),
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

  /// Kindgerechte Themenauswahl für Klasse 1–2.
  /// Zeigt 4 große bunte Kacheln: Zahlen 🔢, Buchstaben 🔤, Farben 🎨, Formen 🔷
  Widget _buildEarlyLearnerTopicSelector() {
    // Nur die Quiz-faehigen Fruehlernen-Themen anbieten.
    // Malen wird direkt im Dashboard geoeffnet, braucht keinen Eltern-Task.
    const topics = [
      ('Zahlen', '🔢', Color(0xFF7E57C2), Color(0xFF512DA8)),
      ('Buchstaben', '🔤', Color(0xFFEC407A), Color(0xFF8E24AA)),
      ('Farben & Formen', '🎨', Color(0xFF1E88E5), Color(0xFF00897B)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Was soll geübt werden?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.9,
          children: topics.map((t) {
            final (label, emoji, c1, c2) = t;
            final isSelected = _earlyLearnerTopic == label;
            return GestureDetector(
              onTap: () => setState(() {
                _earlyLearnerTopic = label;
                _selectedSubject = Subject.farbenFormen;
                _selectedImage = null;
                _errorMessage = null;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(colors: [c1, c2])
                      : null,
                  color: isSelected ? null : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? c1 : Colors.grey.shade200,
                    width: isSelected ? 0 : 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isSelected
                          ? c1.withValues(alpha: 0.35)
                          : Colors.black.withValues(alpha: 0.06),
                      blurRadius: isSelected ? 12 : 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 28)),
                    const SizedBox(height: 6),
                    Text(
                      label,
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
                border: Border.all(color: Colors.deepPurple.shade200, width: 2),
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
          const SizedBox(height: 4),
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
  // FEHLER-CARD
  // ---------------------------------------------------------------------------

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
      final image = await _picker.pickImage(
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

  Future<void> _generateAndSave() async {
    if (_selectedImage == null || _selectedSubject == null) return;

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final userId = ref.read(authRepositoryProvider).currentUser?.uid;
      if (userId == null) throw Exception('Nicht angemeldet');

      final aiService = ref.read(vertexAIServiceProvider);
      final result = await aiService.generateTasksFromImage(
        imageFile: _selectedImage!,
        child: widget.child,
        userId: userId,
        subject: _selectedSubject!,
        numberOfTasks: _numberOfTasks,
        earlyLearnerTopic: widget.child.grade <= 2 ? _earlyLearnerTopic : null,
      );

      if (!result.success || result.questions.isEmpty) {
        throw Exception(
          result.errorMessage ?? 'KI hat keine Aufgaben generiert',
        );
      }

      // In Firestore speichern → gibt Batch-ID zurück
      final repository = ref.read(generatedTaskRepositoryProvider);
      final batchId = await repository.saveGeneratedBatch(
        userId: userId,
        childId: widget.child.id,
        childName: widget.child.name,
        subject: _selectedSubject!,
        imageUrl: result.imageUrl ?? '',
        questions: result.questions,
      );

      if (mounted) {
        // Direkt zum Freigabe-Screen mit dem neuen Batch weiterleiten
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => TaskApprovalScreen(
              childId: widget.child.id,
              initialBatchId: batchId,
            ),
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
      case Subject.farbenFormen:
        return Icons.palette;
    }
  }
}
