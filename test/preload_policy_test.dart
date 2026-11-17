import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/app_settings.dart';
import 'package:shoucangjia/preload_policy.dart';

void main() {
  setUp(AppSettings.resetDefaults);

  group('preloadCandidates', () {
    test('前后各 N 条，方向优先', () {
      expect(
        preloadCandidates(
            index: 5, count: 10, perSide: 2, direction: 1),
        <int>[6, 4, 7, 3],
      );
      expect(
        preloadCandidates(
            index: 5, count: 10, perSide: 2, direction: -1),
        <int>[4, 6, 3, 7],
      );
    });

    test('边界处只返回存在的条目', () {
      expect(
        preloadCandidates(index: 0, count: 3, perSide: 2, direction: 1),
        <int>[1, 2],
      );
      expect(
        preloadCandidates(index: 2, count: 3, perSide: 2, direction: -1),
        <int>[1, 0],
      );
    });

    test('关闭与非法输入', () {
      expect(preloadCandidates(index: 1, count: 3, perSide: 0), isEmpty);
      expect(preloadCandidates(index: -1, count: 3, perSide: 2), isEmpty);
      expect(preloadCandidates(index: 5, count: 3, perSide: 2), isEmpty);
    });

    test('方向未知时前后交替', () {
      expect(preloadCandidates(index: 3, count: 9, perSide: 2),
          <int>[4, 2, 5, 1]);
    });
  });

  group('内存预算', () {
    test('按 48MB/条换算槽位并夹在 2..3（预载槽位默认 2、上限 3）', () {
      expect(preloadSlotBudget(96), 2);
      expect(preloadSlotBudget(256), 3);
      expect(preloadSlotBudget(512), preloadMaxSlots);
      expect(preloadSlotBudget(2000), preloadMaxSlots);
      expect(preloadMaxSlots, 3);
      expect(preloadDefaultPerSide, 2);
    });

    test('设置值夹取', () {
      expect(clampPreloadPerSide(-2), 0);
      expect(clampPreloadPerSide(99), preloadMaxPerSide);
      expect(clampPreloadMemoryMb(1), 128);
      expect(clampPreloadMemoryMb(4000), 768);
    });
  });

  group('PreloadCache 淘汰', () {
    test('优先淘汰反方向最远条目', () {
      final c = PreloadCache();
      // 当前在 5，向下滑动：1/2 在反方向，7/9 在同方向
      for (final i in <int>[1, 2, 7, 9]) {
        c.put(PreloadEntry(slot: i, index: i, key: 'k$i', bytes: 1));
      }
      expect(
          c.evictionSlot(current: 5, direction: 1), 1);
      c.removeKey('k1');
      expect(c.evictionSlot(current: 5, direction: 1), 2);
      c.removeKey('k2');
      expect(c.evictionSlot(current: 5, direction: 1), 9);
    });

    test('受保护槽位与键不淘汰', () {
      final c = PreloadCache();
      c.put(const PreloadEntry(slot: 1, index: 1, key: 'a', bytes: 1));
      c.put(const PreloadEntry(slot: 2, index: 30, key: 'b', bytes: 1));
      expect(
          c.evictionSlot(
              current: 0, direction: 1, protectedSlots: <int>{1}),
          2);
      expect(
          c.evictionSlot(
              current: 0, direction: 1, protectedKeys: <String>{'b'}),
          1);
      expect(
          c.evictionSlot(
              current: 0,
              direction: 1,
              protectedSlots: <int>{1},
              protectedKeys: <String>{'b'}),
          isNull);
    });

    test('账本：槽位映射、字节统计与删除', () {
      final c = PreloadCache();
      c.put(const PreloadEntry(slot: 3, index: 2, key: 'x', bytes: 10));
      expect(c.keyOfSlot(3), 'x');
      expect(c.entryOfKey('x')!.index, 2);
      expect(c.totalBytes, 10);
      expect(c.canFit(5, byteLimit: 15), isTrue);
      expect(c.canFit(6, byteLimit: 15), isFalse);
      c.removeSlot(3);
      expect(c.length, 0);
    });
  });

  group('设置持久化', () {
    test('预加载字段往返', () {
      AppSettings.preloadPerSide = 3;
      AppSettings.preloadMemoryMb = 384;
      final j = AppSettings.toJson();
      AppSettings.resetDefaults();
      expect(AppSettings.preloadPerSide, 2);
      expect(AppSettings.preloadMemoryMb, 256);
      AppSettings.applyJson(j);
      expect(AppSettings.preloadPerSide, 3);
      expect(AppSettings.preloadMemoryMb, 384);
    });

    test('非法值夹取', () {
      AppSettings.applyJson(<String, dynamic>{
        'preloadPerSide': 99,
        'preloadMemory': -5,
      });
      expect(AppSettings.preloadPerSide, preloadMaxPerSide);
      expect(AppSettings.preloadMemoryMb, 128);
    });
  });
}
