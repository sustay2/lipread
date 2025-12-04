import 'package:flutter/material.dart';

import '../../services/secure_storage_service.dart';

class ThemeController extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  Future<void> loadThemeFromStorage() async {
    final stored = await SecureStorageService.readThemeMode();
    _themeMode = _stringToMode(stored);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    await SecureStorageService.saveThemeMode(mode.name);
  }

  ThemeMode _stringToMode(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }
}
