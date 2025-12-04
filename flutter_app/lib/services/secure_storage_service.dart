import 'dart:convert';

import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storageName = 'lipread_bio_v1';
  static const _flagsStorageName = 'lipread_bio_flags_v1';
  static const _themeModeKey = 'theme_mode';

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static Future<BiometricStorageFile?> _getFlagsStorage() async {
    final can = await BiometricStorage().canAuthenticate();
    if (can != CanAuthenticateResponse.success) {
      return null;
    }

    return BiometricStorage().getStorage(
      _flagsStorageName,
      options: const StorageFileInitOptions(authenticationRequired: false),
    );
  }

  static Future<BiometricStorageFile?> _getStorage() async {
    final can = await BiometricStorage().canAuthenticate();
    if (can != CanAuthenticateResponse.success) {
      return null;
    }

    // IMPORTANT: authenticationRequired = false here so we can
    // *inspect* which UID is stored without triggering a system
    // biometric prompt. Actual security is handled by local_auth.
    return BiometricStorage().getStorage(
      _storageName,
      options: StorageFileInitOptions(
        authenticationRequired: false,
      ),
    );
  }

  /// Any biometric credentials stored (for any user)?
  static Future<bool> hasBiometricCredentials() async {
    final storage = await _getStorage();
    if (storage == null) return false;

    final content = await storage.read();
    return content != null && content.isNotEmpty;
  }

  /// Biometric credentials stored **for this UID**?
  static Future<bool> hasBiometricCredentialsForUser(String uid) async {
    final storage = await _getStorage();
    if (storage == null) return false;

    final content = await storage.read();
    if (content == null || content.isEmpty) return false;

    final parts = content.split('|');
    if (parts.length != 3) return false;

    final storedUid = parts[0];
    return storedUid == uid;
  }

  /// Save credentials for the given user.
  /// Only one user can be "biometric owner" per device at a time.
  static Future<void> saveBiometricCredentials({
    required String uid,
    required String email,
    required String password,
  }) async {
    final storage = await _getStorage();
    if (storage == null) {
      throw Exception('Biometric storage is not available on this device.');
    }

    final payload = '$uid|$email|$password';
    await storage.write(payload);
  }

  /// Reads the currently stored credentials (if any), regardless of UID.
  /// Returns (uid, email, password) or null.
  ///
  /// This is used on the *login screen* before we know who the user is.
  static Future<(String uid, String email, String password)?> readBiometricCredentials() async {
    final storage = await _getStorage();
    if (storage == null) return null;

    final content = await storage.read();
    if (content == null || content.isEmpty) return null;

    final parts = content.split('|');
    if (parts.length != 3) return null;

    return (parts[0], parts[1], parts[2]);
  }

  /// Clears biometric credentials if they belong to this UID.
  static Future<void> clearBiometricCredentialsForUser(String uid) async {
    final storage = await _getStorage();
    if (storage == null) return;

    final content = await storage.read();
    if (content == null || content.isEmpty) return;

    final parts = content.split('|');
    if (parts.length != 3) {
      await storage.delete();
      return;
    }

    final storedUid = parts[0];
    if (storedUid == uid) {
      await storage.delete();
    }
  }

  /// Force-clear ANY stored credentials (used only if you really need it).
  static Future<void> clearAllBiometricCredentials() async {
    final storage = await _getStorage();
    if (storage == null) return;
    await storage.delete();
  }

  // ---------------------------------------------------------------------------
  // BIOMETRIC PREFERENCES (toggles)
  // ---------------------------------------------------------------------------

  static Future<void> saveBiometricPreference({
    required String uid,
    required String key,
    required bool enabled,
  }) async {
    final storage = await _getFlagsStorage();
    if (storage == null) return;

    final raw = await storage.read();
    final Map<String, dynamic> data =
        raw == null || raw.isEmpty ? {} : (jsonDecode(raw) as Map<String, dynamic>);

    data['$uid::$key'] = enabled;
    await storage.write(jsonEncode(data));
  }

  static Future<bool?> readBiometricPreference({
    required String uid,
    required String key,
  }) async {
    final storage = await _getFlagsStorage();
    if (storage == null) return null;

    final raw = await storage.read();
    if (raw == null || raw.isEmpty) return null;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return data['$uid::$key'] as bool?;
  }

  static Future<void> clearBiometricPreferencesForUser(String uid) async {
    final storage = await _getFlagsStorage();
    if (storage == null) return;

    final raw = await storage.read();
    if (raw == null || raw.isEmpty) return;

    final data = jsonDecode(raw) as Map<String, dynamic>;
    data.removeWhere((k, _) => k.startsWith('$uid::'));

    if (data.isEmpty) {
      await storage.delete();
    } else {
      await storage.write(jsonEncode(data));
    }
  }

  static Future<void> clearBiometricPreference({
    required String uid,
    required String key,
  }) async {
    final storage = await _getFlagsStorage();
    if (storage == null) return;

    final raw = await storage.read();
    if (raw == null || raw.isEmpty) return;

    final data = jsonDecode(raw) as Map<String, dynamic>;
    data.remove('$uid::$key');

    if (data.isEmpty) {
      await storage.delete();
    } else {
      await storage.write(jsonEncode(data));
    }
  }

  // ---------------------------------------------------------------------------
  // THEME MODE
  // ---------------------------------------------------------------------------

  static Future<void> saveThemeMode(String value) {
    return _secureStorage.write(key: _themeModeKey, value: value);
  }

  static Future<String?> readThemeMode() {
    return _secureStorage.read(key: _themeModeKey);
  }
}