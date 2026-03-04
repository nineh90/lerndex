import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lerndex1/src/features/auth/data/auth_repository.dart';
import 'package:lerndex1/src/features/auth/presentation/active_child_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dashboard_theme.dart';
import 'dashboard_theme_provider.dart';

// ============================================================================
// THEME PICKER SHEET
//
// Bottom Sheet für Klasse 5+ zum Personalisieren des Dashboards:
// • 6 Farbtheme-Presets als Kacheln
// • Eigenes Hintergrundbild auswählen (Galerie)
// • Hintergrundbild entfernen
// ============================================================================

class ThemePickerSheet extends ConsumerStatefulWidget {
  const ThemePickerSheet({super.key});

  @override
  ConsumerState<ThemePickerSheet> createState() => _ThemePickerSheetState();
}

class _ThemePickerSheetState extends ConsumerState<ThemePickerSheet> {
  bool _isUploading = false;
  double _uploadProgress = 0.0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateChangesProvider).value;
    final child = ref.watch(activeChildProvider);
    if (user == null || child == null) return const SizedBox.shrink();

    final themeIds = (userId: user.uid, childId: child.id);
    final themeState = ref.watch(dashboardThemeProvider(themeIds));
    final themeNotifier = ref.read(dashboardThemeProvider(themeIds).notifier);

    return Container(
      decoration: BoxDecoration(
        color: themeState.theme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Ziehgriff ──────────────────────────────────────────────────
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: themeState.theme.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Titel ──────────────────────────────────────────────────────
          Text(
            'Mein Design',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: themeState.theme.onSurface,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Wähle deine Farben und dein Hintergrundbild',
            style: TextStyle(
              fontSize: 13,
              color: themeState.theme.onSurface.withOpacity(0.55),
            ),
          ),
          const SizedBox(height: 24),

          // ── Farbthemes ─────────────────────────────────────────────────
          Text(
            'Farbtheme',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: themeState.theme.onSurface.withOpacity(0.6),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: DashboardThemes.all.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final t = DashboardThemes.all[i];
                final isSelected = t.preset == themeState.theme.preset;
                return _ThemePresetTile(
                  theme: t,
                  isSelected: isSelected,
                  onTap: () => themeNotifier.setTheme(t),
                );
              },
            ),
          ),
          const SizedBox(height: 28),

          // ── Hintergrundbild ────────────────────────────────────────────
          Text(
            'Hintergrundbild',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: themeState.theme.onSurface.withOpacity(0.6),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),

          // Aktuelles Bild Vorschau
          if (themeState.backgroundImageUrl != null) ...[
            _BackgroundPreview(
              url: themeState.backgroundImageUrl!,
              onRemove: () => themeNotifier.clearBackground(),
              theme: themeState.theme,
            ),
            const SizedBox(height: 12),
          ],

          // Upload-Button / Fortschritt
          if (_isUploading)
            _UploadProgress(progress: _uploadProgress, theme: themeState.theme)
          else
            _UploadButton(
              theme: themeState.theme,
              hasBackground: themeState.backgroundImageUrl != null,
              onTap: () => _pickAndUpload(themeNotifier, user.uid, child.id),
            ),
        ],
      ),
    );
  }

  Future<void> _pickAndUpload(
    DashboardThemeNotifier notifier,
    String userId,
    String childId,
  ) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.3; // Lokales Kopieren – kein echter Fortschritt nötig
    });

    try {
      // Lokales App-Verzeichnis – kein Internetzugang nötig, keine Rechteprobleme
      final appDir = await getApplicationDocumentsDirectory();
      final ext = p.extension(picked.path);
      final destPath = p.join(appDir.path, 'bg_${childId}$ext');

      // Datei in App-Verzeichnis kopieren
      await File(picked.path).copy(destPath);

      if (mounted) setState(() => _uploadProgress = 1.0);
      await Future.delayed(const Duration(milliseconds: 200));

      // Pfad als "file://..." URL speichern
      await notifier.setBackgroundUrl('file://$destPath');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Bild konnte nicht geladen werden.'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }
}

// ── Theme Preset Kachel ───────────────────────────────────────────────────────

class _ThemePresetTile extends StatelessWidget {
  final DashboardThemeData theme;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemePresetTile({
    required this.theme,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 70,
        decoration: BoxDecoration(
          gradient: theme.headerGradient,
          borderRadius: BorderRadius.circular(18),
          border: isSelected
              ? Border.all(color: Colors.white, width: 3)
              : Border.all(color: Colors.transparent, width: 3),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: theme.primary.withOpacity(0.5),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(theme.emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 4),
            Text(
              theme.name,
              style: const TextStyle(
                fontSize: 9,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
            if (isSelected) ...[
              const SizedBox(height: 4),
              const Icon(Icons.check_circle, color: Colors.white, size: 14),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Hintergrundbild Vorschau ──────────────────────────────────────────────────

class _BackgroundPreview extends StatelessWidget {
  final String url;
  final VoidCallback onRemove;
  final DashboardThemeData theme;

  const _BackgroundPreview({
    required this.url,
    required this.onRemove,
    required this.theme,
  });

  Widget _buildPreviewImage(String url, DashboardThemeData theme) {
    if (url.startsWith('file://')) {
      final path = url.replaceFirst('file://', '');
      return Image.file(
        File(path),
        height: 100,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          height: 100,
          color: theme.surface,
          child: Icon(Icons.broken_image_outlined, color: theme.primary),
        ),
      );
    }
    return Image.network(
      url,
      height: 100,
      width: double.infinity,
      fit: BoxFit.cover,
      loadingBuilder: (_, child, progress) => progress == null
          ? child
          : Container(
              height: 100,
              color: theme.surface,
              child: const Center(child: CircularProgressIndicator()),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: _buildPreviewImage(url, theme),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 16),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Upload Button ─────────────────────────────────────────────────────────────

class _UploadButton extends StatelessWidget {
  final DashboardThemeData theme;
  final bool hasBackground;
  final VoidCallback onTap;

  const _UploadButton({
    required this.theme,
    required this.hasBackground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(color: theme.primary.withOpacity(0.5), width: 2),
          borderRadius: BorderRadius.circular(16),
          color: theme.primary.withOpacity(0.08),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasBackground
                  ? Icons.swap_horiz_rounded
                  : Icons.add_photo_alternate_rounded,
              color: theme.primary,
              size: 22,
            ),
            const SizedBox(width: 10),
            Text(
              hasBackground ? 'Bild ändern' : 'Bild aus Galerie wählen',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: theme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Upload Fortschritt ────────────────────────────────────────────────────────

class _UploadProgress extends StatelessWidget {
  final double progress;
  final DashboardThemeData theme;

  const _UploadProgress({required this.progress, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Wird hochgeladen...',
                style: TextStyle(
                  fontSize: 14,
                  color: theme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                '${(progress * 100).round()}%',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: theme.primary.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(theme.primary),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}
