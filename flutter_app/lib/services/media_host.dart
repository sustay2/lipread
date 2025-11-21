import 'dart:io';

class MediaHost {
  /// Base URL for your FastAPI admin backend.
  static String baseUrl({String? overrideLanIp}) {
    if (overrideLanIp != null && overrideLanIp.isNotEmpty) {
      return "http://$overrideLanIp:8000";
    }
    if (Platform.isAndroid) return "http://10.0.2.2:8000";
    return "http://localhost:8000";
  }
}