import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../common/theme/app_colors.dart';
import '../../models/content_models.dart';
import '../../services/content_api_service.dart';
import '../../services/home_metrics_service.dart';
import '../../services/daily_task_service.dart';
import '../../common/utils/media_utils.dart';

//
// Helpers
//

class _ActivityIds {
  final String courseId;
  final String moduleId;
  final String lessonId;
  final String activityId;

  _ActivityIds(this.courseId, this.moduleId, this.lessonId, this.activityId);

  static _ActivityIds? fromRef(String ref) {
    final parts = ref.split('|');
    if (parts.length != 4) return null;
    return _ActivityIds(parts[0], parts[1], parts[2], parts[3]);
  }
}

//
// 4) DICTATION
//

class DictationActivityScreen extends StatefulWidget {
  final String activityRef; // courseId|moduleId|lessonId|activityId
  const DictationActivityScreen({super.key, required this.activityRef});

  @override
  State<DictationActivityScreen> createState() => _DictationActivityScreenState();
}

class _DictationActivityScreenState extends State<DictationActivityScreen> {
  final ContentApiService _contentApi = ContentApiService();
  final Map<String, TextEditingController> _controllers = {};
  bool _submitting = false;
  String? _error;
  late final Future<ActivityDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<ActivityDetail> _load() {
    final ids = _ActivityIds.fromRef(widget.activityRef);
    if (ids == null) throw Exception('Invalid activity reference');
    return _contentApi.fetchActivityDetail(
      ids.courseId,
      ids.moduleId,
      ids.lessonId,
      ids.activityId,
    );
  }

  Future<void> _submit(ActivityDetail detail) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final uid = FirebaseAuth.instance.currentUser?.uid;
    final total = detail.dictationItems.length;
    int correct = 0;
    for (final item in detail.dictationItems) {
      final resp = _controllers[item.id]?.text.trim().toLowerCase() ?? '';
      final expected = item.correctText.trim().toLowerCase();
      if (resp.isNotEmpty && resp == expected) correct++;
    }

    final scorePct = total == 0 ? 0 : ((correct / total) * 100).round();

    if (uid != null) {
      await HomeMetricsService.onActivityCompleted(uid);
      await HomeMetricsService.onAttemptSubmitted(
        uid,
        actionType: 'complete_dictation',
      );
    }

