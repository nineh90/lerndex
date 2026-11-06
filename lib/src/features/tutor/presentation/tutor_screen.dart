import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:lerndex/src/ai/vertex_ai_service.dart';
import 'package:lerndex/src/shared/widgets/message_bubble.dart';
import 'package:lerndex/src/shared/widgets/picked_image.dart';
import '../domain/chat_message.dart';
import 'tutor_provider.dart';
import '../../auth/presentation/active_child_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/child_model.dart';
import '../../learning_time/learning_time_tracker.dart';
import '../../rewards/data/xp_service.dart';
import '../../rewards/data/reward_service.dart';
import '../../rewards/presentation/student_notification_popup.dart';
import 'package:lerndex/src/features/stt/stt_provider.dart';
import 'package:lerndex/src/features/tts/tts_provider.dart';
import 'widgets/xp_gain_overlay.dart';
import 'widgets/tutor_xp_banner.dart';
import 'package:lerndex/src/features/auth/domain/account.dart';

/// Chat-Screen mit dem KI-Tutor
class TutorScreen extends ConsumerStatefulWidget {
  const TutorScreen({super.key});

  @override
  ConsumerState<TutorScreen> createState() => _TutorScreenState();
}

class _TutorScreenState extends ConsumerState<TutorScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  LearningTimeTracker? _timeTracker;
  OverlayEntry? _xpOverlay;

  /// Aktuell gewähltes Aufgabenblatt-Foto, das mit der nächsten Nachricht
  /// an den Tutor geschickt wird (null = kein Foto).
  XFile? _selectedImage;

  // Werden in initState gespeichert – kein ref in dispose nötig
  XPService? _xpService;
  RewardService? _rewardService;
  TutorNotifier? _tutorNotifier;
  ActiveChildNotifier? _activeChildNotifier;
  TtsController? _tts;
  SttController? _stt;
  ChildModel? _child;
  String? _userId;

  // Verhindert gleichzeitige parallele Reward-Checks (Debounce)
  bool _isCheckingRewards = false;

  @override
  void initState() {
    super.initState();

    final child = ref.read(activeChildProvider);
    final user = ref.read(authStateChangesProvider).value;

    if (child != null && user != null) {
      _child = child;
      _userId = user.ownerUid;
      _xpService = ref.read(xpServiceProvider);
      _rewardService = ref.read(rewardServiceProvider);
      _activeChildNotifier = ref.read(activeChildProvider.notifier);
      _tts = ref.read(ttsControllerProvider.notifier);
      // Mikrofon-Controller für die Dauer des Bildschirms festhalten, damit
      // dispose genau diesen stoppen kann.
      ref.listenManual(sttControllerProvider, (_, _) {});
      _stt = ref.read(sttControllerProvider.notifier);

      final providerInstance = ref.read(tutorProvider);
      if (providerInstance != null) {
        _tutorNotifier = ref.read(providerInstance.notifier);
      }

      _timeTracker = LearningTimeTracker(
        userId: user.ownerUid,
        childId: child.id,
        subject: 'KI-Tutor',
      );
      _timeTracker!.startTracking();
      debugPrint('⏱️ Tutor: Zeit-Tracking gestartet');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Notifier aktuell halten – wird bei Provider-Invalidierung neu gesetzt
    final providerInstance = ref.read(tutorProvider);
    if (providerInstance != null) {
      _tutorNotifier = ref.read(providerInstance.notifier);
    }
  }

  void _showXpAnimation(int xpGained) {
    if (!mounted) return;
    _xpOverlay?.remove();
    _xpOverlay = OverlayEntry(
      builder: (context) => XpGainOverlay(
        xpGained: xpGained,
        onDone: () {
          _xpOverlay?.remove();
          _xpOverlay = null;
        },
      ),
    );
    Overlay.of(context).insert(_xpOverlay!);
  }

  Future<void> _checkRewardsAfterXp(dynamic child) async {
    // Verhindert parallele/gespammte Checks nach jeder einzelnen Nachricht
    if (_isCheckingRewards) return;
    _isCheckingRewards = true;

    final user = ref.read(authStateChangesProvider).value;
    final xpService = _xpService;
    final rewardService = _rewardService;
    if (user == null || xpService == null || rewardService == null) {
      _isCheckingRewards = false;
      return;
    }

    try {
      // Kurz warten damit Firestore den XP-Write abgeschlossen hat
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) {
        _isCheckingRewards = false;
        return;
      }

      ChildModel? updatedChild = await xpService.getChild(
        userId: user.ownerUid,
        childId: child.id,
      );
      if (updatedChild == null || !mounted) {
        _isCheckingRewards = false;
        return;
      }

      // ✅ FIX: activeChildProvider aktualisieren damit Dashboard-FAB
      // sofort das neue Level anzeigt (Tutor-Freischaltung bei Level 2)
      ref.read(activeChildProvider.notifier).update(updatedChild);

      final unlockedRewards = await rewardService.checkAndApproveRewards(
        userId: user.ownerUid,
        child: updatedChild,
      );

      if (unlockedRewards.isNotEmpty && mounted) {
        showRewardNotifications(context, rewards: unlockedRewards);
      }
    } catch (e) {
      debugPrint('❌ Tutor: Reward-Check fehlgeschlagen: $e');
    } finally {
      _isCheckingRewards = false;
    }
  }

  @override
  void dispose() {
    _tts?.stop(); // Lexi verstummt, wenn das Kind den Chat verlässt
    // Mikrofon aus: sonst startete die Spracherkennung nach jeder Pause neu.
    _stt?.cancel();
    _xpOverlay?.remove();
    _messageController.dispose();
    _scrollController.dispose();

    // Alle gespeicherten Referenzen verwenden – kein ref nötig
    final child = _child;
    final userId = _userId;
    final xpService = _xpService;
    final rewardService = _rewardService;
    final notifier = _tutorNotifier;
    final activeChildNotifier = _activeChildNotifier;
    final tracker = _timeTracker;

    // Session sofort abschließen (nicht erst nach dem Speichern der
    // Lernzeit): öffnet das Kind den Chat gleich wieder, soll es nicht die
    // alte, noch „aktive“ Session erwischen.
    notifier?.completeCurrentSession();

    if (tracker != null) {
      tracker.stopTracking();

      Future(() async {
        try {
          await tracker.saveTime();
          debugPrint('✅ Tutor: Lernzeit gespeichert');

          if (child != null &&
              userId != null &&
              xpService != null &&
              rewardService != null) {
            final newStreak = await xpService.updateStreak(
              userId: userId,
              childId: child.id,
            );
            debugPrint('✅ Tutor: Streak aktualisiert → $newStreak Tage');

            ChildModel? updatedChild = await xpService.getChild(
              userId: userId,
              childId: child.id,
            );

            if (updatedChild != null) {
              updatedChild = updatedChild.copyWith(streak: newStreak);

              // ✅ FIX: Provider aktualisieren → Dashboard zeigt sofort neuen Streak
              activeChildNotifier?.update(updatedChild);

              final unlockedRewards = await rewardService
                  .checkAndApproveRewards(userId: userId, child: updatedChild);
              if (unlockedRewards.isNotEmpty) {
                debugPrint(
                  '🎁 Tutor: ${unlockedRewards.length} Belohnungen freigeschaltet!',
                );
              }
            }
          }
        } catch (e) {
          debugPrint('❌ Fehler beim Speichern der Tutor-Lernzeit: $e');
        }
        tracker.dispose();
      });
    }

    super.dispose();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    final image = _selectedImage;
    if (text.isEmpty && image == null) return;

    final providerInstance = ref.read(tutorProvider);
    if (providerInstance == null) return;
    final notifier = ref.read(providerInstance.notifier);
    // Solange Lexi antwortet, bleibt der Text im Feld.
    if (notifier.isWaitingForAnswer) return;
    // Spracheingabe beenden, sonst schriebe sie ins geleerte Feld weiter.
    _stt?.stop();
    notifier.sendMessage(text, imageFile: image);
    // Safari spricht nur nach einem Tipp – Lexis Antwort kommt aber später.
    final child = ref.read(activeChildProvider);
    if (child != null && ref.read(tutorAutoReadProvider(child.id))) {
      _tts?.unlockWebAudio();
    }
    _messageController.clear();
    setState(() => _selectedImage = null);

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Auswahl-Sheet: Aufgabenblatt fotografieren oder aus Galerie wählen.
  void _showImageSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Aufgabenblatt hochladen',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.deepPurple),
              title: const Text('Foto aufnehmen'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library,
                color: Colors.deepPurple,
              ),
              title: const Text('Aus Galerie wählen'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    // Nur die Kamera braucht eine Runtime-Permission. Die Galerie läuft über
    // den System-Photo-Picker, der ganz ohne Medien-Berechtigung auskommt
    // (Play-Policy: READ_MEDIA_IMAGES ist bei gelegentlichem Zugriff verboten).
    // Im Browser fragt der Browser selbst nach der Kamera.
    if (source == ImageSource.camera && !kIsWeb) {
      final status = await Permission.camera.request();
      if (status.isDenied || status.isPermanentlyDenied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Kamera-Zugriff verweigert. Bitte in den Einstellungen erlauben.',
              ),
              backgroundColor: Colors.red,
              action: status.isPermanentlyDenied
                  ? const SnackBarAction(
                      label: 'Einstellungen',
                      textColor: Colors.white,
                      onPressed: openAppSettings,
                    )
                  : null,
            ),
          );
        }
        return;
      }
    }

    try {
      final image = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (image != null && mounted) {
        setState(() => _selectedImage = image);
      }
    } catch (e) {
      if (mounted) {
        debugPrint('⚠️ Tutor: Foto konnte nicht geladen werden: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Das Foto hat leider nicht geklappt. Versuch es noch einmal! 📷',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final providerInstance = ref.watch(tutorProvider);
    final messages = providerInstance != null
        ? ref.watch(providerInstance)
        : <ChatMessage>[];
    final child = ref.watch(activeChildProvider);

    if (child == null) {
      return const Scaffold(body: Center(child: Text('Kein Kind ausgewählt')));
    }

    // Lexi antwortet gerade → Senden gesperrt
    final isWaiting = messages.any((m) => m.isLoading);
    // Spracheingabe nur mit Erkennung auf dem Gerät (sonst ausgeblendet)
    final sttAvailable = ref.watch(sttAvailableProvider).value ?? false;

    // ✅ XP-Gain Listener → Animation + Reward-Check
    ref.listen(tutorXpGainProvider(child.id), (previous, gained) {
      if (gained > 0 && mounted) {
        _showXpAnimation(gained);
        // Reset damit nächstes Event wieder feuert
        Future.microtask(() {
          if (mounted) {
            ref.read(tutorXpGainProvider(child.id).notifier).state = 0;
          }
        });
        // Reward-Check nach XP-Vergabe
        _checkRewardsAfterXp(child);
      }
    });

    // Lexi automatisch vorlesen, sobald eine neue Antwort da ist (nicht beim
    // Laden des bisherigen Verlaufs)
    final autoRead = ref.watch(tutorAutoReadProvider(child.id));
    final ttsState = ref.watch(ttsControllerProvider);
    // Ohne erlaubte Stimme (im Browser nur lokale) kein Vorlesen
    final canRead = ttsState.isAvailable;
    if (providerInstance != null) {
      ref.listen(providerInstance, (previous, next) {
        final answered =
            (previous?.any((m) => m.isLoading) ?? false) &&
            next.isNotEmpty &&
            !next.last.isUser &&
            !next.last.isLoading;
        if (answered &&
            ref.read(ttsControllerProvider).isAvailable &&
            ref.read(tutorAutoReadProvider(child.id))) {
          _tts?.speakTutor(next.last.text, id: next.last.id);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.deepPurple.shade300,
              child: ClipOval(
                child: Image.asset(
                  'assets/images/lerndex_logo.webp',
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.school, size: 20, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text('Lexi'),
          ],
        ),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          if (canRead)
            IconButton(
              tooltip: autoRead
                  ? 'Automatisch vorlesen: an'
                  : 'Automatisch vorlesen: aus',
              icon: Icon(autoRead ? Icons.volume_up : Icons.volume_off),
              onPressed: () => _toggleAutoRead(child.id, autoRead),
            ),
        ],
      ),
      body: Column(
        children: [
          // Reaktiver XP-Banner mit Fortschrittsbalken
          TutorXpBanner(childId: child.id),

          // Chat-Nachrichten
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.smart_toy,
                          size: 80,
                          color: Colors.deepPurple.shade200,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Hallo ${child.name}! 👋',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Ich bin dein persönlicher Lernbegleiter.\nStell mir eine Frage!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final canSpeak =
                          canRead && !message.isUser && !message.isLoading;
                      return MessageBubble(
                        message: message,
                        childName: child.name,
                        childSelectedAvatar: child.selectedAvatar,
                        isSpeaking: ttsState.isSpeakingId(message.id),
                        onSpeak: canSpeak
                            ? () => _toggleSpeak(message, ttsState)
                            : null,
                      );
                    },
                  ),
          ),

          // ── Eingabe-Leiste ──────────────────────────────────────────────
          // FIX 1: SafeArea (nur bottom) → kein Überlappen mit Home-Indikator
          SafeArea(
            left: false,
            right: false,
            top: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_selectedImage != null) _buildImagePreview(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Foto-Button: Aufgabenblatt fotografieren/hochladen
                      _AttachButton(
                        onTap: isWaiting ? null : _showImageSourceSheet,
                      ),
                      // Mikrofon-Button (Tap-Toggle)
                      // 1x tippen → Aufnahme START, nochmal tippen → STOP.
                      // Bei erneutem Start wird an bestehenden Text angehängt,
                      // damit das Kind in Etappen sprechen und tippen kann.
                      if (sttAvailable)
                        _MicButton(
                          getCurrentText: () => _messageController.text,
                          onPartialResult: (text) {
                            // Text live ins Eingabefeld schreiben (höchstens
                            // so viel, wie Lexi annimmt).
                            final limited =
                                text.length >
                                    VertexAIService.maxTutorMessageLength
                                ? text.substring(
                                    0,
                                    VertexAIService.maxTutorMessageLength,
                                  )
                                : text;
                            _messageController.text = limited;
                            _messageController.selection =
                                TextSelection.fromPosition(
                                  TextPosition(offset: limited.length),
                                );
                          },
                        ),
                      const SizedBox(width: 4),
                      Expanded(
                        // FIX 2: maxLines: null + keyboardType multiline → Zeilenumbruch
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 120),
                          child: TextField(
                            controller: _messageController,
                            // Tippen auf der Bildschirmtastatur ist Lernzeit
                            // (der Tracker sieht nur Berührungen der App)
                            onChanged: (_) => _timeTracker?.markActivity(),
                            decoration: InputDecoration(
                              hintText: 'Stell mir eine Frage...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade100,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                            ),
                            maxLines: null,
                            minLines: 1,
                            maxLength: VertexAIService.maxTutorMessageLength,
                            maxLengthEnforcement: MaxLengthEnforcement.enforced,
                            // Zähler erst kurz vor der Grenze zeigen
                            buildCounter:
                                (
                                  context, {
                                  required currentLength,
                                  required isFocused,
                                  required maxLength,
                                }) =>
                                    maxLength != null &&
                                        currentLength > maxLength - 50
                                    ? Text('$currentLength / $maxLength')
                                    : null,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            textCapitalization: TextCapitalization.sentences,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Senden-Button unten ausgerichtet bei mehrzeiligem Text
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: FloatingActionButton(
                          onPressed: isWaiting ? null : _sendMessage,
                          tooltip: isWaiting
                              ? 'Lexi antwortet gerade …'
                              : 'Senden',
                          backgroundColor: isWaiting
                              ? Colors.grey.shade400
                              : Colors.deepPurple,
                          mini: true,
                          child: const Icon(
                            Icons.send,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Lautsprecher-Knopf an einer Lexi-Nachricht: vorlesen bzw. stoppen.
  void _toggleSpeak(ChatMessage message, TtsState ttsState) {
    if (ttsState.isSpeakingId(message.id)) {
      _tts?.stop();
    } else {
      _tts?.speakTutor(message.text, id: message.id);
    }
  }

  Future<void> _toggleAutoRead(String childId, bool current) async {
    await ref
        .read(tutorAutoReadProvider(childId).notifier)
        .setEnabled(!current);
    if (current) {
      await _tts?.stop();
    } else {
      // Spricht direkt im Tipp – schaltet im Browser auch die Ausgabe frei.
      await _tts?.speakTutor(
        'Ich lese dir meine Antworten ab jetzt vor.',
        id: 'auto_read_on',
      );
    }
  }

  /// Vorschau des gewählten Aufgabenblatt-Fotos mit Entfernen-Button.
  Widget _buildImagePreview() {
    final image = _selectedImage;
    if (image == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: pickedImage(
              image.path,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Aufgabenblatt bereit – schreib dazu, was du wissen willst (oder schick es direkt).',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            tooltip: 'Foto entfernen',
            color: Colors.grey,
            onPressed: () => setState(() => _selectedImage = null),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// MIKROFON-BUTTON (Push-to-Talk)
// ============================================================================
//
// UX-Verhalten:
// • Drücken-und-Halten → Aufnahme startet, ggf. Permission-Dialog
// • Live-Transkript erscheint im TextField (Eltern-Wunsch: nicht direkt
//   abschicken, damit Kind ergänzen kann)
// • Loslassen oder Wegziehen vom Button → Aufnahme stoppt
// • Visuelles Feedback: pulst während Aufnahme, Größe folgt Lautstärke
// • Fehler (z.B. Permission verweigert) erscheinen als SnackBar
//
// Bewusste Design-Entscheidung: KEIN Auto-Send. Das Kind hat immer die
// Kontrolle, was tatsächlich an den Tutor geht.

class _MicButton extends ConsumerStatefulWidget {
  final void Function(String text) onPartialResult;
  final String Function() getCurrentText;
  const _MicButton({
    required this.onPartialResult,
    required this.getCurrentText,
  });

  @override
  ConsumerState<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends ConsumerState<_MicButton> {
  String? _lastErrorShown;

  Future<void> _onTap() async {
    await ref
        .read(sttControllerProvider.notifier)
        .toggle(
          onResult: widget.onPartialResult,
          initialText: widget.getCurrentText(),
        );
    _showErrorIfChanged();
  }

  void _showErrorIfChanged() {
    final err = ref.read(sttControllerProvider).error;
    if (err != null && err != _lastErrorShown && mounted) {
      _lastErrorShown = err;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sttControllerProvider);
    final listening = state.isListening;

    // Größen-Animation: 1.0 normal, 1.0..1.25 abhängig von Lautstärke
    final scale = listening ? (1.0 + state.soundLevel * 0.25) : 1.0;

    final label = listening ? 'Aufnahme stoppen' : 'Spracheingabe starten';
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkResponse(
          onTap: _onTap,
          radius: 26,
          // 48 × 48 Trefferfläche, Kreis darin wie bisher 40 dp
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(child: _circle(listening, scale)),
          ),
        ),
      ),
    );
  }

  Widget _circle(bool listening, double scale) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: listening ? Colors.red.shade400 : Colors.deepPurple,
        boxShadow: listening
            ? [
                BoxShadow(
                  color: Colors.red.withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Transform.scale(
        scale: scale,
        child: Icon(
          listening ? Icons.stop : Icons.mic,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }
}

// ============================================================================
// FOTO-BUTTON – Aufgabenblatt hochladen
// ============================================================================

class _AttachButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _AttachButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    const label = 'Foto vom Aufgabenblatt';
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: label,
        excludeSemantics: true,
        child: InkResponse(
          onTap: onTap,
          radius: 26,
          // 48 × 48 Trefferfläche, Kreis darin wie bisher 40 dp
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.deepPurple.shade50,
                  border: Border.all(color: Colors.deepPurple.shade200),
                ),
                child: Icon(
                  Icons.add_a_photo_outlined,
                  color: onTap == null
                      ? Colors.deepPurple.shade200
                      : Colors.deepPurple,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
