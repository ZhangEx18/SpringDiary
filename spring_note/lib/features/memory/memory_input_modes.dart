import 'package:flutter/material.dart';

/// A composer input mode: a tag the user inserts into the input text from
/// the "+" menu. The tag is stored as a single private-use code point so it
/// behaves like one character — the cursor steps over it and Backspace or
/// Delete removes it whole — while [MemoryComposerController] paints it as
/// a labeled chip. Mode state is therefore derived purely from the text:
/// deleting the tag disables the mode, with no separate global state.
class MemoryInputMode {
  const MemoryInputMode({
    required this.id,
    required this.label,
    required this.icon,
    required this.token,
    required this.prompt,
  });

  /// Stable identifier, e.g. `springtree`.
  final String id;

  /// Chip label shown inside the input field, e.g. `思维导图`.
  final String label;

  /// Icon shown in the "+" menu.
  final IconData icon;

  /// Single private-use code point embedded in the input text.
  final String token;

  /// Prompt appended to the model request while the tag is present.
  final String prompt;
}

/// Mind-map mode: the model answers with a single ```springtree block.
const MemoryInputMode mindMapInputMode = MemoryInputMode(
  id: 'springtree',
  label: '思维导图',
  icon: Icons.account_tree_outlined,
  token: '\u{e100}',
  prompt: r'''
你当前处于 SpringTree 输出模式。

请根据用户请求生成内容，并将最终响应转换为 springtree 格式输出。

输出要求：

1. 最终只能输出一个 Markdown 代码块。
2. 代码块语言必须为 springtree。
3. 不允许输出任何解释文字、标题、说明或总结。
4. 不允许使用表格、JSON 或其他格式。

springtree 格式规范：

* springtree 是一种基于 Markdown 无序列表实现的树形结构格式。
* 每一行表示一个节点。
* 使用 "-" 表示节点。
* 使用缩进表示节点层级关系。
* 节点层级根据内容关系自动组织。
* 父节点表示上层概念或分类。
* 子节点表示具体内容。
* 更深层级表示详细信息。

生成规则：

* 根据用户请求生成对应内容。
* 对内容进行合理分层组织。
* 保留关键名称、时间、事项、细节等有效信息。
* 合并重复内容。
* 删除无意义描述。
* 不编造不存在的信息。
* 保证输出结构稳定，方便程序解析。

示例：

```springtree
- 2026-07-26 周报
  - 项目开发
    - SpringNote
      - 完成 xxx 功能
      - 优化 xxx 模块
  - 技术研究
    - MCP
      - 调试 xxx 流程
```
''',
);

/// Every composer input mode. Future modes only need a new entry here.
const List<MemoryInputMode> memoryInputModes = [mindMapInputMode];

/// The result of resolving mode tags inside an input string.
class MemoryInputModeResolution {
  const MemoryInputModeResolution({
    required this.userText,
    required this.modes,
  });

  /// The input with every mode tag removed — what the user actually typed.
  final String userText;

  /// Active modes in registry order (one entry per mode, duplicates folded).
  final List<MemoryInputMode> modes;

  /// The joined prompts of all active modes, for the model request.
  String get promptSuffix => modes.map((mode) => mode.prompt).join('\n\n');
}

/// Strips mode tags from [input] and collects the modes they activate.
MemoryInputModeResolution resolveMemoryInputModes(String input) {
  final active = <MemoryInputMode>[];
  var userText = input;
  for (final mode in memoryInputModes) {
    if (userText.contains(mode.token)) {
      active.add(mode);
      userText = userText.replaceAll(mode.token, '');
    }
  }
  return MemoryInputModeResolution(userText: userText, modes: active);
}

/// Text controller that paints registered mode tokens as labeled chips.
///
/// Each token is one code point in the text, so selection, cursor movement
/// and deletion treat it atomically; only the visual rendering differs.
class MemoryComposerController extends TextEditingController {
  static const Color _chipColor = Color(0xFF3B82F6);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final chipStyle = base.copyWith(
      color: _chipColor,
      backgroundColor: _chipColor.withValues(alpha: 0.12),
      fontWeight: FontWeight.w600,
    );

    final spans = <TextSpan>[];
    var rest = text;
    while (rest.isNotEmpty) {
      var nearest = -1;
      MemoryInputMode? nearestMode;
      for (final mode in memoryInputModes) {
        final index = rest.indexOf(mode.token);
        if (index >= 0 && (nearest < 0 || index < nearest)) {
          nearest = index;
          nearestMode = mode;
        }
      }
      if (nearestMode == null) {
        spans.add(TextSpan(text: rest));
        break;
      }
      if (nearest > 0) {
        spans.add(TextSpan(text: rest.substring(0, nearest)));
      }
      spans.add(TextSpan(text: ' ${nearestMode.label} ', style: chipStyle));
      rest = rest.substring(nearest + nearestMode.token.length);
    }
    return TextSpan(style: base, children: spans);
  }
}
