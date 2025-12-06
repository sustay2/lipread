import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app/services/auth_services.dart';
import 'package:url_launcher/url_launcher.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});
  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen>
    with WidgetsBindingObserver {
  Timer? _poll;
  Timer? _cooldownTimer;
  bool _sending = false;
  int _cooldown = 0;
  String? _email;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _email = FirebaseAuth.instance.currentUser?.email;

    // Poll every 4s
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _checkNow());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkNow(); // instantly re-check when user returns from email app
    }
  }

  Future<void> _checkNow() async {
    await AuthService.instance.reloadCurrentUser();
    if (AuthService.instance.isEmailVerified) {
      _poll?.cancel();
      if (!mounted) return;

      final uid = FirebaseAuth.instance.currentUser!.uid;
      final role = await AuthService.instance.getEffectiveRole(uid);

      // GoRouter or Navigator target
      final target = switch (role) {
        'admin' => '/admin',
        'creator' => '/creator',
        'instructor' => '/instructor',
        _ => '/app', // learner shell
      };
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(target, (r) => false);
    }
  }

  void _startCooldown([int seconds = 30]) {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_cooldown <= 1) {
        t.cancel();
        if (mounted) setState(() => _cooldown = 0);
      } else {
        if (mounted) setState(() => _cooldown--);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  // --- HELPER ---
  String _getFriendlyErrorMessage(Object e) {
    if (e is FirebaseAuthException) {
      if (e.code == 'network-request-failed') return 'No internet connection.';
      if (e.code == 'too-many-requests') return 'Too many requests. Please wait.';
    }
    return 'Could not resend email.';
  }

  Future<void> _resend() async {
    if (_cooldown > 0) return;
    setState(() => _sending = true);
    final cs = Theme.of(context).colorScheme;
    try {
      await AuthService.instance.sendEmailVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification email sent.')),
        );
      }
      _startCooldown(30);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_getFriendlyErrorMessage(e)),
            backgroundColor: cs.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openMailApp() async {
    // Try to open a mail app. Fallback to common webmail.
    const schemes = [
      'message://', // iOS (some clients)
      'mailto:',    // generic
    ];
    for (final s in schemes) {
      final uri = Uri.parse(s);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return;
      }
    }
    // Fallback options (open in browser)
    final List<Uri> providers = [
      Uri.parse('https://mail.google.com/'),
      Uri.parse('https://outlook.live.com/mail/0/inbox'),
      Uri.parse('https://mail.yahoo.com/'),
    ];
    for (final p in providers) {
      if (await canLaunchUrl(p)) {
        await launchUrl(p, mode: LaunchMode.externalApplication);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.background, // pale blue
      appBar: AppBar(
        backgroundColor: cs.background,
        elevation: 0,
        centerTitle: true,
        foregroundColor: cs.onSurface,
        title: const Text('Verify your email'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withOpacity(0.12),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mark_email_unread_rounded,
                      size: 64, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    'Check your inbox',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _email == null
                        ? "We've sent a verification link to your email."
                        : "We've sent a verification link to",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  if (_email != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: cs.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.outline),
                      ),
                      child: Text(
                        _email!,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    "You’ll be redirected automatically once verification is complete.",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),

                  const SizedBox(height: 24),
                  // Primary actions
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _sending || _cooldown > 0 ? null : _resend,
                          icon: _sending
                              ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.surface,
                            ),
                          )
                              : const Icon(Icons.refresh_rounded),
                          label: Text(_cooldown > 0
                              ? 'Resend in ${_cooldown}s'
                              : 'Resend email'),
                          style: FilledButton.styleFrom(
                            padding:
                            const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openMailApp,
                          icon: const Icon(Icons.mail_outline_rounded),
                          label: const Text('Open mail'),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: cs.surface,
                            side: BorderSide(color: cs.outline),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding:
                            const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Manual check now
                  TextButton.icon(
                    onPressed: _checkNow,
                    icon: const Icon(Icons.verified_rounded,
                        color: Color(0xFF357ABD)),
                    label: const Text(
                      "I've verified — check now",
                      style: TextStyle(color: Color(0xFF357ABD)),
                    ),
                  ),

                  const SizedBox(height: 6),

                  // Tips
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.outline),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 20, color: Color(0xFF357ABD)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Check Spam/Junk if you don’t see the email. '
                                'You can resend after the cooldown.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Sign out
                  TextButton(
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                      if (mounted) context.go('/login');
                    },
                    child: Text.rich(
                      TextSpan(
                        text: 'Wrong email? ',
                        children: [
                          TextSpan(
                            text: 'Sign out',
                            style: TextStyle(
                              color: cs.primary,
                              fontWeight: FontWeight.bold,
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
      ),
    );
  }
}