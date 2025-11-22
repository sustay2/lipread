import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../env.dart';

class LipreadSocket {
  final WebSocketChannel _channel;

  LipreadSocket._(this._channel);

  factory LipreadSocket.connect() {
    final base = Uri.parse(kTranscribeBase);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';

    final basePath = base.path.endsWith('/') && base.path.length > 1
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final normalizedPath = basePath.isEmpty || basePath == '/'
        ? '/ws/lipread'
        : '$basePath/ws/lipread';

    final uri = Uri(
      scheme: scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: normalizedPath,
    );

    return LipreadSocket._(WebSocketChannel.connect(uri));
  }

  Stream<dynamic> get stream => _channel.stream;

  void sendFrame(Uint8List data) {
    _channel.sink.add(data);
  }

  Future<void> close() async {
    await _channel.sink.close();
  }
}
