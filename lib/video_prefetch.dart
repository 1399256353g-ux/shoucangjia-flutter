/// 线③：播放页相邻作品视频预取（轻量 HTTP Range 预热）。
///
/// 与 M6 的「播放器槽位预加载」不同，这里不打开播放器、不占用解码器，
/// 只对前后相邻的视频作品发一次 `Range: bytes=0-...` 请求：
/// 让 NAS 把文件头部读进页缓存、并复用 HTTP 连接，切条时能更快起播。
///
/// 约束：
/// - 只预取视频（`t == 'v'`），图片/图文/合集跳过；
/// - 前后各最多扫 [videoPrefetchPerSide] 条，总目标数不超过
///   [videoPrefetchMaxTargets]；
/// - 单实例并发上限 1（顺序执行），切条/退出时 [VideoPrefetcher.cancel]
///   立即清队列并断开在途连接；
/// - 当前播放正在缓冲或已判定弱网时调用方应跳过（见
///   [shouldRunVideoPrefetch]）；
/// - 一切失败静默，不影响播放。
library;

import 'dart:async';
import 'dart:io';

/// 默认每侧最多向后/向前扫描的条数。
const int videoPrefetchPerSide = 2;

/// 单次播放最多预取的视频条数（前后合计）。
const int videoPrefetchMaxTargets = 2;

/// 预取请求的字节窗口：1 MiB，足够覆盖容器头部与首个关键帧索引。
const int videoPrefetchRangeBytes = 1024 * 1024;

/// 单个请求的等待上限；超时即放弃，绝不拖着影响后续切条。
const Duration videoPrefetchTimeout = Duration(seconds: 8);

/// 当前条起播后延迟多久开始预取，避免和起播抢带宽。
const Duration videoPrefetchDelay = Duration(milliseconds: 1500);

/// 一个待预取的相邻作品。
class VideoPrefetchTarget {
  final int index;
  final String path;

  const VideoPrefetchTarget(this.index, this.path);

  @override
  String toString() => 'VideoPrefetchTarget($index, $path)';
}

/// 从播放列表里挑出相邻视频目标（纯逻辑，可单测）。
///
/// [isVideo] 判断某条是否为视频；[mediaPath] 返回其主媒体路径（空串表示不可用）。
/// [direction] 为 1（往后看）、-1（往前看）或 0（未知，前后交替）；
/// 已知方向时优先排该方向。
///
/// 图片/图文/合集、损坏条目、越界索引都会被跳过；最终最多返回
/// [maxTargets] 条。
List<VideoPrefetchTarget> videoPrefetchTargets({
  required int index,
  required int count,
  required bool Function(int index) isVideo,
  required String Function(int index) mediaPath,
  int perSide = videoPrefetchPerSide,
  int maxTargets = videoPrefetchMaxTargets,
  int direction = 0,
}) {
  if (count <= 1 || index < 0 || index >= count) {
    return const <VideoPrefetchTarget>[];
  }
  if (perSide <= 0 || maxTargets <= 0) return const <VideoPrefetchTarget>[];
  final out = <VideoPrefetchTarget>[];
  final seen = <int>{};
  final forwardFirst = direction >= 0;
  final dirs = forwardFirst ? const <int>[1, -1] : const <int>[-1, 1];
  for (var step = 1; step <= perSide; step++) {
    for (final d in dirs) {
      final i = index + d * step;
      if (i < 0 || i >= count || !seen.add(i)) continue;
      if (!isVideo(i)) continue;
      final p = mediaPath(i).trim();
      if (p.isEmpty) continue;
      out.add(VideoPrefetchTarget(i, p));
      if (out.length >= maxTargets) return out;
    }
  }
  return out;
}

/// 当前是否适合发起预取（纯逻辑，可单测）。
///
/// - 当前条必须是视频；
/// - 播放器正在缓冲、已判定弱网（[slowBuffer]）或仍在打开时跳过，
///   不跟当前播放抢带宽；
/// - [enabled] 供将来接入设置开关，列表只有一条时也无需预取。
bool shouldRunVideoPrefetch({
  required bool isVideo,
  required bool buffering,
  required bool slowBuffer,
  required bool loading,
  required bool enabled,
  required int count,
}) {
  if (!enabled || !isVideo || count <= 1) return false;
  if (buffering || slowBuffer || loading) return false;
  return true;
}

/// 一条预取任务。
class VideoPrefetchTask {
  final String url;
  final Map<String, String> headers;
  final String key;
  bool _canceled = false;

