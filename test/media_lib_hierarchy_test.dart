import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/unit_library.dart';

/// 媒体库下的单元库层级（owner 2026-11-24）。
///
/// 现象：「媒体库下面的单元库都拆散开了，没有按照文件结构设置里的层级」。
///
/// 根因：`_collectServerBasics` 把根节点和它的直接子节点**平铺**成一层，
/// 于是 `/api/nodes` 下发的多层结构在首页被压平，父子关系丢失。
///
/// 这些测试钉住：媒体库卡片的下级单元库必须保持原有的父子嵌套。
void main() {
  BasicLib basic(String id, String rel) => BasicLib(
        id: id,
        name: id,
        rel: rel,
        bigId: '',
        works: 1,
        authors: 1,
      );

  group('媒体库下的层级必须保留（不能被摊平）', () {
    test('三层结构：A → A/B → A/B/C，首页下级仍是嵌套而非平铺', () {
      final nodes = nodesFromMarks(
        const ['(1) A', '(1) A/(2) B', '(1) A/(2) B/(3) C'],
        serverId: 'srv-1',
        serverLabel: 'NAS',
      );
      final tree = buildUnitTree(
        nodes: nodes,
        basics: [
          basic('lib-a', '(1) A'),
          basic('lib-b', '(1) A/(2) B'),
          basic('lib-c', '(1) A/(2) B/(3) C'),
        ],
        topName: 'Secret',
      );
      expect(tree, isNotNull);
      expect(tree!.children.length, 1, reason: '只应有一张媒体库卡');
      final media = tree.children.first;

      // 媒体库下只有一个根单元库 A
      expect(media.children.length, 1, reason: 'A 与 B 不该被平铺成兄弟');
      final a = media.children.first;
      expect(a.name, '(1) A');

      // A 下面才是 B，B 下面才是 C —— 父子链完整
      expect(a.children.length, 1, reason: 'B 必须是 A 的子节点');
      final b = a.children.first;
      expect(b.name, '(2) B');
      expect(b.children.length, 1, reason: 'C 必须是 B 的子节点');
      expect(b.children.first.name, '(3) C');
    });

    test('同层多个兄弟节点仍保持同层，不被提升到媒体库直属', () {
      final nodes = nodesFromMarks(
        const ['(1) A', '(1) A/(2) B1', '(1) A/(2) B2'],
        serverId: 'srv-1',
        serverLabel: 'NAS',
      );
      final tree = buildUnitTree(
        nodes: nodes,
        basics: [
          basic('lib-a', '(1) A'),
          basic('lib-b1', '(1) A/(2) B1'),
          basic('lib-b2', '(1) A/(2) B2'),
        ],
        topName: 'Secret',
      );
      final media = tree!.children.first;
      expect(media.children.length, 1, reason: '只有 A 是媒体库直属');
      expect(media.children.first.children.length, 2,
          reason: 'B1/B2 应在 A 之下同层');
    });

    test('节点总数不因嵌套而丢失（三层 3 个节点 → 树里仍 3 个）', () {
      final nodes = nodesFromMarks(
        const ['(1) A', '(1) A/(2) B', '(1) A/(2) B/(3) C'],
        serverId: 'srv-1',
        serverLabel: 'NAS',
      );
      final tree = buildUnitTree(
        nodes: nodes,
        basics: [
          basic('lib-a', '(1) A'),
          basic('lib-b', '(1) A/(2) B'),
          basic('lib-c', '(1) A/(2) B/(3) C'),
        ],
        topName: 'Secret',
      );
      final media = tree!.children.first;
      var count = 0;
      void walk(UnitLibrary u) {
        count++;
        for (final c in u.children) {
          walk(c);
        }
      }

      for (final c in media.children) {
        walk(c);
      }
      expect(count, 3, reason: '层级保留不等于丢节点');
    });

    test('媒体库直属数量 = 第一层节点数（不是全部节点数）', () {
      final nodes = nodesFromMarks(
        const [
          '(1) A',
          '(1) A/(2) B',
          '(1) A/(2) B/(3) C',
          '(1) X',
          '(1) X/(2) Y',
        ],
        serverId: 'srv-1',
        serverLabel: 'NAS',
      );
      final tree = buildUnitTree(
        nodes: nodes,
        basics: [
          basic('lib-a', '(1) A'),
          basic('lib-b', '(1) A/(2) B'),
          basic('lib-c', '(1) A/(2) B/(3) C'),
          basic('lib-x', '(1) X'),
          basic('lib-y', '(1) X/(2) Y'),
        ],
        topName: 'Secret',
      );
      final media = tree!.children.first;
      expect(media.children.length, 2,
          reason: '只有 A 和 X 是第一层；B/C/Y 不应被提升');
      expect(media.children.map((e) => e.name).toSet(), {'(1) A', '(1) X'});
    });
  });
}
