import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/cover_memo.dart';
import 'package:shoucangjia/work_plays.dart';

void main() {
  group('CoverMemo', () {
    test('同一键只计算一次', () {
      final memo = CoverMemo();
      var calls = 0;
      String compute() {
        calls++;
        return '/media/a.jpg';
      }

      expect(memo.resolve('u1', compute), '/media/a.jpg');
      expect(memo.resolve('u1', compute), '/media/a.jpg');
      expect(calls, 1);
      expect(memo.hits, 1);
      expect(memo.misses, 1);
      expect(memo.size, 1);
    });

    test('不同键各自计算', () {
      final memo = CoverMemo();
      var calls = 0;
      memo.resolve('a', () {
        calls++;
        return 'A';
      });
      memo.resolve('b', () {
        calls++;
        return 'B';
      });
      expect(calls, 2);
      expect(memo.size, 2);
    });

    test('空串同样缓存（避免反复扫描）', () {
      final memo = CoverMemo();
      var calls = 0;
      String compute() {
        calls++;
        return '';
      }

      expect(memo.resolve('empty', compute), '');
      expect(memo.resolve('empty', compute), '');
      expect(calls, 1);
    });

    test('clear 后重新计算', () {
      final memo = CoverMemo();
      var calls = 0;
      String compute() {
        calls++;
        return 'x$calls';
      }

      expect(memo.resolve('k', compute), 'x1');
      memo.clear();
      expect(memo.size, 0);
      expect(memo.resolve('k', compute), 'x2');
    });

    test('超过上限时整体清空，不会无限增长', () {
      final memo = CoverMemo(maxEntries: 3);
      for (var i = 0; i < 10; i++) {
        memo.resolve('k$i', () => 'v$i');
      }
      expect(memo.size <= 3, isTrue);
    });
  });

  group('WorkPlaysStore 按库汇总', () {
    int totalIn(String lib) =>
        WorkPlaysStore.countsFor(lib).values.fold<int>(0, (a, b) => a + b.count);
    test('按库汇总次数', () {
      WorkPlaysStore.resetForTest(items: <String, WorkPlay>{
        'l1/a': const WorkPlay(count: 2),
        'l1/b': const WorkPlay(count: 3),
        'l2/c': const WorkPlay(count: 1),
      });
      expect(totalIn('l1'), 5);
      expect(totalIn('l2'), 1);
      expect(totalIn('l3'), 0);
      expect(totalIn(''), 0);
    });

    test('revision 变化后缓存自动失效', () {
      WorkPlaysStore.resetForTest(items: <String, WorkPlay>{
        'l1/a': const WorkPlay(count: 2),
      });
      expect(totalIn('l1'), 2);
      WorkPlaysStore.resetForTest(items: <String, WorkPlay>{
        'l1/a': const WorkPlay(count: 7),
        'l1/b': const WorkPlay(count: 1),
      });
      expect(totalIn('l1'), 8);
    });

    test('计数为 0 的记录不计入', () {
      WorkPlaysStore.resetForTest(items: <String, WorkPlay>{
        'l/a': const WorkPlay(count: 0),
        'l/b': const WorkPlay(count: 4),
      });
      expect(totalIn('l'), 4);
    });
  });
}
