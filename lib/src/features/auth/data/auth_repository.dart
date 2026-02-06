import 'package:firebase_auth/firebase_auth.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_repository.g.dart';

/// Repository für Authentication (Login, Registrierung, Logout)
/// Kommuniziert mit Firebase Auth
class AuthRepository {
  AuthRepository(this._auth);
  final FirebaseAuth _auth;

  /// Stream der aktuellen User-Status überwacht
  /// null = nicht eingeloggt, User = eingeloggt
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// Aktuell eingeloggter User (oder null)
  User? get currentUser => _auth.currentUser;

  /// Registriert einen neuen Eltern-Account
  Future<UserCredential> createUserWithEmailAndPassword(
      String email,
      String password,
      ) async {
    try {
      return await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      // Übersetze Firebase-Fehler ins Deutsche
      throw _handleAuthException(e);
    }
  }

  /// Login mit E-Mail und Passwort
  Future<UserCredential> signInWithEmailAndPassword(
      String email,
      String password,
      ) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Logout
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Passwort zurücksetzen (E-Mail senden)
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Übersetzt Firebase-Fehler ins Deutsche
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return 'Das Passwort ist zu schwach (min. 6 Zeichen).';
      case 'email-already-in-use':
        return 'Diese E-Mail wird bereits verwendet.';
      case 'user-not-found':
        return 'Kein Benutzer mit dieser E-Mail gefunden.';
      case 'wrong-password':
        return 'Falsches Passwort.';
      case 'invalid-email':
        return 'Ungültige E-Mail-Adresse.';
      case 'user-disabled':
        return 'Dieser Account wurde deaktiviert.';
      case 'too-many-requests':
        return 'Zu viele Anfragen. Bitte später erneut versuchen.';
      default:
        return 'Fehler: ${e.message}';
    }
  }
}

/// Provider für AuthRepository (Singleton)
/// Kann in der ganzen App mit ref.read(authRepositoryProvider) verwendet werden
@riverpod
AuthRepository authRepository(AuthRepositoryRef ref) {
  return AuthRepository(FirebaseAuth.instance);
}

/// Provider für den Auth-Status-Stream
/// Überwacht automatisch, ob jemand ein-/ausgeloggt ist
@riverpod
Stream<User?> authStateChanges(AuthStateChangesRef ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
}