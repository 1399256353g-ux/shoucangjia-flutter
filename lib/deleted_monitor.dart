/// 删除监测：解析服务端 `/api/deleted.json`（来自各单元库 `_deleted.log`）。
///
/// 只读日志，不删除/不改动媒体；App 里只展示「已删除/取消收藏」记录。
///
/// 记录里的 `at` 是爬虫**发现**该作品被删除/不可见的时间，也就是「哪一次同步
/// 发现的」；页面按分钟聚合成「本次同步」分组，避免只看到一串无来源的时间。
library;

import 'api_url.dart';
import 'json_num.dart';
import 'time_labels.dart';

class DeletedEntry {
  final String at;
  final String author;
  final String date;
  final String title;
  final String workId;
  final String collection;
  final String link;
  final String cover;

  /// 发现该记录的单元库（服务端新版下发 `lib`；旧记录为空）。
  final String libName;

  /// 服务端判定的基础库 id（新版下发 `libId`；旧记录为空）。
  /// 删除记录行跳转作品时要带着它去 `/api/work.json` 精确查找。
  final String libId;

  /// 三态（服务端下发 `st`）：
  /// - `deleted` 已删除：平台已删除/不可见，且**本地曾落地**（才计入「已删除」）；
  /// - `failed` 抓取失败：本地从未落地（`本地` 路径不存在），可重试；
  /// - `landed` 已落地：本地仍有文件（旧服务端未区分时的兜底状态）。
  final String stateRaw;

  const DeletedEntry({
    required this.at,
    required this.author,
    required this.date,
    required this.title,
    required this.workId,
    required this.collection,
    required this.link,
    required this.cover,
    this.libName = '',
    this.libId = '',
    this.stateRaw = '',
  });

  /// 三态归一：旧服务端没有 `st` 字段时按「已删除」处理，保持原行为。
  DeletedState get state => deletedStateOf(stateRaw);

  /// `at` 的毫秒时间戳；无法解析时为 0。
  int get atMs => DateTime.tryParse(at)?.millisecondsSinceEpoch ?? 0;

  /// `2026-11-17T01:06:37.489Z` → `11-17 09:06`（本地时区）；
  /// 解析失败时回显原始字符串（这里不能显示 `—`，否则丢线索）。
  String get atLabel => monthDayTimeOfIso(at, fallback: at);

  /// 同步批次键：精确到分钟。同一轮爬虫通常在同一分钟内写入多条。
  String get syncKey => syncKeyOf(at);

  String get syncLabel => syncLabelOf(at);

  /// 列表里单行来源：`同步发现 11-20 22:57 · 库 (2) douyin`。
  String get foundLabel {
    final parts = <String>['同步发现 ${atLabel.isEmpty ? '时间未知' : atLabel}'];
    if (libName.trim().isNotEmpty) parts.add('库 ${libName.trim()}');
    return parts.join(' · ');
  }

  DeletedEntry copyWith({String? libName, String? libId, String? stateRaw}) => DeletedEntry(
        at: at,
        author: author,
        date: date,
        title: title,
        workId: workId,
        collection: collection,
        link: link,
        cover: cover,
        libName: libName ?? this.libName,
        libId: libId ?? this.libId,
        stateRaw: stateRaw ?? this.stateRaw,
      );
}

/// 删除监测的三态。
enum DeletedState { landed, failed, deleted }

/// `st` 字段 → 三态；未知/旧数据按「已删除」兜底（与历史行为一致）。
DeletedState deletedStateOf(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'failed':
    case 'fetch_failed':
    case 'fetchfailed':
      return DeletedState.failed;
    case 'landed':
    case 'ok':
      return DeletedState.landed;
    default:
      return DeletedState.deleted;
  }
}

String deletedStateLabel(DeletedState s) {
  switch (s) {
    case DeletedState.failed:
      return '抓取失败';
    case DeletedState.landed:
      return '已落地';
    case DeletedState.deleted:
      return '已删除';
  }
}

/// 三态计数。**只有曾落地的才算「已删除」**（服务端已按 `st` 归一）。
class DeletedStats {
  final int deleted;
  final int failed;
  final int landed;

  const DeletedStats(
      {this.deleted = 0, this.failed = 0, this.landed = 0});

  int get total => deleted + failed + landed;

  static DeletedStats of(Iterable<DeletedEntry> items) {
    var d = 0, f = 0, l = 0;
    for (final e in items) {
      switch (e.state) {
        case DeletedState.failed:
          f++;
          break;
        case DeletedState.landed:
          l++;
          break;
        case DeletedState.deleted:
          d++;
          break;
      }
    }
    return DeletedStats(deleted: d, failed: f, landed: l);
  }

  /// 页头摘要：`已删除 3 · 抓取失败 1 · 已落地 2`（已落地为 0 时省略）。
  String get label {
    final parts = <String>['已删除 $deleted'];
    if (failed > 0) parts.add('抓取失败 $failed（可重试）');
    if (landed > 0) parts.add('已落地 $landed');
    return parts.join(' · ');
  }
}

