import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/services/router.dart';

import '../../models/transcript_result.dart';
import '../../services/dio_client.dart';
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
    with TickerProviderStateMixin, RouteAware {
  TranscriptResult? _result;
  String? _status;
  bool _busy = false;
  double _progress = 0.0; // 0..1
  late TabController _tab;
  bool _recordTabActive = true;
  bool _routeActive = true;


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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      // Subscribe this page to route changes
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    // Unsubscribe from route observer
    routeObserver.unsubscribe(this);
    _tab.dispose();
    super.dispose();
  }

  void _setRouteActive(bool active) {
    if (_routeActive == active) return;
    setState(() {
      _routeActive = active;
    });
  }

  // RouteAware hooks:
  @override
  void didPush() {
    // Page was pushed on screen
    _setRouteActive(true);
  }

  @override
  void didPopNext() {
    // A subsequent route was popped and this one is visible again
    _setRouteActive(true);
  }

  @override
  void didPushNext() {
    // Another route pushed on top -> this page is now hidden
    _setRouteActive(false);
  }

  @override
  void didPop() {
    // This route is being popped -> treat as inactive
    _setRouteActive(false);
  }

  /// Persist a successful transcription under:
  ///   /users/{uid}/transcriptions/{autoId}
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
      final api = DioClient();
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

      // Save to Firestore history for this user
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
            Tab(text: 'Real-time'),
            Tab(text: 'Upload'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          RecordCard(
            enabled: !_busy,
            onSubmit: _onVideoReady,
            hint: 'Face the camera and say a sentence. Tap stop when done.',
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