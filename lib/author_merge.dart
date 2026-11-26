/// 跨基础库「同名作者合并」的纯逻辑（无 UI、无网络）。
///
/// 背景（owner 2026-11-22）：作者身份原本是**库内**概念——每个基础库各有
/// `@作者` 目录与 `libidx/<lib>/a/<id>.json`，所以同名作者天然分开。
/// 目标：同名作者的作者页把各库作品合并展示，并标注来源库。
///
/// 服务端 `/api/authors.json?lib=all` 的 `libs` 字段已经给出同名作者出现在
/// 哪些基础库；这里只做「计数 / 分组 / 去重」这类可单测的纯计算，
/// 真实数据仍由调用方按库拉取（磁盘结构完全不改）。
library;

import 'work_lib.dart';

/// 参与合并的来源库数量（空/重复一律不计）。
int authorLibCount(Iterable<String> libs) {
  final set = <String>{};
  for (final l in libs) {
    final t = l.trim();
    if (t.isNotEmpty) set.add(t);
  }
  return set.length;
}

/// 合并后的来源说明，例如「来自 2 个库」；只有 1 个库或没有时返回空串。
///
/// 单个库不必提示——那是常态，提示反而像告警。
String authorSourceSummary(Iterable<String> libs) {
  final n = authorLibCount(libs);
  return n >= 2 ? '来自 $n 个库' : '';
}

/// 合并多个库拉回来的作品：按作品 id 去重，**先到先得**（调用方按
/// primaryLib 优先的顺序拉取即可实现「主库优先」）。
///
/// id 为空的作品无法去重，直接保留（宁可多一条也不静默丢内容）。
List<Map<String, dynamic>> mergeAuthorWorks(Iterable<Iterable<dynamic>> perLib) {
  final seen = <String>{};
  final out = <Map<String, dynamic>>[];
  for (final batch in perLib) {
    for (final w in batch) {
      if (w is! Map) continue;
      final m = Map<String, dynamic>.from(w);
      final id = '${m['id'] ?? ''}'.trim();
      if (id.isNotEmpty && !seen.add(id)) continue;
      out.add(m);
    }
  }
  return out;
}

/// 按来源库筛选作品；[lib] 为空表示「全部」。
List<Map<String, dynamic>> filterWorksByLib(
  Iterable<dynamic> works, {
  String lib = '',
  String fallbackLib = '',
}) {
  final want = lib.trim();
  if (want.isEmpty) {
    return [
      for (final w in works)
        if (w is Map) Map<String, dynamic>.from(w)
    ];
  }
  final out = <Map<String, dynamic>>[];
  for (final w in works) {
    if (w is! Map) continue;
    final m = Map<String, dynamic>.from(w);
    if (workLibOf(m, fallback: fallbackLib) == want) out.add(m);
  }
  return out;
}

/// 来源筛选条的选项：`[(libId, 作品数)]`，按首次出现顺序，含「全部」由调用方加。
List<MapEntry<String, int>> libFilterOptions(
  Iterable<dynamic> works, {
  String fallbackLib = '',
}) {
  final counts = <String, int>{};
  final order = <String>[];
  for (final w in works) {
    if (w is! Map) continue;
    final l = workLibOf(w, fallback: fallbackLib);
    if (l.isEmpty) continue;
    if (!counts.containsKey(l)) order.add(l);
    counts[l] = (counts[l] ?? 0) + 1;
  }
  return [for (final l in order) MapEntry(l, counts[l]!)];
}
