import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app/services/auth_services.dart';

class AuthGate extends StatefulWidget {
  final Widget child;
  const AuthGate({super.key, required this.child});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _redirected; // prevent multiple redirects

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeRedirectByRole();
  }

  Future<void> _maybeRedirectByRole() async {
    if (_redirected != null) return; // already handled
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return; // not signed in => router redirect handles

    final location = GoRouterState.of(context).matchedLocation;
    // Only reroute when landing on learner shell root; let deep links alone
    final onLearnerRoot = location == '/' || location.isEmpty;
    if (!onLearnerRoot) return;

    final role = await AuthService.instance.getEffectiveRole(user.uid);
    switch (role) {
      case 'creator':
        _redirected = '/creator';
        if (mounted) context.go('/creator');
        break;
      case 'instructor':
        _redirected = '/instructor';
        if (mounted) context.go('/instructor');
        break;
      case 'admin':
        _redirected = '/admin';
        if (mounted) context.go('/admin');
        break;
      default:
      // learner stays in the app shell
        _redirected = '/';
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}