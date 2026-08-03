import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/diary_entry.dart';
import 'package:spring_note/core/services/diary_note_service.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('spring_note_diary_');
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test('saveEntry creates markdown with mood and json block', () async {
    const service = DiaryNoteService();
    final date = DateTime(2026, 6, 18, 21, 30);
    const entry = DiaryEntry(
      mood: DiaryMood.joyful,
      highlights: ['完成改造'],
      reflection: '状态不错',
      growthPrompt: '保持节奏',
    );

    final path = await service.saveEntry(
      diaryNotesDirectory: temp.path,
      date: date,
      entry: entry,
      rawMarkdown: '今天推进了日记功能。',
    );

    expect(path.endsWith('2026-06-18.md'), isTrue);
    final markdown = await File(path).readAsString();
    expect(markdown, contains('# 2026-06-18 日记'));
    expect(markdown, contains('## 今日随想'));
    expect(markdown, contains('今天推进了日记功能。'));
    expect(markdown, contains('😊 开心'));
    expect(markdown, contains('- 完成改造'));
    expect(markdown, contains('状态不错'));
    expect(markdown, contains('保持节奏'));
    expect(markdown, contains('```json'));
  });

  test('readEntry roundtrips saved entry', () async {
    const service = DiaryNoteService();
    final date = DateTime(2026, 6, 18);
    const entry = DiaryEntry(
      mood: DiaryMood.down,
      highlights: ['a', 'b'],
      reflection: 'r',
      growthPrompt: 'g',
    );

    await service.saveEntry(
      diaryNotesDirectory: temp.path,
      date: date,
      entry: entry,
    );

    final restored = await service.readEntry(
      diaryNotesDirectory: temp.path,
      date: date,
    );
    expect(restored.mood, DiaryMood.down);
    expect(restored.highlights, ['a', 'b']);
    expect(restored.reflection, 'r');
    expect(restored.growthPrompt, 'g');
  });

  test('saveEntry merges into existing markdown without duplicating json', () async {
    const service = DiaryNoteService();
    final date = DateTime(2026, 6, 18);
    const first = DiaryEntry(
      mood: DiaryMood.neutral,
      reflection: '第一段',
    );
    const second = DiaryEntry(
      mood: DiaryMood.joyful,
      reflection: '第二段',
    );

    await service.saveEntry(
      diaryNotesDirectory: temp.path,
      date: date,
      entry: first,
    );
    await service.saveEntry(
      diaryNotesDirectory: temp.path,
      date: date,
      entry: second,
    );

    final markdown = await service.readDiaryMarkdown(
      diaryNotesDirectory: temp.path,
      date: date,
    );
    expect(markdown, contains('第一段'));
    expect(markdown, contains('第二段'));
    final jsonBlocks = RegExp(r'```json').allMatches(markdown).length;
    expect(jsonBlocks, 1);
  });

  test('listDiaryDates returns only matching month dates sorted', () async {
    const service = DiaryNoteService();
    await service.saveEntry(
      diaryNotesDirectory: temp.path,
      date: DateTime(2026, 6, 1),
      entry: DiaryEntry.empty,
    );
    await service.saveEntry(
      diaryNotesDirectory: temp.path,
      date: DateTime(2026, 6, 15),
      entry: DiaryEntry.empty,
    );
    await service.saveEntry(
      diaryNotesDirectory: temp.path,
      date: DateTime(2026, 7, 3),
      entry: DiaryEntry.empty,
    );

    final dates = await service.listDiaryDates(
      diaryNotesDirectory: temp.path,
      year: 2026,
      month: 6,
    );
    expect(dates, [DateTime(2026, 6, 1), DateTime(2026, 6, 15)]);
  });

  test('extractEntry returns empty for markdown without json block', () {
    expect(DiaryNoteService.extractEntry('plain text').isEmpty, isTrue);
  });

  test('extractEntry tolerates malformed json', () {
    final entry = DiaryNoteService.extractEntry('```json\nnot-json\n```');
    expect(entry.isEmpty, isTrue);
  });

  test('listSameDayInPastYears returns previous years same month-day', () async {
    const service = DiaryNoteService();
    await service.saveEntry(
      diaryNotesDirectory: temp.path,
      date: DateTime(2023, 6, 18),
      entry: const DiaryEntry(mood: DiaryMood.joyful, reflection: '2023 年'),
    );
    await service.saveEntry(
      diaryNotesDirectory: temp.path,
      date: DateTime(2024, 6, 18),
      entry: const DiaryEntry(mood: DiaryMood.neutral, reflection: '2024 年'),
    );
    await service.saveEntry(
      diaryNotesDirectory: temp.path,
      date: DateTime(2024, 7, 18),
      entry: DiaryEntry.empty,
    );

    final past = await service.listSameDayInPastYears(
      diaryNotesDirectory: temp.path,
      date: DateTime(2025, 6, 18),
    );

    expect(past.length, 2);
    expect(past[0].year, 2024);
    expect(past[0].markdown, contains('2024 年'));
    expect(past[1].year, 2023);
    expect(past[1].markdown, contains('2023 年'));
  });

  test('listSameDayInPastYears excludes current year and beyond maxYears', () async {
    const service = DiaryNoteService();
    await service.saveEntry(
      diaryNotesDirectory: temp.path,
      date: DateTime(2025, 6, 18),
      entry: const DiaryEntry(mood: DiaryMood.joyful, reflection: '今年'),
    );
    await service.saveEntry(
      diaryNotesDirectory: temp.path,
      date: DateTime(2000, 6, 18),
      entry: const DiaryEntry(mood: DiaryMood.neutral, reflection: '太久远'),
    );

    final past = await service.listSameDayInPastYears(
      diaryNotesDirectory: temp.path,
      date: DateTime(2025, 6, 18),
      maxYears: 5,
    );

    expect(past, isEmpty);
  });
}
