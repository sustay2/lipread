import 'package:local_auth/local_auth.dart';

class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Returns true if device supports any biometric and is allowed to use it.
  static Future<bool> canUseBiometrics() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      return canCheck && supported;
    } catch (_) {
      return false;
    }
  }

  /// Returns:
  ///  - fingerprint: whether fingerprint is available
  ///  - face: whether face recognition is available
  static Future<(bool fingerprint, bool face)> getBiometricTypes() async {
    try {
      final types = await _auth.getAvailableBiometrics();

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
}