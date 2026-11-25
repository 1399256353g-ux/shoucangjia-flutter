/// 第五十一批契约：**排序不稳定 = 用户看到的顺序在刷新后变**，
/// 以及三处「取整把读数说大 / 单位档位到顶」的读数口径。
///
/// 四项真缺陷：
///  1. `sortAuthorEntries` 用 `List.sort`（内省排序，不保证稳定）→ 同名同分
///     作者刷新一次换一次位置；数据里多一位无关作者，原有作者前后顺序也变。
///  2. `pruneWatchProgress` 只按 `updatedAt` 排序 → 同一毫秒的记录被淘汰的是
///     哪一条取决于排序偶然结果；换输入顺序保留的集合完全不同。
///  3. `upsertContinueItems` 先 append 再排序 → 同一时间戳新记录被排到最后，
///     随即被上限截断（刚看过的作品从「继续观看」消失）。
///  4. `ResizeCacheStats.usedPercent` 四舍五入 → 996/1000 显示 `100%`，
///     与同屏其它三个读数（都截断）口径相反；`syncDurationLabel` 到分钟档
///     就结束 → 3599999ms 显示 `60m 00s`（不存在的读数）。
/// 另加 `category_tree.subtitle` 原始计数（0.9.270 漏掉的第六处）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/author_grid.dart';
import 'package:shoucangjia/category_tree.dart';
import 'package:shoucangjia/continue_watching.dart';
import 'package:shoucangjia/resize_cache_api.dart';
import 'package:shoucangjia/sync_ledger.dart';
import 'package:shoucangjia/watch_progress.dart';

class _Author {
  final String name;
  final num metric;
  final num works;
  final int id;
  const _Author(this.name, this.metric, this.works, this.id);
}

List<_Author> _sorted(List<_Author> src) => sortAuthorEntries<_Author>(src,
    metric: (e) => e.metric,
    works: (e) => e.works,
    name: (e) => e.name);

List<int> _ids(List<_Author> a) => [for (final e in a) e.id];

ContinueItem _item(String id, int at) => ContinueItem(
    lib: 'l',
    id: id,
    positionMs: 5000,
    durationMs: 100000,
    updatedAt: at);

