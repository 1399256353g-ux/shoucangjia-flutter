/// 阶段3（调度层）：播放器池决策，纯逻辑，不依赖 Flutter/widget。
///
/// 抖音式的「秒开」来自常驻池 + 预渲染：池里始终留着
/// 当前 / 下一条 / 上一条三个槽位，切条只切换活动槽位，
/// 不再对目标条调用 `player.open`。
///
/// 本文件只回答两件事：
/// 1. 池里该常驻哪些条（[poolHoldIndexes]）；
/// 2. 现有槽位里哪些该释放、还缺哪些要预载（[planPreloadPool]）。
library;

import 'preload_policy.dart';

/// 池槽位上限（含当前条）：当前 + 前后各一条。
const int poolMaxSlots = 3;

/// 切条后禁止预热的静置时间（毫秒）。
///
/// 滑动过程中反复排队会让槽位在「停旧条 → 开新条」之间来回抖，
/// 起播反而更慢；切条后先让当前条稳定 300ms 再预热邻居。
const int poolPreloadCooldownMs = 300;

/// 一个槽位的当前占用情况（由播放页采集后传入，纯数据）。
class PoolSlotState {
  /// 槽位编号（播放页内部唯一）。
  final int sid;

  /// 槽位里已经打开的条目序号；未打开/未知时为 -1。
  final int index;

  /// 槽位里媒体的身份键（库|id|媒体路径）；空闲时为空串。
  final String key;

  /// 正在预载（异步任务未收尾），不得释放、不得重复预载。
  final bool busy;

  /// 是否为当前活动槽位，永不释放。
  final bool active;

  const PoolSlotState({
    required this.sid,
    this.index = -1,
    this.key = '',
    this.busy = false,
    this.active = false,
  });

  @override
  String toString() => 'PoolSlotState(sid: $sid, index: $index, key: $key, '
      'busy: $busy, active: $active)';
}

/// 池的一次决策结果。
class PoolPlan {
  /// 应常驻的条目序号（含当前条，当前条恒在首位）。
  final List<int> hold;

  /// 需要预载的条目序号，按优先级从高到低。
  final List<int> preload;

  /// 应释放的槽位 sid（池外条目；active / busy 槽位永不出现）。
  final List<int> release;

  const PoolPlan({
    required this.hold,
    required this.preload,
    required this.release,
  });

  static const PoolPlan empty =
      PoolPlan(hold: <int>[], preload: <int>[], release: <int>[]);

  bool get isEmpty => hold.isEmpty && preload.isEmpty && release.isEmpty;

  @override
  String toString() =>
      'PoolPlan(hold: $hold, preload: $preload, release: $release)';
}

/// 池应常驻的条目序号：当前条优先，然后按滑动方向排前后邻居。
List<int> poolHoldIndexes({
  required int current,
  required int count,
  int direction = 0,
  int maxSlots = poolMaxSlots,
  int perSide = 1,
  bool Function(int index)? hasMedia,
}) {
  if (count <= 0 || current < 0 || current >= count) return const <int>[];
  final cap = maxSlots <= 0 ? 1 : maxSlots;
  final hold = <int>[current];
  if (cap == 1) return hold;

  for (final i in preloadCandidates(
    index: current,
    count: count,
    perSide: perSide,
    direction: direction,
  )) {
    if (hold.length >= cap) break;
    if (hasMedia != null && !hasMedia(i)) continue;
    hold.add(i);
  }
  return hold;
}

/// 根据池的期望内容与现有槽位，算出「释放 / 预载」清单。
///
/// 规则：
/// - 活动槽位永不释放；
/// - 正在预载的槽位不释放、也不重复预载；
/// - 键不在 hold 集合里的槽位释放，留给下一轮预载复用；
/// - 预载数量受 [maxSlots] 限制，绝不超配。
PoolPlan planPreloadPool({
  required int current,
  required int count,
  int direction = 0,
  int maxSlots = poolMaxSlots,
  int perSide = 1,
  required List<PoolSlotState> slots,
  required String Function(int index) keyOf,
  bool Function(int index)? hasMedia,
}) {
  final cap = maxSlots <= 0 ? 1 : maxSlots;
  final hold = poolHoldIndexes(
    current: current,
    count: count,
    direction: direction,
    maxSlots: cap,
    perSide: perSide,
    hasMedia: hasMedia,
  );
  if (hold.isEmpty) return PoolPlan.empty;

  final holdKeys = <String>{};
  for (final i in hold) {
    final k = keyOf(i);
    if (k.isNotEmpty) holdKeys.add(k);
  }

  final resident = <String>{};
  final busyKeys = <String>{};
  var keptNonActive = 0;
  final release = <int>[];
  for (final s in slots) {
    if (s.active) continue;
    if (s.busy) {
      if (s.key.isNotEmpty) busyKeys.add(s.key);
      keptNonActive++;
      continue;
    }
    final inPool = s.key.isNotEmpty && holdKeys.contains(s.key);
    if (!inPool) {
      release.add(s.sid);
      continue;
    }
    resident.add(s.key);
    keptNonActive++;
  }

  final free = cap - 1 - keptNonActive;
  final preload = <int>[];
  if (free > 0) {
    for (final i in hold) {
      if (preload.length >= free) break;
      if (i == current) continue;
      final k = keyOf(i);
      if (k.isEmpty) continue;
      if (resident.contains(k) || busyKeys.contains(k)) continue;
      preload.add(i);
    }
  }

  return PoolPlan(hold: hold, preload: preload, release: release);
}
