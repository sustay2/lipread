import 'dart:io';

/// Main API base (admin + media).
/// Can be overridden via:
///   --dart-define=API_BASE=http://192.168.0.115:8000
String getDynamicApiBase() {
  const envBase = String.fromEnvironment('API_BASE');
  if (envBase.isNotEmpty) return envBase;

  if (Platform.isAndroid) return 'http://10.0.2.2:8000';
  if (Platform.isIOS) return 'http://127.0.0.1:8000';
  return 'http://localhost:8000';
}

final String kApiBase = getDynamicApiBase();

String getDynamicTranscribeBase() {
  const envBase = String.fromEnvironment('TRANSCRIBE_BASE');
  if (envBase.isNotEmpty) return envBase;

  // Default: use the same as kApiBase
  return kApiBase;
}

final String kTranscribeBase = getDynamicTranscribeBase();