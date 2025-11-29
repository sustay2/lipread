import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_app/services/auth_services.dart';
import 'package:flutter_app/services/router.dart';

class AuthGate extends StatefulWidget {
  final Widget child;
  const AuthGate({super.key, required this.child});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _handled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkRedirect();
  }

  Future<void> _checkRedirect() async {
    if (_handled) return;
    _handled = true;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final role = await AuthService.instance.getEffectiveRole(user.uid);

    switch (role) {
      case 'admin':
        _redirect(Routes.admin);
        break;
      case 'creator':
        _redirect(Routes.creator);
        break;
      case 'instructor':
        _redirect(Routes.instructor);
        break;
      default:
        _redirect(Routes.learnerShell);
    }
  }

  void _redirect(String route) {
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(route, (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}