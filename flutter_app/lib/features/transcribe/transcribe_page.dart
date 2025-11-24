import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/transcript_result.dart';
import '../../services/api_client.dart';
import 'widgets/record_card.dart';
import 'widgets/upload_card.dart';
import 'widgets/transcript_view.dart';

class TranscribePage extends StatefulWidget {
  final String? lessonId;
  const TranscribePage({super.key, this.lessonId});

  @override
  State<TranscribePage> createState() => _TranscribePageState();
}

class _TranscribePageState extends State<TranscribePage>
    with TickerProviderStateMixin {
  TranscriptResult? _result;
  String? _status;
  bool _busy = false;
  double _progress = 0.0; // 0..1
  late TabController _tab;
  bool _recordTabActive = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _recordTabActive = _tab.index == 0;
    _tab.addListener(() {
      final isRecord = _tab.index == 0;
      if (_recordTabActive != isRecord) {
        setState(() => _recordTabActive = isRecord);
      }
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _saveTranscription(TranscriptResult r) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('transcriptions');

    await ref.add({
      'transcript': r.transcript,
      'confidence': r.confidence,
      'words': r.words
          .map((w) => {
                'text': w.text,
                'start': w.start,
                'end': w.end,
                'conf': w.conf,
              })
          .toList(),
      'visemes': r.visemes
          .map((v) => {
                'label': v.label,
                'start': v.start,
                'end': v.end,
              })
          .toList(),
      'lessonId': widget.lessonId,
      'mode': _recordTabActive ? 'record' : 'upload',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _onVideoReady(File file) async {
    setState(() {
      _busy = true;
      _status = 'Uploading…';
      _result = null;
      _progress = 0.0;
    });

    try {
      final api = ApiClient();
      final r = await api.transcribeVideo(
        file,
        lessonId: widget.lessonId,
        onProgress: (sent, total) {
          if (!mounted) return;
          final p = total > 0 ? sent / total : 0.0;
          setState(() {
            _progress = p.clamp(0.0, 1.0);
            _status = 'Uploading… ${(_progress * 100).toStringAsFixed(0)}%';
          });
        },
      );

      await _saveTranscription(r);

      setState(() {
        _result = r;
        _status = 'Done';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transcription saved to history.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Transcription failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = 0.0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomBarNeeded = _busy || _status != null || _result != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lip Transcription'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Record'),
            Tab(text: 'Upload'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _recordTabActive
              ? RecordCard(
                  enabled: !_busy,
                  onSubmit: _onVideoReady,
                  hint: 'Record a 3–5s clip facing the camera.',
                )
              : const Center(
                  child:
                      Text('Switch to Record to start recording'),
                ),
          UploadCard(
            enabled: !_busy,
            onSubmit: _onVideoReady,
            hint: 'Pick an MP4/WebM from your device.',
          ),
        ],
      ),
      bottomNavigationBar: bottomBarNeeded
          ? SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_busy)
                    LinearProgressIndicator(
                      value: _progress == 0 ? null : _progress,
                      minHeight: 2,
                    ),
                  if (_status != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _status!,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  if (_result != null)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: TranscriptView(result: _result!),
                    ),
                ],
              ),
            )
          : null,
    );
  }
}
