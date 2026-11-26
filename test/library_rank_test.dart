import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/library_rank.dart';

void main() {
  test('汇总作者播放与水滴', () {
    final t = libraryTotals({
      'a': {'p': 3, 'dr': 2},
      'b': {'p': 7, 'dr': 1},
      'bad': 'x',
    });
    expect(t.plays, 10);
    expect(t.drops, 3);
  });

  test('离线库不参与，未取到统计的库不参与', () {
    final rows = buildLibraryRank(
      libs: [
        {'id': 'douyin', 'name': '抖音收藏', 'baseOk': true, 'indexOk': true},
        {'id': 'off1', 'name': '离线库A', 'baseOk': false, 'indexOk': true},
        {'id': 'off2', 'name': '离线库B', 'baseOk': true, 'indexOk': false},
        {'id': 'noStats', 'name': '无统计'},
      ],
      stats: {
        'douyin': {
          'a': {'p': 10, 'dr': 1},
        },
      },
      metric: 'play',
      defaultLib: 'douyin',
    );
    expect(rows.length, 1);
    expect(rows.first.id, 'douyin');
    expect(rows.first.plays, 10);
    expect(rows.first.drops, 1);
    expect(rows.first.isDefault, isTrue);
    expect(rows.first.rank, 1);
  });

  test('按指标排序并给出名次', () {
    final libs = [
      {'id': 'a', 'name': 'A库', 'baseOk': true, 'indexOk': true},
      {'id': 'b', 'name': 'B库', 'baseOk': true, 'indexOk': true},
      {'id': 'c', 'name': 'C库', 'baseOk': true, 'indexOk': true},
    ];
    final stats = {
      'a': {
        'x': {'p': 5, 'dr': 9},
      },
      'b': {
        'x': {'p': 20, 'dr': 1},
      },
      'c': {
        'x': {'p': 20, 'dr': 3},
      },
    };
    final byPlay = buildLibraryRank(libs: libs, stats: stats, metric: 'play');
    expect(byPlay.map((e) => e.id).toList(), ['b', 'c', 'a']);
    expect(byPlay.map((e) => e.rank).toList(), [1, 2, 3]);

    final byDrop = buildLibraryRank(libs: libs, stats: stats, metric: 'drop');
    expect(byDrop.map((e) => e.id).toList(), ['a', 'c', 'b']);
    expect(byDrop.first.drops, 9);
  });

  test('默认库标记跟随服务端 default，不是客户端「当前库」', () {
    final libs = [
      {'id': 'a', 'name': 'A库', 'baseOk': true, 'indexOk': true},
      {'id': 'b', 'name': 'B库', 'baseOk': true, 'indexOk': true},
    ];
    final stats = {
      'a': {
        'x': {'p': 1},
      },
      'b': {
        'x': {'p': 2},
      },
    };
    // 服务端没下发 default → 谁都不标「默认」
    final none = buildLibraryRank(libs: libs, stats: stats, metric: 'play');
    expect(none.every((e) => !e.isDefault), isTrue);
    // 指定 b 为默认 → 只有 b 标
    final one = buildLibraryRank(
        libs: libs, stats: stats, metric: 'play', defaultLib: 'b');
    expect([for (final e in one) '${e.id}/${e.isDefault}'], ['b/true', 'a/false']);
  });

  test('同分按名称稳定排序；空库不崩', () {
    final rows = buildLibraryRank(
      libs: [
        {'id': 'z', 'name': 'Z', 'baseOk': true, 'indexOk': true},
        {'id': 'a', 'name': 'A', 'baseOk': true, 'indexOk': true},
        {'id': 'empty', 'name': '空库', 'baseOk': true, 'indexOk': true},
      ],
      stats: {
        'z': {},
        'a': {},
        'empty': {},
      },
      metric: 'play',
    );
    expect(rows.map((e) => e.id).toList(), ['a', 'z', 'empty']);
    expect(rows.every((e) => e.plays == 0 && e.drops == 0), isTrue);
    expect(buildLibraryRank(libs: const [], stats: const {}, metric: 'play'),
        isEmpty);
  });

  test('库 id 重复时不产生两行等键记录（名次不会随下发顺序岔开）', () {
    final libs = [
      {'id': 'x', 'name': '同名', 'baseOk': true, 'indexOk': true},
      {'id': 'x', 'name': '同名', 'baseOk': true, 'indexOk': true},
      {'id': 'y', 'name': '同名', 'baseOk': true, 'indexOk': true},
    ];
    final stats = {
      'x': {
        'a': {'p': 10},
      },
      'y': {
        'a': {'p': 10},
      },
    };
    for (var i = 0; i < 5; i++) {
      final rows = buildLibraryRank(libs: libs, stats: stats, metric: 'play');
      expect(rows.length, 2, reason: '同一个库 id 只该占一行');
      expect(rows.map((e) => e.id).toList(), ['x', 'y'],
          reason: '四级排序键最后一档是 id，结果与入参顺序无关');
      expect(rows.map((e) => e.rank).toList(), [1, 2]);
    }
    // 入参换序也是同一结果
    final rev = buildLibraryRank(
        libs: libs.reversed.toList(), stats: stats, metric: 'play');
    expect(rev.map((e) => e.id).toList(), ['x', 'y']);
  });

  test('解析 author_stats 的 authors 包装', () {    final m = statsAuthors({
      'updated': 1,
      'authors': {
        'a': {'p': 2},
      },
    });
    expect(m.keys, ['a']);
    expect(statsAuthors(null), isEmpty);
    expect(statsAuthors({'a': 1}), isEmpty);
  });

  test('切指标时名次跟着指标重排（名次与数字不能互相矛盾）', () {
    final rows = buildLibraryRank(
      libs: [
        {'id': 'a', 'name': 'A', 'baseOk': true, 'indexOk': true},
        {'id': 'b', 'name': 'B', 'baseOk': true, 'indexOk': true},
      ],
      stats: {
        'a': {
          'x': {'p': 100, 'dr': 1},
        },
        'b': {
          'x': {'p': 10, 'dr': 50},
        },
      },
      metric: 'play',
    );
    expect(rows.map((e) => e.id).toList(), ['a', 'b']);

    // 只换指标、不重排 = 名次与右侧数字矛盾（这就是本轮修掉的形态）
    final byDrop = rankOrder(rows, 'drop');
    expect(byDrop.map((e) => e.id).toList(), ['b', 'a'],
        reason: '水滴多的库排在前面');
    expect(byDrop.map((e) => e.rank).toList(), [1, 2]);
    // 数据本身不因重排而变
    expect(byDrop.first.plays, 10);
    expect(byDrop.first.drops, 50);
    expect(byDrop.last.plays, 100);
    // 再切回来仍是播放量顺序
    expect(rankOrder(byDrop, 'play').map((e) => e.id).toList(), ['a', 'b']);
  });

  test('buildLibraryRank 与 rankOrder 用同一个比较器', () {
    final libs = [
      {'id': 'z', 'name': '同名', 'baseOk': true, 'indexOk': true},
      {'id': 'a', 'name': '同名', 'baseOk': true, 'indexOk': true},
    ];
    final stats = {
      'z': {
        'x': {'p': 5, 'dr': 5},
      },
      'a': {
        'x': {'p': 5, 'dr': 5},
      },
    };
    for (final metric in ['play', 'drop']) {
      final built = buildLibraryRank(libs: libs, stats: stats, metric: metric);
      final reordered = rankOrder(built, metric);
      expect(reordered.map((e) => e.id).toList(),
          built.map((e) => e.id).toList(),
          reason: '$metric：同一套规则重排不该换位');
      // 已排名单再次按同名规则排序也必须稳定（id 是最后一级键）
      expect(reordered.map((e) => e.id).toList(), ['a', 'z']);
    }
  });

  test('页面切指标必须重排名次（不许只换数字）', () {
    final main = File('lib/main.dart').readAsStringSync();
    final start = main.indexOf('class _LibraryRankPageState');
    final end = main.indexOf('class AuthorGridCard', start);
    final body = main.substring(start, end);
    expect(body.contains('rankOrder(rows, metric)'), isTrue,
        reason: '切指标只改 metric 会留下「播放量第 1、水滴数却更少」的矛盾');
    expect('rankOrder('.allMatches(body).length, greaterThanOrEqualTo(2),
        reason: '两个 ChoiceChip 都要重排');
    // 排序规则只有一份：页面不得自己写比较器
    expect(body.contains('compareLibraryRank('), isFalse,
        reason: '比较器只在 library_rank.dart');
    expect(body.contains('.sort((a, b)'), isFalse);
  });
}
