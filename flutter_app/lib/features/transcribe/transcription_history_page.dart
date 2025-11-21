import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../common/theme/app_colors.dart';
import '../../models/transcript_result.dart';
import 'widgets/transcript_view.dart';

class TranscriptionHistoryPage extends StatelessWidget {
  const TranscriptionHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(
          child: Text(
            'You need to be signed in to view your transcriptions.',
            style: TextStyle(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final uid = user.uid;

    final stream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('transcriptions')
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('My Transcriptions'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to load transcriptions:\n${snap.error}',
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
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
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.subtitles_off_rounded,
                      size: 40,
                      color: AppColors.muted,
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
                    SizedBox(height: 6),
                    Text(
                      'Record or upload a video from the Transcribe tab\n'
                          'to see your lip-to-text history here.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d = docs[i];
              final data = d.data();

              final transcript = (data['transcript'] as String?) ?? '';
              final mode = (data['mode'] as String?) ?? 'unknown';
              final lessonId = data['lessonId'] as String?;
              final confidence =
              (data['confidence'] as num?)?.toDouble();

              final createdAtTs = data['createdAt'] as Timestamp?;
              final createdAt = createdAtTs?.toDate();

              final modeLabel = mode == 'record'
                  ? 'Recorded'
                  : mode == 'upload'
                  ? 'Uploaded'
                  : 'Transcription';

              final dateLabel = createdAt != null
                  ? '${createdAt.year.toString().padLeft(4, '0')}-'
                  '${createdAt.month.toString().padLeft(2, '0')}-'
                  '${createdAt.day.toString().padLeft(2, '0')} '
                  '${createdAt.hour.toString().padLeft(2, '0')}:'
                  '${createdAt.minute.toString().padLeft(2, '0')}'
                  : 'Unknown date';

              final preview = transcript.isEmpty
                  ? '(No speech detected)'
                  : (transcript.length > 80
                  ? '${transcript.substring(0, 80)}…'
                  : transcript);

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    // Build a TranscriptResult from stored JSON and show details.
                    final wordsRaw = (data['words'] as List?) ?? [];
                    final visemesRaw = (data['visemes'] as List?) ?? [];

                    final words = wordsRaw
                        .whereType<Map>()
                        .map((w) => WordSpan.fromJson(
                      Map<String, dynamic>.from(
                          w as Map<Object?, Object?>),
                    ))
                        .toList();

                    final visemes = visemesRaw
                        .whereType<Map>()
                        .map((v) => VisemeSpan.fromJson(
                      Map<String, dynamic>.from(
                          v as Map<Object?, Object?>),
                    ))
                        .toList();

                    final result = TranscriptResult(
                      transcript: transcript,
                      confidence: confidence,
                      words: words,
                      visemes: visemes,
                    );

                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (ctx) {
                        return DraggableScrollableSheet(
                          initialChildSize: 0.6,
                          maxChildSize: 0.9,
                          minChildSize: 0.4,
                          builder: (_, controller) {
                            return Container(
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(24),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.softShadow,
                                    blurRadius: 20,
                                    offset: const Offset(0, -8),
                                  ),
                                ],
                              ),
                              child: ListView(
                                controller: controller,
                                padding: const EdgeInsets.fromLTRB(
                                    16, 12, 16, 24),
                                children: [
                                  Center(
                                    child: Container(
                                      width: 40,
                                      height: 4,
                                      margin: const EdgeInsets.only(
                                          bottom: 10),
                                      decoration: BoxDecoration(
                                        color: AppColors.border,
                                        borderRadius:
                                        BorderRadius.circular(999),
                                      ),
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.subtitles_rounded,
                                        color: AppColors.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Transcription details',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '$modeLabel • $dateLabel'
                                        '${lessonId != null ? ' • Lesson: $lessonId' : ''}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TranscriptView(result: result),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.softShadow,
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.subtitles_rounded,
                              size: 20,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      modeLabel,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    if (confidence != null)
                                      Container(
                                        padding:
                                        const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary
                                              .withOpacity(0.08),
                                          borderRadius:
                                          BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          '${(confidence * 100).toStringAsFixed(0)}%',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  preview,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  dateLabel,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: AppColors.muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}