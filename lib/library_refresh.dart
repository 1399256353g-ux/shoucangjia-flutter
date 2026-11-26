// 库卡片「快速刷新」（owner 2026-11-22 需求）。
//
// 一次点击按固定顺序做四件事：
//  1. 服务端重建该库索引：`POST /api/reindex {lib}`（只重建 libidx，不扫全盘）；
//  2. 带 `?t=` 重拉 `/api/libraries.json`，替换库快照（不整页转圈）；
//  3. 清掉该库封面/缩略图在本地磁盘缓存里的旧图（`_cover` 版本号会变）；
//  4. 正开着这个库时，让作品列表与作者列表回到第一页重拉。
//
// 本文件只放**无 UI 的编排**：HTTP、缓存、列表刷新全部通过回调注入，
// 便于单测覆盖顺序、局部失败与防抖，不需要真的连服务端。
library;

import 'error_text.dart';
import 'count_label.dart';
import 'json_num.dart';
import 'http_error_text.dart';
import 'http_json.dart';

/// 单次快速刷新的结果。
class LibRefreshOutcome {
  /// 目标库 id（基础库；单元库会解析成它下面的基础库）。
  final String lib;

  /// 本库所属连接标题，用于失败提示。
  final String server;

  /// 服务端返回的新作品数；null 表示没拿到（旧服务端或解析失败）。
  final int? works;

  /// 第一步重建索引是否成功。
  final bool reindexed;

  /// 第一步的错误原文（空串表示成功）。
  final String error;

  const LibRefreshOutcome({
    required this.lib,
    this.server = '',
    this.works,
    this.reindexed = false,
    this.error = '',
  });

  bool get ok => reindexed && error.isEmpty;

  /// 完成提示：成功报作品数，失败报服务端给的原因（不吞错）。
  String get message {
    if (error.isNotEmpty) return '刷新失败：$error';
    if (works != null) return '已刷新 · ${formatCount(works!)} 个作品';
    return '已刷新';
  }
}

/// 快速刷新防抖窗口（owner 要求 ≥3 秒）。时间注入便于测试。
const Duration kLibRefreshCooldown = Duration(seconds: 3);

/// 是否允许开始一次新的库刷新（按钮禁用判定，不新增定时器）。
bool libRefreshAllowed(DateTime now, DateTime? last) {
  if (last == null) return true;
  return now.difference(last) >= kLibRefreshCooldown;
}

/// `POST /api/reindex` 的请求体：单库。
Map<String, dynamic> reindexBody(String lib) => {'lib': lib.trim()};

/// 解析 `/api/reindex` 的响应：只有 `libs[0].ok == true` 才算成功。
///
/// 服务端在「重建结果为空但旧索引非空」时返回 207 + `rolledBack`，
/// 这里必须把它当作失败并把原因原样带出去，不能静默显示「已刷新」。
LibRefreshOutcome parseReindexResponse(
  int status,
  dynamic body, {
  required String lib,
  String server = '',
}) {
  final map = body is Map ? body : const <String, dynamic>{};
  final rows = map['libs'];
  Map? row;
  if (rows is List) {
    for (final e in rows) {
      if (e is Map && '${e['lib'] ?? ''}' == lib) {
        row = e;
        break;
      }
    }
    if (row == null && rows.isNotEmpty && rows.first is Map) {
      row = rows.first as Map;
    }
  }
  final okRow = serviceSaidOk(row);
  final works = row?['works'] == null ? null : intOf(row!['works']);
  // 成功判定只有一处，**不能**让「行说 ok」与「状态码说失败」各自成立。
  //
  // 旧实现分开算：`reindexed = okRow && status == 200`，而 `error` 只在
  // `!okRow` 时才赋值。于是服务端返回 `201 + {libs:[{ok:true,works:3}]}`
  // （或任何非 200 的 2xx/3xx）时得到一个**自相矛盾**的结果：
  // `ok == false` 却 `error == ''`，而 `message` 走的是 `works != null` 分支 →
  // 界面提示「已刷新 · 3 个作品」，`runLibRefresh` 却在第一步就 `return`，
  // 库快照、封面缓存、列表刷新三件事一件都没做。用户看到的是「刷新成功了但
  // 什么都没变」，下次再看还是旧数据。
  final success = okRow && status >= 200 && status < 300;
  String err = '';
  if (!success) {
    err = serverErrorText(row) ?? '';
    if (err.isEmpty) {
      // 顶层 error 与状态码文案都走唯一出口：`'${map['error']}'` 会把
      // `{code: 500}` 这样的对象插值贴到界面，`'HTTP $status'` 又与本文件
      // 其它地方（httpErrorText）同一个 400 两种说法。
      err = serverErrorText(map) ??
          (status != 200 ? httpErrorText(status) : '服务端未返回结果');
    }
  }
  return LibRefreshOutcome(
    lib: lib,
    server: server,
    works: success ? works : null,
    reindexed: success,
    error: err,
  );
}

/// 快速刷新编排。顺序固定：重建索引 → 重拉库快照 → 清该库封面缓存 → 刷新列表。
///
/// 前两步失败会终止（拿不到新索引就没必要清缓存）；后两步即使前一步成功也
/// 单独容错，因为它们只影响显示时效，不影响数据正确性。
Future<LibRefreshOutcome> runLibRefresh({
  required String lib,
  String server = '',
  required Future<dynamic> Function(Map<String, dynamic> body) reindex,
  required Future<void> Function() reloadLibraries,
  required Future<void> Function() clearLibCovers,
  Future<void> Function()? reloadOpenLists,

  /// 重建成功后广播「该库索引已变」的入口（由调用方接到
  /// [LibDataRevision.bump]，打开中的列表据此回到第一页重拉）。
  void Function()? onBumpRevision,
}) async {
  final id = lib.trim();
  if (id.isEmpty) {
    return const LibRefreshOutcome(lib: '', error: '缺少库标识');
  }

  LibRefreshOutcome outcome;
  try {
    final resp = await reindex(reindexBody(id));
    // 回调返回 `(status, body)` 形式的记录，或直接返回 Map（视为 200）。
    if (resp is ({int status, dynamic body})) {
      outcome = parseReindexResponse(resp.status, resp.body,
          lib: id, server: server);
    } else {
      outcome = parseReindexResponse(200, resp, lib: id, server: server);
    }
  } catch (e) {
    return LibRefreshOutcome(lib: id, server: server, error: errorText(e));
  }
  if (!outcome.ok) return outcome;

  // 2) 库快照：失败不算失败——索引已经重建好了，卡片会在下次刷新时显示。
  try {
    await reloadLibraries();
  } catch (_) {}

  // 3) 该库封面缓存。
  try {
    await clearLibCovers();
  } catch (_) {}

  // 4) 打开中的列表。
  try {
    onBumpRevision?.call();
  } catch (_) {}
  try {
    await reloadOpenLists?.call();
  } catch (_) {}

  return outcome;
}
