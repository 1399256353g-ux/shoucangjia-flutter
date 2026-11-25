/// 库封面的唯一本地状态（owner 2026-11-25）。
///
/// 「单元库选过往封面，返回界面就恢复原样」的根因不在服务端——
/// `/api/libraries.json` 下发的 6 条指针一条不少。真正的问题是客户端把
/// 「当前该显示哪张封面」拆成了两份状态：
///   1. 卡片私有的 `_coverOverride` / `_coverAuto`（只活在这张卡片里）；
///   2. 树快照里的 `node.coverUrl`（只在页面加载那一刻有效）。
/// 选完封面后只有 (1) 变了，(2) 还是旧的；页面一重建，(1) 被清空，
/// 于是回落到 (2) 的旧值——表现出来就是「返回界面就恢复原样」。
///
/// 现在收拢成一处：卡片只问 [rawOf]，改了 store 就 bump 一次 [revision]，
/// 所有可见卡片一起重建。不再有第二份覆盖层。
///
/// 键带命名空间（`u:` 单元库 / `b:` 基础库）：同一个 rel 字符串既可能是
/// 单元库路径也可能是基础库路径，共用一张表会串封面。
library;

import 'package:flutter/foundation.dart';

import 'multi_server.dart' show normalizeUnitRel;

class UnitCoverStore {
  /// 键 → 显示用封面地址（绝对 URL，已含鉴权/路由）。
  ///
  /// 值语义：
  ///  - 键**不存在**：没有本地意见，调用方走服务端指针/自动链；
  ///  - 值**空串**：显式「恢复自动」，忽略服务端指针；
  ///  - 值**非空**：直接用这个地址。
  static final Map<String, String> _byKey = <String, String>{};

  /// 唯一变更信号：任何一处封面改动都自增一次。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// 单元库封面的键（rel 归一化后加前缀）。
  static String unitKey(String rel) => 'u:${normalizeUnitRel(rel)}';

  /// 基础库封面的键（基础库 id 本身唯一）。
  static String basicKey(String id) => 'b:${id.trim()}';

  /// 本地意见；没设过返回 null。
  static String? rawOf(String key) {
    if (key.isEmpty || key == 'u:' || key == 'b:') return null;
    return _byKey[key];
  }

  /// 是否被显式要求「恢复自动」（忽略服务端指针）。
  static bool isAuto(String key) {
    final v = rawOf(key);
    return v != null && v.isEmpty;
  }

  /// 写入。[url] 为空串表示「恢复自动」。
  static void set(String key, String url) {
    if (key.isEmpty || key == 'u:' || key == 'b:') return;
    final v = url.trim();
    if (_byKey[key] == v) return;
    _byKey[key] = v;
    revision.value++;
  }

  /// 服务端的封面指针**不进这张表**。
  ///
  /// 那正是原来出问题的地方：一旦把服务端值抄进来，就又有两份「当前封面」，
  /// 谁先谁后再次决定观感。这里只存「本机意见」，没有意见时调用方直接读
  /// `node.coverUrl`——一份数据一个来源。
  ///
  /// 清空（切库/测试用）。
  @visibleForTesting
  static void reset() {
    if (_byKey.isEmpty) return;
    _byKey.clear();
    revision.value++;
  }
}
