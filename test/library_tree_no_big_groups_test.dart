import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/multi_server.dart';

/// 0.9.321 第八十五批（项 1）：
///
/// 新服务端只下发 `basicLibraries`，`bigLibraries`（旧「大库」分组）已不再
/// 出现。两处解析都把**两者**当必需字段：
///
/// ```
/// LibraryTree.parse:      if (rawBigs is! List || rawBasics is! List) return null
/// mergeLibraryTrees:      if (rb is! List || rs is! List) continue
/// ```
///
/// 于是首页拿到的模型是 null → `buildUnitTree(basics: t?.allBasics ?? [])`
/// 拿到零基础库 → 所有作者/基础库词条落 SECRET、单元库卡片作者数与作品数
/// 全是 0，而 `/api/libraries.json` 里那些字段其实一个都不缺。
String _code(String path) => File(path).readAsStringSync();

Map<String, dynamic> _basicsOnly() => {
      'root': '/root',
      'basicLibraries': [
        {'id': 'lib-1', 'rel': 'A/one', 'name': 'one', 'authors': 3, 'works': 9},
        {'id': 'lib-2', 'rel': 'B/two', 'name': 'two', 'authors': 1, 'works': 2},
      ],
    };

void main() {
  group('LibraryTree.parse 不再把旧「大库」分组当必需字段', () {
    test('只有基础库的载荷照样解析出全部基础库', () {
      final t = LibraryTree.parse(_basicsOnly());
      expect(t, isNotNull);
      expect(t!.bigs, isEmpty, reason: '没有旧分组就没有旧分组，不是解析失败');
      expect(t.allBasics.map((b) => b.id), ['lib-1', 'lib-2']);
      expect(t.unassigned.length, 2, reason: '全部基础库进「未归属」，一条都不能丢');
    });

    test('旧分组仍然认（服务端老版本还能用）', () {
      final t = LibraryTree.parse({
        ..._basicsOnly(),
        'bigLibraries': [
          {'id': 'big-01', 'name': 'g', 'path': '/root/A'},
        ],
        'basicLibraries': [
          {'id': 'lib-1', 'rel': 'A/one', 'big_id': 'big-01'},
          {'id': 'lib-2', 'rel': 'B/two', 'big_id': 'big-01'},
        ],
      })!;
      expect(t.bigs.single.basics.map((b) => b.id), ['lib-1', 'lib-2']);
      expect(t.unassigned, isEmpty);
    });

    test('一条基础库都读不出来才算 v1（返回 null，页面走旧列表）', () {
      expect(LibraryTree.parse({'libraries': []}), isNull);
      expect(LibraryTree.parse({'basicLibraries': <dynamic>[]}), isNull);
      expect(LibraryTree.parse({'bigLibraries': <dynamic>[]}), isNull);
    });

    test('契约：`bigLibraries` 不再是 parse 的必需判定', () {
      final src = _code('lib/library_tree.dart');
      expect(src.contains('if (rawBigs is! List || rawBasics is! List)'),
          isFalse,
          reason: '旧分组缺失又被当成整棵解析失败');
      expect(src.contains('if (rawBasics is! List) return null'), isTrue);
    });
  });

  group('mergeLibraryTrees 只要求基础库', () {
    ServerConn conn(String id) => ServerConn(
          id: id,
          label: id,
          base: 'http://$id:8090',
          user: 'u',
          pass: 'p',
        );

    test('没有旧分组的快照仍参与合并（不再整条跳过）', () {
      final merged = mergeLibraryTrees([
        ServerLibraries(server: conn('s1'), tree: _basicsOnly()),
      ]);
      expect(merged, isNotNull);
      expect((merged!['basicLibraries'] as List).length, 2);
      expect(merged['bigLibraries'], isEmpty);
    });

    test('两台都只有基础库时按 id 去重并保留来源连接', () {
      final merged = mergeLibraryTrees([
        ServerLibraries(server: conn('s1'), tree: _basicsOnly()),
        ServerLibraries(server: conn('s2'), tree: _basicsOnly()),
      ])!;
      final basics = merged['basicLibraries'] as List;
      expect(basics.length, 2);
      expect((basics.first as Map)['_serverId'], 's1');
    });

    test('连基础库都没有的快照不算「有数据」', () {
      expect(
          mergeLibraryTrees([
            ServerLibraries(server: conn('s1'), tree: {'root': '/r'}),
          ]),
          isNull);
    });

    test('契约：合并处不得再要求 bigLibraries', () {
      final src = _code('lib/multi_server.dart');
      expect(src.contains("if (rb is! List || rs is! List) continue"), isFalse,
          reason: '旧分组缺失 → 整条快照被跳过 → 首页零基础库');
      expect(src.contains('if (rs is! List) continue'), isTrue);
    });
  });
}
