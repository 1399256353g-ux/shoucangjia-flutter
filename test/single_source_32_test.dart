/// 第五十二批契约：**同一个数据两种排列**（续）——排序不稳定在四个此前没检查
/// 过的调用点里重新出现，以及一处「总数」读的是「已载入条数」。
///
/// 第五十一批收口了 `sortAuthorEntries` / `pruneWatchProgress` /
/// `upsertContinueItems` / `usedPercent` 四处。这一批是同一类缺口的另外四条，
/// 它们的共同点：**数据没变、读数没变，但顺序/条数在同一个会话里会变一次**，
/// 而且变完之后看起来都很正常，没人会报上来。
///
///  1. 超容量淘汰只按 mtime 排 → 同一毫秒落盘的一批封面「淘汰哪几张」取决于
///     排序内部结果，清两次留下的文件不一样，命中率跟着抖；
///  2. 基础库页底部「共 N 件」插的是 `shown.length`（已载入条数），而列表
///     是 60 条一页的分页加载 → 顶部 tab 写「作品 300」、底部写「共 60 件」，
///     往下滚两屏变成「共 180 件」；
///  3. 爬虫脚本列表按名称 `List.sort` → 同名脚本（重复挂载/两种相对路径各报
///     一次）之间换位置，下拉选中项跟着跳；
///  4. 单元库建树的两处「按深度排序」、基础库列表的「按 rel 排序」、排行榜
///     库下拉的「按名称排序」同样是 `List.sort`，同深度/同名条目顺序不定。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/count_label.dart';
import 'package:shoucangjia/cover_cache.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/source_lib.dart';
import 'package:shoucangjia/unit_crawler.dart';
import 'package:shoucangjia/unit_library.dart';

