class WordSpan {
  final String text;
  final double start, end, conf;
  WordSpan({required this.text, required this.start, required this.end, required this.conf});
  factory WordSpan.fromJson(Map<String, dynamic> j) => WordSpan(
    text: j['text'] ?? '',
    start: (j['start'] ?? 0).toDouble(),
    end: (j['end'] ?? 0).toDouble(),
    conf: (j['conf'] ?? 0).toDouble(),
  );
}

class VisemeSpan {
  final String label;
  final double start, end;
  VisemeSpan({required this.label, required this.start, required this.end});
  factory VisemeSpan.fromJson(Map<String, dynamic> j) => VisemeSpan(
    label: j['label'] ?? '',
    start: (j['start'] ?? 0).toDouble(),
    end: (j['end'] ?? 0).toDouble(),
  );
}

class TranscriptResult {
  final String transcript;
  final double? confidence;
  final List<WordSpan> words;
  final List<VisemeSpan> visemes;

  TranscriptResult({required this.transcript, this.confidence, required this.words, required this.visemes});

  factory TranscriptResult.fromJson(Map<String, dynamic> j) => TranscriptResult(
    transcript: j['transcript'] ?? '',
    confidence: j['confidence'] != null ? (j['confidence'] as num).toDouble() : null,
    words: (j['words'] as List? ?? []).map((e) => WordSpan.fromJson(e)).toList(),
    visemes: (j['visemes'] as List? ?? []).map((e) => VisemeSpan.fromJson(e)).toList(),
  );
}
