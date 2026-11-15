import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/work_plays.dart';

void main() {
  test('记录键', () {
    expect(workPlaysKey(lib: 'lib-1', id: 'a'), 'lib-1/a');
    expect(workPlaysKey(lib: '', id: 'a'), 'a');
    expect(workPlaysKey(lib: 'lib-1', id: ''), '');
  });

  group('计数', () {
    test('自增并记住缩略图', () {
      var m = <String, WorkPlay>{};
      m = bumpWorkPlay(m, 'l/a');
      expect(m['l/a']!.count, 1);
      expect(m['l/a']!.thumb, '');
      m = bumpWorkPlay(m, 'l/a', thumb: '/media/l/a.jpg');
      expect(m['l/a']!.count, 2);
      expect(m['l/a']!.thumb, '/media/l/a.jpg');
      // 后续没有缩略图时保留旧值
      m = bumpWorkPlay(m, 'l/a', thumb: '');
      expect(m['l/a']!.thumb, '/media/l/a.jpg');
      expect(m['l/a']!.count, 3);
    });

    test('空键不记录', () {
      final m = bumpWorkPlay(<String, WorkPlay>{}, '');
      expect(m, isEmpty);
    });
  });

  test('编码 / 解析往返', () {
    final m = {
      'l/b': const WorkPlay(count: 2, thumb: '/media/l/b.jpg'),
      'l/a': const WorkPlay(count: 5),
    };
    final raw = encodeWorkPlays(m);
    final back = parseWorkPlays(raw);
    expect(back['l/a']!.count, 5);
    expect(back['l/b']!.count, 2);
    expect(back['l/b']!.thumb, '/media/l/b.jpg');
  });

  test('坏数据容错', () {
    expect(parseWorkPlays(null), isEmpty);
    expect(parseWorkPlays('not json'), isEmpty);
    expect(parseWorkPlays('{"l/a":{"n":0}}'), isEmpty);
    expect(parseWorkPlays('{"l/a":{"n":"3"}}')['l/a']!.count, 3);
  });

  test('按库过滤', () {
    final m = {
      'l1/a': const WorkPlay(count: 3, thumb: 't1'),
      'l1/b': const WorkPlay(count: 1, thumb: 't2'),
      'l2/a': const WorkPlay(count: 9, thumb: 't3'),
    };
    final l1 = playsOfLib(m, 'l1');
    expect(l1.keys.toSet(), {'a', 'b'});
    expect(l1['a']!.count, 3);
    expect(playsOfLib(m, ''), isEmpty);
  });

  test('取播放量最高且有缩略图的作品', () {
    final m = {
      'l/a': const WorkPlay(count: 2, thumb: 'ta'),
      'l/b': const WorkPlay(count: 7),
      'l/c': const WorkPlay(count: 5, thumb: 'tc'),
    };
    // b 次数最高但没有缩略图 → 跳过
    expect(topPlayed(m)!.thumb, 'tc');
    expect(topPlayed(<String, WorkPlay>{}), isNull);
  });

  test('超出上限按次数淘汰', () {
    final m = {
      for (var i = 0; i < 10; i++)
        'l/$i': WorkPlay(count: i == 0 ? 1 : 100 + i, thumb: 't$i'),
    };
    final pruned = pruneWorkPlays(m, limit: 3);
    expect(pruned.length, 3);
    expect(pruned.containsKey('l/0'), isFalse);
  });
}
