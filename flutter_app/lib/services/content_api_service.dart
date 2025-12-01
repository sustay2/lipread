import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../common/utils/media_utils.dart';
import '../models/content_models.dart';

class ContentApiService {
  ContentApiService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<List<Course>> fetchCourses({String? query}) async {
    final snap = await _db.collection('courses').get();
    final futures = snap.docs.map(_mapCourse);
    var courses = await Future.wait(futures);

    if (query != null && query.isNotEmpty) {
      courses = courses
          .where(
            (c) => (c.title ?? '').toLowerCase().contains(query.toLowerCase()) ||
                (c.description ?? '').toLowerCase().contains(query.toLowerCase()),
          )
          .toList();
    }

    courses.sort((a, b) {
      final aOrder = a.order ?? 0;
      final bOrder = b.order ?? 0;
      if (aOrder != bOrder) return aOrder.compareTo(bOrder);
      final aTs = a.createdAt;
      final bTs = b.createdAt;
      if (aTs == null || bTs == null) return 0;
      return bTs.toString().compareTo(aTs.toString());
    });

    return courses;
  }

  Future<Course?> fetchCourseById(String courseId) async {
    final courses = await fetchCourses();
    try {
      return courses.firstWhere((c) => c.id == courseId);
    } catch (_) {
      return null;
    }
  }

  Future<List<Module>> fetchModules(String courseId) async {
    final snap = await _db
        .collection('courses')
        .doc(courseId)
        .collection('modules')
        .orderBy('order')
        .get();
    final modules = snap.docs.map((doc) {
      final data = doc.data();
      return Module.fromJson({
        ...data,
        'id': doc.id,
        'courseId': courseId,
        'summary': data['summary'] ?? data['description'],
        'order': data['order'] ?? 0,
      });
    }).toList();
    modules.sort((a, b) => a.order.compareTo(b.order));
    return modules;
  }

  Future<Module?> fetchModuleById(String courseId, String moduleId) async {
    final modules = await fetchModules(courseId);
    try {
      return modules.firstWhere((m) => m.id == moduleId);
    } catch (_) {
      return null;
    }
  }

  Future<List<Lesson>> fetchLessons(String courseId, String moduleId) async {
    final snap = await _db
        .collection('courses')
        .doc(courseId)
        .collection('modules')
        .doc(moduleId)
        .collection('lessons')
        .orderBy('order')
        .get();
    final lessons = snap.docs.map((doc) {
      final data = doc.data();
      return Lesson.fromJson({
        ...data,
        'id': doc.id,
        'courseId': courseId,
        'moduleId': moduleId,
        'order': data['order'] ?? 0,
      });
    }).toList();
    lessons.sort((a, b) => a.order.compareTo(b.order));
    return lessons;
  }

  Future<Lesson?> fetchLessonById(
    String courseId,
    String moduleId,
    String lessonId,
  ) async {
    final lessons = await fetchLessons(courseId, moduleId);
    try {
      return lessons.firstWhere((l) => l.id == lessonId);
    } catch (_) {
      return null;
    }
  }

  Future<List<ActivitySummary>> fetchActivities(
    String courseId,
    String moduleId,
    String lessonId,
  ) async {
    final snap = await _db
        .collection('courses')
        .doc(courseId)
        .collection('modules')
        .doc(moduleId)
        .collection('lessons')
        .doc(lessonId)
        .collection('activities')
        .orderBy('order')
        .get();
    final activities = await Future.wait(snap.docs.map((doc) async {
      final data = doc.data();
      final type = (data['type'] as String?) ?? 'activity';
      final itemCount = await _countItems(
        courseId,
        moduleId,
        lessonId,
        doc.id,
        type,
      );
      return ActivitySummary.fromJson({
        ...data,
        'id': doc.id,
        'type': type,
        'order': data['order'] ?? 0,
        'itemCount': itemCount,
      });
    }));
    activities.sort((a, b) => a.order.compareTo(b.order));
    return activities;
  }

  Future<ActivityDetail> fetchActivityDetail(
    String courseId,
    String moduleId,
    String lessonId,
    String activityId,
  ) async {
    final doc = await _db
        .collection('courses')
        .doc(courseId)
        .collection('modules')
        .doc(moduleId)
        .collection('lessons')
        .doc(lessonId)
        .collection('activities')
        .doc(activityId)
        .get();

    if (!doc.exists) {
      throw Exception('Activity not found');
    }

    final data = doc.data() ?? {};
    final type = (data['type'] as String?) ?? 'activity';
    final questions = await _loadQuestions(courseId, moduleId, lessonId, doc.id);
    final dictationItems = await _loadDictationItems(courseId, moduleId, lessonId, doc.id);
    final practiceItems = await _loadPracticeItems(courseId, moduleId, lessonId, doc.id);

    return ActivityDetail.fromJson({
      ...data,
      'id': doc.id,
      'type': type,
      'order': data['order'] ?? 0,
      'questions': questions,
      'dictationItems': dictationItems,
      'practiceItems': practiceItems,
      'itemCount':
          type == 'dictation' ? dictationItems.length : type == 'practice_lip' ? practiceItems.length : questions.length,
    });
  }

