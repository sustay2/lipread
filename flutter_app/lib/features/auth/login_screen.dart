import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_app/services/auth_services.dart';
import 'package:flutter_app/services/router.dart';
import 'package:flutter_app/services/biometric_service.dart';
import 'package:flutter_app/services/secure_storage_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _obscure = true;
  bool _loading = false;
  String? _error;

  bool _hasFingerprint = false;
  bool _hasFace = false;
  bool _storedForThisUser = false;

  @override
  void initState() {
    super.initState();
    _initBiometrics();
  }

  Future<void> _initBiometrics() async {
    final can = await BiometricService.canUseBiometrics();
    if (!can) return;

    final (hasFp, hasFc) = await BiometricService.getBiometricTypes();
    final stored = await SecureStorageService.hasBiometricCredentials();

    if (!mounted) return;

    setState(() {
      _hasFingerprint = hasFp;
      _hasFace = hasFc;
      _storedForThisUser = stored;
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // NORMAL EMAIL/PASSWORD LOGIN
  // ---------------------------------------------------------------------------
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final cred = await AuthService.instance
          .signInWithEmailPassword(email: email, password: password);

      await _maybeOfferBiometrics(email, password);
      await _navigate(cred.user!.uid);
    } catch (e) {
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // OFFER TO ENROLL BIOMETRICS AFTER SUCCESSFUL LOGIN
  // ---------------------------------------------------------------------------
  Future<void> _maybeOfferBiometrics(String email, String password) async {
    final can = await BiometricService.canUseBiometrics();
    if (!can) return;

    final hasStored = await SecureStorageService.hasBiometricCredentials();
    if (hasStored) return;

    final enable = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Enable quick login?"),
        content: const Text(
          "Use fingerprint or face recognition next time you sign in.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Not now"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Enable"),
          ),
        ],
      ),
    );

    if (enable != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await SecureStorageService.saveBiometricCredentials(
      uid: user.uid,
      email: email,
      password: password,
    );

    final ok = await BiometricService.authenticate(
      reason: "Confirm biometrics",
    );

    if (!ok) {
      await SecureStorageService.clearAllBiometricCredentials();
    } else {
      setState(() => _storedForThisUser = true);
    }
  }

  // ---------------------------------------------------------------------------
  // FINGERPRINT LOGIN
  // ---------------------------------------------------------------------------
  Future<void> _loginWithFingerprint() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final stored = await SecureStorageService.readBiometricCredentials();
      if (stored == null) {
        setState(() => _error = "No biometric login configured.");
        return;
      }

      final (uid, email, password) = stored;

      final ok = await BiometricService.authenticateWithFingerprint(
        reason: "Use fingerprint to login",
      );

      if (!ok) {
        setState(() => _error = "Fingerprint authentication failed.");
        return;
      }

      final cred = await AuthService.instance
          .signInWithEmailPassword(email: email, password: password);

      await _navigate(cred.user!.uid);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // FACE LOGIN
  // ---------------------------------------------------------------------------
  Future<void> _loginWithFace() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final stored = await SecureStorageService.readBiometricCredentials();
      if (stored == null) {
        setState(() => _error = "No biometric login configured.");
        return;
      }

      final (uid, email, password) = stored;

      final ok = await BiometricService.authenticateWithFace(
        reason: "Use face recognition to login",
      );

      if (!ok) {
        setState(() => _error = "Face recognition failed.");
        return;
      }

      final cred = await AuthService.instance
          .signInWithEmailPassword(email: email, password: password);

      await _navigate(cred.user!.uid);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // GOOGLE LOGIN
  // ---------------------------------------------------------------------------
  Future<void> _loginWithGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final cred = await AuthService.instance.signInWithGoogle();
      await _navigate(cred.user!.uid);
    } catch (e) {
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // NAVIGATION
  // ---------------------------------------------------------------------------
  Future<void> _navigate(String uid) async {
    final role = await AuthService.instance.getEffectiveRole(uid);

    switch (role) {
      case 'admin':
        Navigator.pushNamedAndRemoveUntil(context, Routes.admin, (_) => false);
        break;
      case 'creator':
        Navigator.pushNamedAndRemoveUntil(context, Routes.creator, (_) => false);
        break;
      case 'instructor':
        Navigator.pushNamedAndRemoveUntil(context, Routes.instructor, (_) => false);
        break;
      default:
        Navigator.pushNamedAndRemoveUntil(context, Routes.learnerShell, (_) => false);
    }
  }

  // ---------------------------------------------------------------------------
  // ERROR MESSAGE
  // ---------------------------------------------------------------------------
  String _friendlyError(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'wrong-password':
          return "Incorrect password.";
        case 'user-not-found':
          return "Account does not exist.";
        case 'network-request-failed':
          return "Network error.";
      }
    }
    return e.toString();
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FB),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        Icon(Icons.mic_none_rounded,
                            size: 64, color: theme.colorScheme.primary),
                        const SizedBox(height: 12),

                        Text(
                          "Welcome Back 👋",
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),

                        Text(
                          "Sign in to continue learning",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.grey,
                          ),
                        ),

                        const SizedBox(height: 32),

                        // EMAIL
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: _input(
                            "Email",
                            prefix: Icons.email_outlined,
                          ),
                          validator: (v) =>
                              v == null || v.isEmpty ? "Required" : null,
                        ),
                        const SizedBox(height: 16),

                        // PASSWORD
                        TextFormField(
                          controller: _passwordCtrl,
                          obscureText: _obscure,
                          decoration: _input(
                            "Password",
                            prefix: Icons.lock_outline,
                            suffix: IconButton(
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) =>
                              v == null || v.isEmpty ? "Required" : null,
                        ),

                        const SizedBox(height: 12),

                        if (_error != null)
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade100),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline,
                                    color: Colors.red, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => Navigator.pushNamed(
                                context, Routes.forgotPassword),
                            child: const Text("Forgot Password?"),
                          ),
                        ),

                        const SizedBox(height: 8),

                        // LOGIN BUTTON
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _loading ? null : _login,
                            child: _loading
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text("Login"),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // BIOMETRIC BUTTONS (SIDE-BY-SIDE)
                        if (_storedForThisUser)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_hasFingerprint)
                                _bioButton(
                                  key: UniqueKey(),
                                  icon: Icons.fingerprint,
                                  onTap: _loginWithFingerprint,
                                ),
                              if (_hasFingerprint && _hasFace)
                                const SizedBox(width: 20),
                              if (_hasFace)
                                _bioButton(
                                  key: UniqueKey(),
                                  icon: Icons.face_unlock_rounded,
                                  onTap: _loginWithFace,
                                ),
                            ],
                          ),

                        const SizedBox(height: 20),

                        Row(
                          children: const [
                            Expanded(child: Divider()),
                            SizedBox(width: 8),
                            Text("Or Continue With"),
                            SizedBox(width: 8),
                            Expanded(child: Divider()),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // GOOGLE LOGIN BUTTON
                        SizedBox(
                          width: 200,
                          height: 55,
                          child: InkWell(
                            onTap: _loading ? null : _loginWithGoogle,
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border:
                                    Border.all(color: Colors.grey.shade300),
                                color: Colors.white,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Image.asset(
                                    "assets/icons/google.png",
                                    width: 28,
                                    height: 28,
                                  ),
                                  const SizedBox(width: 10),
                                  const Text(
                                    "Google",
                                    style: TextStyle(fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        TextButton(
                          onPressed: () =>
                              Navigator.pushNamed(context, Routes.register),
                          child: const Text(
                            "Don't have an account? Sign Up",
                            style: TextStyle(
                              color: Color(0xFF4A90E2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------
  InputDecoration _input(
    String label, {
    IconData? prefix,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: prefix != null ? Icon(prefix) : null,
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF3F4F6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
    );
  }

  Widget _bioButton({
    required IconData icon,
    required VoidCallback onTap,
    Key? key,
  }) {
    return InkWell(
      key: key, // avoid GlobalKey reuse issues
      onTap: _loading ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 65,
        height: 65,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300),
          color: Colors.white,
        ),
        child: Icon(icon, size: 32, color: Colors.black87),
      ),
    );
  }
}