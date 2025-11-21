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
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ctrl?.value.isRecordingVideo == true) {
      _ctrl?.stopVideoRecording();
    }
    _ctrl?.dispose();
    _cancelAutoStop();
    super.dispose();
  }

  void _cancelAutoStop() {
    _autoStopTimer?.cancel();
    _autoStopTimer = null;
  }

  Future<void> _disposeController() async {
    final c = _ctrl;
    _ctrl = null;
    if (c != null) {
      try {
        if (c.value.isRecordingVideo) {
          await c.stopVideoRecording();
        }
      } catch (_) {}
      await c.dispose();
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _ctrl;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _disposeController();
    } else if (state == AppLifecycleState.resumed) {
      if (ctrl == null) _init();
    }
  }

  Future<void> _init() async {
    if (_initializing || _ctrl != null) return;
    _initializing = true;
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No camera available'),
            ),
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

  Future<void> _toggleRecord() async {
    if (!widget.enabled) return;

    if (_ctrl == null || !_ctrl!.value.isInitialized) {
      await _init();
      if (_ctrl == null) return;
    }

    final ctrl = _ctrl!;
    try {
      if (ctrl.value.isRecordingVideo) {
        final x = await ctrl.stopVideoRecording();
        _cancelAutoStop();
        final tmpDir = await getTemporaryDirectory();
        final file = File(
          '${tmpDir.path}/transcribe_${DateTime.now().millisecondsSinceEpoch}.mp4',
        );
        await File(x.path).copy(file.path);
        if (!mounted) return;
        setState(() {
          _recording = false;
          _lastFile = file;
        });
      } else {
        await ctrl.prepareForVideoRecording();
        await ctrl.startVideoRecording();
        if (!mounted) return;
        setState(() {
          _recording = true;
          _lastFile = null;
        });

        _cancelAutoStop();
        _autoStopTimer =
            Timer(const Duration(seconds: 5), () async {
              if (!mounted) return;
              if (_ctrl != null && _ctrl!.value.isRecordingVideo) {
                try {
                  final x = await _ctrl!.stopVideoRecording();
                  final tmpDir = await getTemporaryDirectory();
                  final file = File(
                    '${tmpDir.path}/transcribe_${DateTime.now().millisecondsSinceEpoch}.mp4',
                  );
                  await File(x.path).copy(file.path);
                  if (!mounted) return;
                  setState(() {
                    _recording = false;
                    _lastFile = file;
                  });
                } catch (_) {
                  // ignore
                }
              }
            });
      }
    } catch (e) {
      _cancelAutoStop();
      if (mounted) {
        setState(() => _recording = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recording error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if ((_ctrl == null || !_ctrl!.value.isInitialized) &&
        !_initializing) {
      _init();
    }

    final canSubmit =
        widget.enabled && _lastFile != null && !_recording;

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
                  if (_ctrl == null ||
                      !_ctrl!.value.isInitialized)
                    const Center(
                      child: CircularProgressIndicator(),
                    )
                  else
                    Center(
                      child: AspectRatio(
                        aspectRatio: _ctrl!.value.aspectRatio,
                        child: CameraPreview(_ctrl!),
                      ),
                    ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: _recording
                                  ? AppColors.error
                                  : AppColors.primary,
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius.circular(999),
                              ),
                            ),
                            onPressed:
                            widget.enabled ? _toggleRecord : null,
                            icon: Icon(
                              _recording
                                  ? Icons.stop_rounded
                                  : Icons.fiber_manual_record_rounded,
                              size: 18,
                            ),
                            label: Text(
                              _recording ? 'Stop recording' : 'Record',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_lastFile != null && !_recording)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Clip ready',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding:
          const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: canSubmit
                      ? () => widget.onSubmit(_lastFile!)
                      : null,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Upload & transcribe'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}