String _lib(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

List<String> _paths(List<MapEntry<File, DateTime>> e) =>
    [for (final x in e) x.key.path];

MapEntry<File, DateTime> _entry(String path, DateTime at) =>
    MapEntry(File(path), at);

void main() {
  group('超容量淘汰顺序与目录遍历顺序无关', () {
    final at = DateTime(2026, 11, 26, 4, 30, 0, 500);

    test('同一毫秒按路径升序（与输入顺序无关）', () {
      final a = coverSweepOrder([
        _entry('/c/m.jpg', at),
        _entry('/c/a.jpg', at),
        _entry('/c/z.jpg', at),
      ]);
      final b = coverSweepOrder([
        _entry('/c/z.jpg', at),
        _entry('/c/m.jpg', at),
        _entry('/c/a.jpg', at),
      ]);
      expect(_paths(a), ['/c/a.jpg', '/c/m.jpg', '/c/z.jpg']);
      expect(_paths(a), _paths(b));
    });

    test('时间不同时仍按最久未使用在前', () {
      final old = DateTime(2026, 1, 1);
      final neu = DateTime(2026, 11, 1);
      final out = coverSweepOrder([
        _entry('/c/zzz.jpg', neu),
        _entry('/c/aaa.jpg', old),
      ]);
      expect(_paths(out), ['/c/aaa.jpg', '/c/zzz.jpg']);
    });

    test('不改动入参列表本身', () {
      final src = [
        _entry('/c/b.jpg', at),
        _entry('/c/a.jpg', at),
      ];
      coverSweepOrder(src);
      expect(_paths(src), ['/c/b.jpg', '/c/a.jpg']);
    });

    test('40 条同一毫秒的记录给出确定的排列', () {
      final src = [
        for (var i = 0; i < 40; i++)
          _entry('/c/${(1000 + i).toString()}.jpg', at),
      ];
      final first = _paths(coverSweepOrder(src));
      final shuffled = _paths(coverSweepOrder(src.reversed.toList()));
      expect(first, shuffled);
      expect(first.first, '/c/1000.jpg');
      expect(first.last, '/c/1039.jpg');
    });
  });

  group('作品计数行：总数与已载入条数不能混为一谈', () {
    test('全部加载完时写「共 N 件」', () {
      expect(worksCountLabel(shown: 300, loaded: 300, total: 300), '共 300 件');
    });

    test('还有未加载的页时两个数都写清', () {
      expect(worksCountLabel(shown: 60, loaded: 60, total: 300),
          '已载入 60 / 共 300 件');
      expect(worksCountLabel(shown: 180, loaded: 180, total: 300),
          '已载入 180 / 共 300 件');
    });

    test('服务端没给 total 时只认已载入条数，不编造总数', () {
      expect(worksCountLabel(shown: 42, loaded: 42), '共 42 件');
      expect(worksCountLabel(shown: 42, loaded: 42, total: 0), '共 42 件');
    });

    test('total 比已载入还小时以已载入为准（不能出现 60 件装 120 张卡）', () {
      expect(worksCountLabel(shown: 120, loaded: 120, total: 60), '共 120 件');
    });

    test('叠加类型筛选时写「符合 N 件」，并保留加载进度', () {
      expect(
          worksCountLabel(
              shown: 25, loaded: 300, total: 300, filtered: true),
          '符合 25 件');
      expect(
          worksCountLabel(
              shown: 25, loaded: 60, total: 300, filtered: true),
          '符合 25 件 · 已载入 60 / 共 300 件');
    });

    test('计数走统一单位（不写六个数字）', () {
      expect(worksCountLabel(shown: 12345, loaded: 12345, total: 12345),
          '共 1.2万 件');
    });

    test('负数/零不会输出负数件数', () {
      expect(worksCountLabel(shown: -5, loaded: -5, total: -1), '共 0 件');
    });

    test('基础库页面底部与「全部」菜单都走这一条出口', () {
      final src = _lib('lib/basic_lib_page.dart');
      expect(src.contains('worksCountLabel('), isTrue,
          reason: '底部「共 N 件」必须由 worksCountLabel 给出');
      expect(src.contains("Text('共 \${shown.length} 件'"), isFalse,
          reason: '不能再直接插已载入条数');
      expect(src.contains("Text('全部 \${works.length}'"), isFalse,
          reason: '「全部」是该库作品总数，不是内存里的条数');
    });
  });

  group('爬虫脚本列表：同名脚本保持服务端下发顺序', () {
    test('同名脚本换输入顺序得到同一结果', () {
      final a = UnitCrawlerScript.listFrom([
        {'name': 'sync.sh', 'size': 1},
        {'name': 'sync.sh', 'size': 2},
        {'name': 'a.py', 'size': 3},
        {'name': 'sync.sh', 'size': 4},
      ]);
      final b = UnitCrawlerScript.listFrom([
        {'name': 'sync.sh', 'size': 4},
        {'name': 'sync.sh', 'size': 2},
        {'name': 'a.py', 'size': 3},
        {'name': 'sync.sh', 'size': 1},
      ]);
      expect([for (final s in a) s.name], ['a.py', 'sync.sh', 'sync.sh', 'sync.sh']);
      // 同名之间保持各自输入里的相对顺序（稳定），不按 size 重新排。
      expect([for (final s in a) s.size], [3, 1, 2, 4]);
      expect([for (final s in b) s.size], [3, 4, 2, 1]);
    });

    test('名称不同仍按名称升序', () {
      final list = UnitCrawlerScript.listFrom([
        {'name': 'z.py'},
        {'name': 'a.sh'},
        {'name': 'm.js'},
      ]);
      expect([for (final s in list) s.name], ['a.sh', 'm.js', 'z.py']);
    });
  });

  group('单元库建树：同深度节点不因多一个无关节点而换位', () {
    BasicLib basic(String id, String rel) => BasicLib(
          id: id,
          name: rel.split('/').last,
          rel: rel,
          bigId: '',
          authors: 1,
          works: 1,
        );

    List<String> mediaOrder(List<LibNode> nodes, List<BasicLib> basics) {
      final tree = buildUnitTree(nodes: nodes, basics: basics);
      return [for (final c in tree!.children) c.id];
    }

    test('同深度根顺序与输入一致，且不受无关同深度节点影响', () {
      final nodes = [
        const LibNode(id: 'b', rel: 'B', name: 'B'),
        const LibNode(id: 'a', rel: 'A', name: 'A'),
        const LibNode(id: 'c', rel: 'C', name: 'C'),
      ];
      final basics = [basic('l1', 'B/x'), basic('l2', 'A/x'), basic('l3', 'C/x')];
      final first = mediaOrder(nodes, basics);
      // 多一个无关的同深度节点（不挂任何基础库，建树时被剪掉）+ 打乱输入。
      final more = [
        const LibNode(id: 'nope', rel: 'NOPE', name: 'NOPE'),
        ...nodes.reversed,
      ];
      final second = mediaOrder(more, basics);
      expect(first, second);
      // 单连接时第一层按名称排序（A/B/C），不再受输入顺序影响。
      expect(first, ['a', 'b', 'c']);
    });

    test('深层节点总在浅层之后（深度降序仍成立）', () {
      final nodes = [
        const LibNode(id: 'deep', rel: 'A/sub/deep', name: 'deep'),
        const LibNode(id: 'mid', rel: 'A/sub', name: 'sub'),
        const LibNode(id: 'top', rel: 'A', name: 'A'),
      ];
      final tree = buildUnitTree(
        nodes: nodes,
        basics: [basic('l1', 'A/sub/deep/y')],
      );
      // 基础库挂到最深的节点（归属靠深度优先，而不是靠输入顺序）。
      expect(tree!.children.single.id, 'top');
      expect(tree.children.single.children.single.id, 'mid');
      expect(tree.children.single.children.single.children.single.basics.single.id,
          'l1');
    });

    test('同一个 rel 只保留第一条（去重之后顺序仍是确定的）', () {
      final nodes = [
        const LibNode(id: 'x1', rel: 'X', name: 'X'),
        const LibNode(id: 'x2', rel: 'X', name: 'X'),
      ];
      final tree = buildUnitTree(nodes: nodes, basics: [basic('l1', 'X/y')]);
      expect(tree!.children.single.id, 'x1');
    });
  });

  group('基础库列表：同 rel 条目保持输入顺序', () {
    Map<String, dynamic> row(String id, String rel, String path) => {
          'id': id,
          'name': rel,
          'path': path,
          'big_id': '',
        };

    test('同一 rel 两条记录换输入顺序仍是同一排列', () {
      final base = '/root';
      final l1 = basicsUnderBase({
        'basicLibraries': [
          row('lib-002', 'A', '$base/A'),
          row('lib-001', 'A', '$base/A'),
          row('lib-003', 'B', '$base/B'),
        ]
      }, base);
      final l2 = basicsUnderBase({
        'basicLibraries': [
          row('lib-001', 'A', '$base/A'),
          row('lib-002', 'A', '$base/A'),
          row('lib-003', 'B', '$base/B'),
        ]
      }, base);
      expect([for (final b in l1) b.id], ['lib-002', 'lib-001', 'lib-003']);
      expect([for (final b in l2) b.id], ['lib-001', 'lib-002', 'lib-003']);
      // 两者都是「A 在前、B 在后」且 A 组内保持输入顺序。
      expect(l1.first.rel, 'A');
      expect(l1.last.rel, 'B');
    });
  });

  group('契约扫描：这几处不得再退回裸 List.sort', () {
    test('unit_crawler / source_lib / cover_cache 走稳定排序', () {
      expect(_lib('lib/unit_crawler.dart').contains('stableSort('), isTrue);
      expect(_lib('lib/source_lib.dart').contains('stableSort('), isTrue);
      expect(_lib('lib/cover_cache.dart').contains('coverSweepOrder('), isTrue);
    });

    test('单元库建树的两处深度排序不再用 sort', () {
      final src = _lib('lib/unit_library.dart');
      expect(src.contains('b.segments.length.compareTo(a.segments.length)'),
          isTrue);
      // 深度比较仍在，但必须由 stableSort 驱动：`..sort(` 后面直接跟深度比较
      // 是旧写法，不能再出现。
      expect(
          RegExp(r'\.\.sort\(\(a, b\) => b\.segments\.length')
              .hasMatch(src),
          isFalse);
    });

    test('基础库页作者排序不再用裸 list.sort', () {
      final src = _lib('lib/basic_lib_page.dart');
      expect(src.contains('stableSort(list,'), isTrue);
      expect(src.contains('list.sort((x, y) {'), isFalse);
    });
  });
}
