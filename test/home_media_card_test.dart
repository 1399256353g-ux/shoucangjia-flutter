import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/unit_library.dart';

/// 首页层级契约（owner 2026-11-24）。
///
/// 需求原文：**主页要显示媒体库卡片**，不是库下的第一层目录。
///
/// 历史缺陷：`nodesFromMarks` 生成的节点不带 `serverId`，`buildUnitTree`
/// 因此走进「无连接信息」回退分支，把第一层目录直接当成卡片，却在界面上
/// 标成「媒体库」——层级错位，点进去还会再套一层。
///
/// 这些测试钉住：只要有连接标识，首页第一层必须是「媒体库」，其 children
/// 才是下级单元库。
void main() {
  BasicLib basic(String id, String rel) => BasicLib(
        id: id,
        name: id,
        rel: rel,
        bigId: '',
        works: 1,
        authors: 1,
      );

  group('节点带连接标识 → 首页第一层是媒体库', () {
    test('单连接：第一层一张媒体库卡，children 是下级单元库', () {
      final nodes = nodesFromMarks(
        const ['(1) A', '(2) B'],
        serverId: 'srv-1',
        serverLabel: '我的 NAS',
        serverBase: 'http://192.168.2.4:8090',
      );
      final tree = buildUnitTree(
        nodes: nodes,
        basics: [basic('lib-a', '(1) A'), basic('lib-b', '(2) B')],
        topName: 'Secret',
      );
      expect(tree, isNotNull);
      // 顶层容器下面只应有 1 张媒体库卡。
      expect(tree!.children.length, 1);
      final media = tree.children.first;
      expect(media.name, '我的 NAS');
      expect(media.node.serverId, 'srv-1');
      // 媒体库自己不直接挂基础库，挂的是下级单元库。
      expect(media.basics, isEmpty);
      expect(media.children.length, 2);
      expect(media.children.map((e) => e.name).toSet(), {'(1) A', '(2) B'});
    });

    test('媒体库卡的作品数/作者数覆盖其下全部单元库', () {
      final nodes = nodesFromMarks(
        const ['(1) A', '(2) B'],
        serverId: 'srv-1',
        serverLabel: 'NAS',
      );
      final tree = buildUnitTree(
        nodes: nodes,
        basics: [basic('lib-a', '(1) A'), basic('lib-b', '(2) B')],
        topName: 'Secret',
      );
      final media = tree!.children.first;
      expect(media.works, 2);
      expect(media.authors, 2);
    });

    test('两个连接 → 两张媒体库卡，各自只装自己的单元库', () {
      final nodesA = nodesFromMarks(
        const ['(1) A'],
        serverId: 'srv-1',
        serverLabel: 'NAS-1',
      );
      final nodesB = nodesFromMarks(
        const ['(2) B'],
        serverId: 'srv-2',
        serverLabel: 'NAS-2',
      );
      final tree = buildUnitTree(
        nodes: [...nodesA, ...nodesB],
        basics: [basic('lib-a', '(1) A'), basic('lib-b', '(2) B')],
        topName: 'Secret',
      );
      expect(tree!.children.length, 2);
      final names = tree.children.map((e) => e.name).toSet();
      expect(names, {'NAS-1', 'NAS-2'});
      for (final m in tree.children) {
        expect(m.children.length, 1);
      }
    });
  });

  group('节点缺连接标识 → 保持旧形态（不伪造媒体库）', () {
    test('无 serverId 时不生成媒体库层，第一层就是节点本身', () {
      final nodes = nodesFromMarks(const ['(1) A', '(2) B']);
      final tree = buildUnitTree(
        nodes: nodes,
        basics: [basic('lib-a', '(1) A'), basic('lib-b', '(2) B')],
        topName: 'Secret',
      );
      expect(tree, isNotNull);
      // 回退形态：children 直接是节点，不额外包一层媒体库。
      expect(tree!.children.length, 2);
      expect(tree.children.every((e) => e.node.serverId.isEmpty), isTrue);
    });
  });

  group('nodesFromMarks 连接字段透传', () {
    test('serverId / serverLabel / serverBase 逐个落到节点上', () {
      final nodes = nodesFromMarks(
        const ['(1) A'],
        serverId: 'srv-9',
        serverLabel: '书房 NAS',
        serverBase: 'http://10.0.0.2:8090',
      );
      expect(nodes.length, 1);
      expect(nodes.first.serverId, 'srv-9');
      expect(nodes.first.serverLabel, '书房 NAS');
      expect(nodes.first.serverBase, 'http://10.0.0.2:8090');
    });

    test('不传连接信息时字段为空串（不猜、不继承别的连接）', () {
      final nodes = nodesFromMarks(const ['(1) A']);
      expect(nodes.first.serverId, '');
      expect(nodes.first.serverLabel, '');
    });
  });
}
