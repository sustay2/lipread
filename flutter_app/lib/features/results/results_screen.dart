import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../common/theme/app_colors.dart';

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Please sign in to view your results.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          centerTitle: true,
          title: const Text('My progress'),
          bottom: const TabBar(
            isScrollable: false,
            tabs: [
              Tab(text: 'Attempts'),
              Tab(text: 'Transcriptions'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _AttemptsTab(uid: uid),
            _TranscriptionsTab(uid: uid),
          ],
        ),
      ),
    );
  }
}

// =======================================================
// TAB 1: Attempts (quizzes / activities / results)
// =======================================================

class _AttemptsTab extends StatelessWidget {
  final String uid;

  const _AttemptsTab({required this.uid});

  @override
  Widget build(BuildContext context) {
    final attemptsQuery = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('attempts')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: attemptsQuery,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Failed to load results:\n${snap.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.error,
                  fontSize: 12,
                ),
              ),
            ),
          );
        }

        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(
                    Icons.insights_outlined,
                    size: 40,
                    color: AppColors.textSecondary,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'No attempts yet',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Complete activities and quizzes to see your progress here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // -------- Compute summary stats --------
        int total = docs.length;
        double sumScore = 0;
        int passedCount = 0;

        for (final d in docs) {
          final data = d.data();
          final rawScore = (data['score'] as num?)?.toDouble() ?? 0.0;
          final normalizedScore =
          rawScore <= 1.0 ? rawScore * 100.0 : rawScore;
          sumScore += normalizedScore;
          final passed = data['passed'] == true;
          if (passed) passedCount++;
        }

        final avgScore = total > 0 ? sumScore / total : 0.0;
        final passRate = total > 0 ? (passedCount / total) * 100.0 : 0.0;

        // -------- Group attempts by date (YYYY-MM-DD) --------
        final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
        byDate = {};

        for (final d in docs) {
          final data = d.data();
          DateTime created = DateTime.now();
          if (data['createdAt'] is Timestamp) {
            created = (data['createdAt'] as Timestamp).toDate();
          }
          final key =
              '${created.year.toString().padLeft(4, '0')}-${created.month.toString().padLeft(2, '0')}-${created.day.toString().padLeft(2, '0')}';

          byDate.putIfAbsent(key, () => []).add(d);
        }

        final dateKeys = byDate.keys.toList()
          ..sort((a, b) => b.compareTo(a)); // newest date first

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _SummaryCard(
              totalAttempts: total,
              avgScore: avgScore,
              passRate: passRate,
            ),
            const SizedBox(height: 16),
            ...dateKeys.map((dateKey) {
              final attempts = byDate[dateKey]!;
              final parsed = DateTime.tryParse(dateKey);
              final label = _formatDateLabel(parsed);

              return Column(
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
                  const SizedBox(height: 8),
                  ...attempts.map((d) => _AttemptTile(doc: d)),
                  const SizedBox(height: 16),
                ],
              );
            }),
          ],
        );
      },
    );
  }

  String _formatDateLabel(DateTime? date) {
    if (date == null) return 'Unknown date';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    final diff = today.difference(d).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final m = months[date.month - 1];
    return '${date.day} $m ${date.year}';
  }
}

// =============================
// Summary Card (Attempts Tab)
// =============================

class _SummaryCard extends StatelessWidget {
  final int totalAttempts;
  final double avgScore;
  final double passRate;

  const _SummaryCard({
    required this.totalAttempts,
    required this.avgScore,
    required this.passRate,
  });

