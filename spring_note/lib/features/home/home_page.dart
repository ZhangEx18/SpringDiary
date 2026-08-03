import 'package:flutter/material.dart';

import '../../core/models/app_config.dart';
import '../../core/models/diary_entry.dart';
import '../../core/models/local_data_state.dart';
import '../../core/services/ai_client_service.dart';
import '../../core/services/daily_prompt_service.dart';
import '../../core/services/diary_note_service.dart';
import '../../core/services/mock_ai_service.dart';
import '../../core/services/stats_service.dart';
import '../../core/services/update_check_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/update_dialog.dart';
import '../../src/rust/ai.dart' as rust_ai;
import '../../src/rust/stats.dart' as rust_stats;

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.localDataState,
    this.mockAiService = const MockAiService(),
    this.diaryNoteService = const DiaryNoteService(),
    this.dailyPromptService = const DailyPromptService(),
    this.aiClientService = const AiClientService(),
    this.statsService = const StatsService(),
    this.updateCheckResult = UpdateCheckResult.idle,
    this.updateCheckService,
    this.onDiarySaved,
    this.startupCloudSyncMessage,
  });

  final LocalDataState localDataState;
  final MockAiService mockAiService;
  final DiaryNoteService diaryNoteService;
  final DailyPromptService dailyPromptService;
  final AiClientService aiClientService;
  final StatsService statsService;
  final UpdateCheckResult updateCheckResult;
  final UpdateCheckService? updateCheckService;
  final VoidCallback? onDiarySaved;
  final String? startupCloudSyncMessage;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  rust_stats.StatsSnapshot _activityStats = StatsService.emptySnapshot;

  @override
  void initState() {
    super.initState();
    _loadHomeStats();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.localDataState.dataDirectory !=
        oldWidget.localDataState.dataDirectory) {
      _loadHomeStats();
    }
  }

  Future<void> _loadHomeStats() async {
    final today = DateTime.now();
    final activityStart = today.subtract(const Duration(days: 139));
    final activityStats = await widget.statsService.readSnapshot(
      localDataState: widget.localDataState,
      start: activityStart,
      end: today,
    );
    if (mounted) {
      setState(() => _activityStats = activityStats);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Material(
      color: colors.sidebar,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1184),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(48, 32, 48, 40),
            children: [
              Row(
                children: [
                  Text('首页', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  SpringNoteIconButton(
                    tooltip: '更多',
                    onPressed: () {},
                    icon: Icons.more_horiz,
                  ),
                ],
              ),
              const SizedBox(height: 32),
              _DiaryHeroCard(activityStats: _activityStats),
              const SizedBox(height: 32),
              _DiaryQuickCaptureCard(
                dailyPromptService: widget.dailyPromptService,
                diaryNotesDirectory:
                    widget.localDataState.diaryNotesDirectory,
                diaryNoteService: widget.diaryNoteService,
                aiClientService: widget.aiClientService,
                mockAiService: widget.mockAiService,
                appDataDir: widget.localDataState.dataDirectory,
                config: widget.localDataState.config,
                onSaved: widget.onDiarySaved,
              ),
              if (widget.updateCheckResult.status !=
                  UpdateCheckStatus.idle) ...[
                const SizedBox(height: 12),
                _UpdateNoticeBanner(
                  result: widget.updateCheckResult,
                  updateCheckService: widget.updateCheckService,
                ),
              ],
              if (widget.startupCloudSyncMessage != null) ...[
                const SizedBox(height: 12),
                _CloudSyncIssueBanner(message: widget.startupCloudSyncMessage!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DiaryHeroCard extends StatelessWidget {
  const _DiaryHeroCard({required this.activityStats});

  final rust_stats.StatsSnapshot activityStats;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(32),
      borderRadius: 26,
      child: _ActivityPreview(stats: activityStats, withDivider: false),
    );
  }
}

class _ActivityPreview extends StatelessWidget {
  const _ActivityPreview({required this.stats, this.withDivider = true});

  final rust_stats.StatsSnapshot stats;
  final bool withDivider;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final today = DateTime.now();
    final activityByDate = {
      for (final item in stats.activity) item.date: item.count,
    };
    final weekCount = List.generate(7, (index) {
      final date = today.subtract(Duration(days: 6 - index));
      return activityByDate[StatsService.formatDate(date)] ?? 0;
    }).fold<int>(0, (sum, count) => sum + count);
    final streak = _calculateStreak(today, activityByDate);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'DIARY ACTIVITY',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.textSubtle,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 1,
              ),
            ),
            const Spacer(),
            Text(
              '写日记',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: dark ? const Color(0xFF34D399) : const Color(0xFF10B981),
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ActivityHeatmap(
          today: today,
          activityByDate: activityByDate,
          colors: AppTheme.activityHeatmapColors(context),
          activityLevel: _activityLevel,
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActivityMetric(label: '本周日记', value: '$weekCount 篇'),
                const SizedBox(width: 24),
                _ActivityMetric(label: '连续记录', value: '$streak 天'),
              ],
            ),
          ),
        ),
      ],
    );

    if (!withDivider) {
      return content;
    }

    return Container(
      width: 392,
      padding: const EdgeInsets.only(left: 32),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.divider)),
      ),
      child: content,
    );
  }

  int _activityLevel(int count) {
    if (count >= 8) {
      return 4;
    }
    if (count >= 5) {
      return 3;
    }
    if (count >= 3) {
      return 2;
    }
    if (count >= 1) {
      return 1;
    }
    return 0;
  }

  int _calculateStreak(DateTime today, Map<String, int> activityByDate) {
    var streak = 0;
    for (var index = 0; index < 366; index++) {
      final date = today.subtract(Duration(days: index));
      final count = activityByDate[StatsService.formatDate(date)] ?? 0;
      if (count <= 0) {
        break;
      }
      streak++;
    }
    return streak;
  }
}

