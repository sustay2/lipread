import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../common/services/theme_controller.dart';
import '../../common/theme/app_spacing.dart';
import '../../services/biometric_service.dart';
import '../../services/secure_storage_service.dart';
import '../../services/router.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool _usernameAvailable = true;
  bool _checkingName = false;

  // Biometrics
  bool _biometricsAvailable = false;
  bool _hasFingerprint = false;
  bool _hasFace = false;

  bool _fingerprintEnabled = false;
  bool _faceEnabled = false;

  static const _fingerprintPrefKey = 'fingerprint';
  static const _facePrefKey = 'face';

  late User _user;
  late String _uid;

  @override
  void initState() {
    super.initState();

    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      _error = "You are not signed in.";
      _loading = false;
      return;
    }

    _user = u;
    _uid = u.uid;

    _loadProfile();
    _initBiometrics();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // LOAD PROFILE
  // ---------------------------------------------------------------------------
  Future<void> _loadProfile() async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(_uid).get();
      final data = snap.data() ?? {};

      _nameCtrl.text = data['displayName'] ?? _user.displayName ?? '';

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = "Failed to load: $e";
        _loading = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // BIOMETRICS INITIALIZATION
  // ---------------------------------------------------------------------------
  Future<void> _initBiometrics() async {
    final available = await BiometricService.canUseBiometrics();
    final (hasFp, hasFace) = await BiometricService.getBiometricTypes();
    final hasCredsForUser =
        await SecureStorageService.hasBiometricCredentialsForUser(_uid);
    final savedFingerprint = await SecureStorageService.readBiometricPreference(
      uid: _uid,
      key: _fingerprintPrefKey,
    );
    final savedFace = await SecureStorageService.readBiometricPreference(
      uid: _uid,
      key: _facePrefKey,
    );

    if (!mounted) return;

    setState(() {
      _biometricsAvailable = available;
      _hasFingerprint = hasFp;
      _hasFace = hasFace;

      final credsOk = hasCredsForUser;
      _fingerprintEnabled =
          credsOk && hasFp && (savedFingerprint ?? (hasFp && credsOk));
      _faceEnabled = credsOk && hasFace && (savedFace ?? (hasFace && credsOk));
    });
  }

  // ---------------------------------------------------------------------------
  // USERNAME CHECK
  // ---------------------------------------------------------------------------
  Future<void> _checkUsername(String value) async {
    if (value.trim().isEmpty) return;

    setState(() => _checkingName = true);

    final query = await FirebaseFirestore.instance
        .collection("users")
        .where("displayName", isEqualTo: value.trim())
        .get();

    final taken = query.docs.any((doc) => doc.id != _uid);

    setState(() {
      _usernameAvailable = !taken;
      _checkingName = false;
    });
  }

  // ---------------------------------------------------------------------------
  // SAVE PROFILE
  // ---------------------------------------------------------------------------
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      await FirebaseFirestore.instance.collection('users').doc(_uid).set(
        {
          'displayName': _nameCtrl.text.trim(),
        },
        SetOptions(merge: true),
      );

      await _user.updateDisplayName(_nameCtrl.text.trim());

      _show("Profile updated.");
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _show("Failed to save: $e");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------------------
  // BIOMETRIC TOGGLES
  // ---------------------------------------------------------------------------

  Future<String?> _requestPassword() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Enter password"),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: "Password"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text("Confirm"),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleFingerprint(bool enable) async {
    if (enable) {
      final password = await _requestPassword();
      if (password == null || password.isEmpty) return;

      await Future.delayed(const Duration(milliseconds: 120));

      final ok = await BiometricService.authenticateWithFingerprint(
        reason: "Confirm fingerprint to enable login",
      );

      if (!ok) {
        _show("Fingerprint authentication failed.");
        return;
      }

      await SecureStorageService.saveBiometricCredentials(
        uid: _uid,
        email: _user.email!,
        password: password,
      );
      await SecureStorageService.saveBiometricPreference(
        uid: _uid,
        key: _fingerprintPrefKey,
        enabled: true,
      );

      setState(() {
        _fingerprintEnabled = true;
        // keep faceEnabled as-is; user controls it separately
      });

      _show("Fingerprint login enabled.");
    } else {
      setState(() => _fingerprintEnabled = false);

      // If neither modality is enabled anymore, clear creds for this user.
      if (!_faceEnabled) {
        await SecureStorageService.clearBiometricCredentialsForUser(_uid);
        await SecureStorageService.clearBiometricPreferencesForUser(_uid);
      } else {
        await SecureStorageService.clearBiometricPreference(
          uid: _uid,
          key: _fingerprintPrefKey,
        );
      }

      _show("Fingerprint login disabled.");
    }
  }

  Future<void> _toggleFace(bool enable) async {
    if (enable) {
      final password = await _requestPassword();
      if (password == null || password.isEmpty) return;

      await Future.delayed(const Duration(milliseconds: 120));

      final ok = await BiometricService.authenticateWithFace(
        reason: "Confirm face recognition to enable login",
      );

      if (!ok) {
        _show("Face authentication failed.");
        return;
      }

      await SecureStorageService.saveBiometricCredentials(
        uid: _uid,
        email: _user.email!,
        password: password,
      );
      await SecureStorageService.saveBiometricPreference(
        uid: _uid,
        key: _facePrefKey,
        enabled: true,
      );

      setState(() {
        _faceEnabled = true;
      });

      _show("Face login enabled.");
    } else {
      setState(() => _faceEnabled = false);

      if (!_fingerprintEnabled) {
        await SecureStorageService.clearBiometricCredentialsForUser(_uid);
        await SecureStorageService.clearBiometricPreferencesForUser(_uid);
      } else {
        await SecureStorageService.clearBiometricPreference(
          uid: _uid,
          key: _facePrefKey,
        );
      }

      _show("Face recognition login disabled.");
    }
  }

  void _showUnsupportedBiometric(String method) {
    final label = method.toLowerCase().contains('face')
        ? 'face recognition'
        : 'fingerprint';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Not supported"),
        content: Text(
          "Your device does not support $label login on this device.",
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CHANGE PASSWORD
  // ---------------------------------------------------------------------------
  Future<void> _changePassword() async {
    final current = TextEditingController();
    final newPass = TextEditingController();
    final confirm = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Change Password",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: current,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: "Current password"),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: newPass,
              obscureText: true,
              decoration: const InputDecoration(labelText: "New password"),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: confirm,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: "Confirm new password"),
            ),
            const SizedBox(height: 20),

            FilledButton(
              onPressed: () {
                if (newPass.text != confirm.text) {
                  _show("Passwords do not match.");
                } else {
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text("Update password"),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final cred = EmailAuthProvider.credential(
        email: _user.email!,
        password: current.text.trim(),
      );

      await _user.reauthenticateWithCredential(cred);
      await _user.updatePassword(newPass.text.trim());

      _show("Password updated.");
    } catch (e) {
      _show("Failed: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // DELETE ACCOUNT
  // ---------------------------------------------------------------------------
  Future<void> _deleteAccount() async {
    final passCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Account"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "This cannot be undone.\nEnter password to continue.",
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Password"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final cred = EmailAuthProvider.credential(
        email: _user.email!,
        password: passCtrl.text.trim(),
      );

      await _user.reauthenticateWithCredential(cred);

      await FirebaseFirestore.instance.collection('users').doc(_uid).delete();
      await _user.delete();

      if (mounted) {
        await SecureStorageService.clearBiometricCredentialsForUser(_uid);
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/login',
          (_) => false,
        );
      }
    } catch (e) {
      _show("Failed: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sectionTitleStyle =
        theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Account settings")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // PROFILE CARD
              Container(
                decoration: _cardDecor(context),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Profile",
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _nameCtrl,
                      decoration: InputDecoration(
                        labelText: "Display name",
                        suffixIcon: _checkingName
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : _nameCtrl.text.isEmpty
                                ? null
                            : Icon(
                                _usernameAvailable
                                    ? Icons.check_circle
                                    : Icons.error,
                                    color: _usernameAvailable
                                        ? cs.tertiary
                                        : cs.error,
                                  ),
                      ),
                      onChanged: _checkUsername,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return "Required";
                        if (!_usernameAvailable) return "Name already taken";
                        return null;
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // PASSWORD BLOCK
              Container(
                decoration: _cardDecor(context),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Password", style: sectionTitleStyle),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _changePassword,
                        child: const Text("Change password"),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // SUBSCRIPTION / BILLING
              Container(
                decoration: _cardDecor(context),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Subscription", style: sectionTitleStyle),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: const Text("Billing & Subscription"),
                      subtitle: const Text(
                        "View your plan, usage, and manage billing details.",
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pushNamed(
                        context,
                        Routes.profileBilling,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pushNamed(
                          context,
                          Routes.profileBilling,
                        ),
                        child: const Text("View billing"),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // BIOMETRICS CARD
              Container(
                decoration: _cardDecor(context),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Biometric login", style: sectionTitleStyle),
                    const SizedBox(height: 12),

                    _BiometricTile(
                      title: "Enable Fingerprint Login",
                      subtitle: "Use your fingerprint to log in quickly.",
                      supported: _biometricsAvailable && _hasFingerprint,
                      value: _fingerprintEnabled,
                      onChanged: (v) => _toggleFingerprint(v),
                      onUnsupported: () =>
                          _showUnsupportedBiometric('fingerprint'),
                    ),
                    _BiometricTile(
                      title: "Enable Face Recognition Login",
                      subtitle: "Use face unlock to log in instantly.",
                      supported: _biometricsAvailable && _hasFace,
                      value: _faceEnabled,
                      onChanged: (v) => _toggleFace(v),
                      onUnsupported: () => _showUnsupportedBiometric('face'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // --- Theme selector start ---
              Container(
                decoration: _cardDecor(context),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Appearance",
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 12),
                    RadioListTile<ThemeMode>(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Light'),
                      value: ThemeMode.light,
                      groupValue: themeController.themeMode,
                      onChanged: (mode) {
                        if (mode != null) themeController.setThemeMode(mode);
                      },
                    ),
                    RadioListTile<ThemeMode>(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Dark'),
                      value: ThemeMode.dark,
                      groupValue: themeController.themeMode,
                      onChanged: (mode) {
                        if (mode != null) themeController.setThemeMode(mode);
                      },
                    ),
                    RadioListTile<ThemeMode>(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('System Default'),
                      value: ThemeMode.system,
                      groupValue: themeController.themeMode,
                      onChanged: (mode) {
                        if (mode != null) themeController.setThemeMode(mode);
                      },
                    ),
                  ],
                ),
              ),
              // --- Theme selector end ---

              const SizedBox(height: 20),

              // DANGER ZONE
              Container(
                decoration: _cardDecor(context),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Danger zone",
                      style: sectionTitleStyle?.copyWith(color: cs.error),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.error,
                          foregroundColor: cs.onError,
                        ),
                        onPressed: _deleteAccount,
                        child: const Text("Delete account"),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // SAVE BUTTON
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text("Save changes"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _show(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

BoxDecoration _cardDecor(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return BoxDecoration(
    color: cs.surface,
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(
        color: cs.shadow.withOpacity(0.12),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

class _BiometricTile extends StatelessWidget {
  const _BiometricTile({
    required this.title,
    required this.subtitle,
    required this.supported,
    required this.value,
    required this.onChanged,
    required this.onUnsupported,
  });

  final String title;
  final String subtitle;
  final bool supported;
  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback onUnsupported;

  @override
  Widget build(BuildContext context) {
    final effectiveValue = supported ? value : false;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Switch.adaptive(
        value: effectiveValue,
        onChanged: supported ? onChanged : null,
      ),
      onTap: supported ? () => onChanged(!effectiveValue) : onUnsupported,
      enabled: true,
    );
  }
}