  @override
  Widget build(BuildContext context) {
    final avgStr = avgScore.isNaN ? '0' : avgScore.toStringAsFixed(1);
    final passStr = passRate.isNaN ? '0' : passRate.toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.softShadow,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          _SummaryItem(
            label: 'Attempts',
            value: '$totalAttempts',
            icon: Icons.play_circle_outline_rounded,
          ),
          const SizedBox(width: 12),
          _SummaryItem(
            label: 'Avg. score',
            value: '$avgStr%',
            icon: Icons.analytics_outlined,
          ),
          const SizedBox(width: 12),
          _SummaryItem(
            label: 'Pass rate',
            value: '$passStr%',
            icon: Icons.emoji_events_outlined,
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SummaryItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: AppColors.primaryVariant,
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================
// Attempt Tile
// =============================

class _AttemptTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  const _AttemptTile({required this.doc});

  @override
  Widget build(BuildContext context) {
    final data = doc.data();

    final activityType = (data['activityType'] as String?) ?? 'activity';
    final courseId = (data['courseId'] as String?) ?? '';
    final lessonId = (data['lessonId'] as String?) ?? '';
    final scoreRaw = (data['score'] as num?)?.toDouble() ?? 0.0;
    final passed = data['passed'] == true;

    final ts = data['createdAt'] as Timestamp?;
    final createdAt = ts?.toDate();
    final timeLabel = createdAt != null
        ? '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}'
        : '--:--';

    final normalizedScore =
    scoreRaw <= 1.0 ? scoreRaw * 100.0 : scoreRaw; // handle 0–1 or 0–100
    final scoreStr = '${normalizedScore.toStringAsFixed(1)}%';

    final icon = _iconForType(activityType);
    final typeLabel = _labelForType(activityType);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(
              icon,
              color: AppColors.primaryVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Line 1: type + score chip
                Row(
                  children: [
                    Text(
                      typeLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _ScoreChip(
                      score: normalizedScore,
                      passed: passed,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Line 2: course/lesson IDs
                Text(
                  _buildSubtitle(courseId, lessonId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                // Line 3: time
                Text(
                  'Completed at $timeLabel',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            scoreStr,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: passed ? AppColors.success : AppColors.error,
            ),
          ),
        ],
      ),
    );
  }

  String _buildSubtitle(String courseId, String lessonId) {
    if (courseId.isEmpty && lessonId.isEmpty) {
      return 'Unknown course / lesson';
    }
    if (courseId.isEmpty) {
      return 'Lesson: $lessonId';
    }
    if (lessonId.isEmpty) {
      return 'Course: $courseId';
    }
    return 'Course: $courseId · Lesson: $lessonId';
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'quiz':
        return Icons.quiz_rounded;
      case 'transcribe':
      case 'lip_read':
        return Icons.mic_rounded;
      case 'listen':
        return Icons.headphones_rounded;
      default:
        return Icons.task_alt_rounded;
    }
  }

  String _labelForType(String type) {
    switch (type) {
      case 'quiz':
        return 'Quiz';
      case 'transcribe':
      case 'lip_read':
        return 'Transcription';
      case 'listen':
        return 'Listening';
      default:
        return 'Activity';
    }
  }
}

class _ScoreChip extends StatelessWidget {
  final double score;
  final bool passed;

  const _ScoreChip({
    required this.score,
    required this.passed,
  });

  @override
  Widget build(BuildContext context) {
    final color = passed ? AppColors.success : AppColors.error;
    final bg = passed
        ? AppColors.success.withOpacity(0.06)
        : AppColors.error.withOpacity(0.06);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            passed ? Icons.check_circle_rounded : Icons.close_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            passed ? 'Passed' : 'Failed',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// =======================================================
// TAB 2: Transcription history (lip-to-text only)
// =======================================================

class _TranscriptionsTab extends StatelessWidget {
  final String uid;

  const _TranscriptionsTab({required this.uid});

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('transcriptions') // adjust if needed
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Failed to load transcriptions:\n${snap.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.error,
                  fontSize: 12,
                ),
              ),
            ),
          );
        }

        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(
                    Icons.record_voice_over_outlined,
                    size: 40,
                    color: AppColors.textSecondary,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'No transcriptions yet',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Use the lip transcription screen to record or upload a clip.\nYour results will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Optional summary: total, avg words, avg latency
        int total = docs.length;
        double avgLen = 0;
        double avgLatency = 0;
        int latencyCount = 0;

        for (final d in docs) {
          final data = d.data();
          final t = (data['transcript'] as String?) ?? '';
          avgLen += t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

          final lat = (data['latencyMs'] as num?)?.toDouble();
          if (lat != null) {
            avgLatency += lat;
            latencyCount++;
          }
        }

        if (total > 0) avgLen /= total;
        if (latencyCount > 0) avgLatency /= latencyCount;

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: docs.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _TranscriptionSummaryCard(
                total: total,
                avgWords: avgLen,
                avgLatencyMs: avgLatency,
              );
            }

            final doc = docs[index - 1];
            return _TranscriptionTile(doc: doc);
          },
        );
      },
    );
  }
}

