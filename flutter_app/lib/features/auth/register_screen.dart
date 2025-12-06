import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Added for exception handling
import 'package:flutter_app/services/router.dart';
import 'package:flutter_app/services/auth_services.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscure1 = true,
      _obscure2 = true;
  bool _loading = false;
  bool _acceptTos = true;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // --- HELPER: Translate Errors ---
  String _getFriendlyErrorMessage(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'email-already-in-use':
          return 'The email address is already in use by another account.';
        case 'invalid-email':
          return 'The email address is invalid.';
        case 'weak-password':
          return 'The password is too weak.';
        case 'operation-not-allowed':
          return 'Email/password accounts are not enabled.';
        case 'network-request-failed':
          return 'Network error. Check your internet connection.';
        case 'too-many-requests':
          return 'Too many attempts. Please try again later.';
        default:
          return e.message ?? 'Registration failed.';
      }
    }
    return 'Something went wrong. Please try again.';
  }

  int _calcStrength(String v) {
    int s = 0;
    if (v.length >= 8) s++;
    if (RegExp(r'[A-Z]').hasMatch(v)) s++;
    if (RegExp(r'[a-z]').hasMatch(v)) s++;
    if (RegExp(r'\d').hasMatch(v)) s++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>_\-]').hasMatch(v)) s++;
    return s.clamp(0, 5);
  }

  Color _strengthColor(int s) {
    switch (s) {
      case 0:
      case 1:
        return const Color(0xFFE57373); // red
      case 2:
      case 3:
        return const Color(0xFFFFB74D); // amber
      default:
        return const Color(0xFF4CAF50); // green
    }
  }

  String _strengthLabel(int s) {
    switch (s) {
      case 0:
      case 1:
        return 'Weak';
      case 2:
      case 3:
        return 'Medium';
      default:
        return 'Strong';
    }
  }

  Future<void> _register() async {
    final form = _formKey.currentState;
    if (form == null) return;
    if (!form.validate()) return;
    if (!_acceptTos) {
      setState(() => _error = 'Please accept the Terms to continue.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.instance.registerWithEmail(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        displayName: _nameCtrl.text.trim(),
      );
      if (!mounted) return;
      // Navigate to verify-email screen
      Navigator.of(context).pushNamedAndRemoveUntil(
        Routes.verifyEmail,
            (r) => false,
      );
    } catch (e) {
      setState(() => _error = _getFriendlyErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() {
        _loading = false;
      });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.background,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        foregroundColor: cs.onSurface,
        title: const Text('Create Account'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withOpacity(0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_add_alt_1_rounded,
                        size: 56, color: theme.colorScheme.primary),
                    const SizedBox(height: 10),
                    Text(
                      'Let’s get you started',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Create your account to continue learning',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Full name
                    TextFormField(
                      controller: _nameCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Full name',
                        prefixIcon: Icon(
                            Icons.person_outline, color: cs.primary),
                        filled: true,
                        fillColor: cs.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                              color: cs.outline),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                              color: cs.primary, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 16),
                      ),
                      validator: (v) {
                        if (v == null || v
                            .trim()
                            .isEmpty) {
                          return 'Name is required';
                        }
                        if (v
                            .trim()
                            .length < 2) {
                          return 'Enter a valid name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // Email
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(
                            Icons.email_outlined, color: cs.primary),
                        filled: true,
                        fillColor: cs.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                              color: cs.outline),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                              color: cs.primary, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 16),
                      ),
                      validator: (v) {
                        if (v == null || v
                            .trim()
                            .isEmpty) {
                          return 'Email is required';
                        }
                        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v
                            .trim())) {
                          return 'Enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // Password
                    StatefulBuilder(
                      builder: (context, setSB) {
                        final strength = _calcStrength(_passwordCtrl.text);
                        return Column(
                          children: [
                            TextFormField(
                              controller: _passwordCtrl,
                              obscureText: _obscure1,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon:
                                    Icon(Icons.lock_outline, color: cs.primary),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscure1 ? Icons.visibility_off : Icons
                                        .visibility,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscure1 = !_obscure1),
                                ),
                                filled: true,
                                fillColor: cs.surface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: cs.outline),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide:
                                      BorderSide(color: cs.primary, width: 1.5),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 16),
                              ),
                              onChanged: (_) => setSB(() {}),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Password is required';
                                }
                                if (v.length < 6) {
                                  return 'Use at least 6 characters';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(999),
                                    child: LinearProgressIndicator(
                                      minHeight: 6,
                                      value: strength / 5.0,
                                      backgroundColor: cs.outline,
                                      valueColor: AlwaysStoppedAnimation(
                                          _strengthColor(strength)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(_strengthLabel(strength),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    )),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 14),

                    // Confirm password
                    TextFormField(
                      controller: _confirmCtrl,
                      obscureText: _obscure2,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'Confirm password',
                        prefixIcon:
                            Icon(Icons.lock_reset_outlined, color: cs.primary),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure2 ? Icons.visibility_off : Icons.visibility,
                            color: cs.onSurfaceVariant,
                          ),
                          onPressed: () =>
                              setState(() => _obscure2 = !_obscure2),
                        ),
                        filled: true,
                        fillColor: cs.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cs.outline),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              BorderSide(color: cs.primary, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 16),
                      ),
                      validator: (v) {
                        if (v != _passwordCtrl.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 12),

                    // Clean Error Box
                    if (_error != null)
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: cs.errorContainer.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: cs.errorContainer.withOpacity(0.6)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: cs.error, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(color: cs.error, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Terms (optional)
                    Row(
                      children: [
                        Checkbox(
                          value: _acceptTos,
                          onChanged: (v) =>
                              setState(() => _acceptTos = v ?? false),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4)),
                          side: BorderSide(color: cs.outline),
                        ),
                        Expanded(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text('I agree to the ',
                                  style: TextStyle(color: cs.onSurfaceVariant)),
                              GestureDetector(
                                onTap: () {
                                  // Navigator.pushNamed(context, Routes.terms);
                                },
                                child: Text(
                                  'Terms & Privacy',
                                  style: TextStyle(
                                    color: cs.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    // Submit
                    FilledButton(
                      onPressed: _loading ? null : _register,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _loading
                          ? SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: cs.onPrimary),
                      )
                          : const Text(
                          'Create account', style: TextStyle(fontSize: 16)),
                    ),

                    const SizedBox(height: 12),

                    // Back to sign in
                    TextButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, Routes.login),
                      child: Text.rich(
                        TextSpan(
                          text: 'Already have an account? ',
                          style: TextStyle(color: cs.onSurfaceVariant),
                          children: [
                            TextSpan(
                              text: 'Sign in',
                              style: TextStyle(
                                color: cs.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}