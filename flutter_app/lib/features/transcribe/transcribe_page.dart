import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/transcript_result.dart';
import '../../services/dio_client.dart';
import '../../services/router.dart';
import '../../services/subscription_service.dart';
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
  final SubscriptionService _subscriptionService = SubscriptionService();
  UserSubscription? _subscription;
  int? _transcriptionLimit;
  int _transcriptionsThisMonth = 0;

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

    _loadSubscription();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadSubscription() async {
    try {
      final subscription = await _subscriptionService.getMySubscription();
      setState(() {
        _subscription = subscription;
        _transcriptionLimit =
            subscription?.plan?.transcriptionLimit ?? _transcriptionLimit ?? 10;
      });
    } catch (e) {
      debugPrint('Failed to load subscription for transcription: $e');
    }
  }

  Future<int> _countTranscriptionsThisMonth(String uid) async {
    final now = DateTime.now().toUtc();
    final startOfMonth = DateTime.utc(now.year, now.month, 1);
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('transcriptions')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .get();
    return snap.size;
  }

  int _resolveLimit(UserSubscription? subscription) {
    if (subscription?.plan?.isTranscriptionUnlimited == true) {
      return 1 << 30; // effectively unlimited
    }
    if (subscription?.plan?.transcriptionLimit != null) {
      return subscription!.plan!.transcriptionLimit!;
    }
    return _transcriptionLimit ?? 10;
  }

  Future<bool> _checkTranscriptionAllowance() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    UserSubscription? subscription = _subscription;
    if (subscription == null) {
      try {
        subscription = await _subscriptionService.getMySubscription();
        setState(() => _subscription = subscription);
      } catch (e) {
        debugPrint('Unable to refresh subscription: $e');
      }
    }

    final limit = _resolveLimit(subscription);
    final used = await _countTranscriptionsThisMonth(user.uid);

    setState(() {
      _transcriptionLimit = limit;
      _transcriptionsThisMonth = used;
    });

    if (used >= limit && limit < (1 << 29)) {
      await _showQuotaDialog();
      return false;
    }
    return true;
  }

  Future<void> _showQuotaDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Upgrade to continue'),
          content: Text(
            'You have reached your ${_transcriptionLimit ?? 10}-per-month transcription limit. Upgrade your subscription to keep transcribing.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.pushNamed(context, Routes.subscription);
              },
              child: const Text('View plans'),
            ),
          ],
        );
      },
    );
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
    if (!await _checkTranscriptionAllowance()) {
      return;
    }

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
            _status =
            'Uploading… ${(_progress * 100).toStringAsFixed(0)}%';
          });
        },
      );

      await _saveTranscription(r);
      setState(() {
        _transcriptionsThisMonth += 1;
      });

      setState(() {
        _result = r;
        _status = 'Done';
      });

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        // Clear previous banners before showing a new one
        messenger.clearMaterialBanners();
        messenger.showMaterialBanner(
          MaterialBanner(
            elevation: 2,
            backgroundColor:
            Theme.of(context).colorScheme.surfaceContainerHighest,
            leading: const Icon(
              Icons.check_circle_rounded,
              color: Colors.green,
            ),
            content: const Text(
              'Transcription saved to history.',
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    messenger.hideCurrentMaterialBanner(),
                child: const Text('Dismiss'),
              ),
            ],
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
        actions: [
          IconButton(
            tooltip: 'Transcription History',
            onPressed: () => Navigator.pushNamed(context, Routes.transcriptions),
            icon: const Icon(Icons.history_outlined),
          ),
        ],
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