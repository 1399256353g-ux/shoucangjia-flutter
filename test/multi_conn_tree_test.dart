import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/unit_library.dart';

/// 多连接下的单元库树（owner 2026-11-26）。
///
/// 这一组钉住四类**结构性**缺口，全部由纯结构与计数复现，不涉任何目录名文本：
///
///  1. 节点去重只用 rel → 两台服务端都有同名目录时，后者整条消失，且 B 的
///     基础库被挂到 A 的节点上（封面/鉴权按 A 的连接去请求 → 必然 404）。
///  2. 孤儿基础库不分连接塞进一个 `serverId` 为空的根 → 只要有一台服务端
///     存在节点，首页走「每连接一张媒体库」分支，那个空连接根被丢弃，
///     孤儿库整批不上屏。
///  3. 混合连接（有新格式根 + 旧格式无连接根）时，无连接那组被 `noServer`
///     收集后从未使用 → 整组消失。
///  4. 孤儿根与树根同 id（`topId`），`flattenUnits` 出现两个同 id 单元库，
///     星标/词条按 id 索引时互相顶掉。
void main() {
  BasicLib basic(String id, String rel,
          {String sid = '', String label = '', String base = ''}) =>
      BasicLib(
        id: id,
        name: id,
        rel: rel,
        bigId: '',
        authors: 1,
        works: 1,
        serverId: sid,
        serverLabel: label,
        serverBase: base,
      );

  /// 深度优先收集整棵子树的单元库（含根）。
  List<UnitLibrary> all(UnitLibrary u) => [
        u,
        for (final c in u.children) ...all(c),
      ];

  /// 整棵子树里出现过的基础库 id —— 「这个库有没有上屏」的唯一判据。
  Set<String> basicIds(UnitLibrary u) =>
      {for (final x in all(u)) for (final b in x.basics) b.id};

  group('1. 节点去重必须带连接：同名目录不互相顶掉', () {
    test('两台服务端都有 A：两张卡片、各自只装自己的基础库', () {
      final tree = buildUnitTree(
        nodes: const [
          LibNode(
              id: 'node:A',
              rel: 'A',
              name: 'A',
              serverId: 's1',
              serverBase: 'http://a:8090'),
          LibNode(
              id: 'node:A',
              rel: 'A',
              name: 'A',
              serverId: 's2',
              serverBase: 'http://b:8090'),
        ],
        basics: [
          basic('a1', 'A/x', sid: 's1'),
          basic('b1', 'A/y', sid: 's2'),
        ],
        topName: 'TOP',
      )!;

      final medias = tree.children;
      expect(medias.length, 2, reason: '两台服务端各一张媒体库卡');
      expect(medias.map((m) => m.node.serverId).toSet(), {'s1', 's2'});

      // 每张卡片下只有自己那一个基础库——跨连接串库正是原缺陷。
      final perServer = <String, Set<String>>{};
      for (final m in medias) {
        perServer[m.node.serverId] = {
          for (final u in all(m))
            for (final b in u.basics) b.id
        };
      }
      expect(perServer['s1'], {'a1'});
      expect(perServer['s2'], {'b1'});
    });

    test('同一连接内重复 rel 仍只保留一个（去重没被放宽）', () {
      final tree = buildUnitTree(
        nodes: const [
          LibNode(id: 'node:A', rel: 'A', name: '先到', serverId: 's1'),
          LibNode(id: 'node:A2', rel: 'A', name: '后到', serverId: 's1'),
        ],
        basics: [basic('a1', 'A/x', sid: 's1')],
        topName: 'TOP',
      )!;
      final units = all(tree).where((u) => u.rel == 'A').toList();
      expect(units.length, 1);
      expect(units.single.name, '先到', reason: '同连接重复 rel 先到先得');
    });

    test('基础库只归本连接的节点：不因「更深」而跨连接命中', () {
      // s2 的节点更深（A/deep），s1 的节点更浅（A）；b@s1 的 rel 是 A/deep/y，
      // 旧实现按「全局最深优先」会把它挂到 s2 的节点上。
      final tree = buildUnitTree(
        nodes: const [
          LibNode(id: 'node:A', rel: 'A', name: 'A', serverId: 's1'),
          LibNode(id: 'node:Ad', rel: 'A/deep', name: 'deep', serverId: 's2'),
        ],
        basics: [basic('b', 'A/deep/y', sid: 's1')],
        topName: 'TOP',
      )!;
      final owner = all(tree).firstWhere((u) => u.basics.any((x) => x.id == 'b'));
      expect(owner.node.serverId, 's1');
      expect(owner.rel, 'A');
    });
  });

  group('2. 孤儿基础库必须上屏（以前整批消失）', () {
    test('有节点的那台服务端，孤儿库仍出现在自己的媒体库里', () {
      final tree = buildUnitTree(
        nodes: const [
          LibNode(id: 'node:A', rel: 'A', name: 'A', serverId: 's1'),
        ],
        basics: [
          basic('inA', 'A/x', sid: 's1'),
          basic('orphan', 'Z/y', sid: 's1'),
        ],
        topName: 'TOP',
      )!;
      expect(basicIds(tree), containsAll(<String>['inA', 'orphan']));
    });

    test('两台服务端的孤儿库各回各的媒体库，不混在一张卡里', () {
      final tree = buildUnitTree(
        nodes: const [
          LibNode(id: 'node:A', rel: 'A', name: 'A', serverId: 's1'),
          LibNode(id: 'node:B', rel: 'B', name: 'B', serverId: 's2'),
        ],
        basics: [
          basic('a1', 'A/x', sid: 's1'),
          basic('b1', 'B/x', sid: 's2'),
          basic('bOrphan', 'Z/y', sid: 's2'),
        ],
        topName: 'TOP',
      )!;
      for (final m in tree.children) {
        final ids = {
          for (final u in all(m))
            for (final b in u.basics) b.id
        };
        if (m.node.serverId == 's2') {
          expect(ids, containsAll(<String>['b1', 'bOrphan']));
          expect(ids.contains('a1'), isFalse);
        } else {
          expect(ids, {'a1'});
        }
      }
    });

    test('无连接信息的基础库按旧行为参与最深命中（不被打成孤儿）', () {
      // 单连接旧格式：节点带连接、基础库不带——必须仍能挂上去。
      final tree = buildUnitTree(
        nodes: const [
          LibNode(id: 'node:A', rel: 'A', name: 'A', serverId: 's1'),
        ],
        basics: [basic('b', 'A/x')],
        topName: 'TOP',
      )!;
      expect(basicIds(tree), {'b'});
    });
  });

  group('3. 混合连接：旧格式那组不能被丢', () {
    test('一条带连接 + 一条不带连接：两组都在', () {
      final tree = buildUnitTree(
        nodes: const [
          LibNode(id: 'node:A', rel: 'A', name: 'A', serverId: 's1'),
          LibNode(id: 'node:L', rel: 'L', name: 'L'),
        ],
        basics: [
          basic('a1', 'A/x', sid: 's1'),
          basic('l1', 'L/y'),
        ],
        topName: 'TOP',
      )!;
      expect(basicIds(tree), containsAll(<String>['a1', 'l1']));
    });

    test('只有旧格式（全无连接）时不伪造媒体库层', () {
      final tree = buildUnitTree(
        nodes: const [
          LibNode(id: 'node:A', rel: 'A', name: 'A'),
          LibNode(id: 'node:B', rel: 'B', name: 'B'),
        ],
        basics: [basic('a1', 'A/x'), basic('b1', 'B/x')],
        topName: 'SECRET',
      )!;
      expect(tree.children.length, 2, reason: '第一层就是节点本身');
      expect(tree.children.every((c) => c.node.serverId.isEmpty), isTrue);
    });
  });

  group('4. 单元库 id 不得重复（星标/词条按 id 索引）', () {
    test('孤儿根与树根不同 id', () {
      final tree = buildUnitTree(
        nodes: const [LibNode(id: 'node:A', rel: 'A', name: 'A')],
        basics: [basic('a1', 'A/x'), basic('o1', 'Z/y')],
        topName: 'TOP',
      )!;
      final ids = all(tree).map((u) => u.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'id 重复会互相顶掉: $ids');
      expect(ids.where((i) => i == tree.id).length, 1);
    });

    test('两台服务端的孤儿根也各用不同 id', () {
      final tree = buildUnitTree(
        nodes: const [
          LibNode(id: 'node:A', rel: 'A', name: 'A', serverId: 's1'),
          LibNode(id: 'node:B', rel: 'B', name: 'B', serverId: 's2'),
        ],
        basics: [
          basic('a1', 'A/x', sid: 's1'),
          basic('o1', 'Z/y', sid: 's1'),
          basic('o2', 'Z/y', sid: 's2'),
        ],
        topName: 'TOP',
      )!;
      final ids = all(tree).map((u) => u.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'id 重复: $ids');
    });
  });

  group('结构契约：不再有第二套「按连接摊平」实现', () {
    test('buildUnitTree 里不存在 _collectServerBasics 那层搬运', () {
      // 该函数只做 `out.add(root)`，却让「按有没有 basics 分叉」的历史缺陷
      // 反复复活。删掉它是本次修复的一部分：连接归组在唯一一处完成。
      final src = File('lib/unit_library.dart').readAsStringSync();
      expect(src.contains('_collectServerBasics'), isFalse);
      // 节点去重的键必须带连接：只按 rel 去重的那行不允许回来。
      expect(src.contains('final byRel = <String, LibNode>{}'), isFalse);
      expect(src.contains('_nodeKeyOf('), isTrue);
    });

    test('媒体库卡片 id 带连接前缀，且 `media:local` 只在必要时出现', () {
      final src = File('lib/unit_library.dart').readAsStringSync();
      expect(src.contains("'media:\${sid.isEmpty ? 'local' : sid}'"), isTrue);
      expect(src.contains("'top:\${sid.isEmpty ? 'local' : sid}'"), isTrue);
    });
  });
}
