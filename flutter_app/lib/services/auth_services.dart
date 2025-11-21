import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
    final google = GoogleSignIn.instance;
    await google.initialize();

    // Optional fast path; nullable on some platforms
    final Future<void>? light = google.attemptLightweightAuthentication();
    if (light != null) {
      try { await light.timeout(const Duration(seconds: 3)); } catch (_) {}
    }

    if (!google.supportsAuthenticate()) {
      // If you support web, route to the web button flow instead.
      throw FirebaseAuthException(
        code: 'platform-unsupported',
        message: 'Google authenticate() not supported on this platform.',
      );
    }

    // Start auth UI (this may throw if user cancels immediately)
    try {
      await google.authenticate();
    } on Object catch (e) {
      throw FirebaseAuthException(code: 'auth-ui-failed', message: e.toString());
    }

    // Listen for ANY result: success, cancel, or error
    final completer = Completer<dynamic>();
    late final StreamSubscription sub;
    Timer? timer;

    void finishOnce([Object? error, StackTrace? st]) {
      if (!completer.isCompleted) {
        if (error != null) {
          completer.completeError(error, st);
        } else {
          completer.complete(null); // success will come via event path below
        }
      }
      timer?.cancel();
      sub.cancel();
    }

    sub = google.authenticationEvents.listen(
          (event) async {
        final text = event.toString();
        // Success
        if (text.contains('SignIn')) {
          try {
            // event.user.authentication may be Future OR object
            final dynamic authMaybeFuture = (event as dynamic).user.authentication;
            final dynamic authObj = authMaybeFuture is Future ? await authMaybeFuture : authMaybeFuture;

            final String? idToken = (authObj as dynamic).idToken as String?;
            if (idToken == null || idToken.isEmpty) {
              finishOnce(FirebaseAuthException(
                code: 'missing-id-token',
                message: 'Google did not return an ID token.',
              ));
              return;
            }

            final credential = GoogleAuthProvider.credential(idToken: idToken);
            final cred = await _auth.signInWithCredential(credential);
            await _ensureUserDoc(cred.user!);
            if (!completer.isCompleted) completer.complete(cred);
            timer?.cancel();
            sub.cancel();
          } catch (e, st) {
            finishOnce(FirebaseAuthException(code: 'google-sign-in-failed', message: e.toString()), st);
          }
        }
        // Explicit cancel / sign-out events
        else if (text.contains('Cancel') || text.contains('SignOut') || text.contains('Canceled') || text.contains('Cancelled')) {
          finishOnce(FirebaseAuthException(code: 'canceled', message: 'Sign-in was canceled.'));
        }
        // Any event that looks like an exception
        else if (text.contains('Exception')) {
          finishOnce(FirebaseAuthException(code: 'google-sign-in-failed', message: text));
        }
      },
      onError: (e, st) {
        finishOnce(FirebaseAuthException(code: 'google-sign-in-failed', message: e.toString()), st);
      },
      cancelOnError: false,
    );

    // Hard timeout so the call always returns
    timer = Timer(const Duration(seconds: 45), () {
      finishOnce(FirebaseAuthException(
        code: 'timeout',
        message: 'Google sign-in timed out. Check Play Services/account.',
      ));
    });

    try {
      final result = await completer.future; // either a UserCredential or null (already completed above)
      if (result is UserCredential) return result;

      // If we got here without a credential, treat as failure
      throw FirebaseAuthException(code: 'google-sign-in-failed', message: 'Unknown sign-in result.');
    } finally {
      timer?.cancel();
      await sub.cancel();
    }
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.disconnect();
    } catch (_) {

    }
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
