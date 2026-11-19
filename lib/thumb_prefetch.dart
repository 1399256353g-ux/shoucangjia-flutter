/// 0.9.26：首屏缩略图预热。
///
/// 列表页数据到手时，先把「首屏 + 一屏」可见的封面按显示宽度拉进图片缓存，
/// 避免 GridView 逐张发请求造成的首屏空白/闪烁。
///
/// 只做三件事：算要预热几张（纯函数，可单测）、去重、限量并发。
/// 不做重试、不落盘、不上传；预热失败就是失败，交给卡片自身再请求一次。
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';

import 'decode_plan.dart';
import 'perf_diagnostics.dart';

/// 首屏需要预热的封面张数。
///
/// [viewportWidth] / [viewportHeight] 为页面可用尺寸；网格参数与
/// `SliverGridDelegateWithMaxCrossAxisExtent` 保持一致。
/// 默认预热 2 屏（首屏 + 一屏），上限 [maxItems] 张。
int firstScreenThumbCount({
  required double viewportWidth,
  required double viewportHeight,
  double maxCrossAxisExtent = 150,
  double padding = 10,
  double crossSpacing = 8,
  double mainSpacing = 8,
  double aspectRatio = 0.72,
  int screens = 2,
  int maxItems = 24,
}) {
  if (maxItems <= 0) return 0;
  final usableW = viewportWidth - padding * 2;
  final usableH = viewportHeight - padding * 2;
  if (usableW <= 0 || usableH <= 0) return 0;
  final tileStride = maxCrossAxisExtent + crossSpacing;
  var cols = ((usableW + crossSpacing) / tileStride).ceil();
  if (cols < 1) cols = 1;
  final tileW = (usableW - (cols - 1) * crossSpacing) / cols;
  final tileH = tileW / (aspectRatio <= 0 ? 0.72 : aspectRatio);
  final rowStride = tileH + mainSpacing;
  var rows = ((usableH * (screens < 1 ? 1 : screens)) / rowStride).ceil();
  if (rows < 1) rows = 1;
  final n = cols * rows;
  return n > maxItems ? maxItems : n;
}

/// 列表（非网格）首屏需要预热的行数。
///
/// 排行榜这类 `ListTile` 列表按固定行高估算：默认预热 2 屏、上限 [maxItems] 行。
/// [rowExtent] 取一行（含分隔线）的实际逻辑高度。
int firstScreenRowCount({
  required double viewportHeight,
  double rowExtent = 72,
  int screens = 2,
  int maxItems = 12,
}) {
  if (maxItems <= 0 || viewportHeight <= 0 || rowExtent <= 0) return 0;
  final h = viewportHeight * (screens < 1 ? 1 : screens);
  final n = (h / rowExtent).ceil();
  if (n < 1) return 1;
  return n > maxItems ? maxItems : n;
}

/// 预热统计（诊断信息页读取）。
class ThumbPrefetchStats {
  int requested = 0;
  int loaded = 0;
  int failed = 0;
  int skipped = 0;

  /// 本轮预取的在途并发峰值（诊断用）。
  int peakActive = 0;

  /// 排队等待的峰值（诊断用）。
  int peakWaiting = 0;
  DateTime? lastRun;

  int get pending => requested - loaded - failed;

  String get lastRunText {
    final t = lastRun;
    if (t == null) return '尚未预热';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}

/// 全局预热器：只有一个实例，多页共用去重表与统计。
class ThumbPrefetch extends ChangeNotifier {
  ThumbPrefetch({
    this.maxConcurrent = 4,
    this.scrollMaxConcurrent = 2,
    this.seenLimit = 600,
  })  : assert(maxConcurrent > 0),
        assert(scrollMaxConcurrent > 0),
        assert(seenLimit > 0);

  static final ThumbPrefetch instance = ThumbPrefetch();

  final int maxConcurrent;

  /// 滚动/惯性期间的并发上限（保守值，停下后恢复 [maxConcurrent]）。
  final int scrollMaxConcurrent;
  final int seenLimit;

  final ThumbPrefetchStats stats = ThumbPrefetchStats();
  final Set<String> _seen = <String>{};
  final Queue<String> _seenOrder = Queue<String>();

  /// 已登记但尚未跑完（排队/在途）的 URL。淘汰时不能把它们踢出
  /// 去重表，否则同一张图会被再次预热、重复解码。
  final Set<String> _pending = <String>{};
  late final DecodeBudget budget = DecodeBudget(
    limit: maxConcurrent,
    scrollLimit: scrollMaxConcurrent,
  );
  int _active = 0;

  /// 正在预热的张数（诊断用）。
  int get active => _active;

  bool get busy => _active > 0;

