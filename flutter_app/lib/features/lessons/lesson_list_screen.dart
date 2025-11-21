import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../common/theme/app_colors.dart';
import '../../services/router.dart';
import '../../services/home_metrics_service.dart';
import '../../common/utils/media_utils.dart'; // normalizeMediaUrl

class LessonListScreen extends StatefulWidget {
  const LessonListScreen({super.key});

  @override
  State<LessonListScreen> createState() => _LessonListScreenState();
}

class _LessonListScreenState extends State<LessonListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _levelFilter = 'all'; // all / beginner / intermediate / advanced

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Courses stream with optional difficulty filter
  Stream<QuerySnapshot<Map<String, dynamic>>> _coursesStream() {
    Query<Map<String, dynamic>> query =
    FirebaseFirestore.instance.collection('courses');

    if (_levelFilter != 'all') {
      query = query.where('difficulty', isEqualTo: _levelFilter);
    }
    return query.snapshots();
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
      ),
      body: Column(
        children: [
          // Search + filter bar
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
                    contentPadding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
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
                      borderSide:
                      const BorderSide(color: AppColors.primary, width: 1.2),
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
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _coursesStream(),
              builder: (context, courseSnap) {
                if (courseSnap.hasError) {
                  return const Center(
                    child: Text(
                      'Failed to load courses.',
                      style: TextStyle(color: AppColors.error),
                    ),
                  );
                }

                if (courseSnap.connectionState == ConnectionState.waiting &&
                    !courseSnap.hasData) {
                  return const _CourseSkeletonList();
                }

                final docs = (courseSnap.data?.docs ?? []).where((doc) {
                  final d = doc.data();
                  if (!_isPublished(d)) return false;

                  final difficulty = d['difficulty'] as String?;
                  if (!_matchesLevel(difficulty)) return false;

                  final title = (d['title'] as String?) ?? 'Untitled course';
                  final description = (d['description'] as String?) ?? '';
                  if (!_matchesSearch(title) && !_matchesSearch(description)) {
                    return false;
                  }
                  return true;
                }).toList();

                docs.sort((a, b) {
                  final aTs = a.data()['createdAt'];
                  final bTs = b.data()['createdAt'];
                  if (aTs is Timestamp && bTs is Timestamp) {
                    return bTs.compareTo(aTs);
                  }
                  return 0;
                });

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
                    final doc = docs[index];
                    final data = doc.data();
                    final courseId = doc.id;
                    final title = (data['title'] as String?) ?? 'Untitled course';
                    final desc =
                        (data['description'] as String?) ?? 'No description.';
                    final difficulty =
                        (data['difficulty'] as String?) ?? 'beginner';

                    return _CourseExpansionCard(
                      courseId: courseId,
                      title: title,
                      description: desc,
                      level: difficulty,
                      courseData: data,
                      searchQuery: _searchQuery,
                      onLessonTap: _onLessonTap,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static bool _isPublished(Map<String, dynamic> d) {
    final p = d['published'];
    final ip = d['isPublished'];
    if (p is bool) return p;
    if (ip is bool) return ip;
    return true;
  }
}

//
// Level filter chip
//

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

//
// Course -> Modules -> Lessons Expansion
//

class _CourseExpansionCard extends StatefulWidget {
  final String courseId;
  final String title;
  final String description;
  final String level; // difficulty label
  final String searchQuery;
  final Map<String, dynamic> courseData;
  final void Function({
  required String courseId,
  required String moduleId,
  required String lessonId,
  }) onLessonTap;

  const _CourseExpansionCard({
    required this.courseId,
    required this.title,
    required this.description,
    required this.level,
    required this.searchQuery,
    required this.courseData,
    required this.onLessonTap,
  });

  @override
  State<_CourseExpansionCard> createState() => _CourseExpansionCardState();
}

class _CourseExpansionCardState extends State<_CourseExpansionCard> {
  bool _expanded = false;

  Stream<QuerySnapshot<Map<String, dynamic>>> _modulesStream() {
    return FirebaseFirestore.instance
        .collection('courses')
        .doc(widget.courseId)
        .collection('modules')
        .orderBy('order', descending: false)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _cardDecor(radius: 18),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          onExpansionChanged: (v) => setState(() => _expanded = v),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
          // 🧩 REMOVE the manual trailing icon here!
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Course media thumbnail
              _CourseMediaThumb(data: widget.courseData, height: 72),
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
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _modulesStream(),
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

                final moduleDocs = moduleSnap.data?.docs ?? [];

                if (moduleSnap.connectionState == ConnectionState.waiting &&
                    moduleDocs.isEmpty) {
                  return const _ModuleSkeletonList();
                }

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
                    final moduleId = m.id;
                    final md = m.data();
                    final moduleTitle = (md['title'] as String?) ?? 'Module';
                    final summary = (md['summary'] as String?) ?? '';

                    return _ModuleTile(
                      courseId: widget.courseId,
                      moduleId: moduleId,
                      title: moduleTitle,
                      summary: summary,
                      searchQuery: widget.searchQuery,
                      onLessonTap: widget.onLessonTap,
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

//
// Module + Lesson list (with more spacious lesson rows)
//

class _ModuleTile extends StatelessWidget {
  final String courseId;
  final String moduleId;
  final String title;
  final String summary;
  final String searchQuery;
  final void Function({
  required String courseId,
  required String moduleId,
  required String lessonId,
  }) onLessonTap;

  const _ModuleTile({
    required this.courseId,
    required this.moduleId,
    required this.title,
    required this.summary,
    required this.searchQuery,
    required this.onLessonTap,
  });

  Stream<QuerySnapshot<Map<String, dynamic>>> _lessonsStream() {
    return FirebaseFirestore.instance
        .collection('courses')
        .doc(courseId)
        .collection('modules')
        .doc(moduleId)
        .collection('lessons')
        .orderBy('order', descending: false)
        .snapshots();
  }

  bool _matches(String text) {
    if (searchQuery.trim().isEmpty) return true;
    return text.toLowerCase().contains(searchQuery.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Module header
          Row(
            children: [
              const Icon(
                Icons.folder_open_rounded,
                size: 18,
                color: AppColors.primaryVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (summary.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 4, bottom: 8),
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
          // Lessons list (spacious)
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _lessonsStream(),
            builder: (context, lessonSnap) {
              final lessonDocs = lessonSnap.data?.docs ?? [];

              if (lessonSnap.connectionState == ConnectionState.waiting &&
                  lessonDocs.isEmpty) {
                return const _LessonSkeletonList();
              }

              final filtered = lessonDocs.where((l) {
                final ld = l.data();
                final lt = (ld['title'] as String?) ?? 'Lesson';
                if (!_matches(lt)) return false;
                return true;
              }).toList();

              if (filtered.isEmpty) {
                return const SizedBox.shrink();
              }

              return Column(
                children: [
                  for (final l in filtered) ...[
                    _SpaciousLessonRow(
                      courseId: courseId,
                      moduleId: moduleId,
                      lessonDoc: l,
                      onTap: (lessonId) => onLessonTap(
                        courseId: courseId,
                        moduleId: moduleId,
                        lessonId: lessonId,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SpaciousLessonRow extends StatelessWidget {
  final String courseId;
  final String moduleId;
  final QueryDocumentSnapshot<Map<String, dynamic>> lessonDoc;
  final void Function(String lessonId) onTap;

  const _SpaciousLessonRow({
    required this.courseId,
    required this.moduleId,
    required this.lessonDoc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ld = lessonDoc.data();
    final title = (ld['title'] as String?) ?? 'Lesson';
    final est = (ld['estimatedMin'] as num?)?.toInt();

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onTap(lessonDoc.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.play_circle_outline_rounded,
              size: 22,
              color: AppColors.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (est != null) ...[
              const SizedBox(width: 10),
              Text(
                '${est}m',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

//
// Course media thumbnail (image/video) – non-interactive, letterboxed 16:9
//

class _CourseMediaThumb extends StatelessWidget {
  final Map<String, dynamic> data;
  final double height; // e.g. 72

  const _CourseMediaThumb({required this.data, required this.height});

  Future<_ResolvedMedia?> _resolveMedia() async {
    // 1) Direct string field
    final direct = (data['thumbnailUrl'] as String?);
    if (direct != null && direct.isNotEmpty) {
      final url = normalizeMediaUrl(direct);
      return _ResolvedMedia(url: url, isVideo: _looksVideo(url));
    }

    // 2) Map with `url`
    if (data['thumbnail'] is Map<String, dynamic>) {
      final m = data['thumbnail'] as Map<String, dynamic>;
      final url = normalizeMediaUrl(m['url'] as String?);
      final ct = (m['contentType'] as String?)?.toLowerCase();
      final kind = (m['kind'] as String?)?.toLowerCase();
      if (url != null && url.isNotEmpty) {
        final isVid =
            (ct?.startsWith('video/') ?? false) || kind == 'video' || _looksVideo(url);
        return _ResolvedMedia(url: url, isVideo: isVid);
      }
    }

    // 3) Media doc reference
    final mediaId = (data['mediaId'] as String?);
    if (mediaId != null && mediaId.isNotEmpty) {
      try {
        final snap =
        await FirebaseFirestore.instance.collection('media').doc(mediaId).get();
        if (snap.exists) {
          final m = snap.data() ?? {};
          final url = normalizeMediaUrl(m['url'] as String?);
          final ct = (m['contentType'] as String?)?.toLowerCase();
          final kind = (m['kind'] as String?)?.toLowerCase();
          if (url != null && url.isNotEmpty) {
            final isVid =
                (ct?.startsWith('video/') ?? false) || kind == 'video' || _looksVideo(url);
            return _ResolvedMedia(url: url, isVideo: isVid);
          }
        }
      } catch (_) {/* ignore */}
    }

    return null;
  }

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

    return FutureBuilder<_ResolvedMedia?>(
      future: _resolveMedia(),
      builder: (context, snap) {
        final media = snap.data;

        if (snap.connectionState == ConnectionState.waiting && media == null) {
          return _frame(width, height, const SizedBox());
        }

        if (media == null || media.url == null || media.url!.isEmpty) {
          return _frame(
            width,
            height,
            const Center(
              child: Icon(Icons.play_circle_outline_rounded,
                  color: AppColors.muted, size: 28),
            ),
          );
        }

        if (media.isVideo) {
          return _CourseVideoThumb(url: media.url!, height: height, width: width);
        } else {
          return _frame(
            width,
            height,
            Image.network(media.url!, fit: BoxFit.cover),
          );
        }
      },
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

/// Non-interactive: shows first frame, letterboxed; keeps play glyph visible.
class _CourseVideoThumbState extends State<_CourseVideoThumb> {
  VideoPlayerController? _ctrl;
  bool _err = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _ctrl = c;
      await c.initialize();
      if (!mounted) return;
      await c.setLooping(false);
      setState(() {});
    } catch (_) {
      if (mounted) setState(() => _err = true);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_err) {
      return _CourseMediaThumb._frame(
        widget.width,
        widget.height,
        const Center(
          child: Text('Video failed',
              style: TextStyle(fontSize: 10, color: AppColors.error)),
        ),
      );
    }

    final c = _ctrl;
    if (c == null || !c.value.isInitialized) {
      return _CourseMediaThumb._frame(
        widget.width,
        widget.height,
        const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final ar = (c.value.aspectRatio.isFinite && c.value.aspectRatio > 0)
        ? c.value.aspectRatio
        : 16 / 9;

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // Center the real AR inside the fixed 16:9 frame (letterbox)
            Positioned.fill(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  child: SizedBox(
                    height: widget.height,
                    width: widget.height * ar,
                    child: VideoPlayer(c),
                  ),
                ),
              ),
            ),
            // keep play glyph (non-interactive thumbnail)
            const IgnorePointer(
              ignoring: true,
              child: Center(
                child: Icon(Icons.play_circle_fill_rounded,
                    size: 28, color: Colors.white),
              ),
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
  const _ResolvedMedia({required this.url, required this.isVideo});
}

//
// Skeletons + shared decor
//

class _CourseSkeletonList extends StatelessWidget {
  const _CourseSkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: 3,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => Container(
        height: 96,
        decoration: _cardDecor(radius: 18),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 128,
              decoration: BoxDecoration(
                color: const Color(0xFFE9EEF7),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 16, width: 160, decoration: _shimmerBox()),
                  const SizedBox(height: 8),
                  Container(height: 12, width: 220, decoration: _shimmerBox()),
                ],
              ),
            ),
          ],
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
      children: List.generate(
        2,
            (i) => Padding(
          padding: const EdgeInsets.only(left: 26, right: 8, top: 4, bottom: 4),
          child: Container(height: 14, decoration: _shimmerBox()),
        ),
      ),
    );
  }
}

class _LessonSkeletonList extends StatelessWidget {
  const _LessonSkeletonList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        2,
            (i) => Padding(
          padding: const EdgeInsets.only(left: 26, right: 8, top: 6, bottom: 6),
          child: Container(height: 14, decoration: _shimmerBox()),
        ),
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
        blurRadius: 16,
        offset: const Offset(0, 6),
      ),
    ],
  );
}

BoxDecoration _shimmerBox() {
  return BoxDecoration(
    color: const Color(0xFFE9EEF7),
    borderRadius: BorderRadius.circular(8),
  );
}