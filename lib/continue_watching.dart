/// G17：「继续观看」入口。
///
/// 主页顶部展示最近看过的作品与上次停留位置，点一下直接续播。
/// 数据只存本机（SharedPreferences），不上报服务端：
/// - 播放中与退出时记录「库/作品」的元信息与位置（3 秒节流）；
/// - 看完/清除记录后自动从列表移除；
/// - 最多保留 [kContinueLimit] 条，按最近观看时间排序。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences 键：整个「继续观看」列表存在一个 JSON 字符串里。
const String kContinuePrefsKey = 'continue_watching_v1';

/// 列表条数上限。
const int kContinueLimit = 8;

/// 小于该位置不进入「继续观看」（开头几秒续播没有意义）。
const int kContinueMinMs = 1000;

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
    return (positionMs / durationMs).clamp(0.0, 1.0);
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
    int n(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);
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

  String get key => lib.isEmpty ? id : '$lib/$id';
}

/// 时长格式化：`m:ss` / `h:mm:ss`；非法或 ≤0 返回空串。
String formatContinueDuration(int ms) {
  if (ms <= 0) return '';
  final total = (ms / 1000).round();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

/// 「继续观看」卡片上的位置文案：`1:23 / 5:10`，时长未知时只显示位置。
String formatContinueLabel(int positionMs, int durationMs) {
  final p = formatContinueDuration(positionMs);
  final d = formatContinueDuration(durationMs);
  if (p.isEmpty) return d;
  if (d.isEmpty) return p;
  return '$p / $d';
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
  if (item.durationMs > 0) {
    if (item.durationMs - item.positionMs <= 4000) return false;
    if (item.positionMs / item.durationMs >= 0.95) return false;
  }
  return true;
}

/// 插入/更新一条记录：同「库/作品」覆盖，按最近观看时间降序，截断到上限。
List<ContinueItem> upsertContinueItems(
  List<ContinueItem> items,
  ContinueItem item, {
  int limit = kContinueLimit,
}) {
  final next = <ContinueItem>[
    for (final e in items)
      if (e.key != item.key) e,
  ];
  if (isContinueCandidate(item)) next.add(item);
  next.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
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

/// 上次停留位置：夹在 0–时长之间，回退 1 秒避开解码边界。
int continueResumeMs(ContinueItem item) {
  if (item.positionMs <= 0) return 0;
  if (item.durationMs > 0 && item.positionMs >= item.durationMs) return 0;
  final p = item.positionMs > 1000 ? item.positionMs - 1000 : item.positionMs;
  if (item.durationMs > 0 && p >= item.durationMs) return 0;
  return p;
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
        (prev.first.positionMs - item.positionMs).abs() < 1000 &&
        prev.first.collection == item.collection) {
      return;
    }
    if (!force &&
        prev.isNotEmpty &&
        (prev.first.positionMs - item.positionMs).abs() < 3000) {
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

  /// 单条位置刷新（用于「已看完」后立即消失、以及进度条更新）。
  static void updatePosition(String lib, String id, int positionMs,
      {int durationMs = 0}) {
    final key = (ContinueItem(lib: lib, id: id)).key;
    final idx = _items.indexWhere((e) => e.key == key);
    if (idx < 0) return;
    final prev = _items[idx];
    final next = prev.copyWith(
      positionMs: positionMs,
      durationMs: durationMs > 0 ? durationMs : prev.durationMs,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _set(upsertContinueItems(_items, next));
  }

  static void _set(List<ContinueItem> next) {
    _items = next;
    revision.value++;
    unawaited(_persist());
  }

  static Future<void> _persist() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(kContinuePrefsKey, encodeContinueItems(_items));
    } catch (_) {}
  }

  @visibleForTesting
  static void resetForTest() {
    _items = <ContinueItem>[];
    _loaded = false;
    revision.value++;
  }
}
