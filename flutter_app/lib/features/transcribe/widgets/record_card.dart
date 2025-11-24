import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../../common/theme/app_colors.dart';

class RecordCard extends StatefulWidget {
  final bool enabled;
  final Future<void> Function(File file) onSubmit;
  final String? hint;

  const RecordCard({
    super.key,
    required this.enabled,
    required this.onSubmit,
    this.hint,
  });

  @override
  State<RecordCard> createState() => _RecordCardState();
}

class _RecordCardState extends State<RecordCard>
    with WidgetsBindingObserver {
  CameraController? _ctrl;
  bool _recording = false;
  bool _initializing = false;
  File? _lastFile;
  Timer? _autoStopTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAndDisposeCamera();
    super.dispose();
  }

  // ------------------------------------------------------------
  // CAMERA LIFECYCLE
  // ------------------------------------------------------------

  Future<void> _startCamera() async {
    if (_initializing) return;

    // ALWAYS dispose old camera if exists
    if (_ctrl != null) {
      try {
        await _ctrl!.dispose();
      } catch (_) {}
      _ctrl = null;
    }

    _initializing = true;

    try {
      final cams = await availableCameras();
      final front = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );

      final ctrl = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await ctrl.initialize();

      if (!mounted) {
        await ctrl.dispose();
        return;
      }

      setState(() => _ctrl = ctrl);

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Camera init failed: $e')));
      }
    } finally {
      _initializing = false;
    }
  }

  Future<void> _stopAndDisposeCamera() async {
    final ctrl = _ctrl;
    _ctrl = null;

    _cancelAutoStopTimer();

    if (ctrl != null) {
      try {
        if (ctrl.value.isRecordingVideo) {
          await ctrl.stopVideoRecording();
        }
      } catch (_) {}
      await ctrl.dispose();
    }

    if (mounted) {
      setState(() {
        _recording = false;
      });
    }
  }

  // Release camera when app goes background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _stopAndDisposeCamera();
    }
  }

  // ------------------------------------------------------------
  // RECORDING
  // ------------------------------------------------------------

  Future<void> _onRecordPressed() async {
    if (!widget.enabled) return;

    if (_ctrl == null) {
      await _startCamera();
      if (_ctrl == null) return;
    }

    final ctrl = _ctrl!;
    try {
      if (!ctrl.value.isRecordingVideo) {
        // Start recording
        await ctrl.prepareForVideoRecording();
        await ctrl.startVideoRecording();

        if (!mounted) return;

        setState(() {
          _recording = true;
          _lastFile = null;
        });

        // Auto-stop after 5 seconds
        _autoStopTimer = Timer(const Duration(seconds: 5), () async {
          if (mounted && ctrl.value.isRecordingVideo) {
            await _stopRecordingInternal();
          }
        });
      } else {
        await _stopRecordingInternal();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Recording error: $e')));
      }
    }
  }

  Future<void> _stopRecordingInternal() async {
    final ctrl = _ctrl;
    if (ctrl == null) return;

    _cancelAutoStopTimer();

    try {
      final x = await ctrl.stopVideoRecording();
      final tmpDir = await getTemporaryDirectory();
      final file = File(
        '${tmpDir.path}/lipread_${DateTime.now().millisecondsSinceEpoch}.mp4',
      );
      await File(x.path).copy(file.path);

      if (!mounted) return;

      setState(() {
        _recording = false;
        _lastFile = file;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Stop error: $e')));
      }
    } finally {
      // Dispose camera after recording finished
      await _stopAndDisposeCamera();
    }
  }

  void _cancelAutoStopTimer() {
    _autoStopTimer?.cancel();
    _autoStopTimer = null;
  }

  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        widget.enabled && !_recording && _lastFile != null;

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

        // --------------------------------------------------------
        // CAMERA PREVIEW (only when recording)
        // --------------------------------------------------------
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
              child: _recording && _ctrl != null && _ctrl!.value.isInitialized
                  ? Center(
                      // ⭐ Perfect aspect ratio — prevents stretching ⭐
                      child: AspectRatio(
                        aspectRatio: _ctrl!.value.aspectRatio,
                        child: CameraPreview(_ctrl!),
                      ),
                    )
                  : Center(
                      child: Icon(
                        Icons.videocam_outlined,
                        size: 40,
                        color: AppColors.textSecondary,
                      ),
                    ),
            ),
          ),
        ),

        // --------------------------------------------------------
        // BUTTONS
        // --------------------------------------------------------
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: widget.enabled ? _onRecordPressed : null,
                icon: Icon(
                  _recording
                      ? Icons.stop_rounded
                      : Icons.fiber_manual_record_rounded,
                ),
                label: Text(_recording ? 'Stop Recording' : 'Record'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed:
                    canSubmit ? () => widget.onSubmit(_lastFile!) : null,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Upload & Transcribe'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}