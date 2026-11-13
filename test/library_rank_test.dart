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
      currentLib: 'douyin',
    );
    expect(rows.length, 1);
    expect(rows.first.id, 'douyin');
    expect(rows.first.plays, 10);
    expect(rows.first.drops, 1);
    expect(rows.first.current, isTrue);
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

  test('解析 author_stats 的 authors 包装', () {
    final m = statsAuthors({
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
