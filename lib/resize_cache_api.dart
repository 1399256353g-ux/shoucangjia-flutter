// 服务端缩图缓存（`?w=`）统计与清理接口（0.9.28）。
//
// 服务端把卡片/头像/海报的缩图落在 NAS `~/.cache/gallery-resize`，只读源图、
// 不覆盖媒体；总量超过上限时按最久未用自动清理。设置 → 诊断信息里展示
// 「文件数 / 占用 / 上限 / 命中率」，并提供手动清理（只删缓存，不碰原图）。

import 'package:http/http.dart' as http;
import 'json_num.dart';
import 'unit_fraction.dart';

import 'byte_size.dart';
import 'http_json.dart';

/// `/api/cache/stats` 的解析结果；字段缺失一律按 0，不抛异常。
class ResizeCacheStats {
  final int files;
  final int bytes;
  final int maxBytes;
  final int hit;
  final int miss;
  final int gen;
  final int fail;
  final int savedBytes;
  final int servedBytes;
  final int queue;
  final int active;
  final double hitRate;
  final int pruneRuns;
  final int pruneDeleted;
  final int pruneFreed;

  const ResizeCacheStats({
    this.files = 0,
    this.bytes = 0,
    this.maxBytes = 0,
    this.hit = 0,
    this.miss = 0,
    this.gen = 0,
    this.fail = 0,
    this.savedBytes = 0,
    this.servedBytes = 0,
    this.queue = 0,
    this.active = 0,
    this.hitRate = 0,
    this.pruneRuns = 0,
    this.pruneDeleted = 0,
    this.pruneFreed = 0,
  });

  // 数值解析统一走 `json_num`：此前这里是全仓库唯一用 `round()` 的地方，
  // 同一个 1.6 个文件在缓存页显示 2、在别处显示 1。
  static int _int(dynamic v) => intOf(v);

  /// 命中率：优先用服务端给的值，缺失/非数值/非有限值时按 `hit / (hit+miss)` 自算。
  ///
  /// 此前写成 `json['hitRate'] is num`：服务端把 `0.62` 序列化成字符串
  /// `"0.62"`（或换了类型）时这条分支直接跳过，看起来「用了自算值」其实是
  /// 把服务端给的准确值丢了。判定改成「能不能解析成有限 double」只有一个答案。
  ///
  /// 自算分支的除法用 **double**：`hit + miss` 在 int64 上会回绕（两个
  /// 计数分别接近 int 上限时得到负数），命中率跟着变成负值或超过 100%。
  ///
  /// 服务端值同样要过**同一个区间**：命中率是 0–1 的比例（服务端
  /// `Math.round(hit*1000/total)/1000`），但这里以前只校验「能不能解析成
  /// 有限 double」，于是 `hitRate: 62`（某次改成百分数）显示成
  /// **`6200.0%`**、`hitRate: -0.5` 显示成 **`-50.0%`**（均实测）。
  /// 区间外的值不是「一个更大的命中率」，而是口径变了或数据坏了——
  /// 与「解析不了」一样退回按计数自算，界面上不会出现不可能的百分比。
  static double _rate(dynamic raw, num hit, num miss) {
    final v = doubleOrNull(raw);
    if (v != null && v >= 0 && v <= 1) return v;
    final h = hit <= 0 ? 0.0 : hit.toDouble();
    final m = miss <= 0 ? 0.0 : miss.toDouble();
    final total = h + m;
    if (!total.isFinite || total <= 0) return 0;
    return unitFraction(h / total);
  }

  /// 解析失败（非对象）返回 null，调用方显示「读取失败」而不是 0。
  static ResizeCacheStats? fromJson(dynamic json) {
    if (json is! Map) return null;
    final prune = json['prune'];
    final hit = _int(json['hit']);
    final miss = _int(json['miss']);
    return ResizeCacheStats(
      files: _int(json['files']),
      bytes: _int(json['bytes']),
      maxBytes: _int(json['maxBytes']),
      hit: _int(json['hit']),
      miss: _int(json['miss']),
      gen: _int(json['gen']),
      fail: _int(json['fail']),
      savedBytes: _int(json['savedBytes']),
      servedBytes: _int(json['servedBytes']),
      queue: _int(json['warmQueue']),
      active: _int(json['warmActive']),
      hitRate: _rate(json['hitRate'], hit, miss),
      pruneRuns: prune is Map ? _int(prune['runs']) : 0,
      pruneDeleted: prune is Map ? _int(prune['deleted']) : 0,
      pruneFreed: prune is Map ? _int(prune['freed']) : 0,
    );
  }

  /// 人类可读字节；口径统一在 [formatBytes]（B / 1 位 KB / 1 位 MB / 2 位 GB）。
  static String bytesText(int b) => formatBytes(b);

  /// 「33.0 MB / 1.50 GB」；未知上限时只显示占用。
  String get usageText => maxBytes > 0
      ? '${bytesText(bytes)} / ${bytesText(maxBytes)}'
      : bytesText(bytes);