  Future<Course> _mapCourse(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data() ?? {};
    final modulesRef = doc.reference.collection('modules');
    final moduleCount = await _safeCount(modulesRef);

    int lessonCount = 0;
    final modulesSnap = await modulesRef.get();
    for (final m in modulesSnap.docs) {
      lessonCount += await _safeCount(m.reference.collection('lessons'));
    }

    final mediaId = data['mediaId'] ?? data['coverImageId'];
    final resolvedThumb = await _resolveMediaUrl(
      directUrl: data['thumbnailUrl'] ?? data['thumbUrl'] ?? data['coverImageUrl'],
      path: data['thumbnailPath'] ?? data['thumbPath'],
      mediaId: mediaId as String?,
    );

    return Course.fromJson({
      ...data,
      'id': doc.id,
      'level': data['difficulty'] ?? data['level'],
      'description': data['summary'] ?? data['description'],
      'thumbnailUrl': resolvedThumb ?? data['thumbnailUrl'] ?? data['thumbUrl'],
      'mediaId': mediaId,
      'modulesCount': moduleCount,
      'lessonsCount': lessonCount,
      'order': data['order'] ?? 0,
    });
  }

  Future<int> _countItems(
    String courseId,
    String moduleId,
    String lessonId,
    String activityId,
    String activityType,
  ) async {
    late final Query<Map<String, dynamic>> query;
    if (activityType == 'dictation') {
      query = _db
          .collection('courses')
          .doc(courseId)
          .collection('modules')
          .doc(moduleId)
          .collection('lessons')
          .doc(lessonId)
          .collection('activities')
          .doc(activityId)
          .collection('dictationItems');
    } else if (activityType == 'practice_lip') {
      query = _db
          .collection('courses')
          .doc(courseId)
          .collection('modules')
          .doc(moduleId)
          .collection('lessons')
          .doc(lessonId)
          .collection('activities')
          .doc(activityId)
          .collection('practiceItems');
    } else {
      query = _db
          .collection('courses')
          .doc(courseId)
          .collection('modules')
          .doc(moduleId)
          .collection('lessons')
          .doc(lessonId)
          .collection('activities')
          .doc(activityId)
          .collection('questions');
    }

    return _safeCount(query);
  }

  Future<List<Map<String, dynamic>>> _loadQuestions(
    String courseId,
    String moduleId,
    String lessonId,
    String activityId,
  ) async {
    final snap = await _db
        .collection('courses')
        .doc(courseId)
        .collection('modules')
        .doc(moduleId)
        .collection('lessons')
        .doc(lessonId)
        .collection('activities')
        .doc(activityId)
        .collection('questions')
        .orderBy('order')
        .get();

    return snap.docs.map((doc) {
      final data = doc.data();
      final embedded = data['data'];
      return {
        ...data,
        'id': doc.id,
        'order': data['order'] ?? 0,
        'resolvedQuestion': embedded is Map<String, dynamic> ? embedded : data['resolvedQuestion'],
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _loadDictationItems(
    String courseId,
    String moduleId,
    String lessonId,
    String activityId,
  ) async {
    final snap = await _db
        .collection('courses')
        .doc(courseId)
        .collection('modules')
        .doc(moduleId)
        .collection('lessons')
        .doc(lessonId)
        .collection('activities')
        .doc(activityId)
        .collection('dictationItems')
        .orderBy('order')
        .get();

    return snap.docs.map((doc) {
      final data = doc.data();
      return {
        ...data,
        'id': doc.id,
        'order': data['order'] ?? 0,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _loadPracticeItems(
    String courseId,
    String moduleId,
    String lessonId,
    String activityId,
  ) async {
    final snap = await _db
        .collection('courses')
        .doc(courseId)
        .collection('modules')
        .doc(moduleId)
        .collection('lessons')
        .doc(lessonId)
        .collection('activities')
        .doc(activityId)
        .collection('practiceItems')
        .orderBy('order')
        .get();

    return snap.docs.map((doc) {
      final data = doc.data();
      return {
        ...data,
        'id': doc.id,
        'order': data['order'] ?? 0,
      };
    }).toList();
  }

  Future<int> _safeCount(Query<Map<String, dynamic>> query) async {
    try {
      final agg = await query.count().get();
      return agg.count;
    } catch (_) {
      try {
        final snap = await query.get();
        return snap.docs.length;
      } catch (e) {
        debugPrint('Count failed: $e');
        return 0;
      }
    }
  }

  Future<String?> _resolveMediaUrl({
    String? directUrl,
    String? path,
    String? mediaId,
  }) async {
    final normalized = publicMediaUrl(directUrl, path: path);
    if (normalized != null && normalized.isNotEmpty) return normalized;

    if (mediaId != null && mediaId.isNotEmpty) {
      try {
        final mediaSnap = await _db.collection('media').doc(mediaId).get();
        if (mediaSnap.exists) {
          final mediaData = mediaSnap.data() ?? {};
          return publicMediaUrl(mediaData['url'] as String?);
        }
      } catch (e) {
        debugPrint('Media resolve failed: $e');
      }
    }
    return null;
  }
}
