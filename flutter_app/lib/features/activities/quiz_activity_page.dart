import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../common/theme/app_colors.dart';
import '../../common/utils/media_utils.dart';
import '../../models/content_models.dart';
import '../../services/content_api_service.dart';
import '../../services/home_metrics_service.dart';

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
    if (uid != null) {
      await HomeMetricsService.onActivityCompleted(uid);
      await HomeMetricsService.onAttemptSubmitted(uid);
    }

    if (!mounted) return;

    final correctCount = _isCorrect.values.where((v) => v == true).length;
    final total = _questions.length;
    final scorePct = ((correctCount / total) * 100).round();

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
                      _QuestionMedia(
                        imageUrl: q.imageUrl,
                        videoUrl: q.videoUrl,
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

                        Color borderColor = AppColors.border;
                        Color fillColor = Colors.white;
                        Color textColor = AppColors.textPrimary;

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
                                        ? const Icon(Icons.check,
                                        size: 14, color: Colors.white)
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
   DATA MODEL
   ========================= */

class _QuizQuestion {
  final String id;
  final String stem;
  final List<String> options;
  final List<String> answers;
  final String? explanation;
  final String? imageUrl;
  final String? videoUrl;

  _QuizQuestion({
    required this.id,
    required this.stem,
    required this.options,
    this.answers = const [],
    this.explanation,
    this.imageUrl,
    this.videoUrl,
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
    final singleAnswer = (data['answer'] ?? data['correct'] ?? data['correctAnswer']);
    if (singleAnswer != null) {
      answers.add(singleAnswer.toString());
    }

    final explanation = data['explanation'] as String?;

    String? imageUrl = publicMediaUrl(data['imageUrl'] as String?,
        path: data['imagePath'] as String?);
    String? videoUrl = publicMediaUrl(data['videoUrl'] as String?,
        path: data['videoPath'] as String?);

    final media = data['media'] as Map<String, dynamic>?;
    final mediaId = data['mediaId'] as String?;
    String? mediaUrl = publicMediaUrl(
      media?['url'] as String?,
      path: media?['path'] as String? ?? media?['storagePath'] as String?,
    );
    mediaUrl ??= publicMediaUrl(null, path: mediaId);

    bool looksVideo(String? url) {
      if (url == null) return false;
      final lower = url.toLowerCase();
      return lower.endsWith('.mp4') ||
          lower.endsWith('.mov') ||
          lower.endsWith('.webm') ||
          lower.endsWith('.mkv') ||
          lower.contains('/videos/');
    }

    if ((videoUrl == null || videoUrl.isEmpty) && looksVideo(mediaUrl)) {
      videoUrl = mediaUrl;
    }
    if ((imageUrl == null || imageUrl.isEmpty) &&
        mediaUrl != null &&
        !looksVideo(mediaUrl)) {
      imageUrl = mediaUrl;
    }

    return _QuizQuestion(
      id: aq.id,
      stem: stem,
      options: options,
      answers: answers,
      explanation: explanation,
      imageUrl: normalizeMediaUrl(imageUrl),
      videoUrl: normalizeMediaUrl(videoUrl),
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
   MEDIA WIDGET (Home style)
   ========================= */

class _QuestionMedia extends StatefulWidget {
  final String? imageUrl;
  final String? videoUrl;

  const _QuestionMedia({this.imageUrl, this.videoUrl});

  @override
  State<_QuestionMedia> createState() => _QuestionMediaState();
}

class _QuestionMediaState extends State<_QuestionMedia> {
  VideoPlayerController? _ctrl;
  bool _err = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    final url = widget.videoUrl;
    if (url == null || url.isEmpty) return;
    try {
      final c = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _ctrl = c;
      await c.initialize();
      await c.setLooping(false);
      setState(() {});
      c.addListener(() {
        if (mounted) setState(() {});
      });
    } catch (_) {
      if (mounted) setState(() => _err = true);
    }
  }

  @override
  void didUpdateWidget(covariant _QuestionMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _ctrl?.dispose();
      _ctrl = null;
      _err = false;
      _initVideo();
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  // Outer 16:9 frame used for both image and video
  Widget _frame(Widget child) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: child,
        ),
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
    final items = <Widget>[];

    // IMAGE — centered (letterboxed) inside the 16:9 frame
    if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) {
      items.add(
        _frame(
          // BoxFit.contain to avoid cropping; centered with blanks around
          Image.network(
            widget.imageUrl!,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(
              child: Text('Image failed to load',
                  style: TextStyle(fontSize: 12, color: AppColors.error)),
            ),
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            },
          ),
        ),
      );
      items.add(const SizedBox(height: 10));
    }

    // VIDEO — centered inside 16:9 frame with overlay + progress bar
    if (widget.videoUrl != null && widget.videoUrl!.isNotEmpty) {
      if (_err) {
        items.add(
          _frame(const Center(
            child: Text('Video failed to load',
                style: TextStyle(fontSize: 12, color: AppColors.error)),
          )),
        );
      } else if (_ctrl == null || !_ctrl!.value.isInitialized) {
        items.add(
          _frame(const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )),
        );
      } else {
        final ar = (_ctrl!.value.aspectRatio.isFinite && _ctrl!.value.aspectRatio > 0)
            ? _ctrl!.value.aspectRatio
            : (16 / 9);

        final dur = _ctrl!.value.duration;
        final pos = _ctrl!.value.position;
        final playing = _ctrl!.value.isPlaying;
        final ended = dur > Duration.zero && pos >= dur;

        items.add(
          _frame(
            Stack(
              children: [
                // Center the real video to its aspect ratio (letterbox)
                Center(
                  child: AspectRatio(
                    aspectRatio: ar,
                    child: VideoPlayer(_ctrl!),
                  ),
                ),

                // Play/Pause/Replay overlay — hides while playing
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
                        color: Colors.black26,
                        child: Center(
                          child: Icon(
                            ended
                                ? Icons.replay_rounded
                                : (playing
                                ? Icons.pause_circle_filled_rounded
                                : Icons.play_circle_fill_rounded),
                            size: 56,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Bottom progress bar + time
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
                            backgroundColor: Colors.black26,
                            valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_fmt(pos)} / ${_fmt(dur)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          shadows: [Shadow(blurRadius: 2, color: Colors.black)],
                        ),
                      ),
                    ],
                  ),
                ),

                // Tap anywhere to toggle during playback (while overlay hidden)
                if (playing)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        _ctrl!.pause();
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      }
    }

    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items);
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
                  : (isCorrect ? 'Nice work!' : 'Not quite. Review this and try the next one.'),
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