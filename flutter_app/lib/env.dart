import 'dart:io';
import 'package:flutter/foundation.dart';

/// Normalize a base URL string by:
/// - Adding http:// if missing
/// - Dropping trailing slashes
/// - Falling back to [fallback] if parsing fails or the host is empty
String _normalizeBase(String raw, String fallback) {
  final trimmed = raw.trim();
  final candidate = trimmed.isEmpty
      ? fallback
      : (trimmed.contains('://') ? trimmed : 'http://$trimmed');

  final parsed = Uri.tryParse(candidate);
  if (parsed == null || parsed.host.isEmpty) {
    debugPrint('[env] Invalid base "$raw", falling back to $fallback');
    return fallback;
  }

  final normalized = parsed.toString().replaceFirst(RegExp(r'/+$'), '');
  return normalized.endsWith('/')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
}

/// Main API base (admin + media).
/// Can be overridden via:
///   --dart-define=API_BASE=http://192.168.0.115:8000
String getDynamicApiBase() {
  const envBase = String.fromEnvironment('API_BASE');

  final fallback = Platform.isAndroid
      ? 'http://10.0.2.2:8000'
      : Platform.isIOS
          ? 'http://127.0.0.1:8000'
          : 'http://localhost:8000';

  return _normalizeBase(envBase, fallback);
}

final String kApiBase = getDynamicApiBase();
final Uri kApiBaseUri = Uri.parse(kApiBase);

/// Transcribe (lip-reading) backend base.
/// Can be overridden via:
///   --dart-define=TRANSCRIBE_BASE=http://192.168.0.115:8001
String getDynamicTranscribeBase() {
  const envBase = String.fromEnvironment('TRANSCRIBE_BASE');

  final fallback = Platform.isAndroid
      ? 'http://10.0.2.2:8001'
      : Platform.isIOS
          ? 'http://127.0.0.1:8001'
          : 'http://localhost:8001';

  return _normalizeBase(envBase, fallback);
}

final String kTranscribeBase = getDynamicTranscribeBase();
final Uri kTranscribeBaseUri = Uri.parse(kTranscribeBase);