// ---------- Transcription summary card ----------

class _TranscriptionSummaryCard extends StatelessWidget {
  final int total;
  final double avgWords;
  final double avgLatencyMs;

  const _TranscriptionSummaryCard({
    required this.total,
    required this.avgWords,
    required this.avgLatencyMs,
  });

  @override
  Widget build(BuildContext context) {
    final avgWordsStr = avgWords.isNaN ? '0' : avgWords.toStringAsFixed(1);
    final avgLatencyStr = avgLatencyMs.isNaN
        ? '—'
        : '${(avgLatencyMs / 1000).toStringAsFixed(2)}s';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.softShadow,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          _SummaryItem(
            label: 'Transcripts',
            value: '$total',
            icon: Icons.mic_rounded,
          ),
          const SizedBox(width: 12),
          _SummaryItem(
            label: 'Avg. words',
            value: avgWordsStr,
            icon: Icons.text_snippet_outlined,
          ),
          const SizedBox(width: 12),
          _SummaryItem(
            label: 'Avg. latency',
            value: avgLatencyStr,
            icon: Icons.speed_rounded,
          ),
        ],
      ),
    );
  }
}

// ---------- Individual transcription tile ----------

class _TranscriptionTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  const _TranscriptionTile({required this.doc});

  @override
  Widget build(BuildContext context) {
    final data = doc.data();

    final transcript = (data['transcript'] as String?) ?? '';
    final lessonId = (data['lessonId'] as String?) ?? '';
    final backend = (data['backend'] as String?) ?? '';
    final source = (data['source'] as String?) ?? ''; // 'record' / 'upload'

    final latencyMs = (data['latencyMs'] as num?)?.toDouble();
    final latencyLabel = latencyMs != null
        ? '${(latencyMs / 1000).toStringAsFixed(2)}s'
        : '—';

    final ts = data['createdAt'] as Timestamp?;
    DateTime? dt = ts?.toDate();
    final dateLabel = dt != null
        ? '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}'
        : 'Unknown date';
    final timeLabel = dt != null
        ? '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
        : '--:--';

    final wordsCount = transcript
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;

    final icon = source == 'upload'
        ? Icons.cloud_upload_rounded
        : Icons.videocam_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: icon + date/time + source
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Icon(
                  icon,
                  color: AppColors.primaryVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$dateLabel · $timeLabel',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lessonId.isNotEmpty
                          ? 'Linked lesson: $lessonId'
                          : 'Standalone transcription',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$wordsCount words',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    latencyLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Transcript text
          Text(
            transcript.isEmpty ? 'No transcript text.' : transcript,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textPrimary,
            ),
          ),

          const SizedBox(height: 8),

          // Backend/source chips
          Wrap(
            spacing: 6,
            children: [
              if (backend.isNotEmpty)
                _ChipTag(
                  icon: Icons.memory_rounded,
                  label: backend.toUpperCase(),
                ),
              if (source.isNotEmpty)
                _ChipTag(
                  icon: source == 'upload'
                      ? Icons.cloud_upload_rounded
                      : Icons.videocam_rounded,
                  label: source == 'upload' ? 'Upload' : 'Real-time',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChipTag extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ChipTag({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.muted),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}