  VideoPrefetchTask({
    required this.url,
    Map<String, String>? headers,
    String? key,
  })  : headers = Map<String, String>.unmodifiable(headers ?? const {}),
        key = key ?? url;

  bool get canceled => _canceled;

  void cancel() => _canceled = true;

  @override
  String toString() => 'VideoPrefetchTask($key)';
}

/// 预取统计（诊断/测试用）。
class VideoPrefetchStats {
  int started = 0;
  int loaded = 0;
  int failed = 0;
  int canceled = 0;
  int skipped = 0;

  void reset() {
    started = 0;
    loaded = 0;
    failed = 0;
    canceled = 0;
    skipped = 0;
  }
}

/// 默认取数实现：HTTP Range GET，读完窗口即停。
typedef VideoFetch = Future<bool> Function(VideoPrefetchTask task);

/// 轻量预取器：串行执行、可整体取消、失败静默。
class VideoPrefetcher {
  VideoPrefetcher({
    this.maxConcurrent = 1,
    VideoFetch? fetch,
    this.rangeBytes = videoPrefetchRangeBytes,
    this.timeout = videoPrefetchTimeout,
  })  : assert(maxConcurrent > 0),
        assert(rangeBytes > 0),
        _fetch = fetch;

  /// 当前固定为串行；保留参数便于将来调整。
  final int maxConcurrent;
  final int rangeBytes;
  final Duration timeout;

  final VideoFetch? _fetch;
  final List<VideoPrefetchTask> _queue = <VideoPrefetchTask>[];
  final VideoPrefetchStats stats = VideoPrefetchStats();

  int _generation = 0;
  bool _running = false;
  HttpClient? _client;

  /// 队列中尚未开始的任务数。
  int get pending => _queue.length;

  bool get busy => _running || _queue.isNotEmpty;

  /// 清空并开始一组新任务（同一时刻只保留最新一组）。
  void start(Iterable<VideoPrefetchTask> tasks) {
    cancel();
    for (final t in tasks) {
      if (t.canceled) {
        stats.skipped++;
        continue;
      }
      _queue.add(t);
    }
    _pump();
  }

  /// 取消所有排队与在途请求；之后迟到的结果全部丢弃。
  void cancel() {
    _generation++;
    for (final t in _queue) {
      t.cancel();
      stats.canceled++;
    }
    _queue.clear();
    final c = _client;
    _client = null;
    if (c != null) {
      try {
        c.close(force: true);
      } catch (_) {}
    }
  }

  /// 释放资源，实例不再使用。
  void dispose() {
    cancel();
    stats.reset();
  }

  void _pump() {
    if (_running || _queue.isEmpty) return;
    _running = true;
    final gen = _generation;
    Future<void> run() async {
      while (_queue.isNotEmpty && gen == _generation) {
        final task = _queue.removeAt(0);
        if (task.canceled) {
          stats.skipped++;
          continue;
        }
        // 并发上限 1：串行执行，避免多条同时抢带宽。
        stats.started++;
        var ok = false;
        try {
          ok = await (_fetch ?? _httpFetch)(task);
        } catch (_) {
          ok = false;
        }
        if (gen != _generation || task.canceled) {
          stats.canceled++;
          continue;
        }
        if (ok) {
          stats.loaded++;
        } else {
          stats.failed++;
        }
      }
    }

    run().whenComplete(() {
      _running = false;
      // 期间若 start() 换过一批任务，接着跑最新的队列。
      if (_queue.isNotEmpty && gen != _generation) _pump();
    });
  }

  Future<bool> _httpFetch(VideoPrefetchTask task) async {
    Uri uri;
    try {
      uri = Uri.parse(task.url);
    } catch (_) {
      return false;
    }
    if (!uri.hasScheme || uri.host.isEmpty) return false;
    final client = _client ??= HttpClient()
      ..connectionTimeout = timeout
      ..idleTimeout = const Duration(seconds: 15);
    HttpClientRequest? req;
    try {
      req = await client.getUrl(uri).timeout(timeout);
      task.headers.forEach(req.headers.set);
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-${rangeBytes - 1}');
      final resp = await req.close().timeout(timeout);
      var read = 0;
      await for (final chunk in resp.timeout(timeout)) {
        if (task.canceled) return false;
        read += chunk.length;
        if (read >= rangeBytes) break;
      }
      return read > 0;
    } catch (_) {
      return false;
    } finally {
      // 主动断掉未读完的响应，避免连接被长文件占住。
      try {
        req?.abort();
      } catch (_) {}
    }
  }
}
