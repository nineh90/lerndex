import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// Imports für Auth-System
import 'src/features/auth/presentation/login_screen.dart';
import 'src/features/auth/presentation/active_child_provider.dart';
import 'src/features/auth/data/auth_repository.dart';
import 'src/features/auth/data/profile_repository.dart';
import 'src/features/auth/domain/child_model.dart';

// Import für Quiz-System
import 'src/features/quiz/presentation/quiz_screen.dart';

// Imports für Eltern-Dashboard
import 'src/features/parent_dashboard/presentation/parent_dashboard_screen.dart';
import 'src/features/parent_dashboard/presentation/pin_setup_dialog.dart';
import 'src/features/parent_dashboard/presentation/pin_input_dialog.dart';
import 'src/features/parent_dashboard/data/pin_repository.dart';

// Imports für Belohnungssystem
import 'src/features/rewards/presentation/rewards_screen.dart';
import 'src/features/rewards/presentation/manage_rewards_screen.dart';

// Import KI-Tutor
import 'src/features/tutor/presentation/tutor_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);
    final activeChild = ref.watch(activeChildProvider);

    return MaterialApp(
      title: 'Lerndex',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: authState.when(
        data: (user) {
          if (user == null) return const LoginScreen();
          if (activeChild != null) return const ChildDashboard();
          return const ParentAdminDashboard();
        },
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, st) => Scaffold(body: Center(child: Text('Fehler: $e'))),
      ),
    );
  }
}

// ============================================================================
// ELTERN-DASHBOARD
// ============================================================================

