import 'dart:convert';

import '../common/utils/media_utils.dart';

class Course {
  final String id;
  final String? title;
  final String? slug;
  final String? level;
  final String? description;
  final List<String> tags;
  final String? thumbnailPath;
  final String? thumbnailUrl;
  final Map<String, dynamic>? thumbnail;
  final String? mediaId;
  final bool published;
  final int? version;
  final dynamic createdAt;
  final dynamic updatedAt;

  Course({
    required this.id,
    this.title,
    this.slug,
    this.level,
    this.description,
    this.tags = const [],
    this.thumbnailPath,
    this.thumbnailUrl,
    this.thumbnail,
    this.mediaId,
    this.published = false,
    this.version,
    this.createdAt,
    this.updatedAt,
  });

  factory Course.fromJson(Map<String, dynamic> json) {
    final publishedRaw = json['published'];
    return Course(
      id: json['id'] as String,
      title: json['title'] as String?,
      slug: json['slug'] as String?,
      level: json['level'] as String?,
      description: json['description'] as String?,
      tags: (json['tags'] as List?)?.cast<String>() ?? const [],
      thumbnailPath: json['thumbnailPath'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      thumbnail: json['thumbnail'] is Map<String, dynamic>
          ? json['thumbnail'] as Map<String, dynamic>
          : null,
      mediaId: json['mediaId'] as String?,
      published: publishedRaw is bool ? publishedRaw : true,
      version: (json['version'] as num?)?.toInt(),
      createdAt: json['createdAt'],
      updatedAt: json['updatedAt'],
    );
  }

  String? get resolvedThumbnailUrl {
    // 1) Direct URLs from Firestore/FastAPI
    final direct = thumbnailUrl ?? (thumbnail?['url'] as String?);
    final normalized = publicMediaUrl(direct);
    if (normalized != null) return normalized;

    // 2) Relative path fields
    final path = thumbnailPath ?? (thumbnail?['path'] as String?);
    final fromPath = publicMediaUrl(null, path: path);
    if (fromPath != null) return fromPath;

    // 3) mediaId is carried through so the app can resolve elsewhere if needed
    return null;
  }
}

class Module {
  final String id;
  final String courseId;
  final String? title;
  final String? summary;
  final int order;
  final bool isArchived;
  final dynamic createdAt;
  final dynamic updatedAt;

  Module({
    required this.id,
    required this.courseId,
    required this.title,
    required this.summary,
    required this.order,
    this.isArchived = false,
    this.createdAt,
    this.updatedAt,
  });

  factory Module.fromJson(Map<String, dynamic> json) {
    return Module(
      id: json['id'] as String,
      courseId: json['courseId'] as String,
      title: json['title'] as String?,
      summary: json['summary'] as String?,
      order: (json['order'] as num?)?.toInt() ?? 0,
      isArchived: json['isArchived'] == true,
      createdAt: json['createdAt'],
      updatedAt: json['updatedAt'],
    );
  }
}

class Lesson {
  final String id;
  final String courseId;
  final String moduleId;
  final String? title;
  final int order;
  final List<String> objectives;
  final int estimatedMin;
  final bool isArchived;
  final dynamic createdAt;
  final dynamic updatedAt;

  Lesson({
    required this.id,
    required this.courseId,
    required this.moduleId,
    required this.title,
    required this.order,
    required this.objectives,
    required this.estimatedMin,
    this.isArchived = false,
    this.createdAt,
    this.updatedAt,
  });

  factory Lesson.fromJson(Map<String, dynamic> json) {
    return Lesson(
      id: json['id'] as String,
      courseId: json['courseId'] as String,
      moduleId: json['moduleId'] as String,
      title: json['title'] as String?,
      order: (json['order'] as num?)?.toInt() ?? 0,
      objectives: (json['objectives'] as List?)?.cast<String>() ?? const [],
      estimatedMin: (json['estimatedMin'] as num?)?.toInt() ?? 5,
      isArchived: json['isArchived'] == true,
      createdAt: json['createdAt'],
      updatedAt: json['updatedAt'],
    );
  }
}

class ActivitySummary {
  final String id;
  final String? title;
  final String type;
  final int order;
  final Map<String, dynamic> config;
  final Map<String, dynamic> scoring;
  final int itemCount;
  final String? questionBankId;
  final dynamic createdAt;
  final dynamic updatedAt;

  ActivitySummary({
    required this.id,
    required this.title,
    required this.type,
    required this.order,
    required this.config,
    required this.scoring,
    required this.itemCount,
    this.questionBankId,
    this.createdAt,
    this.updatedAt,
  });

