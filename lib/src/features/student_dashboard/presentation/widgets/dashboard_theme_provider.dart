import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dashboard_theme.dart';

// ============================================================================
// DASHBOARD THEME PROVIDER
//
// Verwaltet Theme + Hintergrundbild für einen Schüler ab Klasse 5.
// Persistiert in Firestore unter:
//   users/{uid}/children/{childId}/dashboardTheme   (Map)
//   users/{uid}/children/{childId}/dashboardBgUrl   (String?)
// ============================================================================

class DashboardThemeState {
  final DashboardThemeData theme;
  final String? backgroundImageUrl; // Firebase Storage URL oder null

  const DashboardThemeState({required this.theme, this.backgroundImageUrl});

  DashboardThemeState copyWith({
    DashboardThemeData? theme,
    String? backgroundImageUrl,
    bool clearBackground = false,
  }) {
    return DashboardThemeState(
      theme: theme ?? this.theme,
      backgroundImageUrl: clearBackground
          ? null
          : (backgroundImageUrl ?? this.backgroundImageUrl),
    );
  }
}

class DashboardThemeNotifier extends StateNotifier<DashboardThemeState> {
  final String userId;
  final String childId;

  DashboardThemeNotifier({required this.userId, required this.childId})
    : super(const DashboardThemeState(theme: DashboardThemes.midnight)) {
    _load();
  }

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  DocumentReference get _childDoc =>
      _db.collection('users').doc(userId).collection('children').doc(childId);

  /// Lädt Theme aus Firestore beim Start
  Future<void> _load() async {
    try {
      final snap = await _childDoc.get();
      final data = snap.data() as Map<String, dynamic>?;
      if (data == null) return;

      final themeMap = data['dashboardTheme'] as Map<String, dynamic>?;
      final bgUrl = data['dashboardBgUrl'] as String?;

      final theme = themeMap != null
          ? DashboardThemeData.fromMap(themeMap)
          : DashboardThemes.midnight;

      state = DashboardThemeState(theme: theme, backgroundImageUrl: bgUrl);
    } catch (e) {
      // Fehler still ignorieren – Default-Theme bleibt aktiv
    }
  }

  /// Wählt ein neues Farbpreset und speichert es
  Future<void> setTheme(DashboardThemeData newTheme) async {
    state = state.copyWith(theme: newTheme);
    try {
      await _childDoc.update({'dashboardTheme': newTheme.toMap()});
    } catch (_) {}
  }

  /// Setzt eine neue Hintergrundbild-URL (nach Firebase Storage Upload)
  Future<void> setBackgroundUrl(String url) async {
    state = state.copyWith(backgroundImageUrl: url);
    try {
      await _childDoc.update({'dashboardBgUrl': url});
    } catch (_) {}
  }

  /// Entfernt das Hintergrundbild
  Future<void> clearBackground() async {
    state = state.copyWith(clearBackground: true);
    try {
      await _childDoc.update({'dashboardBgUrl': FieldValue.delete()});
    } catch (_) {}
  }
}

/// Provider-Familie: ein Provider pro Kind
final dashboardThemeProvider =
    StateNotifierProvider.family<
      DashboardThemeNotifier,
      DashboardThemeState,
      ({String userId, String childId})
    >(
      (ref, ids) =>
          DashboardThemeNotifier(userId: ids.userId, childId: ids.childId),
    );
