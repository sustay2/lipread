import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../env.dart';
import '../models/transcript_result.dart';

class DioClient {
  late Dio _dio;

  DioClient() {
    // Use the dedicated transcription base
    final base = kTranscribeBase;
    debugPrint('[DioClient] using transcribe base: $base');

    _dio = Dio(
      BaseOptions(
        baseUrl: base,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(minutes: 2),
        sendTimeout: const Duration(minutes: 2),
        headers: const {'Accept': 'application/json'},
      ),
    );
  }

  /// Upload a video file to FastAPI /transcribe
  Future<TranscriptResult> transcribeVideo(
      File file, {
        String? lessonId,
        void Function(int sent, int total)? onProgress,
      }) async {
    final form = FormData.fromMap({
      'video': await MultipartFile.fromFile(
        file.path,
        filename: file.uri.pathSegments.last,
      ),
      if (lessonId != null) 'lessonId': lessonId,
    });

    try {
      final res = await _dio.post(
        '/transcribe',
        data: form,
        onSendProgress: onProgress,
      );

      return TranscriptResult.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      // Distinguish connection issues vs server errors
      final status = e.response?.statusCode;
      final data = e.response?.data;

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError) {
        debugPrint(
            '[DioClient] Connection problem to $kTranscribeBase: ${e.message}');
        throw Exception(
          'Upload failed (network): could not reach transcription server at $kTranscribeBase. '
              'Check IP/port and that the server is running.',
        );
      }

      if (status != null) {
        debugPrint(
            '[DioClient] HTTP $status from /transcribe. Body: ${data.toString()}');
        throw Exception(
            'Upload failed (status=$status): ${data is String ? data : data.toString()}');
      }

      throw Exception(
          'Upload failed (status=null): ${e.message ?? 'Unknown Dio error'}');
    }
  }
}