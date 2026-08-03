import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/diary_entry.dart';
import 'package:spring_note/core/services/mock_ai_service.dart';

void main() {
  const service = MockAiService();

  test('createDiaryEntry infers joyful mood from positive keywords', () {
    final entry = service.createDiaryEntry('今天项目上线很顺利，很满意！');
    expect(entry.mood, DiaryMood.joyful);
    expect(entry.moodScore, greaterThanOrEqualTo(7));
    expect(entry.highlights, isNotEmpty);
    expect(entry.reflection, isNotEmpty);
    expect(entry.growthPrompt, isNotEmpty);
  });

  test('createDiaryEntry infers topic tags', () {
    final entry = service.createDiaryEntry('今天项目上线，晚上和家里人吃饭很放松。');
    expect(entry.tags, isNotEmpty);
    expect(entry.tags.any((tag) => tag == '工作' || tag == '家庭'), isTrue);
  });

  test('createDiaryEntry empty input keeps default score and tags', () {
    final entry = service.createDiaryEntry('   ');
    expect(entry.moodScore, 6);
    expect(entry.tags, isEmpty);
  });

  test('createDiaryEntry infers down mood from fatigue keywords', () {
    final entry = service.createDiaryEntry('今天好累，压力很大。');
    expect(entry.mood, DiaryMood.down);
  });

  test('createDiaryEntry defaults to neutral for plain input', () {
    final entry = service.createDiaryEntry('写了个脚本。');
    expect(entry.mood, DiaryMood.neutral);
    expect(entry.highlights, ['写了个脚本']);
  });

  test('createDiaryEntry handles empty input', () {
    final entry = service.createDiaryEntry('   ');
    expect(entry.mood, DiaryMood.neutral);
    expect(entry.highlights, isEmpty);
  });
}