class _ActivityMetric extends StatelessWidget {
  const _ActivityMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Text.rich(
      TextSpan(
        text: '$label: ',
        children: [
          TextSpan(
            text: value,
            style: TextStyle(
              color: colors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: colors.textSubtle, fontSize: 12),
    );
  }
}

class _ActivityHeatmap extends StatefulWidget {
  const _ActivityHeatmap({
    required this.today,
    required this.activityByDate,
    required this.colors,
    required this.activityLevel,
  });

  static const _dayCount = 140;
  static const _rowCount = 7;

  final DateTime today;
  final Map<String, int> activityByDate;
  final List<Color> colors;
  final int Function(int count) activityLevel;

  @override
  State<_ActivityHeatmap> createState() => _ActivityHeatmapState();
}

class _ActivityHeatmapState extends State<_ActivityHeatmap> {
  static const _cellSize = 13.0;
  static const _gap = 3.0;

  int? _hoveredDayIndex;

  double get _pitch => _cellSize + _gap;
  double get _heatmapHeight =>
      (_ActivityHeatmap._rowCount * _cellSize) +
      ((_ActivityHeatmap._rowCount - 1) * _gap);

  @override
  Widget build(BuildContext context) {
    final start = widget.today.subtract(
      const Duration(days: _ActivityHeatmap._dayCount - 1),
    );
    final columns = (_ActivityHeatmap._dayCount / _ActivityHeatmap._rowCount)
        .ceil();
    final width = (columns * _cellSize) + ((columns - 1) * _gap);

    return MouseRegion(
      cursor: _hoveredDayIndex == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onHover: (event) => _updateHoveredIndex(event.localPosition, columns),
      onExit: (_) => _clearHoveredIndex(),
      child: SizedBox(
        width: width,
        height: _heatmapHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(columns, (columnIndex) {
                return Padding(
                  padding: EdgeInsets.only(
                    right: columnIndex == columns - 1 ? 0 : _gap,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(_ActivityHeatmap._rowCount, (
                      rowIndex,
                    ) {
                      final dayIndex =
                          columnIndex * _ActivityHeatmap._rowCount + rowIndex;
                      if (dayIndex >= _ActivityHeatmap._dayCount) {
                        return const SizedBox(
                          width: _cellSize,
                          height: _cellSize,
                        );
                      }
                      final date = start.add(Duration(days: dayIndex));
                      final dateLabel = StatsService.formatDate(date);
                      final count = widget.activityByDate[dateLabel] ?? 0;
                      final color = widget.colors[widget.activityLevel(count)];
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: rowIndex == _ActivityHeatmap._rowCount - 1
                              ? 0
                              : _gap,
                        ),
                        child: _HeatCell(
                          color: color,
                          hovered: _hoveredDayIndex == dayIndex,
                          delay: Duration(milliseconds: 300 + dayIndex * 4),
                        ),
                      );
                    }),
                  ),
                );
              }),
            ),
            if (_hoveredDayIndex != null)
              _buildTooltip(start, _hoveredDayIndex!),
          ],
        ),
      ),
    );
  }

  Widget _buildTooltip(DateTime start, int dayIndex) {
    final date = start.add(Duration(days: dayIndex));
    final dateLabel = StatsService.formatDate(date);
    final count = widget.activityByDate[dateLabel] ?? 0;
    final columnIndex = dayIndex ~/ _ActivityHeatmap._rowCount;
    final rowIndex = dayIndex % _ActivityHeatmap._rowCount;
    final cellLeft = columnIndex * _pitch;
    final cellTop = rowIndex * _pitch;

    return Positioned(
      left: cellLeft + (_cellSize / 2),
      bottom: _heatmapHeight - cellTop + 8,
      child: FractionalTranslation(
        translation: const Offset(-0.5, 0),
        child: _HeatmapTooltip(count: count, dateLabel: dateLabel),
      ),
    );
  }

  void _updateHoveredIndex(Offset position, int columns) {
    final nextIndex = _hitTestDayIndex(position, columns);
    if (nextIndex == _hoveredDayIndex) {
      return;
    }
    setState(() => _hoveredDayIndex = nextIndex);
  }

  void _clearHoveredIndex() {
    if (_hoveredDayIndex == null) {
      return;
    }
    setState(() => _hoveredDayIndex = null);
  }

  int? _hitTestDayIndex(Offset position, int columns) {
    if (position.dx < 0 ||
        position.dy < 0 ||
        position.dx > (columns * _cellSize) + ((columns - 1) * _gap) ||
        position.dy > _heatmapHeight) {
      return null;
    }

    final columnIndex = (position.dx / _pitch).floor();
    final rowIndex = (position.dy / _pitch).floor();
    if (columnIndex < 0 ||
        columnIndex >= columns ||
        rowIndex < 0 ||
        rowIndex >= _ActivityHeatmap._rowCount) {
      return null;
    }

    final dayIndex = columnIndex * _ActivityHeatmap._rowCount + rowIndex;
    if (dayIndex >= _ActivityHeatmap._dayCount) {
      return null;
    }
    return dayIndex;
  }
}

