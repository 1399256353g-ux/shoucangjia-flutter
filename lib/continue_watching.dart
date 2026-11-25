/// G17：「继续观看」入口。
///
/// 主页顶部展示最近看过的作品与上次停留位置，点一下直接续播。
/// 数据只存本机（SharedPreferences），不上报服务端：
/// - 播放中与退出时记录「库/作品」的元信息与位置（3 秒节流）；
/// - 看完/清除记录后自动从列表移除；
/// - 最多保留 [kContinueLimit] 条，按最近观看时间排序。
library;

import 'dart:async';
import 'json_num.dart';
import 'unit_fraction.dart';
import 'stable_order.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'prefs_json.dart';
import 'watch_progress.dart';
import 'work_key.dart';

/// SharedPreferences 键：整个「继续观看」列表存在一个 JSON 字符串里。
const String kContinuePrefsKey = 'continue_watching_v1';

/// 列表条数上限。
const int kContinueLimit = 8;

/// 小于该位置不进入「继续观看」（开头几秒续播没有意义）。
const int kContinueMinMs = 1000;

/// 写盘节流窗口：同一作品、同一收藏夹内位置变化不足该值时跳过写盘。
const int kContinueThrottleMs = 3000;

/// 一条「继续观看」记录（作品元信息 + 上次位置）。
class ContinueItem {
  final String lib;
  final String id;
  final int idx;
  final String collection;
  final String title;
  final String author;
  final String thumb;
  final String type;
  final int positionMs;
  final int durationMs;
  final int updatedAt;

  const ContinueItem({
    required this.lib,
    required this.id,
    this.idx = 0,
    this.collection = '',
    this.title = '',
    this.author = '',
    this.thumb = '',
    this.type = 'v',
    this.positionMs = 0,
    this.durationMs = 0,
    this.updatedAt = 0,
  });

  bool get isVideo => type != 'p';

  /// 0–1 的观看进度；时长未知时按 0 处理。
  double get fraction {
    if (durationMs <= 0) return 0;
    return unitFraction(positionMs / durationMs);
  }

  /// 列表里展示的标题：优先作品标题，其次作者，最后「未命名作品」。
  String get label {
    final t = title.trim();
    if (t.isNotEmpty) return t;
    final a = author.trim();
    if (a.isNotEmpty) return a;
    return '未命名作品';
  }

  ContinueItem copyWith({
    int? positionMs,
    int? durationMs,
    int? updatedAt,
    String? collection,
    int? idx,
  }) =>
      ContinueItem(
        lib: lib,
        id: id,
        idx: idx ?? this.idx,
        collection: collection ?? this.collection,
        title: title,
        author: author,
        thumb: thumb,
        type: type,
        positionMs: positionMs ?? this.positionMs,
        durationMs: durationMs ?? this.durationMs,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'l': lib,
        'i': id,
        'x': idx,
        'c': collection,
        'ti': title,
        'a': author,
        'th': thumb,
        't': type,
        'p': positionMs,
        'd': durationMs,
        'u': updatedAt,
      };

  /// 容错解析：非 Map / 缺关键字段 / 负数位置一律丢弃。
  static ContinueItem? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    int n(dynamic v) => intOf(v);
    String s(dynamic v) => v == null ? '' : '$v';
    final id = s(raw['i']).trim();
    if (id.isEmpty) return null;
    final p = n(raw['p']);
    final d = n(raw['d']);
    if (p < 0 || d < 0) return null;
    return ContinueItem(
      lib: s(raw['l']).trim(),
      id: id,
      idx: n(raw['x']),
      collection: s(raw['c']),
      title: s(raw['ti']),
      author: s(raw['a']),
      thumb: s(raw['th']),
      type: s(raw['t']).isEmpty ? 'v' : s(raw['t']),
      positionMs: p,
      durationMs: d,
      updatedAt: n(raw['u']),
    );
  }

  /// 作品唯一键：`库/作品 id`。
  ///
  /// 必须与观看记录 / 播放量用**同一个**键口径（[workKey]）：那边两条都
  /// `trim()`，而这里旧写法直接拼原串。后果不是显示错，而是**同一条作品在
  /// 两张表里对不上**：库 id 带尾随空白（服务端拼接/手工配置的中间态）时，
  /// 本表存的是 `A /1`，而 `watchProgressKey` / `workPlaysKey` 存的是 `A/1`；
  /// 而 [fromJson] 自己又 `trim()` 了 lib——于是同一个键「写进去一个、读出来
  /// 另一个」（实测：写入后重启，`remove(lib, id)` 算出的键与表里的不一致，
  /// 看完的作品永远删不掉，继续观看里一直挂着）。
  ///
  /// id 为空时返回空串，与 [workKey] 一致（调用方应跳过）。
  String get key => workKey(lib: lib, id: id);
}

/// 解析整表；非法 JSON / 非法条目直接丢弃。
List<ContinueItem> parseContinueItems(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return const [];
  }
  if (decoded is! List) return const [];
  final out = <ContinueItem>[];
  final seen = <String>{};
  for (final e in decoded) {
    final item = ContinueItem.fromJson(e);
    if (item == null) continue;
    if (seen.add(item.key)) out.add(item);
  }
  return out;
}

/// 编码列表（按 key 稳定输出，方便对比）。
String encodeContinueItems(List<ContinueItem> items) =>
    jsonEncode([for (final i in items) i.toJson()]);

