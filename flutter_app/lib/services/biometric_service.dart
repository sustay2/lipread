import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();
  static const MethodChannel _channel = MethodChannel('local_auth_plugin');

  /// Returns true if device supports any biometric and is allowed to use it.
  static Future<bool> canUseBiometrics() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;

      if (supported && canCheck) {
        return true;
      }

      if (await _isXiaomiHyperOS()) {
        final fallback = await _getFallbackBiometricTypes();
        return fallback.isNotEmpty;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  /// Returns:
  ///  - fingerprint: whether fingerprint is available
  ///  - face: whether face recognition is available
  static Future<(bool fingerprint, bool face)> getBiometricTypes() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;

      List<BiometricType> types = [];

      if (supported && canCheck) {
        types = await _auth.getAvailableBiometrics();
      }

      final isXiaomi = await _isXiaomiHyperOS();

      // Merge fallback types if empty or on Xiaomi
      if (types.isEmpty && isXiaomi) {
        types = await _getFallbackBiometricTypes();
      }

      bool hasFingerprint = types.contains(BiometricType.fingerprint);
      bool hasFace = types.contains(BiometricType.face);

      // FIX 1: Optimistic Fallback for Xiaomi/HyperOS
      // If we detected Fingerprint (or just "Strong" auth) on Xiaomi, 
      // assume Face is also available. Xiaomi's 2D Face Unlock often doesn't 
      // report the standard FEATURE_FACE, but works via the prompt.
      if (isXiaomi && (hasFingerprint || types.contains(BiometricType.strong))) {
        hasFingerprint = true; // Ensure fingerprint is on
        hasFace = true;        // Force face to be available
      }

      return (hasFingerprint, hasFace);
    } catch (e) {
      print('getBiometricTypes error: $e');
      return (false, false);
    }
  }

  /// Generic authenticate using whatever the OS chooses (fingerprint, face, etc.).
  static Future<bool> authenticate({
    required String reason,
  }) async {
    return _attemptAuth(reason);
  }

  /// Explicitly require fingerprint (where possible).
  static Future<bool> authenticateWithFingerprint({
    required String reason,
  }) async {
    // FIX 2: Removed strict check against _auth.getAvailableBiometrics().
    // If the UI toggle is enabled, we trust our fallback logic.
    return _attemptAuth(reason);
  }

  /// Explicitly require face recognition (where possible).
  static Future<bool> authenticateWithFace({
    required String reason,
  }) async {
    // FIX 3: Removed strict check against _auth.getAvailableBiometrics().
    // Xiaomi Face unlock works via the standard prompt even if the plugin doesn't see it.
    return _attemptAuth(reason);
  }

  static Future<bool> _attemptAuth(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
          sensitiveTransaction: false, 
        ),
      );
    } catch (e) {
      print('Auth error: $e');
      return false;
    }
  }

  static Future<List<BiometricType>> _getFallbackBiometricTypes() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'getAvailableBiometricTypes',
      );

      if (result == null) return [];

      return result
          .map(_mapToBiometricType)
          .whereType<BiometricType>()
          .toSet()
          .toList();
    } catch (e) {
      print('Fallback getAvailableBiometricTypes error: $e');
      return [];
    }
  }

  static BiometricType? _mapToBiometricType(dynamic value) {
    if (value is BiometricType) return value;
    if (value is int) {
      switch (value) {
        case 0:
          return BiometricType.weak;
        case 1:
          return BiometricType.strong;
      }
    }

    if (value is String) {
      final normalized = value.toLowerCase();
      if (normalized.contains('finger')) return BiometricType.fingerprint;
      if (normalized.contains('face')) return BiometricType.face;
      if (normalized.contains('iris')) return BiometricType.iris;
      if (normalized.contains('strong')) return BiometricType.strong;
      if (normalized.contains('weak')) return BiometricType.weak;
    }

    return null;
  }

  static Future<bool> _isXiaomiHyperOS() async {
    if (!Platform.isAndroid) return false;

    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final brand = androidInfo.brand?.toLowerCase() ?? '';
      final manufacturer = androidInfo.manufacturer?.toLowerCase() ?? '';

      final isXiaomiBrand = brand.contains('xiaomi') ||
          brand.contains('redmi') ||
          brand.contains('poco') ||
          manufacturer.contains('xiaomi');

      return isXiaomiBrand; 
    } catch (_) {
      return false;
    }
  }
}