import '../models/diary_entry.dart';
import '../models/structured_note_section_config.dart';
import '../models/structured_work_note.dart';

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
      highlights: lines.take(3).toList(),
      reflection: _defaultReflection(mood),
      growthPrompt: '保持记录，明天继续观察自己的状态。',
    );
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

  StructuredWorkNote structureWorkNote(
    String input, {
    List<StructuredNoteSectionConfig> sectionConfigs =
        StructuredNoteSectionConfig.defaults,
  }) {
    final sections = StructuredNoteSectionConfig.normalize(sectionConfigs);
    final lines = input
        .split(RegExp(r'[\r\n。；;]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty && input.trim().isNotEmpty) {
      lines.add(input.trim());
    }

    if (!_usesDefaultSemantics(sections)) {
      return _buildNote(
        input: input,
        sections: sections,
        firstItems: lines,
        secondItems: const [],
        thirdItems: const [],
      );
    }

    final firstItems = <String>[];
    final secondItems = <String>[];
    final thirdItems = <String>[];

    for (final line in lines) {
      if (_matches(line, ['明天', '计划', '接下来', '后续', '待办', '准备'])) {
        thirdItems.add(line);
      } else if (_matches(line, ['问题', '阻塞', '报错', '失败', '异常', '卡住', '风险'])) {
        secondItems.add(line);
      } else {
        firstItems.add(line);
      }
    }

    return _buildNote(
      input: input,
      sections: sections,
      firstItems: firstItems,
      secondItems: secondItems,
      thirdItems: thirdItems,
    );
  }

  StructuredWorkNote _buildNote({
    required String input,
    required List<StructuredNoteSectionConfig> sections,
    required List<String> firstItems,
    required List<String> secondItems,
    required List<String> thirdItems,
  }) {
    return StructuredWorkNote(
      rawInput: input.trim(),
      sections: [
        StructuredWorkNoteSection(id: sections[0].id, items: firstItems),
        StructuredWorkNoteSection(id: sections[1].id, items: secondItems),
        StructuredWorkNoteSection(id: sections[2].id, items: thirdItems),
      ],
    );
  }

  bool _usesDefaultSemantics(List<StructuredNoteSectionConfig> sections) {
    final defaults = StructuredNoteSectionConfig.defaults;
    for (var index = 0; index < defaults.length; index++) {
      if (sections[index].aiInstruction.trim() !=
          defaults[index].aiInstruction) {
        return false;
      }
    }
    return true;
  }

  bool _matches(String value, List<String> keywords) {
    return keywords.any(value.contains);
  }
}
