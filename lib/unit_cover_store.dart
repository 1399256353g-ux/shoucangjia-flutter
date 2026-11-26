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
///
/// 键还必须带**连接标识**（owner 2026-11-26）：单元库的 rel 是相对各自
/// 媒体库根的路径，两台服务端各有一个 `(1) 抖音` 时 rel 完全是同一个字符串。
/// 只按 rel 存，在 A 库设的封面会同时改掉 B 库同名目录的卡片——而两边是两份
/// 独立数据、封面文件也各在各的机器上。这与 `buildUnitTree` 里节点去重必须带
/// 连接（`_nodeKeyOf`）是同一条规则；那边修好了，这张表当时漏了。
library;

import 'package:flutter/foundation.dart';

import 'multi_server.dart' show normalizeUnitRel;
import 'node_key.dart' show kNodeKeySep;

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

  /// 键的字段分隔符。rel 里可能出现 `|` `:` `/`，但不会是控制字符。
  ///
  /// 取自 `node_key.kNodeKeySep`（唯一常量）：这里此前自己写了一个
  /// `'\u0001'` 字面量，与节点键/封面键是两份。两份都是控制字符，肉眼
  /// 分不出差别，只在某个键被拼了两次时才炸。
  static const String _sep = kNodeKeySep;

  /// 键的公共拼装口：`<命名空间>:<连接>␁<rel 或 id>`。
  ///
  /// 连接为空时仍是 `u:␁A/B`（不是 `u:A/B`）——留一个固定字段位，
  /// 否则「有连接」与「没连接」两种写法会拼出同一个键，作用域又回到 rel。
  static String _keyOf(String ns, String scope, String id) =>
      '$ns:${scope.trim()}$_sep$id';

  /// 单元库封面的键（连接 + 归一化 rel）。
  static String unitKey(String rel, {String serverId = ''}) =>
      _keyOf('u', serverId, normalizeUnitRel(rel));

  /// 基础库封面的键（连接 + 基础库 id）。
  static String basicKey(String id, {String serverId = ''}) =>
      _keyOf('b', serverId, id.trim());

  /// 本地意见；没设过返回 null。
  static String? rawOf(String key) {
    if (!_isWellFormed(key)) return null;
    return _byKey[key];
  }

  /// 键必须带命名空间与分隔符，否则视为脏键（不读也不写）。
  static bool _isWellFormed(String key) {
    if (key.isEmpty) return false;
    if (!key.startsWith('u:') && !key.startsWith('b:')) return false;
    return key.contains(_sep);
  }

  /// 是否被显式要求「恢复自动」（忽略服务端指针）。
  static bool isAuto(String key) {
    final v = rawOf(key);
    return v != null && v.isEmpty;
  }

  /// 写入。[url] 为空串表示「恢复自动」。
  static void set(String key, String url) {
    if (!_isWellFormed(key)) return;
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
