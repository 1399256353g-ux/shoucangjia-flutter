// 顶部任务栏「总刷新」（owner 2026-11-22 需求）。
//
// 一次点击按固定顺序做四件事：
//  1. 连接状态：对每条启用中的连接探一次 `/api/auth`，汇总在线数；
//  2. 库列表：对在线连接带 `?t=` 重拉 `/api/libraries.json`，取库条数；
//  3. 封面缓存：清空封面缓存并 bump 封面版本，让可见卡片重新取图；
//  4. 作者/头像索引：重拉 `/api/authors.json` 与头像覆盖表。
//
// 本文件只放**无 UI 的编排逻辑**：HTTP、缓存、索引刷新都通过回调注入，
// 便于单测覆盖顺序、局部失败与去抖，不需要真的连服务端。
library;

import 'concurrency.dart';
import 'error_text.dart';
import 'multi_server.dart';

/// 单次总刷新的结果，用于完成提示与失败展示。
class TotalRefreshOutcome {
  /// 参与探测的连接条数。
  final int servers;

  /// `/api/auth` 返回 2xx–4xx 的连接条数（401 也算「在线」）。
  final int online;

  /// 本次 `/api/libraries.json` 拿到的库条数（各连接取最大值）。
  final int libraries;

  /// 第一条错误原文（为空表示全部成功）。
  final String? firstError;

  const TotalRefreshOutcome({
    required this.servers,
    required this.online,
    required this.libraries,
    this.firstError,
  });

  /// 完成提示：成功报库数，失败报第一条错误。
  String get message {
    if (firstError != null) return '刷新失败：$firstError';
    if (servers == 0) return '没有可用的连接';
    return '已刷新 $libraries 个库';
  }
}

/// 探测连接：返回 HTTP 状态码；异常由实现方转成 0。
typedef AuthProbe = Future<int> Function(ServerConn server);

/// 取库条数：返回 `/api/libraries.json` 的 libraries 数量；失败抛异常。
typedef LibraryCountProbe = Future<int> Function(ServerConn server);

/// 总刷新防抖窗口（owner 要求 ≥5 秒）。时间注入便于测试。
const Duration kTotalRefreshCooldown = Duration(seconds: 5);

/// 是否允许开始一次新的总刷新（用于按钮防抖，不新增定时器）。
bool totalRefreshAllowed(DateTime now, DateTime? last) {
  if (last == null) return true;
  return now.difference(last) >= kTotalRefreshCooldown;
}

/// 总刷新编排。顺序固定：先探测连接，再拉库列表，最后清缓存/作者索引。
///
/// 任一连接失败只记录第一条错误，其余步骤照常执行——
/// 总刷新的语义是「能刷的都刷」，不是「一条失败就整体放弃」。
///
/// 0.9.331：两个阶段都改**有界并发**。此前都是串行 `for` + `await`：
/// N 条连接就是 2N 次完整往返（探测 6s + 库列表 12s 上限各一份），
/// 「总刷新」在最慢那台离线时要白等到超时才出结果，而各连接的请求彼此独立。
/// 与首页/爬虫页同一口径（4 路），且 `mapConcurrent` 保序——
/// 因此 `firstError` 仍是「按连接顺序的第一条」，提示文案不变。
Future<TotalRefreshOutcome> runTotalRefresh({
  required List<ServerConn> servers,
  required AuthProbe probe,
  required LibraryCountProbe libraryCount,
  required Future<void> Function() clearCoverCache,
  required Future<void> Function() reloadAuthors,
  DateTime Function()? clock,
}) async {
  final live = servers.where((s) => s.enabled && s.base.isNotEmpty).toList();
  var online = 0;
  var libraries = 0;
  String? firstError;

  // 1) 连接状态：每条连接只探一次，结果给第 2 步复用。
  final probed = await mapConcurrent<ServerConn,
      ({String id, String title, int code, String? err})>(live, 4, (s) async {
    try {
      final code = await probe(s);
      return (id: s.id, title: s.title, code: code, err: null);
    } catch (e) {
      return (id: s.id, title: s.title, code: 0, err: errorText(e));
    }
  });
  final codes = <String, int>{};
  for (final p in probed) {
    codes[p.id] = p.code;
    if (p.code >= 200 && p.code < 500) {
      online++;
    } else if (firstError == null) {
      // 抛异常时记异常原文，否则记「连接失败」（与串行版逐字一致）。
      firstError = '${p.title}：${p.err ?? '连接失败'}';
    }
  }

  // 2) 库列表：只对在线的连接拉，取最大条数用于完成提示。
  final counted = await mapConcurrent<ServerConn, ({int n, String? err})>(
      [for (final s in live) if ((codes[s.id] ?? 0) != 0) s], 4, (s) async {
    try {
      return (n: await libraryCount(s), err: null);
    } catch (e) {
      return (n: 0, err: '${s.title}：${errorText(e)}');
    }
  });
  for (final c in counted) {
    if (c.n > libraries) libraries = c.n;
    if (firstError == null && c.err != null) firstError = c.err;
  }

  // 3) 封面缓存 + 4) 作者索引：即使前面有失败也要执行，避免半新半旧。
  try {
    await clearCoverCache();
  } catch (e) {
    firstError ??= '清除封面缓存失败：${errorText(e)}';
  }
  try {
    await reloadAuthors();
  } catch (e) {
    firstError ??= '重拉作者索引失败：${errorText(e)}';
  }

  return TotalRefreshOutcome(
    servers: live.length,
    online: online,
    libraries: libraries,
    firstError: firstError,
  );
}
