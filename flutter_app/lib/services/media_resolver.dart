import 'media_host.dart';

class MediaResolver {
  static String? toUrl(String? pathOrUrl, {String? lanIp}) {
    if (pathOrUrl == null || pathOrUrl.isEmpty) return null;
    final lower = pathOrUrl.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return pathOrUrl;
    }
    final base = MediaHost.baseUrl(overrideLanIp: lanIp);
    final clean = pathOrUrl.replaceFirst(RegExp(r'^[\\/]+'), '');
    return "$base/media/$clean";
  }
}