/// 行点击「打开作品」的请求地址（`libId` 为空时交给服务端用默认库查）。
Uri? deletedWorkUri(String base, DeletedEntry e) {
  final id = e.workId.trim();
  if (baseForJoin(base).isEmpty || id.isEmpty) return null;
  final lib = e.libId.trim();
  return apiUri(base, '/api/work.json', query: {
    'id': id,
    if (lib.isNotEmpty) 'lib': lib,
  });
}

/// 作品不在本地索引时的提示（与 owner 指定文案一致）。
const String kDeletedNotLocalMessage = '仅在收藏列表出现过，未同步到本地';

/// 同步批次键（UTC 分钟，避免时区切换导致同一批拆开）。
String syncKeyOf(String at) {
  final t = DateTime.tryParse(at);
  if (t == null) return at;
  return yearMonthDayTimeUtc(t);
}

String syncLabelOf(String at) => monthDayTimeOfIso(at, fallback: at);

class DeletedReport {
  final int total;
  final int updated;
  final List<DeletedEntry> items;

  /// 读取链路最终用的地址（诊断用，不参与展示逻辑）。
  final String source;

  const DeletedReport(
      {required this.total,
      required this.updated,
      required this.items,
      this.source = ''});

  static const empty = DeletedReport(total: 0, updated: 0, items: []);

  String get updatedLabel =>
      updated <= 0 ? '' : yearMonthDayTimeOfSec(updated);

  /// 最近一次同步发现（按 `at` 最大）。
  String get lastDiscoveryLabel {
    int best = 0;
    String label = '';
    for (final e in items) {
      final ms = e.atMs;
      if (ms > best) {
        best = ms;
        label = e.atLabel;
      }
    }
    return label;
  }
}

/// 按「同步批次」聚合后的列表（保持输入顺序：服务端已按时间倒序）。
class DeletedSyncGroup {
  final String key;
  final String label;
  final List<DeletedEntry> items;

  const DeletedSyncGroup(
      {required this.key, required this.label, required this.items});
}

List<DeletedSyncGroup> groupDeletedBySync(List<DeletedEntry> items) {
  final out = <DeletedSyncGroup>[];
  final byKey = <String, int>{};
  for (final e in items) {
    final key = e.syncKey;
    final at = byKey[key];
    if (at == null) {
      byKey[key] = out.length;
      out.add(DeletedSyncGroup(
          key: key,
          label: e.syncLabel,
          items: <DeletedEntry>[e]));
    } else {
      out[at].items.add(e);
      // 同一分钟内先出现的记录已经给了标签；保留更早（更准确）的那条。
      if (out[at].label.isEmpty) {
        out[at] = DeletedSyncGroup(
            key: key, label: e.syncLabel, items: out[at].items);
      }
    }
  }
  return out;
}

/// 去重：同一作品如果被同一轮同步重复写入，只保留一条。
/// 不同轮次（不同分钟）的重复记录保留，便于看出「删了又出现」。
List<DeletedEntry> dedupeDeletedEntries(Iterable<DeletedEntry> items) {
  final seen = <String>{};
  final out = <DeletedEntry>[];
  for (final e in items) {
    final key = e.workId.isNotEmpty
        ? '${e.workId}|${e.syncKey}'
        : '${e.author}|${e.title}|${e.syncKey}';
    if (!seen.add(key)) continue;
    out.add(e);
  }
  return out;
}

dynamic _itemsOf(dynamic raw) {
  if (raw is List) return raw;
  if (raw is! Map) return null;
  for (final key in const ['items', 'records', 'deleted', 'list']) {
    final v = raw[key];
    if (v is List) return v;
  }
  return null;
}

DeletedReport parseDeletedReport(dynamic raw, {String source = ''}) {
  final list = _itemsOf(raw);
  final out = <DeletedEntry>[];
  if (list is List) {
    for (final e in list) {
      if (e is! Map) continue;
      final at = '${e['at'] ?? ''}';
      out.add(DeletedEntry(
        at: at,
        author: '${e['a'] ?? ''}',
        date: '${e['d'] ?? ''}',
        title: '${e['t'] ?? ''}',
        workId: '${e['id'] ?? ''}',
        collection: '${e['c'] ?? ''}',
        link: '${e['u'] ?? ''}',
        cover: '${e['th'] ?? ''}',
        libName: '${e['lib'] ?? ''}',
        libId: '${e['libId'] ?? ''}',
        stateRaw: '${e['st'] ?? ''}',
      ));
    }
  }
  final deduped = dedupeDeletedEntries(out);
  final total = raw is Map ? intOf(raw['total'], deduped.length) : deduped.length;
  final updated = raw is Map ? intOf(raw['updated']) : 0;
  return DeletedReport(
      total: total, updated: updated, items: deduped, source: source);
}
