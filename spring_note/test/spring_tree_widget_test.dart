import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/widgets/spring_tree.dart';

Widget _wrap(String source, {bool isComplete = true}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: SpringTreeBlock(source: source, isComplete: isComplete),
      ),
    ),
  );
}

void main() {
  testWidgets('renders mind map nodes from an indented list', (tester) async {
    await tester.pumpWidget(_wrap('- 中心主题\n  - 分支 A\n  - 分支 B\n'));
    await tester.pumpAndSettle();

    expect(find.text('中心主题'), findsOneWidget);
    expect(find.text('分支 A'), findsOneWidget);
    expect(find.text('分支 B'), findsOneWidget);
    expect(find.text('springtree'), findsOneWidget);
  });

  testWidgets('places nodes inside the visible viewport', (tester) async {
    // Regression test: graphview's centerGraph lays the graph out around
    // (100000, 100000), so the nodes exist in the tree but render far
    // outside the visible area and the block looks blank.
    await tester.pumpWidget(_wrap('- 中心主题\n  - 分支 A\n  - 分支 B\n'));
    await tester.pumpAndSettle();

    final screen = Offset(
      tester.view.physicalSize.width / tester.view.devicePixelRatio,
      tester.view.physicalSize.height / tester.view.devicePixelRatio,
    );
    for (final label in ['中心主题', '分支 A', '分支 B']) {
      final topLeft = tester.getTopLeft(find.text(label));
      expect(
        topLeft.dx,
        inInclusiveRange(0.0, screen.dx),
        reason: '$label is horizontally off-screen at $topLeft',
      );
      expect(
        topLeft.dy,
        inInclusiveRange(0.0, screen.dy),
        reason: '$label is vertically off-screen at $topLeft',
      );
    }
  });

  testWidgets('grows progressively as streamed text arrives', (tester) async {
    await tester.pumpWidget(_wrap('- root\n  - a\n', isComplete: false));
    await tester.pumpAndSettle();
    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsNothing);

    // A streaming delta appends a new branch; the block must re-parse and
    // rebuild the graph without losing the existing nodes or throwing.
    await tester.pumpWidget(
      _wrap('- root\n  - a\n  - b\n    - c\n', isComplete: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
    expect(find.text('c'), findsOneWidget);
  });

  testWidgets('joins multiple top-level lines under an origin dot', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap('- first\n- second\n'));
    await tester.pumpAndSettle();

    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);
  });

  testWidgets('settled layout never overlaps nodes', (tester) async {
    // Same shape as a real-world report: two branches with two leaves each.
    // Regression guard against graphview's position animation never
    // converging during streaming (nodes overlapped mid-lerp).
    const source = '''
- Spring AI 架构
  - 基础设施层
    - Nacos 注册中心
    - MCP 服务
  - Graph 微服务
    - AI 结构化决策
    - PCM 语音推流
''';
    // Simulate a few streaming updates before settling.
    await tester.pumpWidget(_wrap('- Spring AI 架构\n  - 基础设施层\n'));
    await tester.pump();
    await tester.pumpWidget(
      _wrap('- Spring AI 架构\n  - 基础设施层\n    - Nacos 注册中心\n'),
    );
    await tester.pump();
    await tester.pumpWidget(_wrap(source));
    await tester.pumpAndSettle();

    const ids = ['0', '0.0', '0.0.0', '0.0.1', '0.1', '0.1.0', '0.1.1'];
    final rects = <String, Rect>{
      for (final id in ids)
        id: tester.getRect(find.byKey(ValueKey('springtree_$id'))),
    };
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final a = rects[ids[i]]!;
        final b = rects[ids[j]]!;
        expect(
          a.overlaps(b),
          isFalse,
          reason: 'node ${ids[i]} $a overlaps node ${ids[j]} $b',
        );
      }
    }
  });

  testWidgets('no overlaps across varied tree shapes', (tester) async {
    final shapes = <String>[
      // Deep unbalanced chain.
      '- a\n  - b\n    - c\n      - d\n        - e very deep node with long label\n',
      // Many siblings on one side.
      '- root\n${List.generate(8, (i) => '  - child number $i with text').join('\n')}\n',
      // Uneven branches with long CJK labels.
      '- 中心主题根节点\n  - 一个相当长的分支节点名称用来测试宽度\n'
          '    - 二级节点甲\n    - 二级节点乙\n  - 短\n    - 另一个稍微长一点的二级节点\n',
      // Multiple roots (virtual origin).
      '- 第一根\n  - 子 A\n- 第二根\n  - 子 B\n    - 孙 B\n- 第三根\n',
    ];

    for (final source in shapes) {
      await tester.pumpWidget(_wrap(source));
      await tester.pumpAndSettle();

      final nodes = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('springtree_'),
      );
      final rects = nodes
          .evaluate()
          .map((e) => tester.getRect(find.byWidget(e.widget)))
          .toList();
      expect(rects.length, greaterThan(1), reason: 'shape: $source');
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(
            rects[i].overlaps(rects[j]),
            isFalse,
            reason: 'shape "$source": ${rects[i]} overlaps ${rects[j]}',
          );
        }
      }
    }
  });

  testWidgets('falls back to a code block when nothing is parseable', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap('   \n---\n'));
    await tester.pumpAndSettle();

    expect(find.text('springtree'), findsOneWidget);
  });
}
