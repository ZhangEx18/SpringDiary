import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/diary_entry.dart';

void main() {
  group('DiaryMood', () {
    test('fromCode maps known codes', () {
      expect(DiaryMood.fromCode('joyful'), DiaryMood.joyful);
      expect(DiaryMood.fromCode('angry'), DiaryMood.angry);
    });

    test('fromCode falls back to neutral for unknown or null', () {
      expect(DiaryMood.fromCode('unknown'), DiaryMood.neutral);
      expect(DiaryMood.fromCode(null), DiaryMood.neutral);
    });

    test('every mood has emoji and label', () {
      for (final mood in DiaryMood.values) {
        expect(mood.emoji, isNotEmpty);
        expect(mood.label, isNotEmpty);
      }
    });
  });

  group('DiaryEntry', () {
    test('toJson/fromJson roundtrip preserves all fields', () {
      const entry = DiaryEntry(
        mood: DiaryMood.down,
        highlights: ['项目上线', '跑步 5km'],
        reflection: '今天效率不错',
        growthPrompt: '明天早点开始',
      );

      final restored = DiaryEntry.fromJson(entry.toJson());

      expect(restored.mood, DiaryMood.down);
      expect(restored.highlights, ['项目上线', '跑步 5km']);
      expect(restored.reflection, '今天效率不错');
      expect(restored.growthPrompt, '明天早点开始');
    });

    test('fromJson tolerates missing fields', () {
      final entry = DiaryEntry.fromJson(const {});
      expect(entry.mood, DiaryMood.neutral);
      expect(entry.highlights, isEmpty);
      expect(entry.reflection, '');
      expect(entry.growthPrompt, '');
    });

    test('fromJson drops non-string highlight items', () {
      final entry = DiaryEntry.fromJson(const {
        'highlights': ['ok', 42, null, 'also-ok'],
      });
      expect(entry.highlights, ['ok', 'also-ok']);
    });

    test('isEmpty is true when no content', () {
      expect(DiaryEntry.empty.isEmpty, isTrue);
      const withReflection = DiaryEntry(
        mood: DiaryMood.joyful,
        reflection: 'x',
      );
      expect(withReflection.isEmpty, isFalse);
    });
  });
}
