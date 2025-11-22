import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../../common/theme/app_colors.dart';
import '../../../services/lipread_socket.dart';

/// Simple "record and stream" card:
/// - User taps Record to start camera & live streaming over WebSocket
/// - Encoded frames are sent until Stop is tapped
/// - Partial transcripts are surfaced via [onTranscript]
class RecordCard extends StatefulWidget {
  final bool enabled;
  final ValueChanged<String>? onTranscript;
  final VoidCallback? onStartStreaming;
  final VoidCallback? onStopStreaming;
  final ValueChanged<Object>? onError;
  final String? hint;

  const RecordCard({
    super.key,
    required this.enabled,
    this.onTranscript,
    this.onStartStreaming,
    this.onStopStreaming,
    this.onError,
    this.hint,
  });

  @override
  State<RecordCard> createState() => _RecordCardState();
}

class _RecordCardState extends State<RecordCard> with WidgetsBindingObserver {
  CameraController? _ctrl;
  bool _initializing = false;
  bool _recording = false;
  bool _connecting = false;
  LipreadSocket? _socket;
  StreamSubscription? _socketSub;
  DateTime? _lastFrameSent;
  bool _encoding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeController();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant RecordCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _recording) {
      _stopStreaming();
    }
  }

  // ---------- App lifecycle ----------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _disposeController();
    }
  }

  // ---------- Camera / controller helpers ----------

  Future<void> _disposeController() async {
    await _stopStreaming(fromDispose: true);

    final c = _ctrl;
    _ctrl = null;

    if (c != null) {
      try {
        if (c.value.isStreamingImages) {
          await c.stopImageStream();
        }
      } catch (_) {
        // ignore
      }
      await c.dispose();
    }

    if (mounted) {
      setState(() {
        _recording = false;
        _connecting = false;
      });
    }
  }

  Future<void> _initCameraIfNeeded() async {
    if (_initializing || _ctrl != null) return;
    _initializing = true;
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No camera available')),
          );
        }
        return;
      }
      final front = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );

      final ctrl = CameraController(
        front,
        ResolutionPreset.low,
        enableAudio: false,
      );
      await ctrl.initialize();

      if (!mounted) {
        await ctrl.dispose();
        return;
      }

      setState(() {
        _ctrl = ctrl;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera init failed: $e')),
        );
      }
    } finally {
      _initializing = false;
    }
  }

  // ---------- Record / stop / streaming ----------

  Future<void> _toggleRecord() async {
    if (!widget.enabled || _connecting || _initializing) return;

    // Ensure camera is ready
    if (_ctrl == null || !_ctrl!.value.isInitialized) {
      await _initCameraIfNeeded();
      if (_ctrl == null || !_ctrl!.value.isInitialized) return;
    }

    try {
      if (_recording) {
        await _stopStreaming();
      } else {
        await _startStreaming();
      }
    } catch (Object e) {
      if (mounted) {
        setState(() {
          _recording = false;
          _connecting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recording error: $e')),
        );
      }
      widget.onError?.call(e);
    }
  }

  Future<void> _startStreaming() async {
    final ctrl = _ctrl;
    if (ctrl == null) return;

    setState(() {
      _connecting = true;
    });

    try {
      final socket = LipreadSocket.connect();
      _socketSub = socket.stream.listen(
        (event) {
          if (event is String) {
            widget.onTranscript?.call(event);
          }
        },
        onError: (Object e) {
          widget.onError?.call(e);
          _stopStreaming();
        },
      );

      _socket = socket;
      _lastFrameSent = null;

      await ctrl.startImageStream(_handleImage);

      if (!mounted) return;
      setState(() {
        _recording = true;
        _connecting = false;
      });
      widget.onStartStreaming?.call();
    } catch (Object e) {
      if (mounted) {
        setState(() {
          _recording = false;
          _connecting = false;
        });
      }
      widget.onError?.call(e);
      rethrow;
    }
  }

  Future<void> _stopStreaming({bool fromDispose = false}) async {
    try {
      if (_ctrl?.value.isStreamingImages ?? false) {
        await _ctrl?.stopImageStream();
      }
    } catch (_) {
      // ignore
    }

    await _socketSub?.cancel();
    _socketSub = null;

    await _socket?.close();
    _socket = null;

    _lastFrameSent = null;

    if (mounted && !fromDispose) {
      setState(() {
        _recording = false;
        _connecting = false;
      });
    } else {
      _recording = false;
      _connecting = false;
    }

    if (!fromDispose) {
      widget.onStopStreaming?.call();
    }
  }

  Future<void> _handleImage(CameraImage image) async {
    final socket = _socket;
    if (socket == null || !mounted) return;

    final now = DateTime.now();
    if (_lastFrameSent != null &&
        now.difference(_lastFrameSent!) < const Duration(milliseconds: 120)) {
      return;
    }
    _lastFrameSent = now;

    if (_encoding) return;
    _encoding = true;

    try {
      final plane = image.planes.first;
      final luminance = img.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: plane.bytes,
        format: img.Format.luminance,
        rowStride: plane.bytesPerRow,
      );

      final resized = img.copyResize(
        luminance,
        width: 96,
        height: 96,
        interpolation: img.Interpolation.average,
      );

      final jpgBytes = Uint8List.fromList(
        img.encodeJpg(resized, quality: 75),
      );

      socket.sendFrame(jpgBytes);
    } catch (Object e) {
      widget.onError?.call(e);
    } finally {
      _encoding = false;
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final isBusy = _initializing || _connecting;
    final buttonEnabled = widget.enabled && !isBusy;

    return Column(
      children: [
        if (widget.hint != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.hint!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.softShadow,
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  // --- Camera preview / placeholder (like live UI) ---
                  if (_ctrl == null || !_ctrl!.value.isInitialized)
                    const Center(
                      child: Text(
                        'Tap Record to activate camera',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    )
                  else
                    Center(
                      child: ClipRect(
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _ctrl!.value.previewSize?.height ?? 1,
                            height: _ctrl!.value.previewSize?.width ?? 1,
                            child: CameraPreview(_ctrl!),
                          ),
                        ),
                      ),
                    ),

                  // --- Status chip (top-right) ---
                  if (_connecting || _recording)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _connecting ? 'Connecting…' : 'Streaming…',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),

                  // --- Bottom Record / Stop button (similar to live UI) ---
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            _recording ? AppColors.error : AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      onPressed: buttonEnabled ? _toggleRecord : null,
                      icon: _connecting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Icon(
                              _recording
                                  ? Icons.stop_rounded
                                  : Icons.fiber_manual_record_rounded,
                              size: 18,
                            ),
                      label: Text(
                        _recording ? 'Stop streaming' : 'Record',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
