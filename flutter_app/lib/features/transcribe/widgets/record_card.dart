import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../../common/theme/app_colors.dart';

/// Simple "record and auto-upload" card:
/// - User taps Record to start camera & recording
/// - Speaks as long as they want
/// - Taps Stop → recording stops and the resulting file is
///   automatically passed to [onSubmit(file)]
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
  bool _initializing = false;
  bool _recording = false;
  bool _submitting = false;
  File? _lastFile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // We only start camera when user taps Record.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeController();
    super.dispose();
  }

  // ---------- App lifecycle ----------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // If app goes inactive or to background, release camera.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _disposeController();
    }
  }

  // ---------- Camera / controller helpers ----------

  Future<void> _disposeController() async {
    final c = _ctrl;
    _ctrl = null;

    if (c != null) {
      try {
        if (c.value.isRecordingVideo) {
          await c.stopVideoRecording();
        }
      } catch (_) {
        // ignore
      }
      await c.dispose();
    }

    if (mounted) {
      setState(() {
        _recording = false;
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
        enableAudio: true,
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

  // ---------- Record / stop / auto-upload ----------

  Future<void> _toggleRecord() async {
    if (!widget.enabled || _submitting) return;

    // Ensure camera is ready
    if (_ctrl == null || !_ctrl!.value.isInitialized) {
      await _initCameraIfNeeded();
      if (_ctrl == null || !_ctrl!.value.isInitialized) return;
    }

    final ctrl = _ctrl!;
    try {
      if (ctrl.value.isRecordingVideo) {
        // ---- STOP: save file & auto-upload ----
        final rec = await ctrl.stopVideoRecording();

        final tmpDir = await getTemporaryDirectory();
        final file = File(
          '${tmpDir.path}/transcribe_${DateTime.now().millisecondsSinceEpoch}.mp4',
        );
        await File(rec.path).copy(file.path);

        if (!mounted) return;

        setState(() {
          _recording = false;
          _lastFile = file;
          _submitting = true;
        });

        try {
          await widget.onSubmit(file);
        } finally {
          if (mounted) {
            setState(() {
              _submitting = false;
            });
          }
        }
      } else {
        // ---- START recording ----
        await ctrl.prepareForVideoRecording();
        await ctrl.startVideoRecording();
        if (!mounted) return;
        setState(() {
          _recording = true;
          _lastFile = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _recording = false;
          _submitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recording error: $e')),
        );
      }
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final isBusy = _initializing || _submitting;
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
                  if (_submitting || (_lastFile != null && !_recording))
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
                          _submitting
                              ? 'Uploading & transcribing...'
                              : 'Clip sent',
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
                      icon: _submitting
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
                        _recording
                            ? 'Stop & transcribe'
                            : 'Record',
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
