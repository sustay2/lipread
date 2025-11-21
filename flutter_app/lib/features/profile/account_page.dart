import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../common/theme/app_colors.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _localeCtrl = ValueNotifier<String>('en');
  bool _subtitles = true;
  bool _autoplay = false;
  String _theme = 'system'; // system / light / dark

  bool _loading = true;
  String? _error;

  late final String _uid;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _error = 'You are not signed in.';
      _loading = false;
      return;
    }
    _uid = user.uid;
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .get();

      final data = snap.data() ?? {};
      final stats =
          (data['stats'] as Map<String, dynamic>?) ?? const {};
      final settings =
          (data['settings'] as Map<String, dynamic>?) ?? const {};

      _nameCtrl.text =
          (data['displayName'] as String?) ??
              (FirebaseAuth.instance.currentUser?.displayName ?? '');
      _localeCtrl.value =
          (data['locale'] as String?) ?? 'en';
      _subtitles = (settings['subtitles'] as bool?) ?? true;
      _autoplay = (settings['autoplay'] as bool?) ?? false;
      _theme =
          (settings['theme'] as String?) ?? 'system';

      setState(() {
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load account: $e';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _error = null;
      _loading = true;
    });

    try {
      final userRef =
      FirebaseFirestore.instance.collection('users').doc(_uid);

      await userRef.set({
        'displayName': _nameCtrl.text.trim(),
        'locale': _localeCtrl.value,
        'settings': {
          'subtitles': _subtitles,
          'autoplay': _autoplay,
          'theme': _theme,
        },
      }, SetOptions(merge: true));

      // Also update FirebaseAuth profile displayName for consistency
      await FirebaseAuth.instance.currentUser
          ?.updateDisplayName(_nameCtrl.text.trim());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account settings saved.'),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = 'Failed to save. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _localeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _error == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null &&
        FirebaseAuth.instance.currentUser == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          title: const Text('Account'),
        ),
        body: Center(
          child: Text(
            _error!,
            style: const TextStyle(color: AppColors.error),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Account settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Basic info card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: _cardDecor(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Profile',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Please enter a name';
                        }
                        if (v.trim().length < 2) {
                          return 'Name is too short';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    ValueListenableBuilder<String>(
                      valueListenable: _localeCtrl,
                      builder: (context, value, _) {
                        return DropdownButtonFormField<String>(
                          value: value,
                          decoration: const InputDecoration(
                            labelText: 'App language',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'en',
                              child: Text('English'),
                            ),
                            DropdownMenuItem(
                              value: 'ms',
                              child: Text('Malay'),
                            ),
                            DropdownMenuItem(
                              value: 'zh',
                              child: Text('Chinese'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) _localeCtrl.value = v;
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Preferences card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: _cardDecor(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Playback & accessibility',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Show subtitles by default',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      subtitle: const Text(
                        'Recommended for lip reading support.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      value: _subtitles,
                      activeColor: AppColors.primary,
                      onChanged: (v) =>
                          setState(() => _subtitles = v),
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Autoplay next exercise',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      subtitle: const Text(
                        'Automatically move to the next step.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      value: _autoplay,
                      activeColor: AppColors.primary,
                      onChanged: (v) =>
                          setState(() => _autoplay = v),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Theme card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: _cardDecor(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Theme',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ThemeRadio(
                      value: 'system',
                      group: _theme,
                      label: 'Use device setting',
                      onChanged: (v) =>
                          setState(() => _theme = v),
                    ),
                    _ThemeRadio(
                      value: 'light',
                      group: _theme,
                      label: 'Light',
                      onChanged: (v) =>
                          setState(() => _theme = v),
                    ),
                    _ThemeRadio(
                      value: 'dark',
                      group: _theme,
                      label: 'Dark',
                      onChanged: (v) =>
                          setState(() => _theme = v),
                    ),
                  ],
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 12,
                  ),
                ),
              ],

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : _save,
                  child: _loading
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                      AlwaysStoppedAnimation<Color>(
                        Colors.white,
                      ),
                    ),
                  )
                      : const Text('Save changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeRadio extends StatelessWidget {
  final String value;
  final String group;
  final String label;
  final ValueChanged<String> onChanged;

  const _ThemeRadio({
    required this.value,
    required this.group,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == group;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onChanged(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Radio<String>(
              value: value,
              groupValue: group,
              activeColor: AppColors.primary,
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: selected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontWeight: selected
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

BoxDecoration _cardDecor({double radius = 16}) {
  return BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: [
      BoxShadow(
        color: AppColors.softShadow,
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ],
  );
}