    if (!mounted) return;
    setState(() => _submitting = false);

    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Dictation submitted',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$correct / $total correct · $scorePct%',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to lesson'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Dictation'),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: FutureBuilder<ActivityDetail>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Failed to load activity.\n${snap.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final detail = snap.data!;
          final items = detail.dictationItems;

          if (items.isEmpty) {
            return const Center(
              child: Text('No dictation items configured.'),
            );
          }

          for (final item in items) {
            _controllers.putIfAbsent(item.id, () => TextEditingController());
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...items.map((item) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: _cardDecor(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Prompt ${item.order + 1}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _ActivityMedia(
                          mediaId: item.mediaId,
                          fallbackLabel: item.mediaId,
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _controllers[item.id],
                          decoration: InputDecoration(
                            labelText: 'Type what you hear',
                            hintText: item.hints ?? 'Enter transcript',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                if (_error != null) ...[
                  Text(
                    _error!,
                    style:
                        const TextStyle(color: AppColors.error, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitting ? null : () => _submit(detail),
                    child: _submitting
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color:
                                  Theme.of(context).colorScheme.onPrimary,
                            ),
                          )
                        : const Text('Submit answers'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

//
// 5) PRACTICE LIP
//

class PracticeActivityScreen extends StatefulWidget {
  final String activityRef;
  const PracticeActivityScreen({super.key, required this.activityRef});

  @override
  State<PracticeActivityScreen> createState() => _PracticeActivityScreenState();
}

class _PracticeActivityScreenState extends State<PracticeActivityScreen> {
  final ContentApiService _contentApi = ContentApiService();
  bool _submitting = false;
  String? _error;
  late final Future<ActivityDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<ActivityDetail> _load() {
    final ids = _ActivityIds.fromRef(widget.activityRef);
    if (ids == null) throw Exception('Invalid activity reference');
    return _contentApi.fetchActivityDetail(
      ids.courseId,
      ids.moduleId,
      ids.lessonId,
      ids.activityId,
    );
  }

  Future<void> _complete(ActivityDetail detail) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await HomeMetricsService.onActivityCompleted(
        uid,
        actionType: 'finish_practice',
      );
      await HomeMetricsService.onAttemptSubmitted(uid);
    }

    if (!mounted) return;
    setState(() => _submitting = false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Practice'),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: FutureBuilder<ActivityDetail>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Failed to load activity.\n${snap.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final detail = snap.data!;
          final items = detail.practiceItems;

          if (items.isEmpty) {
            return const Center(child: Text('No practice items configured.'));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...items.map((item) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: _cardDecor(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.targetWord?.isNotEmpty == true
                              ? item.targetWord!
                              : 'Practice item ${item.order + 1}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.description,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _ActivityMedia(
                          mediaId: item.mediaId,
                          fallbackLabel: item.mediaId,
                        ),
                      ],
                    ),
                  );
                }),
                if (_error != null) ...[
                  Text(
                    _error!,
                    style:
                        const TextStyle(color: AppColors.error, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitting ? null : () => _complete(detail),
                    child: _submitting
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color:
                                  Theme.of(context).colorScheme.onPrimary,
                            ),
                          )
                        : const Text('I’ve practiced'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

DocumentReference<Map<String, dynamic>> _activityDoc(_ActivityIds ids) {
  return FirebaseFirestore.instance
      .collection('courses')
      .doc(ids.courseId)
      .collection('modules')
      .doc(ids.moduleId)
      .collection('lessons')
      .doc(ids.lessonId)
      .collection('activities')
      .doc(ids.activityId);
}

BoxDecoration _cardDecor({double radius = 16}) {
  return BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: [
      BoxShadow(
        color: AppColors.softShadow,
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

bool _looksVideo(String? url) {
  if (url == null) return false;
  final lower = url.toLowerCase();
  return lower.endsWith('.mp4') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.webm') ||
      lower.endsWith('.mkv') ||
      lower.contains('/videos/');
}

bool _looksImage(String? url) {
  if (url == null) return false;
  final lower = url.toLowerCase();
  return lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.webp');
}

/// Home-style media renderer with **ID → Firestore** resolving.
class _ActivityMedia extends StatefulWidget {
  final Map<String, dynamic>? media;    // {url/path/contentType/kind/mediaId/id}
  final String? mediaId;                // config.mediaId OR root mediaId
  final String? videoId;                // config.videoId (treat as mediaId)
  final String? fallbackLabel;          // UI hint if nothing resolves

  const _ActivityMedia({
    this.media,
    this.mediaId,
    this.videoId,
    this.fallbackLabel,
  });

  @override
  State<_ActivityMedia> createState() => _ActivityMediaState();
}

class _ActivityMediaState extends State<_ActivityMedia> {
  VideoPlayerController? _ctrl;
  bool _err = false;

  String? _url;
  String _contentType = '';
  String _kind = '';
  bool _isVideo = false;
  bool _isImage = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolveAndInit();
  }

  @override
  void didUpdateWidget(covariant _ActivityMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media != widget.media ||
        oldWidget.mediaId != widget.mediaId ||
        oldWidget.videoId != widget.videoId) {
      _disposeVideo();
      _resolveAndInit();
    }
  }

  Future<void> _resolveAndInit() async {
    setState(() {
      _loading = true;
      _err = false;
      _url = null;
      _contentType = '';
      _kind = '';
      _isVideo = false;
      _isImage = false;
    });

    // 1) Direct values from media map
    final m = widget.media ?? {};
    String? url = (m['url'] as String?) ?? (m['path'] as String?);
    String? mediaId =
        (m['mediaId'] as String?) ?? (m['id'] as String?) ?? widget.mediaId ?? widget.videoId;

    String contentType = (m['contentType'] as String?)?.toLowerCase() ?? '';
    String kind = (m['kind'] as String?)?.toLowerCase() ?? '';

    // 2) If no URL but we have an ID, resolve from /media/{id}
    if ((url == null || url.isEmpty) && mediaId != null && mediaId.isNotEmpty) {
      try {
        final snap =
        await FirebaseFirestore.instance.collection('media').doc(mediaId).get();
        if (snap.exists) {
          final data = snap.data() ?? {};
          url = data['url'] as String?;
          contentType = (data['contentType'] as String?)?.toLowerCase() ?? contentType;
          kind = (data['kind'] as String?)?.toLowerCase() ?? kind;
        }
      } catch (_) {
        // swallow; will show fallback chip later
      }
    }

    // 3) Normalize URL for emulator/device
    url = normalizeMediaUrl(url);

    // 4) Decide type
    final looksVid = _looksVideo(url);
    final looksImg = _looksImage(url);
    final isVid = contentType.startsWith('video/') || kind == 'video' || looksVid;
    final isImg = contentType.startsWith('image/') || kind == 'image' || looksImg;

    setState(() {
      _url = url;
      _contentType = contentType;
      _kind = kind;
      _isVideo = isVid && (url != null && url.isNotEmpty);
      _isImage = isImg && (url != null && url.isNotEmpty);
    });

    // 5) Init video if needed
    if (_isVideo) {
      try {
        final c = VideoPlayerController.networkUrl(
          Uri.parse(_url!),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
        _ctrl = c;
        await c.initialize();
        await c.setLooping(false);
        if (!mounted) return;
        c.addListener(() {
          if (mounted) setState(() {});
        });
      } catch (_) {
        if (mounted) setState(() => _err = true);
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  void _disposeVideo() {
    _ctrl?.dispose();
    _ctrl = null;
  }

  @override
  void dispose() {
    _disposeVideo();
    super.dispose();
  }

  Widget _frame(Widget child) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(aspectRatio: 16 / 9, child: child),
      ),
    );
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    // Fallback chip if absolutely nothing resolved
    if ((_url == null || _url!.isEmpty) && widget.fallbackLabel != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.play_circle_fill_rounded, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.fallbackLabel!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    if (_loading) {
      return _frame(const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ));
    }

    if (_url == null || _url!.isEmpty) {
      return const SizedBox.shrink();
    }

    // IMAGE (letterboxed like Home)
    if (_isImage) {
      return _frame(
        Image.network(
          _url!,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Center(
            child:
            Text('Image failed to load', style: TextStyle(color: AppColors.error)),
          ),
        ),
      );
    }

    // VIDEO (centered to its AR + hidden overlay while playing + progress bar)
    if (_isVideo) {
      if (_err) {
        return _frame(const Center(
          child: Text('Video failed to load', style: TextStyle(color: AppColors.error)),
        ));
      }
      if (_ctrl == null || !_ctrl!.value.isInitialized) {
        return _frame(const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ));
      }

      final ar = (_ctrl!.value.aspectRatio.isFinite && _ctrl!.value.aspectRatio > 0)
          ? _ctrl!.value.aspectRatio
          : (16 / 9);
      final playing = _ctrl!.value.isPlaying;
      final dur = _ctrl!.value.duration;
      final pos = _ctrl!.value.position;
      final ended = dur > Duration.zero && pos >= dur;

      return _frame(
        Stack(
          children: [
            Center(
              child: AspectRatio(aspectRatio: ar, child: VideoPlayer(_ctrl!)),
            ),
            // Play/Pause/Replay overlay (auto hides when playing)
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: playing ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 180),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (ended) {
                      _ctrl!.seekTo(Duration.zero);
                      _ctrl!.play();
                    } else {
                      playing ? _ctrl!.pause() : _ctrl!.play();
                    }
                  },
                  child: Container(
                    color:
                        Theme.of(context).colorScheme.scrim.withOpacity(0.26),
                    child: Center(
                      child: Icon(
                        ended
                            ? Icons.replay_rounded
                            : (playing
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded),
                        size: 56,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Bottom progress + time
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 4,
                        value: (dur.inMilliseconds == 0)
                            ? 0
                            : pos.inMilliseconds / dur.inMilliseconds,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withOpacity(0.3),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_fmt(pos)} / ${_fmt(dur)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurface,
                      shadows: [
                        Shadow(
                          blurRadius: 2,
                          color: Theme.of(context).colorScheme.scrim,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (playing)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _ctrl!.pause(),
                ),
              ),
          ],
        ),
      );
    }

    // Unknown type → small URL chip
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.play_circle_fill_rounded, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _url!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

//
// 1) VIDEO DRILL
//

class VideoDrillScreen extends StatefulWidget {
  final String activityRef; // courseId|moduleId|lessonId|activityId
  const VideoDrillScreen({super.key, required this.activityRef});

  @override
  State<VideoDrillScreen> createState() => _VideoDrillScreenState();
}

class _VideoDrillScreenState extends State<VideoDrillScreen> {
  bool _submitting = false;
  String? _error;

  Future<void> _completeAsWatched(
      _ActivityIds ids,
      Map<String, dynamic> activity,
      ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await HomeMetricsService.recordActivityAttempt(
        uid: uid,
        courseId: ids.courseId,
        moduleId: ids.moduleId,
        lessonId: ids.lessonId,
        activityId: ids.activityId,
        activityType: 'video_drill',
        score: 100,
        passed: true,
        baseXp: (activity['points'] as num?)?.toInt() ?? 10,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = 'Could not record completion. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ids = _ActivityIds.fromRef(widget.activityRef);
    if (ids == null) {
      return const Scaffold(body: Center(child: Text('Invalid activity reference')));
    }
    final docRef = _activityDoc(ids);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Video drill'),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(
              child: Text('Failed to load activity.',
                  style: TextStyle(color: AppColors.error)),
            );
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snap.data!.data()!;
          final title =
              (data['label'] as String?) ??
                  (data['title'] as String?) ??
                  'Watch & repeat';
          final config = (data['config'] as Map<String, dynamic>?) ?? {};
          final videoId = config['videoId'] as String?;
          final loopSection = (config['loopSection'] as List?)?.cast<num>();
          final playbackRate = (config['playbackRate'] as num?)?.toDouble() ?? 1.0;
          final media = (config['media'] as Map<String, dynamic>?);
          final mediaId = (config['mediaId'] as String?) ?? (data['mediaId'] as String?);

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: _cardDecor(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Watch the clip carefully and mimic the speaker’s lip movements.',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 14),

                      _ActivityMedia(
                        media: media,
                        mediaId: mediaId,
                        videoId: videoId,
                        fallbackLabel: videoId != null ? 'Video: $videoId' : null,
                      ),

                      if (loopSection != null && loopSection.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Loop: ${loopSection.join(' - ')}',
                          style:
                          const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                        ),
                      ],
                      const SizedBox(height: 2),
                      Text(
                        'Playback: ${playbackRate}x',
                        style:
                        const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      if (_error != null) ...[
                        Text(_error!,
                            style: const TextStyle(
                                color: AppColors.error, fontSize: 12)),
                        const SizedBox(height: 8),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed:
                          _submitting ? null : () => _completeAsWatched(ids, data),
                          child: _submitting
                              ? SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color:
                                  Theme.of(context).colorScheme.onPrimary,
                            ),
                          )
                              : const Text('Mark as completed'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

//
// 2) VISEME MATCH
//

class VisemeMatchScreen extends StatefulWidget {
  final String activityRef;
  const VisemeMatchScreen({super.key, required this.activityRef});

  @override
  State<VisemeMatchScreen> createState() => _VisemeMatchScreenState();
}

class _VisemeMatchScreenState extends State<VisemeMatchScreen> {
  bool _submitting = false;
  String? _error;

  Future<void> _complete(_ActivityIds ids, Map<String, dynamic> activity) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await HomeMetricsService.recordActivityAttempt(
        uid: uid,
        courseId: ids.courseId,
        moduleId: ids.moduleId,
        lessonId: ids.lessonId,
        activityId: ids.activityId,
        activityType: 'viseme_match',
        score: 100,
        passed: true,
        baseXp: (activity['points'] as num?)?.toInt() ?? 15,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Could not record completion.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ids = _ActivityIds.fromRef(widget.activityRef);
    if (ids == null) {
      return const Scaffold(body: Center(child: Text('Invalid activity reference')));
    }
    final docRef = _activityDoc(ids);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Viseme match'),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(
              child: Text('Failed to load activity.',
                  style: TextStyle(color: AppColors.error)),
            );
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snap.data!.data()!;
          final config = (data['config'] as Map<String, dynamic>?) ?? {};
          final expected = (config['expected'] as List?)?.cast<String>() ?? const [];
          final toleranceMs = (config['toleranceMs'] as num?)?.toInt() ?? 200;
          final media = (config['media'] as Map<String, dynamic>?);
          final mediaId = (config['mediaId'] as String?) ?? (data['mediaId'] as String?);
          final videoId = config['videoId'] as String?;

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: _cardDecor(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Match the visemes',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Say the phrase and align your mouth shapes (visemes) with the expected sequence.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),

                  _ActivityMedia(
                    media: media,
                    mediaId: mediaId,
                    videoId: videoId,
                    fallbackLabel: videoId,
                  ),
                  const SizedBox(height: 12),

                  if (expected.isNotEmpty) ...[
                    const Text(
                      'Expected viseme sequence:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: expected
                          .map(
                            (e) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            e,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      )
                          .toList(),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tolerance: ±$toleranceMs ms',
                      style:
                      const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (_error != null) ...[
                    Text(_error!,
                        style:
                        const TextStyle(color: AppColors.error, fontSize: 12)),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submitting ? null : () => _complete(ids, data),
                      child: _submitting
                          ? SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color:
                              Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                          : const Text('I’ve completed this'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

//
// 3) MIRROR PRACTICE
//

class MirrorPracticeScreen extends StatefulWidget {
  final String activityRef;
  const MirrorPracticeScreen({super.key, required this.activityRef});

  @override
  State<MirrorPracticeScreen> createState() => _MirrorPracticeScreenState();
}

class _MirrorPracticeScreenState extends State<MirrorPracticeScreen> {
  bool _submitting = false;
  String? _error;

  Future<void> _complete(_ActivityIds ids, Map<String, dynamic> activity) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await HomeMetricsService.recordActivityAttempt(
        uid: uid,
        courseId: ids.courseId,
        moduleId: ids.moduleId,
        lessonId: ids.lessonId,
        activityId: ids.activityId,
        activityType: 'mirror_practice',
        score: 100,
        passed: true,
        baseXp: (activity['points'] as num?)?.toInt() ?? 12,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Could not record completion.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ids = _ActivityIds.fromRef(widget.activityRef);
    if (ids == null) {
      return const Scaffold(body: Center(child: Text('Invalid activity reference')));
    }
    final docRef = _activityDoc(ids);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Mirror practice'),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(
              child: Text('Failed to load activity.',
                  style: TextStyle(color: AppColors.error)),
            );
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snap.data!.data()!;
          final config = (data['config'] as Map<String, dynamic>?) ?? {};
          final overlayGuides = config['overlayGuides'] == true;
          final media = (config['media'] as Map<String, dynamic>?);
          final mediaId = (config['mediaId'] as String?) ?? (data['mediaId'] as String?);
          final videoId = config['videoId'] as String?;

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: _cardDecor(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mirror your lips',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Use your front camera as a mirror. Focus on clear lip shapes, timing, and consistency.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 14),

                  _ActivityMedia(
                    media: media,
                    mediaId: mediaId,
                    videoId: videoId,
                    fallbackLabel: videoId,
                  ),
                  const SizedBox(height: 12),

                  Container(
                    height: 160,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.flip_camera_android_rounded,
                              size: 40, color: AppColors.primary),
                          const SizedBox(height: 8),
                          Text(
                            overlayGuides
                                ? 'Guides enabled (future overlay)'
                                : 'Front camera preview placeholder',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null) ...[
                    Text(_error!,
                        style:
                        const TextStyle(color: AppColors.error, fontSize: 12)),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submitting ? null : () => _complete(ids, data),
                      child: _submitting
                          ? SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color:
                              Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                          : const Text('Mark as completed'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}