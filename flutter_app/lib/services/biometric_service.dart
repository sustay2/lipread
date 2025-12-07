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

      if (types.isEmpty && await _isXiaomiHyperOS()) {
        types = await _getFallbackBiometricTypes();
      }

      final hasFingerprint = types.contains(BiometricType.fingerprint);
      final hasFace = types.contains(BiometricType.face);

      return (hasFingerprint, hasFace);
    } catch (e) {
      // If anything goes wrong, assume none are available.
      print('getBiometricTypes error: $e');
      return (false, false);
    }
  }

  /// Generic authenticate using whatever the OS chooses (fingerprint, face, etc.).
  static Future<bool> authenticate({
    required String reason,
  }) async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      if (!supported || !canCheck) return false;

      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      );
    } catch (e) {
      print('BiometricService.authenticate error: $e');
      return false;
    }
  }

  /// Explicitly require fingerprint (where possible).
  /// Note: On some Android versions, the OS may still show a combined prompt.
  static Future<bool> authenticateWithFingerprint({
    required String reason,
  }) async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      if (!supported || !canCheck) return false;

      final types = await _auth.getAvailableBiometrics();
      if (!types.contains(BiometricType.fingerprint)) {
        return false;
      }

      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      );
    } catch (e) {
      print('BiometricService.authenticateWithFingerprint error: $e');
      return false;
    }
  }

  /// Explicitly require face recognition (where possible).
  static Future<bool> authenticateWithFace({
    required String reason,
  }) async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      if (!supported || !canCheck) return false;

      final types = await _auth.getAvailableBiometrics();
      if (!types.contains(BiometricType.face)) {
        return false;
      }

      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      );
    } catch (e) {
      print('BiometricService.authenticateWithFace error: $e');
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

      // FIX: Relaxed check. If it is a Xiaomi family device, use the fallback.
      // The previous 'hyperos' string check was too strict for some ROM versions.
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
