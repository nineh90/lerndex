import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../ai/vertex_ai_service.dart';
import '../../../shared/widgets/picked_image.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/account.dart';
import '../../auth/domain/child_model.dart';
import '../../generated_tasks/data/generated_task_models.dart';
import '../../generated_tasks/data/generated_task_repository.dart';
import '../../student_dashboard/presentation/subject_config.dart'
    show getSubjectsForChild;
import '../domain/school_models.dart';

/// Lehrkraft: Aufgaben für die Klasse erzeugen – aus einem Foto (Arbeitsblatt,
/// Tafelbild) oder aus einem Thema. Die Lehrkraft prüft die Aufgaben, streicht
/// unpassende und wählt die Kinder. Jedes Kind bekommt die Aufgaben dann
/// freigegeben in seinem Quiz (wie Eltern-Aufgaben).
class ClassTaskScreen extends ConsumerStatefulWidget {
  const ClassTaskScreen({
    super.key,
    required this.schoolId,
    required this.schoolClass,
    required this.students,
  });

  final String schoolId;
  final SchoolClass schoolClass;
  final List<ChildModel> students;

  @override
  ConsumerState<ClassTaskScreen> createState() => _ClassTaskScreenState();
}

enum _Source { topic, photo }

class _ClassTaskScreenState extends ConsumerState<ClassTaskScreen> {
  static const _purple = Color(0xFF6B21A8);
  static const _stringToSubject = {
    'Mathe': Subject.mathe,
    'Deutsch': Subject.deutsch,
    'Englisch': Subject.englisch,
    'Sachkunde': Subject.sachkunde,
    'Biologie': Subject.biologie,
    'Chemie': Subject.chemie,
    'Physik': Subject.physik,
    'Geschichte': Subject.geschichte,
  };

  late final ChildModel _classChild = ChildModel(
    id: widget.schoolClass.id,
    name: 'Klasse ${widget.schoolClass.name}',
    grade: widget.schoolClass.grade,
    schoolType: widget.schoolClass.schoolType,
    age: (widget.schoolClass.grade + 5).clamp(6, 16),
  );

  late final List<Subject> _subjects = _subjectsForClass();
  Subject? _subject;
  _Source _source = _Source.topic;
  final _topic = TextEditingController();
  XFile? _image;
  int _count = 5;

  bool _busy = false;
  String? _error;
  List<GeneratedQuestion>? _questions;
  String _imageUrl = '';
  final _removed = <int>{};
  late final Set<String> _selected = widget.students.map((s) => s.id).toSet();

  List<Subject> _subjectsForClass() {
    if (widget.schoolClass.grade <= 2) return [];
    final result = <Subject>[];
    for (final config in getSubjectsForChild(_classChild)) {
      final s = _stringToSubject[config.subject];
      if (s != null && !result.contains(s)) result.add(s);
    }
    return result.isEmpty
        ? SubjectExtension.forGrade(widget.schoolClass.grade)
        : result;
  }

