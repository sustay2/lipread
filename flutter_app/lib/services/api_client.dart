import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../env.dart';
import '../models/transcript_result.dart';

class ApiClient {
  final String base = kApiBase;

  Future<TranscriptResult> transcribeVideo(File file, {String? lessonId}) async {
    final uri = Uri.parse('$base/transcribe');
    final req = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('video', file.path))
      ..fields.addAll({
        if (lessonId != null) 'lessonId': lessonId,
      });

    final streamed = await req.send().timeout(const Duration(seconds: 25));
    final res = await http.Response.fromStream(streamed);

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final jsonMap = json.decode(res.body) as Map<String, dynamic>;
      return TranscriptResult.fromJson(jsonMap);
    } else {
      throw Exception('Transcription failed: ${res.statusCode} ${res.body}');
    }
  }
}
