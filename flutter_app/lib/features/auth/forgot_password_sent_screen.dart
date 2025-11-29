import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_app/services/router.dart';
import 'package:flutter_app/services/auth_services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';

class ForgotPasswordSentScreen extends StatefulWidget {
  const ForgotPasswordSentScreen({super.key});

  @override
  State<ForgotPasswordSentScreen> createState() => _ForgotPasswordSentScreenState();
}

class _ForgotPasswordSentScreenState extends State<ForgotPasswordSentScreen> {
  static const int _initialCooldown = 30;
  int _cooldown = 0;
  Timer? _timer;
  String? _email;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final arg = ModalRoute.of(context)?.settings.arguments;
    if (arg is String) _email = arg;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = _initialCooldown);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_cooldown <= 1) {
        t.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  String _getFriendlyErrorMessage(Object e) {
    if (e is FirebaseAuthException) {
      if (e.code == 'network-request-failed') return 'No internet connection.';
      if (e.code == 'too-many-requests') return 'Too many requests. Please wait.';
    }
    return 'Could not resend email.';
  }

  Future<void> _resend() async {
    if (_cooldown > 0 || _email == null) return;
    setState(() => _sending = true);
    try {
      await AuthService.instance.sendPasswordResetEmail(_email!.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reset link sent.')),
      );
      _startCooldown();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_getFriendlyErrorMessage(e)),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // --- UPDATED: Triggers System "Open With" Picker ---
  Future<void> _openMailApp() async {
    if (Platform.isAndroid) {
      // Android: Fire an Intent to "List all Email Apps"
      // This triggers the native "Just Once / Always" system picker
      const intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        category: 'android.intent.category.APP_EMAIL',
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      try {
        await intent.launch();
      } catch (e) {
        // Fallback if no specific email app is found
        _launchFallback();
      }
    } else if (Platform.isIOS) {
      // iOS: Try opening the "message://" scheme (Apple Mail)
      // If that fails, open "mailto:" which will ask the user to restore default
      final Uri mailUri = Uri.parse('message://');
      if (await canLaunchUrl(mailUri)) {
        await launchUrl(mailUri);
      } else {
        _launchFallback();
      }
    } else {
      _launchFallback();
    }
  }

  Future<void> _launchFallback() async {
    final Uri uri = Uri.parse('mailto:');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = _email;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FD),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F8FD),
        elevation: 0,
        centerTitle: true,
        foregroundColor: const Color(0xFF1C1C28),
        title: const Text('Email sent'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mark_email_read_rounded,
                      size: 64, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    'Check your inbox',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1C1C28),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    email == null
                        ? "We've sent a password reset link to your email."
                        : "We've sent a password reset link to",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF6E7A8A),
                    ),
                  ),
                  if (email != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F8FD),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFDCE3F0)),
                      ),
                      child: Text(
                        email,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1C1C28),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),

                  if (_cooldown > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F8FD),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFDCE3F0)),
                      ),
                      child: Text(
                        'You can resend in ${_cooldown}s',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF6E7A8A),
                        ),
                      ),
                    ),

                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: (_cooldown > 0 || _sending) ? null : _resend,
                          icon: _sending
                              ? const SizedBox(
                            height: 18, width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                              : const Icon(Icons.refresh_rounded),
                          label: Text(_cooldown > 0 ? 'Resend (${_cooldown}s)' : 'Resend link'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openMailApp, // Calls system picker now
                          icon: const Icon(Icons.mail_outline_rounded),
                          label: const Text('Open mail'),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFFDCE3F0)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  TextButton(
                    onPressed: () => Navigator.pushNamedAndRemoveUntil(context, Routes.login, (r) => false),
                    child: const Text.rich(
                      TextSpan(
                        text: 'Back to ',
                        children: [
                          TextSpan(
                            text: 'sign in',
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
                            'Didn’t receive it? Check Spam/Junk. You can resend after the cooldown.',
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
    );
  }
}