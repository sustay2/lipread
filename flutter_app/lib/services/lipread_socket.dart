import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../env.dart';

class LipreadSocket {
  final WebSocketChannel _channel;

  LipreadSocket._(this._channel);

  factory LipreadSocket.connect() {
    final base = Uri.parse(kTranscribeBase);
    final scheme =
        (base.scheme == 'https' || base.scheme == 'wss') ? 'wss' : 'ws';

    final segments = <String>[
      ...base.pathSegments.where((s) => s.isNotEmpty),
      'ws',
      'lipread',
    ];

    final uri = base.replace(
      scheme: scheme,
      pathSegments: segments,
      query: null,
      fragment: null,
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
