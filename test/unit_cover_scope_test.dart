import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/multi_server.dart';
import 'package:shoucangjia/unit_cover_store.dart';
import 'package:shoucangjia/unit_library.dart' show parseNodesPayload;

/// owner 2026-11-26：封面指针的**作用域**必须包含连接。
///
/// 背景：0.9.266 刚把「单元库选过往封面，返回界面就恢复原样」修成
/// 「本机意见只有一份」（[UnitCoverStore]），0.9.267 补上了整棵树的
/// `cover.u` 合并（`mergeLibraryTrees` 的 `unitCovers`）。两处都只按
/// **rel** 作键，而 rel 是相对各自媒体库根的路径——两台服务端各有一个
/// `(1) 抖音` 时字符串完全一样。
///
/// 这与 `buildUnitTree` 的节点去重必须带连接（`_nodeKeyOf`）是同一条
/// 规则，那边 3e0aa99 修好了，封面这两张表当时漏了。后果不是「显示不好看」：
/// A 的连接会去请求 B 的封面文件（404），或者 B 卡片直接显示 A 的图。
void main() {
  group('UnitCoverStore 的键带连接', () {
    setUp(UnitCoverStore.reset);

    const urlA = 'http://nas-a:8090/media/lib-001/_cover/c1.jpg';
    const urlB = 'http://nas-b:8090/media/lib-001/_cover/c1.jpg';

    test('同 rel 不同连接互不串封面', () {
      final a = UnitCoverStore.unitKey('(1) 抖音', serverId: 's1');
      final b = UnitCoverStore.unitKey('(1) 抖音', serverId: 's2');
      expect(a, isNot(b));
      UnitCoverStore.set(a, urlA);
      expect(UnitCoverStore.rawOf(a), urlA);
      expect(UnitCoverStore.rawOf(b), isNull);
    });

    test('基础库同理：同 id 两条连接分开存', () {
      final a = UnitCoverStore.basicKey('lib-001', serverId: 's1');
      final b = UnitCoverStore.basicKey('lib-001', serverId: 's2');
      UnitCoverStore.set(a, urlA);
      expect(UnitCoverStore.rawOf(b), isNull);
      UnitCoverStore.set(b, urlB);
      expect(UnitCoverStore.rawOf(a), urlA);
      expect(UnitCoverStore.rawOf(b), urlB);
    });

    test('「没连接」与「有连接」不塌成同一个键', () {
      // 空连接仍留固定字段位：否则 `u:␁A` 与 `u:A` 拼出来的键含义不同
      // 却可能被后来的写法顶掉，作用域又退回 rel。
      final none = UnitCoverStore.unitKey('A');
      final some = UnitCoverStore.unitKey('A', serverId: 's1');
      expect(none, isNot(some));
      UnitCoverStore.set(none, urlA);
      expect(UnitCoverStore.rawOf(some), isNull);
    });

    test('连接标识两侧空白等价（与 _nodeKeyOf 的 trim 口径一致）', () {
      expect(UnitCoverStore.unitKey('A', serverId: ' s1 '),
          UnitCoverStore.unitKey('A', serverId: 's1'));
    });

    test('缺分隔符的旧式键一律视为脏键（不读不写）', () {
      // 旧实现拼的是 `u:A/B`。若某处仍按旧写法拼，写入必须被拒绝，
      // 而不是悄悄写进一张永远读不到的表。
      final before = UnitCoverStore.revision.value;
      UnitCoverStore.set('u:A/B', urlA);
      expect(UnitCoverStore.rawOf('u:A/B'), isNull);
      expect(UnitCoverStore.revision.value, before);
      UnitCoverStore.set('b:lib-001', urlA);
      expect(UnitCoverStore.rawOf('b:lib-001'), isNull);
      expect(UnitCoverStore.revision.value, before);
    });

    test('恢复自动（空串）也在本连接作用域内', () {
      final a = UnitCoverStore.unitKey('A', serverId: 's1');
      final b = UnitCoverStore.unitKey('A', serverId: 's2');
      UnitCoverStore.set(a, urlA);
      UnitCoverStore.set(a, '');
      expect(UnitCoverStore.isAuto(a), isTrue);
      // 另一连接没有任何意见，不能被这次「恢复自动」牵连。
      expect(UnitCoverStore.rawOf(b), isNull);
      expect(UnitCoverStore.isAuto(b), isFalse);
    });
  });

  group('mergeLibraryTrees 的封面表按连接分开', () {
    ServerConn s(String id) => ServerConn(
          id: id,
          label: id,
          base: 'http://$id:8090',
          user: 'u',
          pass: 'p',
        );

    Map<String, dynamic> tree(String coverRel, String coverPath) => {
          'bigLibraries': <Map<String, dynamic>>[],
          'basicLibraries': <Map<String, dynamic>>[
            {'id': 'lib-001', 'name': 'l', 'rel': 'A'}
          ],
          'nodes': <Map<String, dynamic>>[
            {
              'rel': coverRel,
              'cover': {'u': coverPath},
            }
          ],
        };

    test('两台服务端同名 rel 各留各的指针', () {
      final merged = mergeLibraryTrees([
        ServerLibraries(
            server: s('s1'),
            tree: tree('(1) 抖音', '/media/lib-001/_cover/a1.jpg')),
        ServerLibraries(
            server: s('s2'),
            tree: tree('(1) 抖音', '/media/lib-001/_cover/b1.jpg')),
      ])!;
      final covers = merged['unitCovers'] as Map;
      expect(covers[unitCoverKey('s1', '(1) 抖音')],
          '/media/lib-001/_cover/a1.jpg');
      expect(covers[unitCoverKey('s2', '(1) 抖音')],
          '/media/lib-001/_cover/b1.jpg');
      // 裸 rel 不得出现在表里——它无法区分连接。
      expect(covers['(1) 抖音'], isNull);
      expect(covers.length, 2);
    });

    test('分隔符写法不同的同一 rel 归一成一个键', () {
      final merged = mergeLibraryTrees([
        ServerLibraries(
            server: s('s1'),
            tree: tree(r'A\B', '/media/lib-001/_cover/x.jpg')),
      ])!;
      final covers = merged['unitCovers'] as Map;
      expect(covers[unitCoverKey('s1', 'A/B')], '/media/lib-001/_cover/x.jpg');
      expect(covers.length, 1);
    });

    test('非媒体路径的指针不收（避免半截路径被当封面请求）', () {
      final merged = mergeLibraryTrees([
        ServerLibraries(server: s('s1'), tree: tree('A', 'http://cdn/x.jpg')),
      ]);
      // 没有可用指针时不带这张表。
      expect(merged!.containsKey('unitCovers'), isFalse);
    });
  });

  group('parseNodesPayload：rel 与 covers 键同一套归一', () {
    test('反斜杠/多余分隔符的节点只产生一个归一 rel', () {
      final p = parseNodesPayload({
        'nodes': [r'A\B', 'A//B/', 'A/B'],
      });
      // 三种写法是同一个目录；不归一就会建出三张同名卡片。
      expect(p.rels, ['A/B']);
    });

    test('对象形式的节点取 rel/path/name', () {
      final p = parseNodesPayload({
        'nodes': [
          {'rel': r'X\Y'},
          {'path': 'X/Y'},
          {'name': 'X/Y'},
        ],
      });
      expect(p.rels, ['X/Y']);
    });

    test('covers 的键归一后才能被节点查到', () {
      // 服务端把 covers 键写成 `A\B`、节点写成 `A/B` 时，旧实现两处都只 trim，
      // 卡片永远拿不到这张封面（写进去、读不回来）。
      final p = parseNodesPayload({
        'nodes': ['A/B'],
        'covers': {r'A\B': '/media/lib-001/_cover/v1.jpg'},
      });
      expect(p.covers['A/B'], '/media/lib-001/_cover/v1.jpg');
    });

    test('非媒体路径的 covers 不收', () {
      final p = parseNodesPayload({
        'nodes': ['A'],
        'covers': {'A': 'http://cdn/x.jpg', 'B': '/api/thumb/lib/x'},
      });
      expect(p.covers, isEmpty);
    });

    test('载荷不是对象时返回空（不抛异常）', () {
      expect(parseNodesPayload(null).rels, isEmpty);
      expect(parseNodesPayload('oops').covers, isEmpty);
      expect(parseNodesPayload({}).rels, isEmpty);
    });
  });

  group('契约扫描：同一件事只有一处实现', () {
    String libText() {
      final b = StringBuffer();
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        b.writeln(f.readAsStringSync().replaceAll('\r\n', '\n'));
      }
      return b.toString();
    }

    test('页面不得自己解析 /api/nodes 的 covers（只走 parseNodesPayload）', () {
      final s = libText();
      // 两处手写解析曾经同时存在（主页与文件结构页），改一处忘一处就会出现
      // 「主页有封面、文件结构页没有」。`/api/folders` 的 nodes 是另一个载荷，
      // 所以这里只钉 covers 映射的读取点。
      final hits = RegExp(r"\[\s*'covers'\s*\]").allMatches(s).length;
      expect(hits, lessThanOrEqualTo(1),
          reason: 'covers 映射出现 $hits 处，只允许 parseNodesPayload 内一处');
    });

    test('封面表不用裸 rel 查（必须带连接）', () {
      final s = libText();
      expect(s.contains('treeCovers[normalizeUnitRel('), isFalse,
          reason: '裸 rel 查封面表会把 B 的指针交给 A 的卡片');
      expect(s.contains('out.putIfAbsent(rel, () => u)'), isFalse,
          reason: '封面表键必须走 unitCoverKey（带连接）');
    });
  });
}
