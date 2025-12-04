import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../common/theme/app_colors.dart';
import '../../common/utils/media_utils.dart';
import '../../models/content_models.dart';
import '../../services/content_api_service.dart';
import '../../services/home_metrics_service.dart';
import '../../services/router.dart';
import '../../services/subscription_service.dart';

class LessonListScreen extends StatefulWidget {
  const LessonListScreen({super.key});

  @override
  State<LessonListScreen> createState() => _LessonListScreenState();
}

class _LessonListScreenState extends State<LessonListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ContentApiService _contentApi = ContentApiService();
  final SubscriptionService _subscriptionService = SubscriptionService();

  Future<List<Course>>? _coursesFuture;
  Future<UserSubscription?>? _subscriptionFuture;
  String _searchQuery = '';
  String _levelFilter = 'all'; // all / beginner / intermediate / advanced

  @override
  void initState() {
    super.initState();
    _coursesFuture = _contentApi.fetchCourses();
    _subscriptionFuture = _loadSubscription();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final coursesFuture = _contentApi.fetchCourses();
    final subscriptionFuture = _loadSubscription();
    setState(() {
      _coursesFuture = coursesFuture;
      _subscriptionFuture = subscriptionFuture;
    });
    await Future.wait([coursesFuture, subscriptionFuture]);
  }

  Future<UserSubscription?> _loadSubscription() async {
    try {
      return await _subscriptionService.getMySubscription();
    } catch (e) {
      debugPrint('Failed to load subscription: $e');
      return null;
    }
  }

  void _onLessonTap({
    required String courseId,
    required String moduleId,
    required String lessonId,
  }) {
    final encodedId = '$courseId|$moduleId|$lessonId';

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      HomeMetricsService.updateEnrollmentProgress(
        uid: uid,
        courseId: courseId,
        lastLessonId: encodedId,
        progress: 0,
      );
    }

    Navigator.pushNamed(
      context,
      Routes.lessonDetail,
      arguments: LessonDetailArgs(encodedId),
    );
  }

  bool _matchesSearch(String text) {
    if (_searchQuery.trim().isEmpty) return true;
    return text.toLowerCase().contains(_searchQuery.toLowerCase());
  }

  bool _matchesLevel(String? difficulty) {
    if (_levelFilter == 'all') return true;
    if (difficulty == null) return false;
    return difficulty.toLowerCase() == _levelFilter;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Lessons'),
        centerTitle: true,
        backgroundColor: AppColors.background,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Lesson Attempts',
            onPressed: () => Navigator.pushNamed(context, Routes.results),
            icon: const Icon(Icons.insights_outlined),
          ),
        ],
      ),
      body: FutureBuilder<UserSubscription?>(
        future: _subscriptionFuture,
        builder: (context, subSnap) {
          final subscription = subSnap.data;
          final hasPremiumAccess =
              subscription?.plan?.canAccessPremiumCourses ?? false;
          final checkingAccess = subSnap.connectionState == ConnectionState.waiting;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchCtrl,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search courses, modules, lessons...',
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: AppColors.primary,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppColors.border, width: 1),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppColors.border, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: AppColors.primary, width: 1.2),
                        ),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v.trim()),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 34,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _LevelChip(
                            label: 'All levels',
                            value: 'all',
                            groupValue: _levelFilter,
                            onSelected: (v) => setState(() => _levelFilter = v),
                          ),
                          const SizedBox(width: 6),
                          _LevelChip(
                            label: 'Beginner',
                            value: 'beginner',
                            groupValue: _levelFilter,
                            onSelected: (v) => setState(() => _levelFilter = v),
                          ),
                          const SizedBox(width: 6),
                          _LevelChip(
                            label: 'Intermediate',
                            value: 'intermediate',
                            groupValue: _levelFilter,
                            onSelected: (v) => setState(() => _levelFilter = v),
                          ),
                          const SizedBox(width: 6),
                          _LevelChip(
                            label: 'Advanced',
                            value: 'advanced',
                            groupValue: _levelFilter,
                            onSelected: (v) => setState(() => _levelFilter = v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: FutureBuilder<List<Course>>(
                    future: _coursesFuture,
                    builder: (context, courseSnap) {
                      if (courseSnap.hasError) {
                        return const Center(
                          child: Text(
                            'Failed to load courses.',
                            style: TextStyle(color: AppColors.error),
                          ),
                        );
                      }

                      if (courseSnap.connectionState == ConnectionState.waiting) {
                        return const _CourseSkeletonList();
                      }

                      final docs = (courseSnap.data ?? [])
                          .where((c) => _isPublished(c))
                          .where((c) => _matchesLevel(c.level))
                          .where((c) {
                        final title = c.title ?? 'Untitled course';
                        final description = c.description ?? '';
                        return _matchesSearch(title) ||
                            _matchesSearch(description);
                      }).toList();

                      if (docs.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'No lessons found.\nTry a different keyword or filter.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final course = docs[index];
                          final title = course.title ?? 'Untitled course';
                          final desc = course.description ?? 'No description.';
                          final difficulty = course.level ?? 'beginner';

                          return _CourseExpansionCard(
                            course: course,
                            title: title,
                            description: desc,
                            level: difficulty,
                            searchQuery: _searchQuery,
                            contentApi: _contentApi,
                            onLessonTap: _onLessonTap,
                            hasPremiumAccess: hasPremiumAccess,
                            checkingAccess: checkingAccess,
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static bool _isPublished(Course c) => c.published;
}

class _LevelChip extends StatelessWidget {
  final String label;
  final String value;
  final String groupValue;
  final ValueChanged<String> onSelected;

  const _LevelChip({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final bool selected = value == groupValue;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => onSelected(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected)
              const Icon(Icons.check, size: 14, color: AppColors.primary),
            if (selected) const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CourseExpansionCard extends StatefulWidget {
  final Course course;
  final String title;
  final String description;
  final String level;
  final String searchQuery;
  final ContentApiService contentApi;
  final bool hasPremiumAccess;
  final bool checkingAccess;
  final void Function({
    required String courseId,
    required String moduleId,
    required String lessonId,
  }) onLessonTap;

  const _CourseExpansionCard({
    required this.course,
    required this.title,
    required this.description,
    required this.level,
    required this.searchQuery,
    required this.contentApi,
    required this.hasPremiumAccess,
    required this.checkingAccess,
    required this.onLessonTap,
  });

  @override
  State<_CourseExpansionCard> createState() => _CourseExpansionCardState();
}

class _CourseExpansionCardState extends State<_CourseExpansionCard> {
  bool _expanded = false;
  Future<List<Module>>? _modulesFuture;

  void _ensureModules() {
    _modulesFuture ??= widget.contentApi.fetchModules(widget.course.id);
  }

  @override
  Widget build(BuildContext context) {
    final isPremiumCourse = widget.course.isPremium;
    final showOverlay =
        isPremiumCourse && (!widget.hasPremiumAccess || widget.checkingAccess);

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            decoration: _cardDecor(radius: 18),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: false,
                onExpansionChanged: (v) {
                  setState(() => _expanded = v);
                  if (v) _ensureModules();
                },
                tilePadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                title: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CourseMediaThumb(
                        url: widget.course.resolvedThumbnailUrl, height: 72),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.flag_outlined,
                                size: 14,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                widget.level,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              if (isPremiumCourse) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: const Text(
                                    'Premium',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                children: [
                  if (_modulesFuture == null && !_expanded)
                    const SizedBox.shrink()
                  else
                    FutureBuilder<List<Module>>(
                      future: _modulesFuture,
                      builder: (context, moduleSnap) {
                        if (moduleSnap.hasError) {
                          return const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Text(
                              'Failed to load modules.',
                              style: TextStyle(
                                color: AppColors.error,
                                fontSize: 12,
                              ),
                            ),
                          );
                        }

                        if (moduleSnap.connectionState == ConnectionState.waiting) {
                          return const _ModuleSkeletonList();
                        }

                        final moduleDocs = moduleSnap.data ?? [];

                        if (moduleDocs.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Text(
                              'No modules yet.',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          );
                        }

                        return Column(
                          children: moduleDocs.map((m) {
                            final moduleTitle = m.title ?? 'Module';
                            final summary = m.summary ?? '';

                            return _ModuleTile(
                              courseId: widget.course.id,
                              module: m,
                              title: moduleTitle,
                              summary: summary,
                              searchQuery: widget.searchQuery,
                              contentApi: widget.contentApi,
                              onLessonTap: widget.onLessonTap,
                            );
                          }).toList(),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
        if (showOverlay)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: _PremiumOverlay(
                isLoading: widget.checkingAccess,
                onTap: () => Navigator.pushNamed(context, Routes.subscription),
              ),
            ),
          ),
      ],
    );
  }
}

class _PremiumOverlay extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;

  const _PremiumOverlay({
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
          child: Container(color: Colors.grey.withOpacity(0.4)),
        ),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, color: Colors.white, size: 40),
                  const SizedBox(height: 8),
                  const Text(
                    'This is premium content',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isLoading ? 'Checking access...' : 'Upgrade to access',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
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

class _ModuleTile extends StatelessWidget {
  final String courseId;
  final Module module;
  final String title;
  final String summary;
  final String searchQuery;
  final ContentApiService contentApi;
  final void Function({
    required String courseId,
    required String moduleId,
    required String lessonId,
  }) onLessonTap;

  const _ModuleTile({
    required this.courseId,
    required this.module,
    required this.title,
    required this.summary,
    required this.searchQuery,
    required this.contentApi,
    required this.onLessonTap,
  });

  bool _matchesSearch(String text) {
    if (searchQuery.trim().isEmpty) return true;
    return text.toLowerCase().contains(searchQuery.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.view_module_outlined,
                      color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (summary.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              summary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            FutureBuilder<List<Lesson>>(
              future: contentApi.fetchLessons(courseId, module.id),
              builder: (context, lessonSnap) {
                if (lessonSnap.hasError) {
                  return const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Text(
                      'Failed to load lessons.',
                      style: TextStyle(color: AppColors.error, fontSize: 12),
                    ),
                  );
                }

                if (lessonSnap.connectionState == ConnectionState.waiting) {
                  return const _LessonSkeletonList();
                }

                final lessonDocs = (lessonSnap.data ?? [])
                    .where((l) => _matchesSearch(l.title ?? ''))
                    .toList();

                if (lessonDocs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Text(
                      'No lessons yet.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  );
                }

                return Column(
                  children: lessonDocs.map((l) {
                    final label = l.title ?? 'Lesson';
                    return InkWell(
                      onTap: () => onLessonTap(
                        courseId: courseId,
                        moduleId: module.id,
                        lessonId: l.id,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.menu_book_outlined,
                                size: 18, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    label,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${l.estimatedMin} mins · ${l.objectives.isNotEmpty ? l.objectives.first : 'Lipreading practice'}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded,
                                color: AppColors.textSecondary),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ResolvedMedia {
  final String? url;
  final bool isVideo;
  const _ResolvedMedia({this.url, this.isVideo = false});
}

class _CourseMediaThumb extends StatelessWidget {
  final String? url;
  final double height;

  const _CourseMediaThumb({required this.url, required this.height});

  static bool _looksVideo(String? url) {
    if (url == null) return false;
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mkv') ||
        lower.contains('/videos/');
  }

  @override
  Widget build(BuildContext context) {
    final width = height * (16 / 9);
    final resolved = url != null && url!.isNotEmpty
        ? _ResolvedMedia(url: normalizeMediaUrl(url), isVideo: _looksVideo(url))
        : const _ResolvedMedia();

    if (resolved.url == null || resolved.url!.isEmpty) {
      return _frame(
        width,
        height,
        const Center(
          child: Icon(Icons.play_circle_outline_rounded,
              color: AppColors.muted, size: 28),
        ),
      );
    }

    if (resolved.isVideo) {
      return _CourseVideoThumb(url: resolved.url!, height: height, width: width);
    }

    return _frame(
      width,
      height,
      Image.network(resolved.url!, fit: BoxFit.cover),
    );
  }

  static Widget _frame(double width, double height, Widget child) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(aspectRatio: 16 / 9, child: child),
      ),
    );
  }
}

class _CourseVideoThumb extends StatefulWidget {
  final String url;
  final double height;
  final double width;

  const _CourseVideoThumb({
    required this.url,
    required this.height,
    required this.width,
  });

  @override
  State<_CourseVideoThumb> createState() => _CourseVideoThumbState();
}

class _CourseVideoThumbState extends State<_CourseVideoThumb> {
  VideoPlayerController? _ctrl;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      await c.setLooping(true);
      c.setVolume(0);
      c.play();
      if (!mounted) return;
      setState(() => _ctrl = c);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error || _ctrl == null || !_ctrl!.value.isInitialized) {
      return _CourseMediaThumb._frame(
        widget.width,
        widget.height,
        const SizedBox(),
      );
    }

    return _CourseMediaThumb._frame(
      widget.width,
      widget.height,
      VideoPlayer(_ctrl!),
    );
  }
}

class _CourseSkeletonList extends StatelessWidget {
  const _CourseSkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: 3,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => Container(
        height: 96,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
      ),
    );
  }
}

class _ModuleSkeletonList extends StatelessWidget {
  const _ModuleSkeletonList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(2, (i) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Container(
            height: 88,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
          ),
        );
      }),
    );
  }
}

class _LessonSkeletonList extends StatelessWidget {
  const _LessonSkeletonList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(3, (i) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          alignment: Alignment.centerLeft,
          child: Container(
            height: 14,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }),
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
