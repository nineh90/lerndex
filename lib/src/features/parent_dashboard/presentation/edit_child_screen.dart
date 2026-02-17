import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/domain/child_model.dart';
import '../../auth/data/profile_repository.dart';

/// Screen zum Bearbeiten eines Kindes
class EditChildScreen extends ConsumerStatefulWidget {
  final ChildModel child;

  const EditChildScreen({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<EditChildScreen> createState() => _EditChildScreenState();
}

class _EditChildScreenState extends ConsumerState<EditChildScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _ageController;
  late int _selectedGrade;
  late String _selectedSchoolType;
  bool _isSaving = false;

  static const List<String> _schoolTypes = [
    'Grundschule',
    'Gymnasium',
    'Realschule',
    'Hauptschule',
    'Gesamtschule',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.child.name);
    _ageController = TextEditingController(text: widget.child.age.toString());
    _selectedGrade = widget.child.grade;
    _selectedSchoolType = widget.child.schoolType;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      await ref.read(profileRepositoryProvider).updateChild(
        childId: widget.child.id,
        name: _nameController.text.trim(),
        age: int.tryParse(_ageController.text.trim()) ?? widget.child.age,
        schoolType: _selectedSchoolType,
        grade: _selectedGrade,
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Änderungen gespeichert!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Fehler beim Speichern: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.child.name} bearbeiten'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text(
                'Speichern',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar Vorschau
              Center(
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: Colors.deepPurple.shade100,
                  child: Text(
                    widget.child.name[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              _SectionHeader(icon: Icons.person, title: 'Persönliche Daten'),
              const SizedBox(height: 12),

              TextFormField(
                controller: _nameController,
                decoration: _inputDecoration(
                    label: 'Name', hint: 'z.B. Max', icon: Icons.badge_outlined),
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Bitte gib einen Namen ein';
                  if (value.trim().length < 2) return 'Name muss mindestens 2 Zeichen haben';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _ageController,
                decoration: _inputDecoration(
                    label: 'Alter', hint: 'z.B. 10', icon: Icons.cake_outlined),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Bitte gib das Alter ein';
                  final age = int.tryParse(value.trim());
                  if (age == null || age < 5 || age > 20) return 'Alter zwischen 5 und 20';
                  return null;
                },
              ),
              const SizedBox(height: 28),

              _SectionHeader(icon: Icons.school, title: 'Schulinformationen'),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                value: _selectedSchoolType,
                decoration: _inputDecoration(
                    label: 'Schulform', hint: '', icon: Icons.account_balance_outlined),
                items: _schoolTypes
                    .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _selectedSchoolType = value);
                },
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<int>(
                value: _selectedGrade,
                decoration: _inputDecoration(
                    label: 'Klasse', hint: '', icon: Icons.class_outlined),
                items: List.generate(13, (i) => i + 1)
                    .map((g) => DropdownMenuItem(value: g, child: Text('Klasse $g')))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _selectedGrade = value);
                },
              ),
              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save),
                  label: Text(_isSaving ? 'Wird gespeichert...' : 'Änderungen speichern'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Lernfortschritte (XP, Sterne, Level) bleiben erhalten.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500],
                      fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
      {required String label, required String hint, required IconData icon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: Colors.deepPurple),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
      ),
      filled: true,
      fillColor: Colors.grey.shade50,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.deepPurple, size: 20),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: Colors.deepPurple.shade100, thickness: 1)),
      ],
    );
  }
}