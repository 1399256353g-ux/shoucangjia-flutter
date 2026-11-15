import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/unit_library.dart';

BasicLib basic(String id, String rel, {int authors = 1, int works = 10}) =>
    BasicLib(
      id: id,
      name: rel.split('/').last,
      rel: rel,
      bigId: '',
      authors: authors,
      works: works,
    );

void main() {
  group('splitRel / relFromPath', () {
    test('统一分隔符并去掉空段', () {
      expect(splitRel('a//b/c/'), ['a', 'b', 'c']);
      expect(splitRel('a\\b'), ['a', 'b']);
      expect(splitRel(''), isEmpty);
    });

    test('去掉库根前缀', () {
      expect(
        relFromPath('/vol1/x/Secret/(1) A/(2) B', '/vol1/x/Secret'),
        '(1) A/(2) B',
      );
      expect(relFromPath('/other/(1) A', '/vol1/x/Secret'), 'other/(1) A');
    });
  });

  group('buildUnitTree 层级与收敛', () {
    test('顶级节点成单元库，基础库挂在最深节点下', () {
      final nodes = [
        const LibNode(id: 'big-01', rel: '(1) A', name: '(1) A'),
        const LibNode(id: 'grp-01', rel: '(1) A/(9) 子节点', name: '(9) 子节点'),
      ];
      final tree = buildUnitTree(
        nodes: nodes,
        basics: [
          basic('l1', '(1) A/(2) 直属'),
          basic('l2', '(1) A/(9) 子节点/(3) 深层'),
        ],
      )!;

      expect(tree.name, 'SECRET');
      expect(tree.children.length, 1);
      final a = tree.children.first;
      expect(a.name, '(1) A');
      expect(a.basics.map((b) => b.id), ['l1']);
      expect(a.children.length, 1);
      expect(a.children.first.basics.map((b) => b.id), ['l2']);
      // 父节点不重复认领子节点的基础库
      expect(a.works, 20);
      expect(a.basicCount, 2);
    });

    test('同一路径多节点只保留一个（取最下级不重复认领）', () {
      final nodes = [
        const LibNode(id: 'n1', rel: '(1) A', name: '(1) A'),
        const LibNode(id: 'n2', rel: '(1) A', name: '(1) A 重复'),
      ];
      final tree = buildUnitTree(nodes: nodes, basics: [basic('l1', '(1) A/x')])!;
      expect(tree.children.length, 1);
      expect(tree.children.first.basics.length, 1);
    });

    test('空单元库整棵子树消失', () {
      final nodes = [
        const LibNode(id: 'empty', rel: '(9) 空', name: '(9) 空'),
        const LibNode(id: 'kept', rel: '(1) A', name: '(1) A'),
      ];
      final tree = buildUnitTree(nodes: nodes, basics: [basic('l1', '(1) A/x')])!;
      expect(tree.children.map((c) => c.name), ['(1) A']);
    });

    test('无节点归属的基础库归入默认顶级单元库', () {
      final tree = buildUnitTree(
        nodes: const [LibNode(id: 'big-01', rel: '(1) A', name: '(1) A')],
        basics: [basic('l1', '(1) A/x'), basic('l2', '(5) 无节点/x')],
        topName: 'SECRET',
      )!;
      final secret = tree.children.firstWhere((c) => c.name == 'SECRET');
      expect(secret.basics.map((b) => b.id), ['l2']);
      expect(tree.children.length, 2);
    });

    test('没有任何基础库时整棵树消失', () {
      expect(buildUnitTree(nodes: const [], basics: const []), isNull);
    });

    test('多级嵌套按名称排序，深度优先取全部基础库', () {
      final tree = buildUnitTree(
        nodes: const [
          LibNode(id: 'b2', rel: '(2) B', name: '(2) B'),
          LibNode(id: 'b1', rel: '(1) A', name: '(1) A'),
        ],
        basics: [basic('l1', '(2) B/x'), basic('l2', '(1) A/y')],
      )!;
      expect(tree.children.map((c) => c.name), ['(1) A', '(2) B']);
      expect(tree.allBasics.map((b) => b.id), ['l2', 'l1']);
    });
  });

  group('nodesFromV2', () {
    test('合并大库与分组节点，缺 rel 时按 root 推导', () {
      final json = {
        'bigLibraries': [
          {'id': 'big-01', 'name': '(1) A', 'path': '/r/Secret/(1) A'},
        ],
        'groups': [
          {
            'id': 'grp-01',
            'name': '(9) G',
            'path': '/r/Secret/(1) A/(9) G',
            'basic_ids': ['l1'],
          },
        ],
      };
      final nodes = nodesFromV2(json, root: '/r/Secret');
      expect(nodes.map((n) => n.rel), ['(1) A', '(1) A/(9) G']);
      expect(nodes.last.name, '(9) G');
    });
  });

  test('formatCount 千/万分位', () {
    expect(formatCount(999), '999');
    expect(formatCount(1200), '1.2k');
    expect(formatCount(12345), '1.2万');
  });
}
