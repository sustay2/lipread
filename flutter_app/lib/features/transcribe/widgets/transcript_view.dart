import 'package:flutter/material.dart';

import '../../../common/theme/app_colors.dart';
import '../../../models/transcript_result.dart';

class TranscriptView extends StatelessWidget {
  final TranscriptResult result;
  const TranscriptView({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final hasWords = result.words.isNotEmpty;
    final hasVisemes = result.visemes.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.softShadow,
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(
                  Icons.subtitles_rounded,
                  size: 20,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Transcript',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Transcript box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                result.transcript.isEmpty
                    ? '(No speech detected)'
                    : result.transcript,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.4,
                  color: AppColors.textPrimary,
                ),
              ),
            ),

            // Confidence (if available)
            if (result.confidence != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.insights_outlined,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Model confidence: '
                        '${(result.confidence! * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],

            // Word timings
            if (hasWords) ...[
              const SizedBox(height: 12),
              Text(
                'Word timings',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: -6,
                children: [
                  for (final w in result.words)
                    Chip(
                      materialTapTargetSize:
                      MaterialTapTargetSize.shrinkWrap,
                      label: Text(
                        '${w.text}  '
                            '(${w.start.toStringAsFixed(2)}–'
                            '${w.end.toStringAsFixed(2)}s • '
                            '${(w.conf * 100).toStringAsFixed(0)}%)',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                ],
              ),
            ],

            // Viseme timeline
            if (hasVisemes) ...[
              const SizedBox(height: 12),
              Text(
                'Viseme timeline',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: -6,
                children: [
                  for (final v in result.visemes)
                    Chip(
                      materialTapTargetSize:
                      MaterialTapTargetSize.shrinkWrap,
                      label: Text(
                        '${v.label} '
                            '${v.start.toStringAsFixed(2)}–'
                            '${v.end.toStringAsFixed(2)}s',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}