void main() {
  group('作者总览排序必须稳定（同名同分不换位）', () {
    test('40 位同名同分：输出顺序 = 输入顺序', () {
      final src = <_Author>[for (var i = 0; i < 40; i++) _Author('同名', 10, 5, i)];
      expect(_ids(_sorted(src)), _ids(src));
    });

    test('数据里多一位无关作者，原有作者的相对顺序不变', () {
      final src = <_Author>[for (var i = 0; i < 40; i++) _Author('同名', 10, 5, i)];
      final before = _ids(_sorted(src));
      final grown = [...src, const _Author('张三', 10, 5, 99)];
      final after = _ids(_sorted(grown)).where((i) => i != 99).toList();
      expect(after, before);
    });

    test('真有序（分数不同）时仍是降序，不受稳定性影响', () {
      final src = [
        const _Author('a', 1, 0, 0),
        const _Author('b', 3, 0, 1),
        const _Author('c', 2, 0, 2),
      ];
      expect(_ids(_sorted(src)), [1, 2, 0]);
    });

    test('同分时按作品数降序、再按名称升序（既有语义不变）', () {
      final src = [
        const _Author('b', 10, 5, 0),
        const _Author('a', 10, 5, 1),
        const _Author('c', 99, 1, 2),
        const _Author('d', 10, 8, 3),
      ];
      expect(_sorted(src).map((e) => e.name).toList(), ['c', 'd', 'a', 'b']);
    });
  });

  group('观看记录淘汰必须与输入顺序无关', () {
    Map<String, WatchProgress> seed({bool reversed = false}) {
      final keys = [for (var i = 0; i < 40; i++) 'k$i'];
      final m = <String, WatchProgress>{};
      for (final k in reversed ? keys.reversed : keys) {
        m[k] = const WatchProgress(
            positionMs: 1000, durationMs: 100000, done: false, updatedAt: 5000);
      }
      return m;
    }

    test('同一时间戳：换输入顺序保留同一集合', () {
      final a = pruneWatchProgress(seed(), limit: 10).keys.toSet();
      final b = pruneWatchProgress(seed(reversed: true), limit: 10).keys.toSet();
      expect(a, b);
    });

    test('同一时间戳：保留哪 10 条完全由键名决定（与输入顺序无关）', () {
      final kept = pruneWatchProgress(seed(), limit: 10).keys.toList()..sort();
      // 键名按字典序：`k0,k1,k10…k19` 排在 `k2` 之前（不是数字序）。
      // 关键不在“哪个排序”，而在**同一份数据任何时候淘汰同一批**。
      expect(kept,
          ['k0', 'k1', 'k10', 'k11', 'k12', 'k13', 'k14', 'k15', 'k16', 'k17']);
    });

    test('时间戳不同时仍淘汰最久未更新的（既有语义不变）', () {
      final items = {
        for (var i = 0; i < 10; i++)
          'k$i': WatchProgress(
              positionMs: i, durationMs: 100, done: false, updatedAt: i),
      };
      expect(pruneWatchProgress(items, limit: 3).keys.toSet(), {'k7', 'k8', 'k9'});
    });

    test('不超限时原样返回', () {
      expect(pruneWatchProgress(seed(), limit: 100).length, 40);
    });
  });

  group('继续观看：同一时间戳的新记录必须留在列表里', () {
    test('同秒连续看 20 条，列表是最近 8 条的前 8 项且顺序为输入顺序', () {
      var list = <ContinueItem>[];
      for (var i = 0; i < 20; i++) {
        list = upsertContinueItems(list, _item('w$i', 5000));
      }
      // 每次插入的都在首位（时间戳相同），于是最先插的沉到末尾并被截断。
      expect(list.length, kContinueLimit);
      expect(list.map((e) => e.id).toList(),
          [for (var i = 12; i < 20; i++) 'w$i'].reversed.toList());
    });

    test('更新一条已存在的记录（时间戳不变）后它在首位，不被截断', () {
      var list = <ContinueItem>[];
      for (var i = 0; i < 12; i++) {
        list = upsertContinueItems(list, _item('w$i', 5000));
      }
      final before = list.map((e) => e.id).toList();
      final updated = upsertContinueItems(
          list, _item('w5', 5000).copyWith(positionMs: 60000));
      expect(updated.first.id, 'w5');
      expect(updated.length, kContinueLimit);
      // 除被移出的最后一条外，其余相对顺序不变。
      expect(updated.map((e) => e.id).skip(1).toList(),
          before.where((id) => id != 'w5').take(kContinueLimit - 1).toList());
    });

    test('更新的记录在末尾输入顺序下同样置顶（与输入顺序无关）', () {
      var a = <ContinueItem>[];
      for (var i = 0; i < 5; i++) {
        a = upsertContinueItems(a, _item('x$i', 7000));
      }
      final r1 = upsertContinueItems(a, _item('x0', 7000).copyWith(positionMs: 9000));
      expect(r1.first.id, 'x0');

      var b = <ContinueItem>[];
      for (var i = 4; i >= 0; i--) {
        b = upsertContinueItems(b, _item('x$i', 7000));
      }
      final r2 = upsertContinueItems(b, _item('x0', 7000).copyWith(positionMs: 9000));
      expect(r2.first.id, 'x0');
    });

    test('时间戳真不同时仍按最近降序（既有语义不变）', () {
      var list = upsertContinueItems([], _item('1', 1000));
      list = upsertContinueItems(list, _item('2', 2000));
      expect(list.map((e) => e.id).toList(), ['2', '1']);
    });
  });

  group('缓存占用百分比必须截断，不把 99.6% 说成 100%', () {
    test('996/1000 → 99（旧写法给 100）', () {
      expect(const ResizeCacheStats(bytes: 996, maxBytes: 1000).usedPercent, 99);
    });

    test('999/1000 → 99；只有真满才写 100', () {
      expect(const ResizeCacheStats(bytes: 999, maxBytes: 1000).usedPercent, 99);
      expect(const ResizeCacheStats(bytes: 1000, maxBytes: 1000).usedPercent, 100);
      expect(const ResizeCacheStats(bytes: 1001, maxBytes: 1000).usedPercent, 100);
    });

    test('小数比例同样截断（50.9% → 50）', () {
      expect(const ResizeCacheStats(bytes: 509, maxBytes: 1000).usedPercent, 50);
    });

    test('既有边界不变：超上限夹到 100、上限未知为 null、负数按 0', () {
      expect(const ResizeCacheStats(bytes: 350, maxBytes: 100).usedPercent, 100);
      expect(const ResizeCacheStats(bytes: 10, maxBytes: 0).usedPercent, isNull);
      expect(const ResizeCacheStats(bytes: 10, maxBytes: -5).usedPercent, isNull);
      expect(const ResizeCacheStats(bytes: -5, maxBytes: 100).usedPercent, 0);
      expect(const ResizeCacheStats(bytes: 50, maxBytes: 100).usedPercent, 50);
    });
  });

  group('同步耗时到分钟档不能写出 60m 00s', () {
    test('59:59.999 不再进位成「60m 00s」这种不存在的读数', () {
      // 秒级仍是「四舍五入到秒」（与 119600 → 2m 00s 同一规则），
      // 3599.999s 进位成整 3600s 后必须落到**小时档**，不能写成 60 分钟。
      expect(syncDurationLabel(3599999), '1h 00m');
      expect(syncDurationLabel(3599999).contains('60m'), isFalse);
    });

    test('满 1 小时改用小时档', () {
      expect(syncDurationLabel(3600000), '1h 00m');
      expect(syncDurationLabel(3600001), '1h 00m');
      expect(syncDurationLabel(3720000), '1h 02m');
    });

    test('48 小时上限内最大读数不出现两位以上小时以外的荒唐值', () {
      expect(syncDurationLabel(kSyncMaxDurationMs), '48h 00m');
    });

    test('既有行为不变：119600 → 2m 00s、65000 → 1m 05s、59900 → 59s', () {
      expect(syncDurationLabel(119600), '2m 00s');
      expect(syncDurationLabel(65000), '1m 05s');
      expect(syncDurationLabel(59900), '59s');
      expect(syncDurationLabel(9999), '9.9s');
      expect(syncDurationLabel(10000), '10s');
      expect(syncDurationLabel(820), '820ms');
      expect(syncDurationLabel(0), '—');
    });
  });

  group('分类树摘要用计数文案（与其它页面同一个读数）', () {
    CategoryNode node({int authors = 0, List<CategoryNode> children = const []}) =>
        CategoryNode(name: 'n', rel: 'n', authors: [
          for (var i = 0; i < authors; i++) 'a$i'
        ], children: children);

    test('12345 位作者写 1.2万，不写 12345', () {
      expect(node(authors: 12345).subtitle, '1.2万 位作者');
    });

    test('分类与作者都用同一口径', () {
      newCategory(int c, int a) =>
          CategoryNode(name: 'n', rel: 'n', authors: [
            for (var i = 0; i < a; i++) 'a$i'
          ], children: [
            for (var i = 0; i < c; i++)
              CategoryNode(name: 'c$i', rel: 'c$i', authors: const [])
          ]);
      expect(newCategory(12345, 20000).subtitle, '1.2万 个分类 · 2万 位作者');
    });

    test('小数字原样显示', () {
      expect(node(authors: 12).subtitle, '12 位作者');
      expect(node(authors: 0).subtitle, '0 位作者');
    });
  });

  group('契约扫描：这几处不得回退成裸 sort / 裸计数', () {
    String src(String p) => File(p).readAsStringSync();

    test('author_grid 排序走 stableSort', () {
      // 扫描时剔掉注释行：文件头里就写着旧写法 `list.sort(...)` 作为反例。
      final code = src('lib/author_grid.dart')
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code.contains('stableSort<T>(list'), isTrue);
      expect(code.contains('list.sort('), isFalse);
    });

    test('watch_progress 淘汰有键名次排序键', () {
      final s = src('lib/watch_progress.dart');
      expect(s.contains('c != 0 ? c : a.key.compareTo(b.key)'), isTrue);
    });

    test('continue_watching 不再「先 add 再 sort」', () {
      final s = src('lib/continue_watching.dart');
      expect(s.contains('next.insert(0, item)'), isTrue);
      expect(s.contains('next.add(item)'), isFalse);
      expect(s.contains('next.sort('), isFalse);
    });

    test('resize_cache_api 占用百分比不四舍五入', () {
      final s = src('lib/resize_cache_api.dart');
      expect(s.contains('(ratio * 100).floor()'), isTrue);
      expect(s.contains('(ratio * 100).round()'), isFalse);
    });

    test('sync_ledger 有小时档', () {
      final s = src('lib/sync_ledger.dart');
      expect(s.contains("if (totalSec >= 3600)"), isTrue);
      expect(s.contains("h \${m.toString().padLeft(2, '0')}m"), isTrue);
    });

    test('category_tree 摘要走 formatCount', () {
      final s = src('lib/category_tree.dart');
      expect(s.contains("formatCount(a)} 位作者"), isTrue);
      expect(s.contains("'\$a 位作者'"), isFalse);
    });
  });
}
