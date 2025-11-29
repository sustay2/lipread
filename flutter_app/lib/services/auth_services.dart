import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_app/services/secure_storage_service.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  // ----------------------------
  // Email / Password Sign-In
  // ----------------------------
  Future<UserCredential> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    await _ensureUserDoc(cred.user!);
    return cred;
  }

  // ----------------------------
  // Registration + email verification
  // ----------------------------
  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    if (displayName != null && displayName.isNotEmpty) {
      await cred.user!.updateDisplayName(displayName);
    }
    await _ensureUserDoc(cred.user!);
    await sendEmailVerification();
    return cred;
  }

  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  Future<void> reloadCurrentUser() async {
    await _auth.currentUser?.reload();
  }

  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  // --- Google Sign-In ---
  Future<UserCredential> signInWithGoogle() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile'],
      );

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        throw FirebaseAuthException(
          code: 'canceled',
          message: 'You cancelled the sign-in.',
        );
      }

      final GoogleSignInAuthentication googleAuth =
      await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCred =
      await FirebaseAuth.instance.signInWithCredential(credential);

      await _ensureUserDoc(userCred.user!);
      return userCred;

    } on FirebaseAuthException catch (e) {
      throw FirebaseAuthException(code: e.code, message: e.message);
    } catch (e) {
      throw FirebaseAuthException(
        code: 'unknown',
        message: 'Google Sign-In failed: $e',
      );
    }
  }

  Future<void> signOut() async {
    // Sign out from Google if applicable
    final google = GoogleSignIn();
    try {
      await google.signOut();
    } catch (_) {}

    // Clear biometric credentials only for the current user
    final user = _auth.currentUser;
    if (user != null) {
      await SecureStorageService.clearBiometricCredentialsForUser(user.uid);
    }

    // Firebase sign out
    await _auth.signOut();
  }

  // ----------------------------
  // Role resolution (claims-first)
  // ----------------------------
  Future<String> getEffectiveRole(String uid) async {
    final user = _auth.currentUser;
    if (user != null) {
      final token = await user.getIdTokenResult(true); // force refresh
      final claimRole = (token.claims?['role'] as String?)?.toLowerCase();
      if (claimRole != null && claimRole.isNotEmpty) return claimRole;
    }
    final doc = await _db.collection('users').doc(uid).get();
    return (doc.data()?['role'] as String? ?? 'learner').toLowerCase();
  }

  // ----------------------------
  // First-login profile bootstrap
  // ----------------------------
  Future<void> _ensureUserDoc(User user) async {
    final ref = _db.collection('users').doc(user.uid);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'displayName': user.displayName ?? '',
        'email': user.email,
        'photoURL': user.photoURL,
        'locale': 'en',
        'role': 'learner', // default
        'createdAt': FieldValue.serverTimestamp(),
        'lastActiveAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      await ref.update({'lastActiveAt': FieldValue.serverTimestamp()});
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }
}
