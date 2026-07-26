import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/widgets/spring_tree_parser.dart';

void main() {
  group('parseSpringTree', () {
    test('parses a nested dash list', () {
      final tree = parseSpringTree('''
- 中心主题
  - 分支 A
    - 子节点 1
  - 分支 B
''');
      expect(tree.nodeCount, 4);
      expect(tree.roots, hasLength(1));
      final root = tree.roots.single;
      expect(root.label, '中心主题');
      expect(root.depth, 0);
      expect(root.children, hasLength(2));
      expect(root.children[0].label, '分支 A');
      expect(root.children[0].children.single.label, '子节点 1');
      expect(root.children[1].label, '分支 B');
      expect(root.children[1].children, isEmpty);
    });

    test('supports *, +, numbered and task markers', () {
      final tree = parseSpringTree('''
* root
  1. one
  2. two
+ other
  - [ ] todo
  - [x] done
''');
      expect(tree.roots, hasLength(2));
      expect(tree.roots[0].label, 'root');
      expect(tree.roots[0].children.map((n) => n.label), ['one', 'two']);
      expect(tree.roots[1].children.map((n) => n.label), ['todo', 'done']);
    });

    test('parses plain indented text without markers', () {
      final tree = parseSpringTree('''
项目计划
  需求分析
  架构设计
    模块划分
''');
      expect(tree.roots.single.label, '项目计划');
      expect(tree.roots.single.children.map((n) => n.label), ['需求分析', '架构设计']);
      expect(tree.roots.single.children[1].children.single.label, '模块划分');
    });

    test('handles tabs the same as spaces', () {
      final tree = parseSpringTree('root\n\tchild\n\t\tgrand\n');
      expect(tree.roots.single.children.single.label, 'child');
      expect(tree.roots.single.children.single.children.single.label, 'grand');
    });

    test('tolerates indentation jumps and dedents', () {
      final tree = parseSpringTree('''
- a
        - b jumps several levels
  - c dedents
- d
''');
      expect(tree.nodeCount, 4);
      expect(tree.roots.map((n) => n.label), ['a', 'd']);
      expect(tree.roots[0].children.map((n) => n.label), [
        'b jumps several levels',
        'c dedents',
      ]);
      expect(tree.roots[0].children[1].children, isEmpty);
    });

    test('skips blank lines, horizontal rules and empty labels', () {
      final tree = parseSpringTree('''
- root

---
  -
  - real child
***
''');
      expect(tree.nodeCount, 2);
      expect(tree.roots.single.children.single.label, 'real child');
    });

    test('reduces inline markdown to plain text', () {
      final tree = parseSpringTree('''
- **Bold** and `code`
  - [链接文字](https://example.com) and ![alt](img.png)
  - ~~删除线~~ <b>html</b>
''');
      expect(tree.roots.single.label, 'Bold and code');
      expect(tree.roots.single.children.map((n) => n.label), [
        '链接文字 and alt',
        '删除线 html',
      ]);
    });

    test('assigns stable path ids that survive appends', () {
      final before = parseSpringTree('- root\n  - a\n  - b\n');
      final after = parseSpringTree('- root\n  - a\n  - b\n    - new\n  - c\n');
      String idOf(SpringTree tree, String label) {
        String? find(SpringTreeNode n) {
          if (n.label == label) return n.id;
          for (final c in n.children) {
            final r = find(c);
            if (r != null) return r;
          }
          return null;
        }

        for (final root in tree.roots) {
          final r = find(root);
          if (r != null) return r;
        }
        fail('label $label not found');
      }

      expect(idOf(after, 'root'), idOf(before, 'root'));
      expect(idOf(after, 'a'), idOf(before, 'a'));
      expect(idOf(after, 'b'), idOf(before, 'b'));
      expect(idOf(after, 'new'), '${idOf(after, 'b')}.0');
    });

    test('returns an empty tree for empty or junk input', () {
      expect(parseSpringTree('').isEmpty, isTrue);
      expect(parseSpringTree('\n\n  \n---\n').isEmpty, isTrue);
    });

    test('caps the node count for pathological input', () {
      final huge = List.filled(1000, '- node').join('\n');
      final tree = parseSpringTree(huge);
      expect(tree.nodeCount, lessThanOrEqualTo(300));
    });

    test('parses large input fast enough for streaming', () {
      final lines = StringBuffer('- root\n');
      for (var i = 0; i < 200; i++) {
        lines.writeln('  - child $i with some **markdown** text');
      }
      final stopwatch = Stopwatch()..start();
      final tree = parseSpringTree(lines.toString());
      stopwatch.stop();
      expect(tree.nodeCount, 201);
      // Very generous bound — typical runs are well under a millisecond.
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });
  });
}
