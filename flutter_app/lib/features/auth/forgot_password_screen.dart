import 'package:flutter/material.dart';
import 'package:flutter_app/services/router.dart';
import 'package:flutter_app/services/auth_services.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendReset() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await AuthService.instance.sendPasswordResetEmail(_emailCtrl.text.trim());
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        Routes.forgotPasswordSent,
            (r) => false,
        arguments: _emailCtrl.text.trim(),
      );
    } catch (e) {
      setState(() => _error = 'Could not send reset email. Please try again.');
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FD), // pale blue
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F8FD),
        elevation: 0,
        centerTitle: true,
        foregroundColor: const Color(0xFF1C1C28),
        title: const Text('Forgot password'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.shade100.withOpacity(0.4),
                    blurRadius: 20,
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
                    Icon(Icons.lock_reset_rounded,
                        size: 56, color: theme.colorScheme.primary),
                    const SizedBox(height: 10),
                    Text(
                      'Reset your password',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1C1C28),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter the email associated with your account and we’ll send you a link to reset your password.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF6E7A8A),
                      ),
                    ),
                    const SizedBox(height: 20),

                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF4A90E2)),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFFDCE3F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFF4A90E2), width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Email is required';
                        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) return 'Enter a valid email';
                        return null;
                      },
                    ),

                    const SizedBox(height: 12),

                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFE57373)),
                        ),
                      ),

                    FilledButton(
                      onPressed: _loading ? null : _sendReset,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                          : const Text('Send reset link', style: TextStyle(fontSize: 16)),
                    ),

                    const SizedBox(height: 12),

                    TextButton(
                      onPressed: _loading ? null : () => Navigator.pushNamed(context, Routes.login),
                      child: const Text.rich(
                        TextSpan(
                          text: 'Remembered it? ',
                          style: TextStyle(color: Colors.grey),
                          children: [
                            TextSpan(
                              text: 'Back to sign in',
                              style: TextStyle(
                                color: Color(0xFF4A90E2),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Tip box
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F8FD),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFDCE3F0)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              size: 20, color: Color(0xFF357ABD)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'We’ll email you a secure link to reset your password. '
                                  'Check Spam/Junk if it doesn’t arrive.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF6E7A8A),
                              ),
                            ),
                          ),
                        ],
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