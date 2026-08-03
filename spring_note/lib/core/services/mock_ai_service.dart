import '../models/diary_entry.dart';

class MockAiService {
  const MockAiService();

  DiaryEntry createDiaryEntry(String input) {
    final trimmed = input.trim();
    final lines = trimmed
        .split(RegExp(r'[\r\n。；;]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty && trimmed.isNotEmpty) {
      lines.add(trimmed);
    }

    final mood = _inferMood(trimmed);
    return DiaryEntry(
      mood: mood,
      moodScore: _inferMoodScore(trimmed),
      tags: _inferTags(lines),
      highlights: lines.take(3).toList(),
      reflection: _defaultReflection(mood),
      growthPrompt: '保持记录，明天继续观察自己的状态。',
    );
  }

  int _inferMoodScore(String text) {
    if (_matches(text, ['开心', '高兴', '棒', '顺利', '爽', '满意', '收获'])) {
      return 8;
    }
    if (_matches(text, ['累', '低落', '烦', '焦虑', '压力', '沮丧'])) {
      return 4;
    }
    if (_matches(text, ['难过', '哭', '伤心', '委屈'])) {
      return 3;
    }
    if (_matches(text, ['生气', '愤怒', '气死', '火大'])) {
      return 2;
    }
    return 6;
  }

  List<String> _inferTags(List<String> lines) {
    const topicKeywords = {
      '工作': ['工作', '项目', '开会', '代码', '任务', '上线'],
      '家庭': ['家人', '孩子', '父母', '爸妈', '家'],
      '健康': ['跑步', '健身', '运动', '早睡', '身体', '累'],
      '放松': ['电影', '游戏', '散步', '旅行', '美食', '朋友'],
      '成长': ['学习', '读书', '新技能', '课程', '反思'],
    };
    final text = lines.join(' ');
    final tags = <String>[];
    for (final entry in topicKeywords.entries) {
      if (entry.value.any(text.contains)) {
        tags.add(entry.key);
      }
    }
    return tags.take(3).toList();
  }

  DiaryMood _inferMood(String text) {
    if (_matches(text, ['开心', '高兴', '棒', '顺利', '爽', '满意', '收获'])) {
      return DiaryMood.joyful;
    }
    if (_matches(text, ['累', '低落', '烦', '焦虑', '压力', '沮丧'])) {
      return DiaryMood.down;
    }
    if (_matches(text, ['难过', '哭', '伤心', '委屈'])) {
      return DiaryMood.sad;
    }
    if (_matches(text, ['生气', '愤怒', '气死', '火大'])) {
      return DiaryMood.angry;
    }
    return DiaryMood.neutral;
  }

  String _defaultReflection(DiaryMood mood) {
    return switch (mood) {
      DiaryMood.joyful => '今天是值得记住的一天。',
      DiaryMood.down => '今天有些疲惫，允许自己慢一点。',
      DiaryMood.sad => '今天不太容易，抱抱自己。',
      DiaryMood.angry => '今天有情绪波动，先深呼吸。',
      DiaryMood.neutral => '今天平淡但真实。',
    };
  }

  bool _matches(String value, List<String> keywords) {
    return keywords.any(value.contains);
  }
}
