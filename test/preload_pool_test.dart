import 'package:shoucangjia/preload_pool.dart';
import 'package:flutter_test/flutter_test.dart';

/// 阶段3：播放器池决策的纯逻辑回归。
///
/// 这些用例锁住三件事：
/// 1. 池始终包含当前条，且最多 [poolMaxSlots] 个；
/// 2. 预载按滑动方向优先，不超配槽位；
/// 3. 活动/在途槽位永不被释放。
void main() {
  group('poolHoldIndexes', () {
    test('当前条恒在首位，方向优先', () {
      expect(poolHoldIndexes(current: 5, count: 10, direction: 1), [5, 6, 4]);
      expect(poolHoldIndexes(current: 5, count: 10, direction: -1), [5, 4, 6]);
    });

    test('边界处不会越界', () {
      expect(poolHoldIndexes(current: 0, count: 10), [0, 1]);
      expect(poolHoldIndexes(current: 9, count: 10), [9, 8]);
    });

    test('非法索引返回空', () {
      expect(poolHoldIndexes(current: -1, count: 10), isEmpty);
      expect(poolHoldIndexes(current: 10, count: 10), isEmpty);
      expect(poolHoldIndexes(current: 0, count: 0), isEmpty);
    });

    test('跳过没有媒体的条目，但当前条不受限制', () {
      final hold = poolHoldIndexes(
        current: 3,
        count: 10,
        perSide: 2,
        hasMedia: (i) => i != 4,
      );
      expect(hold.first, 3);
      expect(hold.contains(4), isFalse);
    });

    test('槽位上限生效', () {
      final hold = poolHoldIndexes(current: 5, count: 10, perSide: 3, maxSlots: 2);
      expect(hold.length, 2);
    });
  });

  group('planPreloadPool', () {
    String keyOf(int i) => 'lib|$i';

    test('池外槽位被释放，缺的条目进入预载', () {
      final plan = planPreloadPool(
        current: 5,
        count: 10,
        direction: 1,
        slots: const [
          PoolSlotState(sid: 1, key: 'lib|5', active: true),
          PoolSlotState(sid: 2, key: 'lib|1'),
        ],
        keyOf: keyOf,
      );
      expect(plan.release, [2]);
      // 池容量 3：活动槽位之外还能放两个邻居
      expect(plan.preload, [6, 4]);
    });

    test('已在池中的槽位不重复预载', () {
      final plan = planPreloadPool(
        current: 5,
        count: 10,
        direction: 1,
        slots: const [
          PoolSlotState(sid: 1, key: 'lib|5', active: true),
          PoolSlotState(sid: 2, key: 'lib|6'),
        ],
        keyOf: keyOf,
      );
      expect(plan.preload, [4]);
      expect(plan.release, isEmpty);
      expect(plan.hold, [5, 6, 4]);
    });

    test('在途槽位既不释放也不重复排队', () {
      final plan = planPreloadPool(
        current: 5,
        count: 10,
        direction: 1,
        slots: const [
          PoolSlotState(sid: 1, key: 'lib|5', active: true),
          PoolSlotState(sid: 2, key: 'lib|6', busy: true),
          PoolSlotState(sid: 3, key: 'lib|7'),
        ],
        keyOf: keyOf,
      );
      expect(plan.release, [3]);
      // 池容量 3：活动 5 + 在途 6 占 2，只剩 1 个位置给反方向邻居
      expect(plan.preload, [4]);
    });

    test('空池只预载一个邻居，不超配', () {
      final plan = planPreloadPool(
        current: 5,
        count: 10,
        slots: const [PoolSlotState(sid: 1, key: 'lib|5', active: true)],
        keyOf: keyOf,
      );
      // 池容量 3：当前 5 之外还能常驻前后各一条
      expect(plan.preload, [6, 4]);
      expect(plan.hold.length <= poolMaxSlots, isTrue);
    });
  });
}
