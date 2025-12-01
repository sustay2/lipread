import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../env.dart';
import '../models/content_models.dart';

class ContentApiService {
  ContentApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<Course>> fetchCourses({String? query}) async {
    final uri = Uri.parse('$kApiBase/api/courses').replace(
      queryParameters: {
        if (query != null && query.isNotEmpty) 'q': query,
      },
    );
    final res = await _get(uri);
    final decoded = jsonDecode(res.body);
    final items = (decoded is Map && decoded['items'] is List)
        ? decoded['items'] as List
        : (decoded as List? ?? []);
    return items
        .whereType<Map<String, dynamic>>()
        .map(Course.fromJson)
        .toList();
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
    final uri = Uri.parse('$kApiBase/api/courses/$courseId/modules');
    final res = await _get(uri);
    final decoded = jsonDecode(res.body);
    final list = decoded is List ? decoded : <dynamic>[];
    return list.whereType<Map<String, dynamic>>().map(Module.fromJson).toList();
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
    final uri = Uri.parse('$kApiBase/api/modules/$moduleId/lessons');
    final res = await _get(uri);
    final decoded = jsonDecode(res.body);
    final list = decoded is List ? decoded : <dynamic>[];
    return list.whereType<Map<String, dynamic>>().map(Lesson.fromJson).toList();
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
    final uri = Uri.parse('$kApiBase/api/lessons/$lessonId/activities');
    final res = await _get(uri);
    final decoded = jsonDecode(res.body);
    final items = (decoded is Map && decoded['items'] is List)
        ? decoded['items'] as List
        : (decoded as List? ?? []);
    return items
        .whereType<Map<String, dynamic>>()
        .map(ActivitySummary.fromJson)
        .toList();
  }

  Future<ActivityDetail> fetchActivityDetail(
    String courseId,
    String moduleId,
    String lessonId,
    String activityId,
  ) async {
    final uri = Uri.parse('$kApiBase/api/activities/$activityId').replace(
      queryParameters: {
        'courseId': courseId,
        'moduleId': moduleId,
        'lessonId': lessonId,
      },
    );
    final res = await _get(uri);
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    return ActivityDetail.fromJson(decoded);
  }

  Future<http.Response> _get(Uri uri) async {
    final headers = await _headers();
    final res = await _client.get(uri, headers: headers);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res;
    }
    debugPrint('[ContentApi] GET ${uri.toString()} -> ${res.statusCode}');
    throw Exception('Request failed (${res.statusCode}): ${res.body}');
  }

  Future<Map<String, String>> _headers() async {
    final headers = <String, String>{'Accept': 'application/json'};
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final token = await user.getIdToken();
        headers['Authorization'] = 'Bearer $token';
      } catch (_) {
        // ignore token issues; fallback to anonymous access
      }
    }
    return headers;
  }
}