class ParentAdminDashboard extends ConsumerWidget {
  const ParentAdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final childrenAsync = ref.watch(childrenListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lerndex Admin'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          // NEU: Eltern-Dashboard Icon
          IconButton(
            onPressed: () async => await _openParentDashboard(context, ref),
            icon: const Icon(Icons.admin_panel_settings),
            tooltip: 'Eltern-Dashboard',
          ),
          IconButton(
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            icon: const Icon(Icons.logout),
            tooltip: 'Abmelden',
          ),
        ],
      ),
      body: childrenAsync.when(
        data: (children) {
          if (children.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.child_care, size: 100, color: Colors.grey[400]),
                  const SizedBox(height: 20),
                  Text('Noch keine Kinder angelegt', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                  const SizedBox(height: 10),
                  const Text('Füge dein erstes Kind hinzu!', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: children.length,
            itemBuilder: (context, index) {
              final child = children[index];
              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.deepPurple.shade100,
                    child: Text(
                      child.name[0].toUpperCase(),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                    ),
                  ),
                  title: Text(child.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Text('${child.schoolType} • Klasse ${child.grade}'),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.stars, size: 16, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text('${child.stars}'),
                          const SizedBox(width: 16),
                          const Icon(Icons.emoji_events, size: 16, color: Colors.orange),
                          const SizedBox(width: 4),
                          Text('Level ${child.level}'),
                        ],
                      ),
                    ],
                  ),
                  trailing: SizedBox(
                    width: 110,
                    child: ElevatedButton(
                      onPressed: () => ref.read(activeChildProvider.notifier).select(child),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        minimumSize: const Size(0, 32),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow, size: 14),
                          SizedBox(width: 3),
                          Text('Lernen', style: TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Fehler: $e')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddChildDialog(context, ref),
        label: const Text('Kind hinzufügen'),
        icon: const Icon(Icons.add),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
    );
  }

  /// Öffnet das Eltern-Dashboard (mit PIN-Schutz)
  Future<void> _openParentDashboard(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authStateChangesProvider).value;
    if (user == null) return;

    // Prüfe ob PIN existiert
    final hasPin = await ref.read(pinRepositoryProvider).hasPinSet(user.uid);

    if (!hasPin) {
      // Kein PIN gesetzt → PIN erstellen
      final created = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const PinSetupDialog(),
      );

      if (created != true) return; // Abgebrochen
    }

    // PIN abfragen
    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PinInputDialog(),
    );

    if (verified == true) {
      // PIN korrekt → Dashboard öffnen
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ParentDashboardScreen(),
          ),
        );
      }
    }
  }

  void _showAddChildDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final ageController = TextEditingController();
    int selectedGrade = 1;
    String selectedSchoolType = 'Grundschule';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Neues Kind registrieren'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ageController,
                  decoration: const InputDecoration(labelText: 'Alter'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: selectedGrade,
                  decoration: const InputDecoration(labelText: 'Klasse'),
                  items: List.generate(13, (i) => i + 1)
                      .map((g) => DropdownMenuItem(value: g, child: Text('Klasse $g')))
                      .toList(),
                  onChanged: (val) => setState(() => selectedGrade = val!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedSchoolType,
                  decoration: const InputDecoration(labelText: 'Schulform'),
                  items: ['Grundschule', 'Gymnasium', 'Realschule', 'Hauptschule', 'Gesamtschule']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (val) => setState(() => selectedSchoolType = val!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.isNotEmpty) {
                  ref.read(profileRepositoryProvider).addChild(
                    name: nameController.text,
                    age: int.tryParse(ageController.text) ?? 6,
                    grade: selectedGrade,
                    schoolType: selectedSchoolType,
                  );
                  Navigator.pop(context);
                }
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// KIND-DASHBOARD (VERBESSERT)
// ============================================================================

class ChildDashboard extends ConsumerStatefulWidget {
  const ChildDashboard({super.key});

  @override
  ConsumerState<ChildDashboard> createState() => _ChildDashboardState();
}

class _ChildDashboardState extends ConsumerState<ChildDashboard> {
  int _sessionSeconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _sessionSeconds++);
    });
  }

  @override
  void dispose() {
    final activeChild = ref.read(activeChildProvider);
    if (activeChild != null && _sessionSeconds > 0) {
      ref.read(profileRepositoryProvider).addLearningTime(activeChild.id, _sessionSeconds);
    }
    _timer?.cancel();
    super.dispose();
  }

  String _formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final activeChild = ref.watch(activeChildProvider)!;

    return Scaffold(
      appBar: AppBar(
        title: Text('Hallo ${activeChild.name}! 👋'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => ref.read(activeChildProvider.notifier).deselect(),
          tooltip: 'Zurück',
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer, size: 18),
                    const SizedBox(width: 6),
                    Text(_formatTime(_sessionSeconds), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildStatusHeader(activeChild),
            const SizedBox(height: 30),
            const Text('Wähle ein Fach zum Lernen:', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 15,
              crossAxisSpacing: 15,
              children: [
                _SubjectTile(title: 'Mathe', icon: Icons.calculate, color: Colors.orange, onTap: () => _startQuiz(context, 'Mathe')),
                _SubjectTile(title: 'Deutsch', icon: Icons.menu_book, color: Colors.redAccent, onTap: () => _startQuiz(context, 'Deutsch')),
                _SubjectTile(title: 'Englisch', icon: Icons.language, color: Colors.blue, onTap: () => _startQuiz(context, 'Englisch')),
                _SubjectTile(title: 'Sachkunde', icon: Icons.wb_sunny, color: Colors.green, onTap: () => _startQuiz(context, 'Sachkunde')),
              ],
            ),
            const SizedBox(height: 30),
            _buildRewardsSection(activeChild),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'tutor',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TutorScreen()),
          );
        },
        backgroundColor: Colors.deepPurple,
        tooltip: 'KI-Tutor',
        child: const Icon(Icons.smart_toy, color: Colors.white),
      ),
    );
  }

  Widget _buildStatusHeader(ChildModel child) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.deepPurple, Colors.purple.shade700]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Level ${child.level}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text('${child.stars} ⭐ Sterne', style: const TextStyle(color: Colors.white70)),
                ],
              ),
              const Icon(Icons.emoji_events, color: Colors.amber, size: 50),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('XP: ${child.xp} / ${child.xpToNextLevel}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: child.xpProgress,
                  minHeight: 12,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRewardsSection(ChildModel child) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.amber.shade100, Colors.amber.shade200],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.card_giftcard, color: Colors.orange, size: 32),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Meine Belohnungen',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Verdiene Belohnungen durchs Lernen!',
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
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RewardsScreen()),
                );
              },
              icon: const Icon(Icons.redeem),
              label: const Text('Belohnungen ansehen'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _startQuiz(BuildContext context, String subject) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => QuizScreen(subject: subject)));
  }
}

// ============================================================================
// HILFSWIDGE
// ============================================================================

class _SubjectTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SubjectTile({required this.title, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      color: color.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
              child: Icon(icon, size: 40, color: color),
            ),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}