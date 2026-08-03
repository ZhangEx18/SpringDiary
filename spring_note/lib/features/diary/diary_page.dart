import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/models/app_config.dart';
import '../../core/models/diary_entry.dart';
import '../../core/models/local_data_state.dart';
import '../../core/services/ai_client_service.dart';
import '../../core/services/diary_note_service.dart';
import '../../core/services/note_service.dart';
import '../../core/widgets/page_scaffold.dart';

class DiaryPage extends StatefulWidget {
  const DiaryPage({
    super.key,
    required this.localDataState,
    this.noteService = const NoteService(),
    this.diaryNoteService = const DiaryNoteService(),
    this.aiClientService = const AiClientService(),
  });

  final LocalDataState localDataState;
  final NoteService noteService;
  final DiaryNoteService diaryNoteService;
  final AiClientService aiClientService;

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> {
  late DateTime _visibleMonth;
  late DateTime _selectedDate;
  Map<String, DiaryEntry> _entriesByDate = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _visibleMonth = DateTime(today.year, today.month);
    _selectedDate = today;
    _loadMonth();
  }

  @override
  void didUpdateWidget(covariant DiaryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.localDataState.diaryNotesDirectory !=
        widget.localDataState.diaryNotesDirectory) {
      _loadMonth();
    }
  }

  Future<void> _loadMonth() async {
    setState(() => _loading = true);
    final dates = await widget.diaryNoteService.listDiaryDates(
      diaryNotesDirectory: widget.localDataState.diaryNotesDirectory,
      year: _visibleMonth.year,
      month: _visibleMonth.month,
    );
    final byDate = <String, DiaryEntry>{};
    for (final date in dates) {
      final entry = await widget.diaryNoteService.readEntry(
        diaryNotesDirectory: widget.localDataState.diaryNotesDirectory,
        date: date,
      );
      byDate[StatsDateKey.of(date)] = entry;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _entriesByDate = byDate;
      _loading = false;
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
    _loadMonth();
  }

  Future<void> _exportMonth() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final suggestedName = 'diary-${_visibleMonth.year}-'
        '${_visibleMonth.month.toString().padLeft(2, '0')}.md';
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Markdown', extensions: ['md']),
      ],
    );
    if (location == null) {
      return;
    }
    final markdown = await widget.diaryNoteService.exportMonthMarkdown(
      diaryNotesDirectory: widget.localDataState.diaryNotesDirectory,
      year: _visibleMonth.year,
      month: _visibleMonth.month,
    );
    try {
      final file = File(location.path);
      await file.writeAsString(markdown);
      messenger?.showSnackBar(SnackBar(content: Text('已导出到 ${file.path}')));
    } catch (_) {
      messenger?.showSnackBar(const SnackBar(content: Text('导出失败，请重试')));
    }
  }

  Future<void> _reviewDiary({required bool weekly}) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final today = DateTime.now();
    final start = weekly
        ? today.subtract(Duration(days: today.weekday - 1))
        : DateTime(today.year, today.month);
    final end = today;
    final periodLabel = weekly ? '本周' : '本月';

    messenger?.showSnackBar(
      SnackBar(content: Text('正在生成$periodLabel回顾…')),
    );
    final diaryMarkdown = await widget.diaryNoteService.exportRangeMarkdown(
      diaryNotesDirectory: widget.localDataState.diaryNotesDirectory,
      start: start,
      end: end,
    );
    final review = await widget.aiClientService.generateDiaryReview(
      appDataDir: widget.localDataState.dataDirectory,
      config: widget.localDataState.config,
      periodLabel: periodLabel,
      diaryMarkdown: diaryMarkdown,
    );
    messenger?.hideCurrentSnackBar();
    if (!mounted) {
      return;
    }
    if (review == null || review.trim().isEmpty) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('回顾生成失败，请检查模型配置')),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$periodLabel回顾'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: SelectableText(review),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SpringNotePageScaffold(
      title: '日记',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _MonthCalendar(
                    visibleMonth: _visibleMonth,
                    selectedDate: _selectedDate,
                    entriesByDate: _entriesByDate,
                    onSelect: (date) => setState(() => _selectedDate = date),
                    onPreviousMonth: () => _changeMonth(-1),
                    onNextMonth: () => _changeMonth(1),
                    onExport: _exportMonth,
                    onReviewWeekly: () => _reviewDiary(weekly: true),
                    onReviewMonthly: () => _reviewDiary(weekly: false),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _SelectedDayDetail(
                    date: _selectedDate,
                    entry: _entriesByDate[StatsDateKey.of(_selectedDate)],
                    diaryNotesDirectory:
                        widget.localDataState.diaryNotesDirectory,
                    appDataDir: widget.localDataState.dataDirectory,
                    config: widget.localDataState.config,
                    diaryNoteService: widget.diaryNoteService,
                    aiClientService: widget.aiClientService,
                    onSaved: _loadMonth,
                  ),
                ),
              ],
            ),
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.visibleMonth,
    required this.selectedDate,
    required this.entriesByDate,
    required this.onSelect,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onExport,
    required this.onReviewWeekly,
    required this.onReviewMonthly,
  });

  final DateTime visibleMonth;
  final DateTime selectedDate;
  final Map<String, DiaryEntry> entriesByDate;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onExport;
  final VoidCallback onReviewWeekly;
  final VoidCallback onReviewMonthly;

  static const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final firstDay = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final daysInMonth = DateTime(
      visibleMonth.year,
      visibleMonth.month + 1,
      0,
    ).day;
    final leadingBlanks = firstDay.weekday - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Row(
            children: [
              IconButton(
                tooltip: '上个月',
                onPressed: onPreviousMonth,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  '${visibleMonth.year} 年 ${visibleMonth.month} 月',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: '周回顾',
                onPressed: onReviewWeekly,
                icon: const Icon(Icons.view_week_outlined),
              ),
              IconButton(
                tooltip: '月回顾',
                onPressed: onReviewMonthly,
                icon: const Icon(Icons.calendar_month_outlined),
              ),
              IconButton(
                tooltip: '导出本月',
                onPressed: onExport,
                icon: const Icon(Icons.file_download_outlined),
              ),
              IconButton(
                tooltip: '下个月',
                onPressed: onNextMonth,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              for (final label in _weekdayLabels)
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: leadingBlanks + daysInMonth,
            itemBuilder: (context, index) {
              final day = index - leadingBlanks + 1;
              if (day < 1 || day > daysInMonth) {
                return const SizedBox.shrink();
              }
              final date = DateTime(visibleMonth.year, visibleMonth.month, day);
              final entry = entriesByDate[StatsDateKey.of(date)];
              final isSelected =
                  StatsDateKey.of(date) == StatsDateKey.of(selectedDate);
              final isToday =
                  StatsDateKey.of(date) == StatsDateKey.of(DateTime.now());
              return _DayCell(
                day: day,
                entry: entry,
                isSelected: isSelected,
                isToday: isToday,
                onTap: () => onSelect(date),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.entry,
    required this.isSelected,
    required this.isToday,
    required this.onTap,
  });

  final int day;
  final DiaryEntry? entry;
  final bool isSelected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasEntry = entry != null && !entry!.isEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primaryContainer
              : hasEntry
              ? colors.surfaceContainerHighest
              : colors.surface,
          borderRadius: BorderRadius.circular(10),
          border: isToday
              ? Border.all(color: colors.primary, width: 1.5)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: TextStyle(
                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (entry != null)
              Text(entry!.mood.emoji, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _SelectedDayDetail extends StatefulWidget {
  const _SelectedDayDetail({
    required this.date,
    required this.entry,
    required this.diaryNotesDirectory,
    required this.appDataDir,
    required this.config,
    required this.diaryNoteService,
    required this.aiClientService,
    required this.onSaved,
  });

  final DateTime date;
  final DiaryEntry? entry;
  final String diaryNotesDirectory;
  final String appDataDir;
  final AppConfig config;
  final DiaryNoteService diaryNoteService;
  final AiClientService aiClientService;
  final VoidCallback onSaved;

  @override
  State<_SelectedDayDetail> createState() => _SelectedDayDetailState();
}

class _SelectedDayDetailState extends State<_SelectedDayDetail> {
  late final TextEditingController _contentController;
  late final TextEditingController _tagsController;
  late DiaryMood _selectedMood;
  int _moodScore = 5;
  List<SameDayDiaryEntry> _pastEntries = const [];
  String? _followUp;
  bool _askingFollowUp = false;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController();
    _tagsController = TextEditingController();
    _selectedMood = widget.entry?.mood ?? DiaryMood.neutral;
    _moodScore = widget.entry?.moodScore ?? 5;
    _tagsController.text = (widget.entry?.tags ?? const []).join(', ');
    _loadMarkdown();
    _loadPastEntries();
  }

  @override
  void didUpdateWidget(covariant _SelectedDayDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (StatsDateKey.of(oldWidget.date) != StatsDateKey.of(widget.date)) {
      _selectedMood = widget.entry?.mood ?? DiaryMood.neutral;
      _moodScore = widget.entry?.moodScore ?? 5;
      _tagsController.text = (widget.entry?.tags ?? const []).join(', ');
      _loadMarkdown();
      _loadPastEntries();
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _loadMarkdown() async {
    final markdown = await widget.diaryNoteService.readDiaryMarkdown(
      diaryNotesDirectory: widget.diaryNotesDirectory,
      date: widget.date,
    );
    if (!mounted) {
      return;
    }
    _contentController.text = markdown
        .replaceAll(RegExp(r'```json\s*{.*?}\s*```', dotAll: true), '')
        .trim();
  }

  Future<void> _loadPastEntries() async {
    final past = await widget.diaryNoteService.listSameDayInPastYears(
      diaryNotesDirectory: widget.diaryNotesDirectory,
      date: widget.date,
    );
    if (!mounted) {
      return;
    }
    setState(() => _pastEntries = past);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.date.year}-${widget.date.month.toString().padLeft(2, '0')}-${widget.date.day.toString().padLeft(2, '0')}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (widget.entry != null)
                  Text(
                    widget.entry!.mood.emoji,
                    style: const TextStyle(fontSize: 22),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final mood in DiaryMood.values)
                  ChoiceChip(
                    label: Text('${mood.emoji} ${mood.label}'),
                    selected: _selectedMood == mood,
                    onSelected: (_) => setState(() => _selectedMood = mood),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.sentiment_satisfied_outlined, size: 16),
                const SizedBox(width: 8),
                Text('心情分 $_moodScore / 10'),
                Expanded(
                  child: Slider(
                    value: _moodScore.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: '$_moodScore',
                    onChanged: (value) =>
                        setState(() => _moodScore = value.round()),
                  ),
                ),
              ],
            ),
            TextField(
              controller: _tagsController,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: '标签（逗号分隔，如 工作, 放松）',
              ),
            ),
            if (_pastEntries.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '往年今日',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              for (final past in _pastEntries)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${past.year} 年 ${widget.date.month} 月 ${widget.date.day} 日',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _pastPreview(past.markdown),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 4),
            if (widget.entry != null && widget.entry!.reflection.isNotEmpty)
              Text(
                widget.entry!.reflection,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            if (widget.entry != null &&
                widget.entry!.highlights.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final highlight in widget.entry!.highlights)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.star_outline, size: 14),
                      const SizedBox(width: 6),
                      Expanded(child: Text(highlight)),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _contentController,
              maxLines: 6,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '记录此刻的想法…',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _askingFollowUp ? null : _askFollowUp,
                  icon: _askingFollowUp
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.psychology_outlined, size: 18),
                  label: const Text('AI 追问'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _saveRaw,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存'),
                ),
              ],
            ),
            if (_followUp != null && _followUp!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.psychology_outlined, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _followUp!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _pastPreview(String markdown) {
    final withoutJson = markdown
        .replaceAll(RegExp(r'```json\s*{.*?}\s*```', dotAll: true), '')
        .trim();
    return withoutJson.replaceAll(RegExp(r'^#+\s*.*$', multiLine: true), '').trim();
  }

  List<String> _parseTags(String text) {
    return text
        .split(RegExp(r'[,，]'))
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .take(5)
        .toList();
  }

  Future<void> _askFollowUp() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final body = _contentController.text.trim();
    if (body.isEmpty) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('先写点什么，AI 才能追问')),
      );
      return;
    }
    setState(() => _askingFollowUp = true);
    final followUp = await widget.aiClientService.generateDiaryReview(
      appDataDir: widget.appDataDir,
      config: widget.config,
      periodLabel: '追问',
      diaryMarkdown: body,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _askingFollowUp = false;
      _followUp = followUp;
    });
  }

  Future<void> _saveRaw() async {
    final previous = widget.entry ?? DiaryEntry.empty;
    await widget.diaryNoteService.saveEntry(
      diaryNotesDirectory: widget.diaryNotesDirectory,
      date: widget.date,
      entry: DiaryEntry(
        mood: _selectedMood,
        moodScore: _moodScore,
        tags: _parseTags(_tagsController.text),
        highlights: previous.highlights,
        reflection: previous.reflection,
        growthPrompt: previous.growthPrompt,
      ),
      rawMarkdown: _contentController.text,
    );
    widget.onSaved();
  }
}

/// Date key helper matching the `YYYY-MM-DD` format used by diary files.
abstract final class StatsDateKey {
  static String of(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
