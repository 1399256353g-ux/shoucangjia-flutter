// 服务端缩图缓存（`?w=`）统计与清理接口（0.9.28）。
//
// 服务端把卡片/头像/海报的缩图落在 NAS `~/.cache/gallery-resize`，只读源图、
// 不覆盖媒体；总量超过上限时按最久未用自动清理。设置 → 诊断信息里展示
// 「文件数 / 占用 / 上限 / 命中率」，并提供手动清理（只删缓存，不碰原图）。
import 'dart:convert';

import 'package:http/http.dart' as http;

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

  static int _int(dynamic v) =>
      v is num ? v.round() : int.tryParse('${v ?? ''}') ?? 0;

  static double _dbl(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

  /// 解析失败（非对象）返回 null，调用方显示「读取失败」而不是 0。
  static ResizeCacheStats? fromJson(dynamic json) {
    if (json is! Map) return null;
    final prune = json['prune'];
    final total = _int(json['hit']) + _int(json['miss']);
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
      hitRate: json['hitRate'] is num
          ? _dbl(json['hitRate'])
          : (total > 0 ? _int(json['hit']) / total : 0),
      pruneRuns: prune is Map ? _int(prune['runs']) : 0,
      pruneDeleted: prune is Map ? _int(prune['deleted']) : 0,
      pruneFreed: prune is Map ? _int(prune['freed']) : 0,
    );
  }

  /// 人类可读字节：B / KB / MB / GB，保留一位小数。
  static String bytesText(int b) {
    if (b <= 0) return '0 B';
    if (b < 1024) return '$b B';
    final kb = b / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  /// 「33.0 MB / 1.50 GB」；未知上限时只显示占用。
  String get usageText => maxBytes > 0
      ? '${bytesText(bytes)} / ${bytesText(maxBytes)}'
      : bytesText(bytes);

  /// 占用百分比（0–100，整数），上限未知时返回 null。
  int? get usedPercent =>
      maxBytes > 0 ? ((bytes * 100) / maxBytes).round().clamp(0, 100) : null;

  String get hitRateText => '${(hitRate * 100).toStringAsFixed(1)}%';

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
    return ResizeCacheStats.fromJson(jsonDecode(utf8.decode(r.bodyBytes)));
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
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    if (j is! Map) return null;
    final deleted = j['deleted'] is num ? (j['deleted'] as num).round() : 0;
    final freed = j['freed'] is num ? (j['freed'] as num).round() : 0;
    final after = j['bytesAfter'] is num ? (j['bytesAfter'] as num).round() : 0;
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
