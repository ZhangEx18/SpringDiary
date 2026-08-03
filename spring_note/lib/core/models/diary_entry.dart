/// Diary mood taxonomy. Fixed five-level set, extensible later.
enum DiaryMood {
  joyful('😊', '开心'),
  neutral('😐', '平静'),
  down('😔', '低落'),
  sad('😢', '难过'),
  angry('😠', '生气');

  const DiaryMood(this.emoji, this.label);

  final String emoji;
  final String label;

  static DiaryMood fromCode(String? code) {
    return DiaryMood.values.firstWhere(
      (mood) => mood.name == code,
      orElse: () => DiaryMood.neutral,
    );
  }
}

/// Structured diary entry produced by the AI reflection model.
///
/// Stored inside a daily Markdown file as a JSON code block:
/// ```json
/// {
///   "mood": "joyful",
///   "moodScore": 8,
///   "tags": ["工作", "放松"],
///   "highlights": ["..."],
///   "reflection": "...",
///   "growthPrompt": "..."
/// }
/// ```
class DiaryEntry {
  const DiaryEntry({
    required this.mood,
    this.moodScore = 5,
    this.tags = const [],
    this.highlights = const [],
    this.reflection = '',
    this.growthPrompt = '',
  });

  final DiaryMood mood;
  final int moodScore;
  final List<String> tags;
  final List<String> highlights;
  final String reflection;
  final String growthPrompt;

  bool get isEmpty =>
      highlights.isEmpty && reflection.isEmpty && growthPrompt.isEmpty;

  Map<String, Object?> toJson() => {
        'mood': mood.name,
        'moodScore': moodScore,
        'tags': tags,
        'highlights': highlights,
        'reflection': reflection,
        'growthPrompt': growthPrompt,
      };

  factory DiaryEntry.fromJson(Map<String, Object?> json) {
    return DiaryEntry(
      mood: DiaryMood.fromCode(json['mood'] as String?),
      moodScore: (json['moodScore'] as num?)?.round().clamp(1, 10) ?? 5,
      tags: [
        for (final item in (json['tags'] as List<Object?>? ?? const []))
          if (item is String) item,
      ],
      highlights: [
        for (final item in (json['highlights'] as List<Object?>? ?? const []))
          if (item is String) item,
      ],
      reflection: json['reflection'] as String? ?? '',
      growthPrompt: json['growthPrompt'] as String? ?? '',
    );
  }

  static const empty = DiaryEntry(mood: DiaryMood.neutral);
}
