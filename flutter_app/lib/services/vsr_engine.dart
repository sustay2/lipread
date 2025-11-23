import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import 'camera_service.dart';
import 'vsr_socket.dart';

class VsrEngine {
  final CameraService _cameraService;
  VsrSocket? _socket;
  StreamSubscription<String>? _socketSub;
  DateTime? _lastSent;
  bool _running = false;
  bool _sending = false;

  VsrEngine(this._cameraService);

  bool get isRunning => _running;
  CameraController? get controller => _cameraService.controller;

  Future<void> start({
    required void Function(String text) onTranscript,
    void Function(Object error)? onError,
    VoidCallback? onStarted,
  }) async {
    if (_running) return;

    try {
      await _cameraService.initialize();

      final socket = await VsrSocket.connect();
      _socket = socket;
      _socketSub = socket.partialTranscripts.listen(
        onTranscript,
        onError: (Object e) async {
          await stop();
          onError?.call(e);
        },
      );

      await _cameraService.startStream(
        (image) => _handleImage(image, onError),
      );

      _running = true;
      onStarted?.call();
    } catch (e) {
      await _socketSub?.cancel();
      _socketSub = null;
      await _socket?.close();
      _socket = null;
      _lastSent = null;
      _sending = false;
      rethrow;
    }
  }

  Future<void> stop() async {
    _running = false;
    await _cameraService.stopStream();
    await _socketSub?.cancel();
    _socketSub = null;
    await _socket?.close();
    _socket = null;
    _lastSent = null;
    _sending = false;
  }

  Future<void> dispose() async {
    await stop();
    await _cameraService.dispose();
  }

  Future<void> _handleImage(
    CameraImage image,
    void Function(Object error)? onError,
  ) async {
    if (!_running) return;
    final socket = _socket;
    if (socket == null) return;

    final now = DateTime.now();
    if (_lastSent != null &&
        now.difference(_lastSent!) < const Duration(milliseconds: 66)) {
      return; // ~15 FPS
    }

    if (_sending) return;
    _sending = true;

    try {
      final jpeg = await _cameraService.yuvToJpeg(image, quality: 80);
      socket.sendFrame(jpeg);
      _lastSent = DateTime.now();
    } catch (e) {
      await stop();
      onError?.call(e);
    } finally {
      _sending = false;
    }
  }
}
