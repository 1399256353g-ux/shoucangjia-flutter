import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shoucangjia/main.dart';
import 'package:shoucangjia/watch_progress.dart';

Map<String, dynamic> _w(String id, {String lib = 'douyin'}) =>
    <String, dynamic>{'id': id, '_lib': lib, 'ti': '作品 $id'};

void main() {
  group('parseRecommendCount', () {
    test('空/非数字回落默认 40', () {
      expect(parseRecommendCount(null), 40);
      expect(parseRecommendCount(''), 40);
      expect(parseRecommendCount('   '), 40);
      expect(parseRecommendCount('abc'), 40);
    });

    test('数字夹紧到 0..500', () {
      expect(parseRecommendCount('0'), 0);
      expect(parseRecommendCount('40'), 40);
      expect(parseRecommendCount('500'), 500);
      expect(parseRecommendCount('999'), 500);
      expect(parseRecommendCount('-12'), 0);
      expect(parseRecommendCount(120.6), 121);
    });
  });

  group('recommendRequestCount', () {
    test('0 折算为 40，其余照用', () {
      expect(recommendRequestCount(0), 40);
      expect(recommendRequestCount(1), 1);
      expect(recommendRequestCount(500), 500);
    });
  });

  group('mergeRecommendPages', () {
    test('追加到尾部并按 id 去重，保留原顺序', () {
      final first = [_w('a'), _w('b')];
      final second = [_w('b'), _w('c')];
      final merged = mergeRecommendPages(first, second);
      expect(merged.map((e) => e['id']).toList(), ['a', 'b', 'c']);
    });

    test('同 id 不同库不算重复', () {
      final merged = mergeRecommendPages(
          [_w('a', lib: 'l1')], [_w('a', lib: 'l2')]);
      expect(merged.length, 2);
    });

    test('无 id 的条目原样保留', () {
      final merged = mergeRecommendPages(
          [_w('a')], [<String, dynamic>{'_lib': 'douyin'}]);
      expect(merged.length, 2);
    });
  });

  group('nextRecommendSeed', () {
    test('跳过已用 seed，保证连续续播不重复请求同一批', () {
      final used = <int>{1000 + 1 * 7919};
      final s1 = nextRecommendSeed(nowSeconds: 1000, seq: 1, used: used);
      expect(used.contains(s1), isFalse);
      used.add(s1);
      final s2 = nextRecommendSeed(nowSeconds: 1000, seq: 2, used: used);
      expect(s2, isNot(s1));
    });
  });

  testWidgets('WorkGrid 滚到末尾时触发 onEndReached（无限续播入口）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await WatchProgressStore.ensureLoaded();
    final works = List<Map<String, dynamic>>.generate(
        60,
        (i) => <String, dynamic>{
              'id': 'w$i',
              't': 'v',
              'th': '',
              'ti': '作品 $i',
              'a': '作者',
              '_lib': 'douyin',
            });
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 800,
          child: WorkGrid(
            works: works,
            lib: 'douyin',
            onEndReached: () => calls++,
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(calls, 0);
    await tester.drag(find.byType(GridView), const Offset(0, -20000));
    await tester.pumpAndSettle();
    expect(calls, greaterThan(0));
  });
}
