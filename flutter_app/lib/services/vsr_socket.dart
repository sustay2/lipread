import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../env.dart';

class VsrSocket {
  final WebSocketChannel _channel;
  final StreamController<String> _partialController =
      StreamController<String>.broadcast();

  VsrSocket._(this._channel) {
    _channel.stream.listen(
      (event) {
        if (event is String) {
          try {
            final decoded = jsonDecode(event);
            if (decoded is Map && decoded['partial_text'] is String) {
              _partialController.add(decoded['partial_text'] as String);
            }
          } catch (_) {
            // Ignore malformed payloads.
          }
        }
      },
      onError: _partialController.addError,
      onDone: _partialController.close,
      cancelOnError: true,
    );
  }

  static Future<VsrSocket> connect() async {
    final uri = _buildWebSocketUri();
    debugPrint('[VsrSocket] Connecting to $uri');
    final channel = WebSocketChannel.connect(uri);
    return VsrSocket._(channel);
  }

  static Uri _buildWebSocketUri() {
    if (kTranscribeBase.isEmpty || kTranscribeBaseUri.host.isEmpty) {
      throw StateError(
        'TRANSCRIBE_BASE is not configured. Provide --dart-define=TRANSCRIBE_BASE=http://<ip>:8001',
      );
    }

    final base = kTranscribeBaseUri;
    final scheme =
        (base.scheme == 'https' || base.scheme == 'wss') ? 'wss' : 'ws';

    // Preserve any base path (e.g. /api) while appending ws/vsr.
    final segments = <String>[
      ...base.pathSegments.where((s) => s.isNotEmpty),
      'ws',
      'vsr',
    ];

    return Uri(
      scheme: scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      pathSegments: segments,
    );
  }

  Stream<String> get partialTranscripts => _partialController.stream;

  void sendFrame(Uint8List jpegBytes) {
    final payload = base64Encode(jpegBytes);
    _channel.sink.add(payload);
  }

  Future<void> close() async {
    await _channel.sink.close();
  }
}