  /// Fach-Name, wie ihn die Quiz-Generierung erwartet („Mathe“, …)
  String _quizSubject(Subject s) =>
      _stringToSubject.entries.firstWhere((e) => e.value == s).key;

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final subject = _subject;
    if (subject == null) {
      setState(() => _error = 'Bitte ein Fach wählen.');
      return;
    }
    if (_source == _Source.topic && _topic.text.trim().length < 3) {
      setState(() => _error = 'Bitte ein Thema eingeben.');
      return;
    }
    if (_source == _Source.photo && _image == null) {
      setState(() => _error = 'Bitte ein Foto wählen.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ai = ref.read(vertexAIServiceProvider);
      final owner = schoolOwnerUid(widget.schoolId);
      if (_source == _Source.photo) {
        final result = await ai.generateTasksFromImage(
          imageFile: _image!,
          child: _classChild,
          userId: owner,
          subject: subject,
          numberOfTasks: _count,
        );
        if (!result.success || result.questions.isEmpty) {
          throw Exception(result.errorMessage ?? 'Keine Aufgaben erzeugt.');
        }
        _imageUrl = result.imageUrl ?? '';
        _questions = result.questions;
      } else {
        final quiz = await ai.generateQuizQuestions(
          child: _classChild,
          subject: _quizSubject(subject),
          count: _count,
          teacherTopic: _topic.text.trim(),
        );
        if (quiz.isEmpty) throw Exception('Keine Aufgaben erzeugt.');
        _imageUrl = '';
        _questions = [
          for (final q in quiz)
            GeneratedQuestion(
              id: '',
              question: q.question,
              options: q.options,
              correctAnswer: q.answer,
              difficulty: q.difficulty,
              topic: q.topic.isEmpty ? _topic.text.trim() : q.topic,
              status: TaskApprovalStatus.approved,
              createdAt: DateTime.now(),
            ),
        ];
      }
      _removed.clear();
    } catch (e) {
      _error = 'Das hat nicht geklappt: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _assign() async {
    final kept = [
      for (var i = 0; i < _questions!.length; i++)
        if (!_removed.contains(i)) _questions![i],
    ];
    final students = widget.students
        .where((s) => _selected.contains(s.id))
        .map((s) => (id: s.id, name: s.name))
        .toList();
    if (kept.isEmpty || students.isEmpty) return;
    setState(() => _busy = true);
    try {
      final title = _source == _Source.topic
          ? _topic.text.trim()
          : (kept.first.topic.isNotEmpty ? kept.first.topic : 'Aufgaben');
      await ref
          .read(generatedTaskRepositoryProvider)
          .assignToStudents(
            ownerUid: schoolOwnerUid(widget.schoolId),
            classId: widget.schoolClass.id,
            students: students,
            subject: _subject!,
            title: title,
            questions: kept,
            assignedBy: ref.read(authRepositoryProvider).currentUser?.uid ?? '',
            imageUrl: _imageUrl,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${kept.length} Aufgaben an ${students.length} '
            '${students.length == 1 ? 'Kind' : 'Kinder'} gegeben.',
          ),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Speichern hat nicht geklappt: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Aufgaben für ${widget.schoolClass.name}'),
        backgroundColor: _purple,
        foregroundColor: Colors.white,
      ),
      body: _subjects.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Für Klasse 1 und 2 gibt es eigene Lernspiele, eigene '
                  'Aufgaben gehen hier noch nicht.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: _questions == null ? _setup() : _review(),
            ),
    );
  }

  List<Widget> _setup() => [
    const Text('Fach', style: TextStyle(fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in _subjects)
          ChoiceChip(
            label: Text(s.displayName),
            selected: _subject == s,
            onSelected: _busy ? null : (_) => setState(() => _subject = s),
          ),
      ],
    ),
    const SizedBox(height: 20),
    SegmentedButton<_Source>(
      segments: const [
        ButtonSegment(
          value: _Source.topic,
          label: Text('Zu einem Thema'),
          icon: Icon(Icons.edit_note),
        ),
        ButtonSegment(
          value: _Source.photo,
          label: Text('Aus einem Foto'),
          icon: Icon(Icons.photo_camera_outlined),
        ),
      ],
      selected: {_source},
      onSelectionChanged: _busy
          ? null
          : (v) => setState(() => _source = v.first),
    ),
    const SizedBox(height: 16),
    if (_source == _Source.topic)
      TextField(
        controller: _topic,
        enabled: !_busy,
        decoration: const InputDecoration(
          labelText: 'Thema',
          hintText: 'z.B. Schriftliche Addition bis 1000',
          border: OutlineInputBorder(),
        ),
      )
    else ...[
      if (_image != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: pickedImage(_image!.path, height: 180, fit: BoxFit.cover),
        ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _pick(ImageSource.camera),
              icon: const Icon(Icons.photo_camera),
              label: const Text('Kamera'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _pick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library),
              label: const Text('Datei'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        'Arbeitsblatt, Buchseite oder Tafelbild. Bitte ohne Namen von Kindern.',
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
    ],
    const SizedBox(height: 16),
    Row(
      children: [
        const Text('Anzahl Aufgaben'),
        const Spacer(),
        DropdownButton<int>(
          value: _count,
          items: const [
            DropdownMenuItem(value: 5, child: Text('5')),
            DropdownMenuItem(value: 10, child: Text('10')),
          ],
          onChanged: _busy ? null : (v) => setState(() => _count = v ?? 5),
        ),
      ],
    ),
    if (_error != null) ...[
      const SizedBox(height: 8),
      Text(_error!, style: const TextStyle(color: Colors.red)),
    ],
    const SizedBox(height: 16),
    FilledButton.icon(
      onPressed: _busy ? null : _generate,
      style: FilledButton.styleFrom(
        backgroundColor: _purple,
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.auto_awesome),
      label: Text(_busy ? 'Lexi erstellt die Aufgaben …' : 'Aufgaben erstellen'),
    ),
  ];

  Future<void> _pick(ImageSource source) async {
    final image = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );
    if (image != null) setState(() => _image = image);
  }

  List<Widget> _review() {
    final questions = _questions!;
    final kept = questions.length - _removed.length;
    return [
      Text(
        'Bitte prüfen: Aufgaben, die nicht passen, abwählen.',
        style: TextStyle(color: Colors.grey[800]),
      ),
      const SizedBox(height: 8),
      for (var i = 0; i < questions.length; i++)
        Card(
          child: CheckboxListTile(
            value: !_removed.contains(i),
            onChanged: _busy
                ? null
                : (v) => setState(
                    () => v == true ? _removed.remove(i) : _removed.add(i),
                  ),
            title: Text(questions[i].question),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final o in questions[i].options)
                    Chip(
                      label: Text(o, style: const TextStyle(fontSize: 12)),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: o == questions[i].correctAnswer
                          ? const Color(0xFFDCFCE7)
                          : null,
                    ),
                ],
              ),
            ),
          ),
        ),
      const SizedBox(height: 16),
      Row(
        children: [
          const Text('Für', style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    if (_selected.length == widget.students.length) {
                      _selected.clear();
                    } else {
                      _selected.addAll(widget.students.map((s) => s.id));
                    }
                  }),
            child: Text(
              _selected.length == widget.students.length
                  ? 'Keins'
                  : 'Alle',
            ),
          ),
        ],
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final s in widget.students)
            FilterChip(
              label: Text(s.name),
              selected: _selected.contains(s.id),
              onSelected: _busy
                  ? null
                  : (v) => setState(
                      () => v ? _selected.add(s.id) : _selected.remove(s.id),
                    ),
            ),
        ],
      ),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(_error!, style: const TextStyle(color: Colors.red)),
      ],
      const SizedBox(height: 20),
      FilledButton(
        onPressed: _busy || kept == 0 || _selected.isEmpty ? null : _assign,
        style: FilledButton.styleFrom(
          backgroundColor: _purple,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text(
          '$kept ${kept == 1 ? 'Aufgabe' : 'Aufgaben'} an ${_selected.length} '
          '${_selected.length == 1 ? 'Kind' : 'Kinder'} geben',
        ),
      ),
      TextButton(
        onPressed: _busy ? null : () => setState(() => _questions = null),
        child: const Text('Neu erstellen'),
      ),
    ];
  }
}
