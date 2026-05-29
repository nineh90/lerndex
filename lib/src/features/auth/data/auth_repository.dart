import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_repository.g.dart';

/// Repository für Authentication (Login, Registrierung, Logout)
/// Unterstützt: E-Mail/Passwort + Google Sign-In
class AuthRepository {
  AuthRepository(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  /// Stream der aktuellen User-Status überwacht
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// Aktuell eingeloggter User (oder null)
  User? get currentUser => _auth.currentUser;

  // =========================================================================
  // E-MAIL / PASSWORT
  // =========================================================================

  /// Registriert einen neuen Eltern-Account
  Future<UserCredential> createUserWithEmailAndPassword(
    String email,
    String password,
    String displayName, {
    DateTime? birthdate,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // DisplayName sofort setzen
      await credential.user?.updateDisplayName(displayName);

      // E-Mail Verifizierung senden
      await credential.user?.sendEmailVerification();

      // User-Dokument in Firestore anlegen
      await _createUserDocument(
        credential.user!,
        displayName: displayName,
        birthdate: birthdate,
      );

      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Login mit E-Mail und Passwort
  Future<UserCredential> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Prüfen ob E-Mail verifiziert ist
      if (!credential.user!.emailVerified) {
        await _auth.signOut();
        throw 'Bitte bestätige zuerst deine E-Mail-Adresse. Schau in dein Postfach!';
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// E-Mail Verifizierungs-Mail erneut senden
  Future<void> resendVerificationEmail() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  /// Prüft ob die aktuelle E-Mail verifiziert ist (refresht den User)
  Future<bool> isEmailVerified() async {
    await _auth.currentUser?.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  // =========================================================================
  // GOOGLE SIGN-IN
  // =========================================================================

  /// Login / Registrierung mit Google
  /// Gibt zurück ob es ein NEUER User ist (für Onboarding-Entscheidung)
  Future<({UserCredential credential, bool isNewUser})>
  signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) throw 'Google-Login abgebrochen.';

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final oauthCredential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final credential = await _auth.signInWithCredential(oauthCredential);
      final isNewUser = credential.additionalUserInfo?.isNewUser ?? false;

      // Bei neuem User: Firestore-Dokument anlegen
      if (isNewUser) {
        await _createUserDocument(
          credential.user!,
          displayName: credential.user!.displayName ?? '',
        );
      }

      return (credential: credential, isNewUser: isNewUser);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw e.toString();
    }
  }

  // =========================================================================
  // ONBOARDING
  // =========================================================================

  /// Prüft ob der Onboarding-Flow abgeschlossen wurde
  Future<bool> isOnboardingComplete() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final doc = await _firestore.collection('users').doc(user.uid).get();
    return doc.data()?['onboardingCompleted'] == true;
  }

  /// Markiert das Onboarding als abgeschlossen
  Future<void> completeOnboarding({required String displayName}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore.collection('users').doc(user.uid).set({
      'onboardingCompleted': true,
      'displayName': displayName,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Auch in Firebase Auth aktualisieren
    await user.updateDisplayName(displayName);
  }

  // =========================================================================
  // ALLGEMEIN
  // =========================================================================

  /// Logout (E-Mail + Google)
  Future<void> signOut() async {
    await Future.wait([_auth.signOut(), _googleSignIn.signOut()]);
  }

  /// Passwort zurücksetzen
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Account löschen
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Kein Benutzer angemeldet.');
    await user.delete();
  }

  // =========================================================================
  // PRIVATE HELPER
  // =========================================================================

  /// Erstellt das initiale User-Dokument in Firestore
  Future<void> _createUserDocument(
    User user, {
    required String displayName,
    DateTime? birthdate,
  }) async {
    await _firestore.collection('users').doc(user.uid).set({
      'email': user.email,
      'displayName': displayName,
      'createdAt': FieldValue.serverTimestamp(),
      'onboardingCompleted': false,
      'betaTester': false,
      'premiumUntil': null,
      if (birthdate != null) 'birthdate': Timestamp.fromDate(birthdate),
    }, SetOptions(merge: true));
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
      case 'account-exists-with-different-credential':
        return 'Diese E-Mail ist bereits mit einer anderen Anmeldemethode verknüpft.';
      default:
        return 'Fehler: ${e.message}';
    }
  }
}

// NACHHER — authStateChanges mit keepAlive damit er nie disposed wird:
@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) {
  return AuthRepository(FirebaseAuth.instance, FirebaseFirestore.instance);
}

@Riverpod(keepAlive: true)
Stream<User?> authStateChanges(Ref ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
}
