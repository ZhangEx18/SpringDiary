part of 'settings_page.dart';

class _DiaryPanel extends StatelessWidget {
  const _DiaryPanel();

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return _SettingsScrollFrame(
      maxWidth: 1120,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.edit_note, size: 20),
                  const SizedBox(width: 10),
                  Text('日记', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '日记以 Markdown 文件保存在本地数据目录的 notes/diary 下，'
                '按日期命名（YYYY-MM-DD.md），可直接用任何文本编辑器打开。'
                '支持在首页快速记录心情与随想，由 AI 反思模型整理为高光、'
                '反思与明日期许。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  for (final mood in DiaryMood.values)
                    Chip(
                      avatar: Text(mood.emoji),
                      label: Text(mood.label),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