/// 是否值得出现在「继续观看」：位置足够、未看完。
bool isContinueCandidate(ContinueItem item) {
  if (item.positionMs < kContinueMinMs) return false;
  // 「看完没有」只有一条判定（`watch_progress.watchedDone`：剩余 ≤4s 或
  // 进度 ≥95%）。这里原先又写了一遍 `- 4000` 与 `>= 0.95`——两个阈值聚在
  // 三处（`kWatchedTailMs` / `kWatchedFraction` / 这里的字面量），改一处忘
  // 一处的后果是「列表里已打勾的作品还留在继续观看」或反之。
  return !watchedDone(
    positionMs: item.positionMs,
    durationMs: item.durationMs,
  );
}

/// 插入/更新一条记录：同「库/作品」覆盖，按最近观看时间降序，截断到上限。
///
/// **同一时间戳时刚记录的那条在最前**。旧实现是「先 append 到末尾，再 `sort`」，
/// 而 `List.sort` 不保证稳定：同一秒内连续滑过多条（更新时间粒度到毫秒但常常
/// 相同）时，刚看的那条会被掎到最后一名（实测 20 条同时间戳，更新 `w3` 后
/// 列表变成 `w0,w1,w2,w4…,w3`）——它接着又被上限截断掉，用户刚看过的作品从
/// 「继续观看」里消失。现在新记录先插到首位，排序改走 [stableSort]：同时间戳
/// 保持输入顺序（即「新的在前」），结果与输入顺序无关。
List<ContinueItem> upsertContinueItems(
  List<ContinueItem> items,
  ContinueItem item, {
  int limit = kContinueLimit,
}) {
  final next = <ContinueItem>[
    for (final e in items)
      if (e.key != item.key) e,
  ];
  if (isContinueCandidate(item)) next.insert(0, item);
  stableSort<ContinueItem>(next, (a, b) => b.updatedAt.compareTo(a.updatedAt));
  if (limit > 0 && next.length > limit) return next.sublist(0, limit);
  return next;
}

/// 移除单条记录。
List<ContinueItem> removeContinueItem(
    List<ContinueItem> items, String lib, String id) {
  final key = ContinueItem(lib: lib, id: id).key;
  return [
    for (final e in items)
      if (e.key != key) e,
  ];
}

/// 写盘节流判定（纯函数）：同一作品、同一收藏夹、位置变化不足
/// [kContinueThrottleMs] 时才跳过；换了收藏夹（换条）必须立即记录，
/// 否则「刚换条又滑回来」会丢掉新的收藏夹归属。
bool shouldSkipContinueRecord(ContinueItem prev, ContinueItem next) {
  if (prev.key != next.key) return false;
  if (prev.collection != next.collection) return false;
  // 差值必须在**不会溢出**的空间里算：
  //
  // `prev.positionMs - next.positionMs` 在两个极端值之间会回绕——
  // `9223372036854775807 - (-9223372036854775808)` 实测得 **-1**，
  // abs 后是 1，小于节流窗口，于是这次「从片头跳到片尾」被当成
  // 「位置没变，不写盘」。后果不是显示错，是**这次真实的进度变化整条丢掉**
  // （下次续播回到旧位置）。回绕方向不可预测，abs 补救不了，
  // 只能一开始就用双精度算——阈值是 3000ms，double 在这个量级上精确。
  final mag = (prev.positionMs.toDouble() - next.positionMs.toDouble()).abs();
  return mag < kContinueThrottleMs;
}

/// 本地「继续观看」仓库：内存缓存 + 直接落盘 + 变更通知。
class ContinueWatchingStore {
  ContinueWatchingStore._();

  /// 每次变更自增，主页用 ValueListenableBuilder 监听即可刷新。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static List<ContinueItem> _items = <ContinueItem>[];
  static bool _loaded = false;

  static List<ContinueItem> get items => List.unmodifiable(_items);

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final sp = await SharedPreferences.getInstance();
      _items = parseContinueItems(sp.getString(kContinuePrefsKey));
      revision.value++;
    } catch (_) {
      _items = <ContinueItem>[];
    }
  }

  /// 记录一次观看位置（内部按 key 合并；位置不足 1 秒时跳过；
  /// [force] 为 false 时同一作品约 3 秒内不重复写盘）。
  static void record(ContinueItem item, {bool force = false}) {
    if (item.id.trim().isEmpty) return;
    if (item.positionMs < kContinueMinMs) return;
    final prev = _items.where((e) => e.key == item.key).toList();
    if (!force &&
        prev.isNotEmpty &&
        shouldSkipContinueRecord(prev.first, item)) {
      return;
    }
    final merged = prev.isEmpty
        ? item
        : item.copyWith(
            idx: item.idx > 0 ? item.idx : prev.first.idx,
            collection: item.collection.isEmpty
                ? prev.first.collection
                : item.collection,
            durationMs:
                item.durationMs > 0 ? item.durationMs : prev.first.durationMs,
          );
    _set(upsertContinueItems(_items, merged));
  }

  /// 看完/清除记录时移除。
  static void remove(String lib, String id) {
    final next = removeContinueItem(_items, lib, id);
    if (next.length != _items.length) _set(next);
  }

  static void _set(List<ContinueItem> next) {
    _items = next;
    revision.value++;
    unawaited(_persist());
  }

  static Future<void> _persist() =>
      savePrefString(kContinuePrefsKey, encodeContinueItems(_items));

  @visibleForTesting
  static void resetForTest() {
    _items = <ContinueItem>[];
    _loaded = false;
    revision.value++;
  }
}
