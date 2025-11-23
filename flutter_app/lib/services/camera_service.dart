import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Camera wrapper that provides a front-facing controller plus YUV420 -> JPEG
/// conversion for streaming.
class CameraService {
  CameraController? _controller;
  bool _initializing = false;
  bool _streaming = false;

  CameraController? get controller => _controller;
  bool get isStreaming => _streaming;

  Future<void> initialize() async {
    if (_controller != null) return;
    if (_initializing) return;
    _initializing = true;

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('no-camera', 'No camera devices found');
      }

      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final ctrl = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await ctrl.initialize();
      _controller = ctrl;
    } finally {
      _initializing = false;
    }
  }

  Future<void> startStream(
    FutureOr<void> Function(CameraImage image) onImage,
  ) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) {
      throw CameraException('not-initialized', 'Camera is not initialized');
    }

    if (_streaming) return;

    await ctrl.startImageStream(onImage);
    _streaming = true;
  }

  Future<void> stopStream() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    if (_streaming && ctrl.value.isStreamingImages) {
      try {
        await ctrl.stopImageStream();
      } catch (_) {
        // ignored
      }
    }
    _streaming = false;
  }

  Future<void> dispose() async {
    await stopStream();
    final ctrl = _controller;
    _controller = null;
    if (ctrl != null) {
      await ctrl.dispose();
    }
  }

  /// Convert [CameraImage] in YUV420 format to a JPEG-encoded byte array.
  ///
  /// This conversion follows standard BT.601 coefficients and includes
  /// optional downscaling to reduce bandwidth.
  Future<Uint8List> yuvToJpeg(
    CameraImage image, {
    int quality = 80,
    int targetWidth = 224,
  }) async {
    // Use compute to avoid blocking UI if heavy. Falls back to sync on web.
    if (!kIsWeb) {
      return compute<(_YuvFrame, int, int), Uint8List>(
        _encodeFrame,
        (
          _YuvFrame(
            image.width,
            image.height,
            image.planes.map((p) => Uint8List.fromList(p.bytes)).toList(),
            image.planes.map((p) => p.bytesPerRow).toList(),
            image.planes.map((p) => p.bytesPerPixel ?? 1).toList(),
          ),
          quality,
          targetWidth,
        ),
      );
    }

    return _encodeFrame(
      _YuvFrame(
        image.width,
        image.height,
        image.planes.map((p) => p.bytes).toList(),
        image.planes.map((p) => p.bytesPerRow).toList(),
        image.planes.map((p) => p.bytesPerPixel ?? 1).toList(),
      ),
      quality,
      targetWidth,
    );
  }
}

class _YuvFrame {
  final int width;
  final int height;
  final List<Uint8List> planes;
  final List<int> strides;
  final List<int> pixelStrides;
  const _YuvFrame(
    this.width,
    this.height,
    this.planes,
    this.strides,
    this.pixelStrides,
  );
}

Uint8List _encodeFrame(_YuvFrame frame, int quality, int targetWidth) {
  final width = frame.width;
  final height = frame.height;
  final yPlane = frame.planes[0];
  final uPlane = frame.planes[1];
  final vPlane = frame.planes[2];
  final yStride = frame.strides[0];
  final uvStride = frame.strides[1];
  final uvPixelStride = frame.pixelStrides[1];

  final img.Image rgbImage = img.Image(height: height, width: width);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int uvIndex = (y >> 1) * uvStride + (x >> 1) * uvPixelStride;
      final int yp = yPlane[y * yStride + x];
      final int up = uPlane[uvIndex];
      final int vp = vPlane[uvIndex];

      // YUV420 to RGB conversion (BT.601)
      double r = yp + 1.402 * (vp - 128);
      double g = yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128);
      double b = yp + 1.772 * (up - 128);

      rgbImage.setPixelRgba(
        x,
        y,
        _clamp255(r.round()),
        _clamp255(g.round()),
        _clamp255(b.round()),
        255,
      );
    }
  }

  final resized = img.copyResize(
    rgbImage,
    width: targetWidth,
    height: (targetWidth * height / width).round(),
    interpolation: img.Interpolation.average,
  );

  return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
}

int _clamp255(int value) => math.max(0, math.min(255, value));
