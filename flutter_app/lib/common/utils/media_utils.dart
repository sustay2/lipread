import '../../env.dart';

/// Optionally set this at app start based on server_info or manual override:
/// e.g. "http://10.0.2.2:8000" (Android emulator) or "http://192.168.0.115:8000" (real device)
///
/// If not set, we fall back to kApiBase from env.dart.
String? mediaBaseOverride;

/// Normalize any media URL/path so it always uses the same host as API_BASE
/// and is served from `/media/<path>`.
String? normalizeMediaUrl(String? url) {
  final parts = _mediaParts(url: url);
  if (parts == null) return url;
  return _buildMediaUrl(parts);
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

Uri _defaultBaseUri() => Uri.parse(_defaultBase());

/// Helper used across the app (videos, thumbnails, badges, etc.)
///
/// Usage patterns:
/// - If you already have a full URL from Firestore:
///     publicMediaUrl(doc['videoUrl'])
/// - If you only stored a relative path like "qb/images/foo.jpg":
///     publicMediaUrl(null, path: doc['thumbnailPath'])
///
/// This will:
///   * Build a full URL when only a path is given (BASE + /media + path)
///   * Normalize any existing URL to the current API host.
String? publicMediaUrl(String? url, {String? path}) {
  final parts = _mediaParts(url: url, path: path);
  if (parts == null) return null;
  return _buildMediaUrl(parts);
}

class _MediaUrlParts {
  const _MediaUrlParts(this.path, {this.query, this.fragment});

  final String path;
  final String? query;
  final String? fragment;
}

_MediaUrlParts? _mediaParts({String? url, String? path}) {
  String? rawPath;
  String? query;
  String? fragment;

  if (url != null && url.isNotEmpty) {
    final parsed = Uri.tryParse(url);
    if (parsed != null) {
      rawPath = parsed.path.isNotEmpty ? parsed.path : null;
      query = parsed.hasQuery ? parsed.query : null;
      fragment = parsed.fragment.isNotEmpty ? parsed.fragment : null;
    }
  }

  rawPath ??= path;

  if (rawPath == null || rawPath.isEmpty) {
    return null;
  }

  final normalizedPath = _normalizeMediaPath(rawPath);
  return _MediaUrlParts(normalizedPath, query: query, fragment: fragment);
}

String _buildMediaUrl(_MediaUrlParts parts) {
  final base = _defaultBaseUri();
  final normalizedPath = parts.path.replaceAll(RegExp(r'/+'), '/');
  return Uri(
    scheme: base.scheme,
    host: base.host,
    port: base.hasPort ? base.port : null,
    path: normalizedPath,
    query: parts.query?.isNotEmpty == true ? parts.query : null,
    fragment: parts.fragment?.isNotEmpty == true ? parts.fragment : null,
  ).toString();
}

String _normalizeMediaPath(String rawPath) {
  var path = rawPath;
  if (path.startsWith('http://') || path.startsWith('https://')) {
    final parsed = Uri.tryParse(path);
    if (parsed != null) {
      path = parsed.path;
    }
  }

  path = path.trim();
  if (path.isEmpty) return '/media';

  path = path.replaceFirst(RegExp('^/+'), '');
  if (!path.startsWith('media/')) {
    path = 'media/$path';
  }

  return '/$path';
}