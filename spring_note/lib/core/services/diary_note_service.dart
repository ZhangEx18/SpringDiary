import 'dart:convert';
import 'dart:io';

import '../models/diary_entry.dart';
import 'note_service.dart';

class DiaryNoteService {
  const DiaryNoteService({this.noteService = const NoteService()});

  final NoteService noteService;

  Future<String> saveEntry({
    required String diaryNotesDirectory,
    required DateTime date,
    required DiaryEntry entry,
    String? rawMarkdown,
  }) async {
    final path = diaryNotePath(diaryNotesDirectory, date);
    final existing = await noteService.readMarkdown(path);
    final merged = _mergeMarkdown(existing, date, entry, rawMarkdown);
    await noteService.writeMarkdown(path, merged);
    return path;
  }

  Future<String> readDiaryMarkdown({
    required String diaryNotesDirectory,
    required DateTime date,
  }) {
    return noteService.readMarkdown(diaryNotePath(diaryNotesDirectory, date));
  }

  Future<DiaryEntry> readEntry({
    required String diaryNotesDirectory,
    required DateTime date,
  }) async {
    final markdown = await readDiaryMarkdown(
      diaryNotesDirectory: diaryNotesDirectory,
      date: date,
    );
    return extractEntry(markdown);
  }

  Future<List<DateTime>> listDiaryDates({
    required String diaryNotesDirectory,
    required int year,
    required int month,
  }) async {
    final directory = Directory(diaryNotesDirectory);
    if (!await directory.exists()) {
      return const [];
    }
    final prefix = '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-';
    final dates = <DateTime>[];
    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      final name = entity.uri.pathSegments.last;
      if (!name.endsWith('.md')) {
        continue;
      }
      final stem = name.substring(0, name.length - 3);
      if (!stem.startsWith(prefix)) {
        continue;
      }
      final parts = stem.split('-');
      if (parts.length != 3) {
        continue;
      }
      final day = int.tryParse(parts[2]);
      if (day == null) {
        continue;
      }
      dates.add(DateTime(year, month, day));
    }
    dates.sort();
    return dates;
  }

  Future<List<SameDayDiaryEntry>> listSameDayInPastYears({
    required String diaryNotesDirectory,
    required DateTime date,
    int maxYears = 10,
  }) async {
    final directory = Directory(diaryNotesDirectory);
    if (!await directory.exists()) {
      return const [];
    }
    final monthDay = '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final results = <SameDayDiaryEntry>[];
    final thisYear = date.year;

    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      final name = entity.uri.pathSegments.last;
      if (!name.endsWith('.md')) {
        continue;
      }
      final stem = name.substring(0, name.length - 3);
      if (!stem.endsWith('-$monthDay')) {
        continue;
      }
      final year = int.tryParse(stem.substring(0, 4));
      if (year == null || year >= thisYear || thisYear - year > maxYears) {
        continue;
      }
      final content = await File(entity.path).readAsString();
      results.add(SameDayDiaryEntry(year: year, markdown: content));
    }
    results.sort((a, b) => b.year.compareTo(a.year));
    return results;
  }

  /// Concatenates all diary entries of a month into one Markdown document.
  /// Internal JSON metadata blocks are stripped; each day becomes an
  /// `## YYYY-MM-DD` section.
  Future<String> exportRangeMarkdown({
    required String diaryNotesDirectory,
    required DateTime start,
    required DateTime end,
  }) async {
    final buffer = StringBuffer()
      ..writeln('# ${_formatDate(start)} 至 ${_formatDate(end)} 日记回顾')
      ..writeln();
    for (var day = 0; day <= end.difference(start).inDays; day++) {
      final date = start.add(Duration(days: day));
      final markdown = await readDiaryMarkdown(
        diaryNotesDirectory: diaryNotesDirectory,
        date: date,
      );
      final body = markdown
          .replaceAll(RegExp(r'```json\s*{.*?}\s*```', dotAll: true), '')
          .trim();
      if (body.isEmpty) {
        continue;
      }
      buffer
        ..writeln('## ${_formatDate(date)}')
        ..writeln()
        ..writeln(body)
        ..writeln();
    }
    return '${buffer.toString().trimRight()}\n';
  }

  Future<String> exportMonthMarkdown({
    required String diaryNotesDirectory,
    required int year,
    required int month,
  }) async {
    final dates = await listDiaryDates(
      diaryNotesDirectory: diaryNotesDirectory,
      year: year,
      month: month,
    );
    final buffer = StringBuffer()
      ..writeln('# $year-${month.toString().padLeft(2, '0')} 日记')
      ..writeln();
    for (final date in dates) {
      final markdown = await readDiaryMarkdown(
        diaryNotesDirectory: diaryNotesDirectory,
        date: date,
      );
      final body = markdown
          .replaceAll(RegExp(r'```json\s*{.*?}\s*```', dotAll: true), '')
          .trim();
      buffer
        ..writeln('## ${_formatDate(date)}')
        ..writeln()
        ..writeln(body)
        ..writeln();
    }
    return '${buffer.toString().trimRight()}\n';
  }

  String diaryNotePath(String diaryNotesDirectory, DateTime date) {
    final separator = Platform.pathSeparator;
    final directory = diaryNotesDirectory.endsWith(separator)
        ? diaryNotesDirectory.substring(0, diaryNotesDirectory.length - 1)
        : diaryNotesDirectory;
    return '$directory$separator${_formatDate(date)}.md';
  }

  static DiaryEntry extractEntry(String markdown) {
    final match = RegExp(
      r'```json\s*({.*?})\s*```',
      dotAll: true,
    ).firstMatch(markdown);
    if (match == null) {
      return DiaryEntry.empty;
    }
    try {
      final decoded = jsonDecode(match.group(1)!) as Map<String, Object?>;
      return DiaryEntry.fromJson(decoded);
    } on FormatException {
      return DiaryEntry.empty;
    }
  }

  String _mergeMarkdown(
    String existing,
    DateTime date,
    DiaryEntry entry,
    String? rawMarkdown,
  ) {
    final buffer = StringBuffer();
    final withoutJson = existing
        .replaceAll(RegExp(r'```json\s*{.*?}\s*```', dotAll: true), '')
        .trim();

    if (withoutJson.isEmpty) {
      buffer.writeln('# ${_formatDate(date)} 日记');
    } else {
      buffer.writeln(withoutJson);
    }

    if (rawMarkdown != null && rawMarkdown.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## 今日随想')
        ..writeln()
        ..writeln(rawMarkdown.trimRight());
    }

    buffer
      ..writeln()
      ..writeln('## 今日心情')
      ..writeln()
      ..writeln('${entry.mood.emoji} ${entry.mood.label}');

    if (entry.highlights.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## 今日高光')
        ..writeln();
      for (final highlight in entry.highlights) {
        buffer.writeln('- $highlight');
      }
    }

    if (entry.reflection.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## 反思')
        ..writeln()
        ..writeln(entry.reflection.trimRight());
    }

    if (entry.growthPrompt.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## 明日期许')
        ..writeln()
        ..writeln(entry.growthPrompt.trimRight());
    }

    buffer
      ..writeln()
      ..writeln('```json')
      ..writeln(jsonEncode(entry.toJson()))
      ..writeln('```');

    return '${buffer.toString().trimRight()}\n';
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

class SameDayDiaryEntry {
  const SameDayDiaryEntry({required this.year, required this.markdown});

  final int year;
  final String markdown;
}
