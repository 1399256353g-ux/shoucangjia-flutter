/// M6：滑动方向预加载策略（纯逻辑，便于单测）。
///
/// - 预载当前条目前后各 N 条（N 可设置，默认 2），按滑动方向排序；
/// - 缓存条目受「条数 + 字节」双上限约束，超限时优先淘汰
///   离当前条目最远、且不在滑动方向上的条目；
/// - 当前条目、正在预载的条目不会被淘汰。
library;

/// 默认每侧预载条数（唯一取值处）。
///
/// 桌面端与移动端都是 2：每条预载 = 一只常驻 mpv 实例，2 条以上在移动端
/// 容易把解码器吃光（表现为 App 无日志消失）。实际槽位数由
/// [preloadSlotBudget] 按内存上限与 48MB/条共同收敛，所以「每侧 2」并不会
/// 无条件撑到 5 只播放器。
const int preloadDefaultPerSide = 2;

/// 按平台取默认值；目前两端一致，保留签名以便将来移动端单独收紧。
int preloadDefaultPerSideFor({required bool mobile}) => preloadDefaultPerSide;

/// 设置允许的每侧条数范围（0 表示关闭预加载）。
const int preloadMaxPerSide = 4;

/// 缓存单条的估算内存（媒体缓冲 + 解码器常驻）。
const int preloadEntryBytes = 48 * 1024 * 1024;

/// 播放器槽位总数上限（含当前播放槽位）。
///
/// owner 2026-11-20：目标是「滑动秒切、看不到加载痕迹」，槽位上限放宽到 5
/// （当前 + 前后各 2 条）。内存由 [preloadSlotBudget] 按 48MB/条与设置里的
/// 内存上限共同约束：默认 256MB 正好容纳 5 条，设置调低会自动减到 2–3 条。
const int preloadMaxSlots = 5;

/// 默认内存上限（MB）。
const int preloadDefaultMemoryMb = 256;

/// 内存上限可选值。
const List<int> preloadMemoryOptions = <int>[128, 256, 384, 512];

/// 预加载等待解封装/首帧就绪的轮询次数与间隔（约 4 秒）。
const int preloadReadyAttempts = 26;
const Duration preloadReadyInterval = Duration(milliseconds: 150);

/// 就绪后再等一小段时间，让解码器铺好首帧。
const Duration preloadFirstFrameDelay = Duration(milliseconds: 120);

/// 规范化设置里的每侧条数。
int clampPreloadPerSide(int v) => v.clamp(0, preloadMaxPerSide);

/// 规范化设置里的内存上限（MB）。
int clampPreloadMemoryMb(int v) => v.clamp(128, 768);

/// 由内存上限换算可同时存在的播放器槽位（含当前播放槽位）。
/// 至少 2 个（当前 + 正/反各一条的最基本体验），最多 [preloadMaxSlots] 个。
int preloadSlotBudget(int memoryMb) =>
    (clampPreloadMemoryMb(memoryMb) * 1024 * 1024 ~/ preloadEntryBytes)
        .clamp(2, preloadMaxSlots);

/// 预载候选序号，按优先级从高到低。
///
/// [direction] 为 1（向下/下一条）、-1（向上/上一条）或 0（未知）。
/// 方向已知时先排该方向，再排反方向；方向未知时前后交替。
List<int> preloadCandidates({
  required int index,
  required int count,
  required int perSide,
  int direction = 0,
}) {
  if (count <= 0 || index < 0 || index >= count) return const <int>[];
  final n = clampPreloadPerSide(perSide);
  if (n == 0) return const <int>[];
  final out = <int>[];
  void add(int i) {
    if (i < 0 || i >= count || i == index) return;
    if (!out.contains(i)) out.add(i);
  }

  final d = direction == 0 ? 1 : (direction > 0 ? 1 : -1);
  for (var k = 1; k <= n; k++) {
    add(index + d * k);
    add(index - d * k);
  }
  return out;
}

/// 淘汰优先级：数值越大越应先淘汰。
///
/// 同距离时反方向条目优先淘汰；当前条目返回 -1（永不淘汰）。
int preloadEvictionRank({
  required int index,
  required int current,
  int direction = 0,
}) {
  if (index == current) return -1;
  final d = direction > 0 ? 1 : (direction < 0 ? -1 : 0);
  final delta = index - current;
  final dist = delta.abs();
  if (d == 0) return dist * 2;
  final sameSide = delta.sign == d;
  // 反方向的条目整体先淘汰（+100），同方向内再按距离从远到近。
  return dist * 2 + (sameSide ? 0 : 100);
}

/// 单条缓存记录。slot 为播放器槽位编号，bytes 用于内存核算。
class PreloadEntry {
  final int slot;
  final int index;
  final String key;
  final int bytes;
  const PreloadEntry({
    required this.slot,
    required this.index,
    required this.key,
    this.bytes = preloadEntryBytes,
  });
}

/// 预加载缓存：key -> slot 的映射，带条数/字节上限与确定性淘汰。
///
/// 只维护账本，不持有播放器；真实槽位的创建/销毁由播放页负责。
class PreloadCache {
  PreloadCache({this.maxEntries = 8});

  final int maxEntries;
  final Map<String, PreloadEntry> _byKey = <String, PreloadEntry>{};

  int get length => _byKey.length;
  int get totalBytes =>
      _byKey.values.fold(0, (sum, e) => sum + e.bytes);

  String? keyOfSlot(int slot) {
    for (final e in _byKey.values) {
      if (e.slot == slot) return e.key;
    }
    return null;
  }

  PreloadEntry? entryOfSlot(int slot) {
    for (final e in _byKey.values) {
      if (e.slot == slot) return e;
    }
    return null;
  }

  PreloadEntry? entryOfKey(String key) => _byKey[key];

  bool containsKey(String key) => _byKey.containsKey(key);

  bool containsSlot(int slot) => entryOfSlot(slot) != null;

  void put(PreloadEntry e) {
    _byKey.remove(e.key);
    _byKey[e.key] = e;
  }

  void removeKey(String key) => _byKey.remove(key);

  void removeSlot(int slot) => _byKey.removeWhere((_, e) => e.slot == slot);

  /// 是否还能再放进一个 [bytes] 大小的条目。
  bool canFit(int bytes, {required int byteLimit}) =>
      totalBytes + bytes <= byteLimit;

  /// 选出应淘汰的槽位；[protectedSlots] 内的槽位永不淘汰。
  /// 返回 null 表示无需/无法淘汰。
  int? evictionSlot({
    required int current,
    required int direction,
    Set<int> protectedSlots = const <int>{},
    Set<String> protectedKeys = const <String>{},
  }) {
    PreloadEntry? victim;
    var best = -1;
    for (final e in _byKey.values) {
      if (protectedSlots.contains(e.slot)) continue;
      if (protectedKeys.contains(e.key)) continue;
      final rank = preloadEvictionRank(
          index: e.index, current: current, direction: direction);
      if (rank < 0) continue;
      if (rank > best) {
        best = rank;
        victim = e;
      }
    }
    return victim?.slot;
  }

  void clear() => _byKey.clear();
}
