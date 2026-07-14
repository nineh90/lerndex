import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_repository.g.dart';

/// Repository für Authentication (Login, Registrierung, Logout)
/// Unterstützt: E-Mail/Passwort + Google Sign-In + Sign in with Apple
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
  // SIGN IN WITH APPLE
  // =========================================================================

  /// Login / Registrierung mit Apple (Pflicht auf iOS – Guideline 4.8).
  /// Gibt zurück ob es ein NEUER User ist (für Onboarding-Entscheidung).
  Future<({UserCredential credential, bool isNewUser})>
  signInWithApple() async {
    try {
      // Sicherheits-Nonce: rawNonce geht an Apple (gehasht), rawNonce an Firebase.
      final rawNonce = _generateNonce();
      final hashedNonce = _sha256ofString(rawNonce);

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );

      final credential = await _auth.signInWithCredential(oauthCredential);
      final isNewUser = credential.additionalUserInfo?.isNewUser ?? false;

      // Apple liefert Vor-/Nachname NUR beim allerersten Login → sofort sichern.
      final fullName = [
        appleCredential.givenName,
        appleCredential.familyName,
      ].where((e) => e != null && e.isNotEmpty).join(' ').trim();

      if (isNewUser) {
        if (fullName.isNotEmpty) {
          await credential.user?.updateDisplayName(fullName);
        }
        await _createUserDocument(
          credential.user!,
          displayName: fullName.isNotEmpty
              ? fullName
              : (credential.user!.displayName ?? ''),
        );
      }

      return (credential: credential, isNewUser: isNewUser);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw 'Apple-Login abgebrochen.';
      }
      throw 'Apple-Login fehlgeschlagen: ${e.message}';
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw e.toString();
    }
  }

  /// Erzeugt einen kryptografisch sicheren Zufalls-Nonce.
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  /// SHA256-Hash eines Strings (für den an Apple übergebenen Nonce).
  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
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

  /// Version der Datenschutzerklärung, der aktuell zugestimmt wird.
  /// Bei inhaltlichen Änderungen der Erklärung hochzählen – so ist
  /// nachvollziehbar, welcher Fassung ein Nutzer zugestimmt hat (Art. 7 DSGVO).
  static const String privacyPolicyVersion = '2026-07';

  /// Protokolliert die Zustimmung zur Datenschutzerklärung mit Server-
  /// Zeitstempel und Versionsnummer im User-Dokument.
  Future<void> recordPrivacyConsent() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _firestore.collection('users').doc(user.uid).set({
      'privacyAcceptedAt': FieldValue.serverTimestamp(),
      'privacyPolicyVersion': privacyPolicyVersion,
    }, SetOptions(merge: true));
  }

  /// Bricht eine Social-Neuregistrierung ab, wenn der Nutzer der
  /// Datenschutzerklärung NICHT zustimmt: löscht das eben angelegte
  /// User-Dokument und den Auth-Account wieder, damit ohne Einwilligung
  /// keine Daten zurückbleiben (DSGVO). Der Account ist frisch angemeldet,
  /// daher ist kein Re-Auth nötig.
  Future<void> abortNewSocialAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _firestore.collection('users').doc(user.uid).delete();
    await user.delete();
    await _googleSignIn.signOut();
  }

  /// Account löschen.
  ///
  /// ⚠️ ACHTUNG: Diese Methode löscht NUR den Firebase-Auth-Account.
  /// Firestore-/Storage-Daten müssen VORHER über
  /// `ProfileRepository.deleteAllUserData()` gelöscht werden – sonst bleiben
  /// Kinderdaten als verwaiste Datensätze zurück (DSGVO-Verstoß).
  /// Der vollständige Lösch-Flow liegt in `settings_screen.dart`.
  /// Wirft 'requires-recent-login', wenn die letzte Anmeldung zu lange her
  /// ist – dann muss vorher re-authentifiziert werden.
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Kein Benutzer angemeldet.');
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
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
      case 'requires-recent-login':
        return 'Bitte melde dich erneut an, um diese Aktion durchzuführen.';
      case 'network-request-failed':
        return 'Keine Internetverbindung. Bitte prüfe dein Netzwerk.';
      case 'invalid-credential':
        return 'E-Mail oder Passwort ist falsch.';
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