class _HeatCell extends StatelessWidget {
  const _HeatCell({
    required this.color,
    required this.hovered,
    required this.delay,
  });

  final Color color;
  final bool hovered;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final delayMs = delay.inMilliseconds;
    final totalMs = delayMs + 300;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: totalMs),
      builder: (context, value, child) {
        final elapsed = value * totalMs;
        final delayedProgress = ((elapsed - delayMs) / 300).clamp(0.0, 1.0);
        final eased = Curves.easeOutCubic.transform(delayedProgress);
        return Opacity(
          opacity: eased,
          child: Transform.scale(scale: 0.4 + 0.6 * eased, child: child),
        );
      },
      child: AnimatedScale(
        scale: hovered ? 1.1 : 1,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2.5),
          ),
          child: const SizedBox(width: 13, height: 13),
        ),
      ),
    );
  }
}

class _HeatmapTooltip extends StatelessWidget {
  const _HeatmapTooltip({required this.count, required this.dateLabel});

  final int count;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.24),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Text.rich(
          _tooltipMessage(colors),
          softWrap: false,
          overflow: TextOverflow.visible,
        ),
      ),
    );
  }

  InlineSpan _tooltipMessage(SpringThemeColors colors) {
    final baseStyle = TextStyle(
      color: colors.text,
      fontSize: 11,
      fontWeight: FontWeight.w500,
      height: 1.2,
    );

    if (count == 0) {
      return TextSpan(
        style: baseStyle,
        children: [
          TextSpan(
            text: 'No contributions on ',
            style: TextStyle(color: colors.textSubtle),
          ),
          TextSpan(
            text: dateLabel,
            style: TextStyle(
              color: colors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return TextSpan(
      style: baseStyle,
      children: [
        TextSpan(
          text: '$count ${count == 1 ? '篇' : '篇'}',
          style: TextStyle(color: colors.text, fontWeight: FontWeight.w700),
        ),
        TextSpan(
          text: ' on ',
          style: TextStyle(color: colors.textSubtle),
        ),
        TextSpan(
          text: dateLabel,
          style: TextStyle(
            color: colors.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _DiaryQuickCaptureCard extends StatefulWidget {
  const _DiaryQuickCaptureCard({
    required this.diaryNotesDirectory,
    required this.diaryNoteService,
    required this.aiClientService,
    required this.mockAiService,
    required this.appDataDir,
    required this.config,
    this.dailyPromptService = const DailyPromptService(),
    this.onSaved,
  });

  final String diaryNotesDirectory;
  final DiaryNoteService diaryNoteService;
  final AiClientService aiClientService;
  final MockAiService mockAiService;
  final String appDataDir;
  final AppConfig config;
  final DailyPromptService dailyPromptService;
  final VoidCallback? onSaved;

  @override
  State<_DiaryQuickCaptureCard> createState() => _DiaryQuickCaptureCardState();
}

class _DiaryQuickCaptureCardState extends State<_DiaryQuickCaptureCard> {
  final TextEditingController _controller = TextEditingController();
  DiaryMood _mood = DiaryMood.neutral;
  bool _saving = false;
  String? _savedMessage;
  bool _expanded = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _mood == DiaryMood.neutral) {
      return;
    }
    setState(() {
      _saving = true;
      _savedMessage = null;
    });
    try {
      final generated = await _generateEntry(text);
      final entry = generated != null
          ? DiaryEntry(
              mood: _mood,
              highlights: generated.highlights,
              reflection: generated.reflection,
              growthPrompt: generated.growthPrompt,
            )
          : DiaryEntry(mood: _mood);
      await widget.diaryNoteService.saveEntry(
        diaryNotesDirectory: widget.diaryNotesDirectory,
        date: DateTime.now(),
        entry: entry,
        rawMarkdown: text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _savedMessage = '已记录到今天的日记';
        _controller.clear();
        _mood = DiaryMood.neutral;
      });
      widget.onSaved?.call();
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<rust_ai.DiaryEntryResult?> _generateEntry(String text) async {
    final existing = await widget.diaryNoteService.readDiaryMarkdown(
      diaryNotesDirectory: widget.diaryNotesDirectory,
      date: DateTime.now(),
    );
    final aiEntry = await widget.aiClientService.generateDiaryEntry(
      appDataDir: widget.appDataDir,
      config: widget.config,
      rawInput: text,
      existingMarkdown: existing,
    );
    if (aiEntry != null && aiEntry.ok) {
      return aiEntry;
    }
    final mock = widget.mockAiService.createDiaryEntry(text);
    return rust_ai.DiaryEntryResult(
      ok: true,
      mood: mock.mood.name,
      moodScore: mock.moodScore,
      tags: mock.tags,
      highlights: mock.highlights,
      reflection: mock.reflection,
      growthPrompt: mock.growthPrompt,
      rawContent: '',
      errorCode: '',
      errorMessage: '',
      inputTokens: 0,
      outputTokens: 0,
      cachedTokens: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                const Icon(Icons.edit_note, size: 18),
                const SizedBox(width: 8),
                Text('今日日记', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (_savedMessage != null)
                  Text(
                    _savedMessage!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onAccent,
                    ),
                  ),
                const SizedBox(width: 8),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 20,
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final mood in DiaryMood.values)
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text('${mood.emoji} ${mood.label}'),
                    selected: _mood == mood,
                    onSelected: (_) => setState(() => _mood = mood),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              maxLines: 2,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                hintText: widget.dailyPromptService.promptFor(DateTime.now()),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('写入日记'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CloudSyncIssueBanner extends StatelessWidget {
  const _CloudSyncIssueBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF3B1119) : const Color(0xFFFEF2F2);
    final border = dark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA);
    final accent = dark ? const Color(0xFFFCA5A5) : const Color(0xFFDC2626);
    final foreground = dark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateNoticeBanner extends StatefulWidget {
  const _UpdateNoticeBanner({
    required this.result,
    required this.updateCheckService,
  });

  final UpdateCheckResult result;
  final UpdateCheckService? updateCheckService;

  @override
  State<_UpdateNoticeBanner> createState() => _UpdateNoticeBannerState();
}

class _UpdateNoticeBannerState extends State<_UpdateNoticeBanner> {
  bool _hovered = false;

  bool get _clickable =>
      widget.result.status == UpdateCheckStatus.updateAvailable &&
      widget.result.latest != null;

  @override
  Widget build(BuildContext context) {
    final latest = widget.result.latest;
    final colors = AppTheme.colors(context);
    final message = switch (widget.result.status) {
      UpdateCheckStatus.updateAvailable =>
        '发现新版本 ${latest?.version ?? ''}，点击查看更新内容',
      UpdateCheckStatus.failed => '更新检测失败',
      UpdateCheckStatus.idle => '',
    };
    final foreground = widget.result.status == UpdateCheckStatus.failed
        ? colors.textSubtle
        : colors.textMuted;

    return MouseRegion(
      cursor: _clickable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) {
        if (_clickable) {
          setState(() => _hovered = true);
        }
      },
      onExit: (_) {
        if (_clickable) {
          setState(() => _hovered = false);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _clickable ? () => _showUpdateDialog(context, latest!) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _hovered ? colors.surfaceHover : colors.surfaceMuted,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              if (widget.result.status == UpdateCheckStatus.failed)
                Icon(Icons.info_outline_rounded, size: 18, color: foreground)
              else
                UpdateDownloadIcon(size: 18, color: foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (_clickable)
                Icon(Icons.chevron_right_rounded, size: 20, color: foreground),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showUpdateDialog(
    BuildContext context,
    AppUpdateInfo latest,
  ) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.48),
      builder: (context) {
        return AppUpdateDialog(
          updateCheckService: widget.updateCheckService ?? UpdateCheckService(),
          currentVersion: widget.result.currentVersion,
          latest: latest,
        );
      },
    );
  }
}
