import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
    final base = Uri.parse(kTranscribeBase);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';

    final basePath = base.path.endsWith('/') && base.path.length > 1
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final normalizedPath = basePath.isEmpty || basePath == '/'
        ? '/ws/vsr'
        : '$basePath/ws/vsr';

    final uri = Uri(
      scheme: scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: normalizedPath,
    );

    final channel = WebSocketChannel.connect(uri);
    return VsrSocket._(channel);
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
