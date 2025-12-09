import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../common/theme/app_colors.dart';
import '../../common/utils/media_utils.dart';
import '../../models/content_models.dart';
import '../../services/content_api_service.dart';
import '../../services/home_metrics_service.dart';
import '../../services/daily_task_service.dart';

class QuizActivityArgs {
  final String courseId;
  final String moduleId;
  final String lessonId;
  final String activityId;

  const QuizActivityArgs({
    required this.courseId,
    required this.moduleId,
    required this.lessonId,
    required this.activityId,
  });
}

class QuizActivityPage extends StatefulWidget {
  final String courseId;
  final String moduleId;
  final String lessonId;
  final String activityId;

  const QuizActivityPage({
    super.key,
    required this.courseId,
    required this.moduleId,
    required this.lessonId,
    required this.activityId,
  });

  @override
  State<QuizActivityPage> createState() => _QuizActivityPageState();
}

class _QuizActivityPageState extends State<QuizActivityPage> {
  final ContentApiService _contentApi = ContentApiService();
  bool _loading = true;
  String? _error;

  ActivityDetail? _activityDetail;
  List<_QuizQuestion> _questions = [];
  int _currentIndex = 0;
  final Map<int, int> _selectedOption = {}; // questionIndex -> optionIndex
  final Map<int, bool> _isCorrect = {}; // questionIndex -> correct?
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _loadQuiz();
  }

  Future<void> _loadQuiz() async {
    try {
      final detail = await _contentApi.fetchActivityDetail(
        widget.courseId,
        widget.moduleId,
        widget.lessonId,
        widget.activityId,
      );

      _activityDetail = detail;

      if (detail.questions.isEmpty) {
        setState(() {
          _error = 'No questions available in this quiz.';
          _loading = false;
        });
        return;
      }

      final numQuestions = (detail.config['numQuestions'] as num?)?.toInt() ??
          (detail.itemCount > 0 ? detail.itemCount : detail.questions.length);

      final all = detail.questions
          .map(_QuizQuestion.fromActivityQuestion)
          .where((q) => q.options.isNotEmpty)
          .toList();

      if (all.isEmpty) {
        setState(() {
          _error = 'No valid questions found.';
          _loading = false;
        });
        return;
      }

      all.shuffle();
      _questions = all.take(numQuestions.clamp(1, all.length)).toList();

      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load quiz: $e';
        _loading = false;
      });
    }
  }

  void _submitCurrent() async {
    final idx = _currentIndex;
    if (idx < 0 || idx >= _questions.length) return;
    if (_selectedOption[idx] == null) return;

    final question = _questions[idx];
    final selectedIdx = _selectedOption[idx]!;
    final isCorrect = question.isCorrect(selectedIdx);

    setState(() {
      _isCorrect[idx] = isCorrect;
    });

    final allAnswered = List.generate(
      _questions.length,
      (i) => _selectedOption[i] != null,
    ).every((v) => v);

    if (allAnswered && !_finished) {
      await _onQuizFinished();
    }
  }

  Future<void> _onQuizFinished() async {
    _finished = true;

    final uid = FirebaseAuth.instance.currentUser?.uid;

    final correctCount = _isCorrect.values.where((v) => v == true).length;
    final total = _questions.length;
    final scorePct = ((correctCount / total) * 100).round();

    if (uid != null) {
      final baseXp = (_activityDetail?.scoring['points'] as num?)?.toInt() ?? 10;
      await HomeMetricsService.recordActivityAttempt(
        uid: uid,
        courseId: widget.courseId,
        moduleId: widget.moduleId,
        lessonId: widget.lessonId,
        activityId: widget.activityId,
        activityType: 'quiz',
        score: scorePct.toDouble(),
        passed: scorePct >= 60,
        baseXp: baseXp,
      );
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
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
                'Quiz completed',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$correctCount / $total correct · $scorePct%',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop();
                },
                child: const Text('Back to lesson'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _goNext() {
    if (_currentIndex < _questions.length - 1) {
      setState(() => _currentIndex++);
    }
  }

  void _goPrev() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          title: const Text('Quiz'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    if (_questions.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          title: const Text('Quiz'),
        ),
        body: const Center(
          child: Text(
            'No questions found.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final q = _questions[_currentIndex];
    final selected = _selectedOption[_currentIndex];
    final checked = _isCorrect.containsKey(_currentIndex);
    final isCorrect = _isCorrect[_currentIndex] == true;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: const Text('Quiz'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Question ${_currentIndex + 1} of ${_questions.length}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: (_currentIndex + 1) / _questions.length,
                backgroundColor: AppColors.background,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
            const SizedBox(height: 16),

            // Question card
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: _cardDecor(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ActivityMedia(
                        mediaId: q.mediaId,
                        fallbackLabel: 'Tap to play',
                      ),
                      const SizedBox(height: 12),

                      Text(
                        q.stem,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 14),

                      ...List.generate(q.options.length, (i) {
                        final optionText = q.options[i];
                        final isSelected = selected == i;
                        final cs = Theme.of(context).colorScheme;

                        Color borderColor = cs.outline;
                        Color fillColor = cs.surface;
                        Color textColor = cs.onSurface;

                        if (checked) {
                          if (i == selected && isCorrect) {
                            borderColor = AppColors.success;
                            fillColor = AppColors.success.withOpacity(0.06);
                          } else if (i == selected && !isCorrect) {
                            borderColor = AppColors.error;
                            fillColor = AppColors.error.withOpacity(0.05);
                            textColor = AppColors.error;
                          } else if (q.isCorrect(i)) {
                            borderColor = AppColors.success;
                            fillColor = AppColors.success.withOpacity(0.04);
                          }
                        } else if (isSelected) {
                          borderColor = AppColors.primary;
                          fillColor = AppColors.primary.withOpacity(0.06);
                        }

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: checked
                                ? null
                                : () {
                                    setState(() {
                                      _selectedOption[_currentIndex] = i;
                                    });
                                  },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: fillColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: borderColor),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: checked
                                            ? (q.isCorrect(i)
                                                ? AppColors.success
                                                : AppColors.error)
                                            : (isSelected
                                                ? AppColors.primary
                                                : AppColors.border),
                                      ),
                                      color: isSelected
                                          ? (checked
                                              ? (q.isCorrect(i)
                                                  ? AppColors.success
                                                  : AppColors.error)
                                              : AppColors.primary)
                                          : Colors.transparent,
                                    ),
                                    child: isSelected
                                        ? Icon(
                                            Icons.check,
                                            size: 14,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onPrimary,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      optionText,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: textColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),

                      const SizedBox(height: 8),

                      if (checked)
                        _Explanation(
                          isCorrect: isCorrect,
                          explanation: q.explanation,
                        ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                if (_currentIndex > 0)
                  TextButton.icon(
                    onPressed: _goPrev,
                    icon: const Icon(Icons.chevron_left_rounded),
                    label: const Text('Previous'),
                  )
                else
                  const SizedBox(width: 0, height: 0),
                const Spacer(),
                if (!_isCorrect.containsKey(_currentIndex))
                  FilledButton(
                    onPressed: (selected == null) ? null : _submitCurrent,
                    child: const Text('Submit'),
                  )
                else if (_currentIndex < _questions.length - 1)
                  FilledButton.icon(
                    onPressed: _goNext,
                    icon: const Icon(Icons.chevron_right_rounded),
                    label: const Text('Next'),
                  )
                else
                  FilledButton(
                    onPressed: () async {
                      if (!_finished) {
                        await _onQuizFinished();
                      } else {
                        Navigator.of(context).pop();
                      }
                    },
                    child: Text(_finished ? 'Back' : 'Finish quiz'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/* =========================
   HELPERS FOR MEDIA TYPE
   ========================= */

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

/* =========================
   DATA MODEL
   ========================= */

class _QuizQuestion {
  final String id;
  final String stem;
  final List<String> options;
  final List<String> answers;
  final String? explanation;
  final String? mediaId;

  _QuizQuestion({
    required this.id,
    required this.stem,
    required this.options,
    this.answers = const [],
    this.explanation,
    this.mediaId,
  });

  static _QuizQuestion fromActivityQuestion(ActivityQuestion aq) {
    final data = aq.effectiveQuestion;
    final stem = (data['stem'] as String?) ?? 'Question';
    final options = (data['options'] as List?)
            ?.map((e) => e.toString())
            .toList()
            .cast<String>() ??
        const <String>[];

    final answers = ((data['answers'] as List?) ?? [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList();
    final singleAnswer =
        (data['answer'] ?? data['correct'] ?? data['correctAnswer']);
    if (singleAnswer != null) {
      answers.add(singleAnswer.toString());
    }

    final explanation = data['explanation'] as String?;

    final media = data['media'] as Map<String, dynamic>?;
    final mediaId = (data['mediaId'] as String?) ??
        (media?['mediaId'] as String?) ??
        (media?['id'] as String?);

    return _QuizQuestion(
      id: aq.id,
      stem: stem,
      options: options,
      answers: answers,
      explanation: explanation,
      mediaId: mediaId,
    );
  }

  bool isCorrect(int optionIndex) {
    if (answers.isEmpty) return false;
    if (optionIndex < 0 || optionIndex >= options.length) return false;

    final selected = options[optionIndex].trim().toLowerCase();
    return answers.any((a) {
      final normalized = a.trim().toLowerCase();
      final numeric = int.tryParse(normalized);
      if (numeric != null) {
        return numeric == optionIndex;
      }
      return normalized == selected;
    });
  }
}

/* =========================
   MEDIA WIDGET (Home-style)
   ========================= */

/// Home-style media renderer with **ID → Firestore** resolving.
class _ActivityMedia extends StatefulWidget {
  final Map<String, dynamic>? media; // {url/path/contentType/kind/mediaId/id}
  final String? mediaId; // config.mediaId OR root mediaId
  final String? videoId; // config.videoId (treat as mediaId)
  final String? fallbackLabel; // UI hint if nothing resolves

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

/* =========================
   EXPLANATION + DECOR
   ========================= */

class _Explanation extends StatelessWidget {
  final bool isCorrect;
  final String? explanation;

  const _Explanation({
    required this.isCorrect,
    this.explanation,
  });

  @override
  Widget build(BuildContext context) {
    final color = isCorrect ? AppColors.success : AppColors.error;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isCorrect ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              (explanation != null && explanation!.trim().isNotEmpty)
                  ? explanation!
                  : (isCorrect
                      ? 'Nice work!'
                      : 'Not quite. Review this and try the next one.'),
              style: TextStyle(
                fontSize: 12,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
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