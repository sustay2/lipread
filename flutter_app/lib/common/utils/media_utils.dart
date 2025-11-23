import 'dart:io';

import '../../env.dart';

/// Optionally set this at app start based on server_info or manual override:
/// e.g. "http://10.0.2.2:8000" (Android emulator) or "http://192.168.0.115:8000" (real device)
///
/// If not set, we fall back to kApiBase from env.dart.
String? mediaBaseOverride;

/// Rewrites localhost-like and docker-service hostnames to something
/// the device can actually reach.
String? normalizeMediaUrl(String? url) {
  if (url == null || url.isEmpty) return url;

  // If caller gave us a hard override, apply it
  if (mediaBaseOverride != null && mediaBaseOverride!.isNotEmpty) {
    final overrideUri = Uri.tryParse(mediaBaseOverride!);
    final u = Uri.tryParse(url);

    if (u != null && u.hasScheme && overrideUri != null) {
      return Uri(
        scheme: overrideUri.scheme.isNotEmpty ? overrideUri.scheme : u.scheme,
        host: overrideUri.host.isNotEmpty ? overrideUri.host : u.host,
        port: overrideUri.hasPort ? overrideUri.port : u.port,
        path: u.path,
        query: u.query,
        fragment: u.fragment,
      ).toString();
    }
  }

  String out = url;

  // Map common dev hosts → emulator/host
  final replacements = <Pattern, String>{
    RegExp(r'^http://localhost:8000'): _defaultBase(),
    RegExp(r'^http://127\.0\.0\.1:8000'): _defaultBase(),
    RegExp(r'^http://api:8000'): _defaultBase(),
    RegExp(r'^http://backend:8000'): _defaultBase(),
    RegExp(r'^http://fastapi:8000'): _defaultBase(),
  };

  replacements.forEach((pattern, repl) {
    out = out.replaceFirst(pattern, repl);
  });

  return out;
}

/// Default base for media URLs:
/// - If you’ve set `mediaBaseOverride`, we use that.
/// - Otherwise we use kApiBase (main backend).
String _defaultBase() {
  if (mediaBaseOverride != null && mediaBaseOverride!.isNotEmpty) {
    return mediaBaseOverride!;
  }

  // kApiBase itself already handles Platform and dart-define logic.
  return kApiBase;
}

/// Helper used across the app (videos, thumbnails, badges, etc.)
///
/// Usage patterns:
/// - If you already have a full URL from Firestore:
///     publicMediaUrl(doc['videoUrl'])
/// - If you only stored a relative path like "qb/images/foo.jpg":
///     publicMediaUrl(null, path: doc['thumbnailPath'])
///
/// This will:
///   * Build a full URL when only a path is given (BASE + path)
///   * Normalize localhost/api/backend hosts so they work on emulator/real devices.
String? publicMediaUrl(String? url, {String? path}) {
  // If we were given a full URL, just normalize and return.
  if (url != null && url.isNotEmpty) {
    return normalizeMediaUrl(url);
  }

  // No URL, try to build from a stored path.
  if (path == null || path.isEmpty) return null;

  // If path is already an absolute URL, just normalize.
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return normalizeMediaUrl(path);
  }

  // Resolve the relative path against the configured backend base.
  // We intentionally *do not* force a "/media" prefix because
  // Firestore stores paths like "qb/images/foo.jpg" that are served from
  // the backend root.
  final base = _defaultBase();
  final sanitizedPath = path.startsWith('/') ? path.substring(1) : path;

  final resolved = Uri.parse(base.endsWith('/') ? base : '$base/')
      .resolve(sanitizedPath)
      .toString();

  return normalizeMediaUrl(resolved);
}