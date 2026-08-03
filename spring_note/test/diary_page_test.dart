import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/app_config.dart';
import 'package:spring_note/core/models/diary_entry.dart';
import 'package:spring_note/core/models/local_data_state.dart';
import 'package:spring_note/core/services/diary_note_service.dart';
import 'package:spring_note/features/diary/diary_page.dart';

class _FakeDiaryNoteService extends DiaryNoteService {
  final Map<DateTime, DiaryEntry> entries = {};
  final Map<DateTime, String> rawMarkdown = {};
  List<SameDayDiaryEntry> pastEntries = const [];

  static DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

  @override
  Future<List<DateTime>> listDiaryDates({
    required String diaryNotesDirectory,
    required int year,
    required int month,
  }) async {
    return entries.keys
        .where((d) => d.year == year && d.month == month)
        .toList()
      ..sort();
  }

  @override
  Future<DiaryEntry> readEntry({
    required String diaryNotesDirectory,
    required DateTime date,
  }) async {
    return entries[_day(date)] ?? DiaryEntry.empty;
  }

  @override
  Future<String> readDiaryMarkdown({
    required String diaryNotesDirectory,
    required DateTime date,
  }) async {
    return rawMarkdown[_day(date)] ?? '';
  }

  @override
  Future<List<SameDayDiaryEntry>> listSameDayInPastYears({
    required String diaryNotesDirectory,
    required DateTime date,
    int maxYears = 10,
  }) async {
    return pastEntries;
  }

  @override
  Future<String> saveEntry({
    required String diaryNotesDirectory,
    required DateTime date,
    required DiaryEntry entry,
    String? rawMarkdown,
  }) async {
    final day = _day(date);
    entries[day] = entry;
    this.rawMarkdown[day] = rawMarkdown ?? '';
    return '$diaryNotesDirectory${date.toIso8601String()}.md';
  }
}

void main() {
  LocalDataState state() {
    return LocalDataState(
      dataDirectory: '/tmp/diary',
      configPath: '/tmp/diary/config.json',
      dailyNotesDirectory: '/tmp/diary/daily',
      weeklyNotesDirectory: '/tmp/diary/weekly',
      monthlyNotesDirectory: '/tmp/diary/monthly',
      diaryNotesDirectory: '/tmp/diary/diary',
      config: AppConfig.defaults(),
    );
  }

  testWidgets('diary page renders month calendar and today cell', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DiaryPage(
          localDataState: state(),
          diaryNoteService: _FakeDiaryNoteService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('年'), findsWidgets);
    expect(find.text('1'), findsWidgets);
    expect(find.text('保存'), findsOneWidget);
  });

  testWidgets('diary page shows mood emoji on days with entries', (
    tester,
  ) async {
    final service = _FakeDiaryNoteService();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    service.entries[today] = const DiaryEntry(
      mood: DiaryMood.joyful,
      highlights: ['测试高光'],
      reflection: '测试反思',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DiaryPage(
          localDataState: state(),
          diaryNoteService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('😊'), findsWidgets);
    expect(find.text('测试反思'), findsOneWidget);
  });

  testWidgets('diary page saves raw markdown for selected day', (
    tester,
  ) async {
    final service = _FakeDiaryNoteService();

    await tester.pumpWidget(
      MaterialApp(
        home: DiaryPage(
          localDataState: state(),
          diaryNoteService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '今天记了点什么');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    expect(service.rawMarkdown[today], contains('今天记了点什么'));
    expect(service.entries.containsKey(today), isTrue);
  });

  testWidgets('diary page saves selected mood with entry', (tester) async {
    final service = _FakeDiaryNoteService();

    await tester.pumpWidget(
      MaterialApp(
        home: DiaryPage(
          localDataState: state(),
          diaryNoteService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('😊 开心'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    expect(service.entries[today]?.mood, DiaryMood.joyful);
  });

  testWidgets('diary page shows same day entries from past years', (
    tester,
  ) async {
    final service = _FakeDiaryNoteService();
    service.pastEntries = const [
      SameDayDiaryEntry(year: 2024, markdown: '去年的今天去爬山了'),
      SameDayDiaryEntry(year: 2023, markdown: '前年的今天写下了第一篇日记'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: DiaryPage(
          localDataState: state(),
          diaryNoteService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('往年今日'), findsOneWidget);
    expect(find.textContaining('2024 年'), findsOneWidget);
    expect(find.textContaining('2023 年'), findsOneWidget);
  });
}