  factory ActivitySummary.fromJson(Map<String, dynamic> json) {
    return ActivitySummary(
      id: json['id'] as String,
      title: json['title'] as String?,
      type: (json['type'] as String?) ?? 'activity',
      order: (json['order'] as num?)?.toInt() ?? 0,
      config: (json['config'] is Map)
          ? Map<String, dynamic>.from(json['config'] as Map)
          : <String, dynamic>{},
      scoring: (json['scoring'] is Map)
          ? Map<String, dynamic>.from(json['scoring'] as Map)
          : <String, dynamic>{},
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
      questionBankId: json['questionBankId'] as String?,
      createdAt: json['createdAt'],
      updatedAt: json['updatedAt'],
    );
  }
}

class ActivityQuestion {
  final String id;
  final String? questionId;
  final String? bankId;
  final String mode;
  final int order;
  final Map<String, dynamic>? data;
  final Map<String, dynamic>? resolvedQuestion;

  ActivityQuestion({
    required this.id,
    required this.questionId,
    required this.bankId,
    required this.mode,
    required this.order,
    this.data,
    this.resolvedQuestion,
  });

  factory ActivityQuestion.fromJson(Map<String, dynamic> json) {
    return ActivityQuestion(
      id: json['id'] as String,
      questionId: json['questionId'] as String?,
      bankId: json['bankId'] as String?,
      mode: (json['mode'] as String?) ?? 'reference',
      order: (json['order'] as num?)?.toInt() ?? 0,
      data: json['data'] is Map<String, dynamic> ? json['data'] as Map<String, dynamic> : null,
      resolvedQuestion: json['resolvedQuestion'] is Map<String, dynamic>
          ? json['resolvedQuestion'] as Map<String, dynamic>
          : null,
    );
  }

  Map<String, dynamic> get effectiveQuestion => resolvedQuestion ?? data ?? {};
}

class DictationItem {
  final String id;
  final String correctText;
  final String? mediaId;
  final String? hints;
  final int order;

  DictationItem({
    required this.id,
    required this.correctText,
    required this.mediaId,
    required this.hints,
    required this.order,
  });

  factory DictationItem.fromJson(Map<String, dynamic> json) {
    return DictationItem(
      id: json['id'] as String,
      correctText: (json['correctText'] as String?) ?? '',
      mediaId: json['mediaId'] as String?,
      hints: json['hints'] as String?,
      order: (json['order'] as num?)?.toInt() ?? 0,
    );
  }
}

class PracticeItem {
  final String id;
  final String description;
  final String? targetWord;
  final String? mediaId;
  final int order;

  PracticeItem({
    required this.id,
    required this.description,
    required this.targetWord,
    required this.mediaId,
    required this.order,
  });

  factory PracticeItem.fromJson(Map<String, dynamic> json) {
    return PracticeItem(
      id: json['id'] as String,
      description: (json['description'] as String?) ?? '',
      targetWord: json['targetWord'] as String?,
      mediaId: json['mediaId'] as String?,
      order: (json['order'] as num?)?.toInt() ?? 0,
    );
  }
}

class ActivityDetail extends ActivitySummary {
  final List<ActivityQuestion> questions;
  final List<DictationItem> dictationItems;
  final List<PracticeItem> practiceItems;

  ActivityDetail({
    required super.id,
    required super.title,
    required super.type,
    required super.order,
    required super.config,
    required super.scoring,
    required super.itemCount,
    super.questionBankId,
    super.createdAt,
    super.updatedAt,
    this.questions = const [],
    this.dictationItems = const [],
    this.practiceItems = const [],
  });

  factory ActivityDetail.fromJson(Map<String, dynamic> json) {
    return ActivityDetail(
      id: json['id'] as String,
      title: json['title'] as String?,
      type: (json['type'] as String?) ?? 'activity',
      order: (json['order'] as num?)?.toInt() ?? 0,
      config: (json['config'] is Map)
          ? Map<String, dynamic>.from(json['config'] as Map)
          : <String, dynamic>{},
      scoring: (json['scoring'] is Map)
          ? Map<String, dynamic>.from(json['scoring'] as Map)
          : <String, dynamic>{},
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
      questionBankId: json['questionBankId'] as String?,
      createdAt: json['createdAt'],
      updatedAt: json['updatedAt'],
      questions: (json['questions'] as List?)
              ?.map((q) => ActivityQuestion.fromJson(q as Map<String, dynamic>))
              .toList() ??
          const [],
      dictationItems: (json['dictationItems'] as List?)
              ?.map((d) => DictationItem.fromJson(d as Map<String, dynamic>))
              .toList() ??
          const [],
      practiceItems: (json['practiceItems'] as List?)
              ?.map((p) => PracticeItem.fromJson(p as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

// Helpers for debugging/logging
String prettyJson(Object? data) {
  try {
    return const JsonEncoder.withIndent('  ').convert(data);
  } catch (_) {
    return data.toString();
  }
}