  /// 当前是否处于滚动收紧状态（诊断/单测用）。
  bool get scrolling => budget.scrolling;

  /// 当前实际生效的并发上限。
  int get effectiveLimit => budget.effectiveLimit;

  /// 由 [ScrollDecodeScope] 上报滚动状态。
  void setScrolling(bool value) => budget.setScrolling(value);

  /// 清掉去重表与统计（仅内存，用于诊断页手动重置）。
  void reset() {
    _seen.clear();
    _seenOrder.clear();
    stats
      ..requested = 0
      ..loaded = 0
      ..failed = 0
      ..skipped = 0
      ..peakActive = 0
      ..peakWaiting = 0
      ..lastRun = null;
    notifyListeners();
  }

  /// 按显示尺寸预取图片。[provider] 需与卡片实际使用的 provider 同为
  /// `CachedNetworkImageProvider` + 同宽度 `ResizeImage`，否则缓存键不匹配。
  Future<int> run(
    Iterable<String> urls, {
    required ImageProvider Function(String url) provider,
    int limit = 24,
  }) {
    return runWith(
      urls,
      limit: limit,
      fetch: (u) => loadImage(provider(u)),
    );
  }

  /// 实际预热入口（把「取图」注入进来，便于单测）。
  Future<int> runWith(
    Iterable<String> urls, {
    required Future<bool> Function(String url) fetch,
    int limit = 24,
  }) async {
    if (limit <= 0) return 0;
    final todo = <String>[];
    for (final raw in urls) {
      final u = raw.trim();
      if (u.isEmpty) continue;
      if (!_mark(u)) {
        stats.skipped++;
        continue;
      }
      todo.add(u);
      if (todo.length >= limit) break;
    }
    if (todo.isEmpty) return 0;
    stats.requested += todo.length;
    stats.lastRun = DateTime.now();
    notifyListeners();

    Future<void> one(String url) async {
      if (budget.waiting > stats.peakWaiting) {
        stats.peakWaiting = budget.waiting;
      }
      _active++;
      if (_active > stats.peakActive) stats.peakActive = _active;
      var ok = false;
      try {
        ok = await fetch(url);
      } catch (_) {
        ok = false;
      } finally {
        _active--;
        _pending.remove(url);
      }
      if (ok) {
        stats.loaded++;
      } else {
        stats.failed++;
        // 失败不留在去重表里，下次进页面还能再试。
        _forget(url);
      }
    }

    // 并发由 [budget] 统一把关：滚动期间自动收紧，不打断在途请求。
    final pending = <Future<void>>[];
    for (final url in todo) {
      if (budget.waiting > stats.peakWaiting) {
        stats.peakWaiting = budget.waiting;
      }
      pending.add(budget.run(() => one(url)));
    }
    await Future.wait(pending);
    // 解码并发峰值上报给本地诊断日志（不联网）。
    PerfDiagnostics.instance.recordDecode(
      active: stats.peakActive,
      waiting: stats.peakWaiting,
      limit: effectiveLimit,
    );
    notifyListeners();
    return todo.length;
  }

  /// 标记为已预热；返回 false 表示重复（已在表里或正在预热）。
  bool _mark(String url) {
    if (!_seen.add(url)) return false;
    _seenOrder.add(url);
    _pending.add(url);
    _evictOverflow();
    return true;
  }

  /// 去重表超限时淘汰最旧的**已完成**项；排队/在途项即使最旧也保留，
  /// 避免被再次入队造成重复请求与重复解码。
  void _evictOverflow() {
    while (_seenOrder.length > seenLimit) {
      String? victim;
      for (final candidate in _seenOrder) {
        if (!_pending.contains(candidate)) {
          victim = candidate;
          break;
        }
      }
      if (victim == null) return; // 全都在途，允许短暂超出上限
      _seenOrder.remove(victim);
      _seen.remove(victim);
    }
  }

  void _forget(String url) {
    if (_seen.remove(url)) _seenOrder.remove(url);
  }
}

/// 把 `ImageProvider` 解析到图片缓存里，返回是否成功。
///
/// 不用 `precacheImage` 是为了不依赖 `BuildContext`（页面 dispose 后
/// 仍可能有一次在途预热），失败也不抛异常。
Future<bool> loadImage(ImageProvider provider) {
  final stream = provider.resolve(ImageConfiguration.empty);
  final done = Completer<bool>();
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, sync) {
      stream.removeListener(listener);
      if (!done.isCompleted) done.complete(true);
    },
    onError: (e, st) {
      stream.removeListener(listener);
      if (!done.isCompleted) done.complete(false);
    },
  );
  stream.addListener(listener);
  return done.future;
}