  /// 占用百分比（0–100，整数），上限未知时返回 null。
  ///
  /// **不能写 `(bytes * 100) / maxBytes`**：int64 上 `9223372036854775807 * 100`
  /// 实测得 **-100**，服务端把一个坏值（或 int 上限的占位值）写进 `bytes`
  /// 时，缓存页会显示「已用 0%」——刚好是「看起来一切正常」的那种错。
  /// 先做除法再乘 100，中间值始终在 0–1。
  ///
  /// **取整必须截断，不能四舍五入**：旧写法 `round()` 让 `996 / 1000`
  /// 显示成 **`占用上限的 100%`**（实测），而同一个页面上的命中率
  /// （`hitRateText`）、字节（`formatBytes`）、计数（`formatCount`）三处
  /// 全部是「宁可少报也不能虚假跨档」。四个读数并排时只有这一处说大，
  /// 用户看到的是「缓存快满了」而实际还差 0.4%——与第十二批修的
  /// `1024.0 KB`、第四十八批的 `100.0%` 命中率同一条口径。
  int? get usedPercent {
    if (maxBytes <= 0) return null;
    // `bytes` 比 `maxBytes` 大时不是反常数据，而是「已超上限」（缓存清理还没
    // 跑）。比例 ≥ 1 时才写 100%，不显示 `350%`，也不把 99.6% 说成 100%。
    final b = bytes < 0 ? 0 : bytes;
    final ratio = b / maxBytes;
    if (!ratio.isFinite) return null;
    if (ratio >= 1) return 100;
    final pct = (ratio * 100).floor();
    return pct < 0 ? 0 : pct;
  }

  /// 命中率文案：`90.0%`。
  ///
  /// 不能用 `toStringAsFixed(1)` 直接乘 100：它是**四舍五入**，于是
  /// `0.99995` 显示成 **`100.0%`**（实测）——等于说「命中率已经满了」，
  /// 而实际还有未命中。与字节文案的 `1024.0 KB`、同步耗时的 `10.0s`
  /// 是同一条口径（「宁可少报也不能虚假跨档」）：先截断到 0.1%，再输出。
  ///
  /// 也不能写成 `round()`：`0.00004` 会被舍成 `0.0%`（看起来一次没命中），
  /// 截断同样是 `0.0%`，两种写法在这里一致；但 `0.99996` 截断给 `99.9%`，
  /// 四舍五入会给 `100.0%`。统一截断后「100.0%」只在真的是 1.0 时出现。
  String get hitRateText => '${_truncTenths(hitRate * 100)}%';

  /// 截断到 0.1（不进位），避免四舍五入把比值说大。
  static String _truncTenths(double v) {
    if (!v.isFinite || v <= 0) return '0.0';
    final t = (v * 10).floorToDouble() / 10;
    return t.toStringAsFixed(1);
  }

  /// 诊断页副标题：命中/未命中/生成/失败 + 预热队列。
  String get countersText =>
      '命中 $hit · 未命中 $miss · 生成 $gen · 失败 $fail'
      '${queue > 0 ? ' · 预热队列 $queue' : ''}';
}

/// 读取统计；网络/解析失败返回 null（页面显示「读取失败」）。
Future<ResizeCacheStats?> fetchResizeCacheStats(
  Uri uri,
  Map<String, String> headers, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final c = client ?? http.Client();
  try {
    final r = await c.get(uri, headers: headers).timeout(timeout);
    if (r.statusCode != 200) return null;
    return ResizeCacheStats.fromJson(jsonOf(r));
  } catch (_) {
    return null;
  } finally {
    if (client == null) c.close();
  }
}

/// 手动清理缩图缓存（服务端只删 `~/.cache/gallery-resize`，不动媒体原图）。
/// 返回一句话结果，失败返回 null。
Future<String?> pruneResizeCache(
  Uri uri,
  Map<String, String> headers, {
  bool dryRun = false,
  http.Client? client,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final c = client ?? http.Client();
  final target = dryRun
      ? uri.replace(queryParameters: {
          ...uri.queryParameters,
          'dry': '1',
        })
      : uri;
  try {
    final r = await c.get(target, headers: headers).timeout(timeout);
    if (r.statusCode != 200) return null;
    final j = jsonOf(r);
    if (j is! Map) return null;
    final deleted = intOf(j['deleted']);
    final freed = intOf(j['freed']);
    final after = intOf(j['bytesAfter']);
    if (dryRun) {
      return deleted > 0
          ? '可清理 $deleted 个文件，释放 ${ResizeCacheStats.bytesText(freed)}'
          : '未超过上限，无需清理（当前 ${ResizeCacheStats.bytesText(after)}）';
    }
    if (deleted <= 0) {
      return '未超过上限，未清理（当前 ${ResizeCacheStats.bytesText(after)}）';
    }
    return '已清理 $deleted 个文件，释放 ${ResizeCacheStats.bytesText(freed)}'
        '，现占用 ${ResizeCacheStats.bytesText(after)}';
  } catch (_) {
    return null;
  } finally {
    if (client == null) c.close();
  }
}
