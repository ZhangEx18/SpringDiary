import 'dart:math';

import 'package:flutter/gestures.dart';
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

/// Current zoom factor of the graph's InteractiveViewer. Reads the X basis
/// length because getMaxScaleOnAxis also inspects the (always 1x) Z basis
/// and would never report less than 1.
double _graphScale(WidgetTester tester) {
  final s = tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer))
      .transformationController!
      .value
      .storage;
  return sqrt(s[0] * s[0] + s[1] * s[1]);
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

  testWidgets('dense trees start fitted and offer zoom controls', (
    tester,
  ) async {
    final buffer = StringBuffer('- 根\n');
    for (var i = 0; i < 12; i++) {
      buffer.writeln('  - 分支 $i 的标题比较长一些');
      for (var j = 0; j < 3; j++) {
        buffer.writeln('    - 子项 $i-$j 也是一段不短的文本内容');
      }
    }
    await tester.pumpWidget(_wrap(buffer.toString()));
    await tester.pumpAndSettle();

    // The initial view always shows the whole graph, even when that means
    // shrinking a dense map; the user zooms in manually.
    final initial = _graphScale(tester);
    expect(initial, lessThan(0.9));

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    expect(_graphScale(tester), greaterThan(initial));

    await tester.tap(find.byIcon(Icons.fit_screen_rounded));
    await tester.pumpAndSettle();
    expect(_graphScale(tester), closeTo(initial, 0.01));
  });

  testWidgets('fullscreen button opens an expanded dialog', (tester) async {
    await tester.pumpWidget(_wrap('- root\n  - a\n'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.fullscreen_rounded));
    await tester.pumpAndSettle();

    // The inline block plus the one in the fullscreen dialog.
    expect(find.byType(SpringTreeBlock), findsNWidgets(2));
    expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);

    // The dialog offers its own exit button (previously only ESC worked).
    expect(find.byIcon(Icons.fullscreen_exit_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.fullscreen_exit_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(SpringTreeBlock), findsOneWidget);
  });

  testWidgets('node labels are not selectable inside a SelectionArea', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: SpringTreeBlock(source: '- root\n  - a\n', isComplete: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A disabled SelectionContainer between the label and the SelectionArea
    // keeps node text out of text selection (and the pan gesture free).
    final containers = tester.widgetList<SelectionContainer>(
      find.ancestor(
        of: find.text('root'),
        matching: find.byType(SelectionContainer),
      ),
    );
    expect(containers.any((container) => container.delegate == null), isTrue);
  });

  testWidgets('wheel zooms the graph without scrolling the outer page', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: controller,
            child: Column(
              children: [
                const SizedBox(height: 100),
                SpringTreeBlock(source: '- root\n  - a\n  - b\n'),
                const SizedBox(height: 600),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final before = _graphScale(tester);
    final center = tester.getCenter(find.byType(SpringTreeBlock));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, -120)),
    );
    await tester.pump();

    expect(
      _graphScale(tester),
      greaterThan(before),
      reason: "wheel should zoom",
    );
    expect(
      controller.offset,
      0.0,
      reason: 'wheel over the graph must not scroll the outer page',
    );
  });

  testWidgets('falls back to a code block when nothing is parseable', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap('   \n---\n'));
    await tester.pumpAndSettle();

    expect(find.text('springtree'), findsOneWidget);
  });
}
