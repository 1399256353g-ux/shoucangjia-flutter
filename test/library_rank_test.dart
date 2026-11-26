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
}
