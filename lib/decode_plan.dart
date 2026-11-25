/// 图片解码预算（纯逻辑，便于单测）。
///
/// 背景（0.9.44 · 已缓存图二次解码 + 滚动解码并发）：
///  - `CachedNetworkImage` 的缓存键 = 图片地址 + `memCacheWidth`。同一张封面
///    在不同页面用不同的解码宽度，会在图片缓存里各存一份、各解码一次；从
///    列表卡点进详情时明明图已经在内存里，却还要按新宽度再解码一遍。
///    这里给「同一展示场景」定唯一的解码宽度（[workCardDecodeWidth] /
///    [libCardDecodeWidth]），卡片与首屏预热都用它，键一致就直接命中。
///  - 滚动时同时解码十几张缩略图会把 CPU 打满、掉帧。缩略图预取统一走
///    [DecodeBudget]，滚动/惯性期间把并发收紧到保守值，停下后再放开；
///    首屏预热在滚动开始前发起，不因此变慢。
library;

import 'dart:async';

import 'layout_metric.dart';

/// 作品卡（`WorkCard`）的最大显示宽度（逻辑像素）。
///
/// 卡片按 `maxCrossAxisExtent: 150` 铺网格，桌面宽窗口下单格最大约 220dp；
/// 取上限做解码宽度，保证任何一屏都够清晰，同时全站只有一个值。
const double kWorkCardDisplayWidth = 220;

/// 库卡片（`BasicLibCard` / `UnitLibraryCard`）的最大显示宽度（逻辑像素）。
///
/// 基础库卡片 `maxCrossAxisExtent: 220`，单元库卡片 260，但封面铺满整卡、
/// 信息压在底部；按 220 解码 + 3x 上限足够，再大只是浪费内存。
const double kLibCardDisplayWidth = 220;

/// 作品卡解码宽度上限（220dp × 3x）。
const int kWorkCardMaxDecodeWidth = 660;

/// 库卡片解码宽度上限（220dp × 3x）。
const int kLibCardMaxDecodeWidth = 660;

/// 显示尺寸 × 设备像素比 → 解码宽度（向上取整）。
///
/// - [displayWidth] <= 0 返回 0（调用方视为「不缩放」）；
/// - [devicePixelRatio] <= 0 按 1.0 处理；
/// - [maxWidth] > 0 时作为上限，避免平板/高 DPI 下解码过大。
int decodeWidthForDisplay(
  double displayWidth,
  double devicePixelRatio, {
  int maxWidth = 0,
}) {
  // 必须判 `isFinite`：`NaN <= 0` / `infinity <= 0` 都是 false，只判 `<= 0`
  // 的守卫会让 `(NaN * 3).ceil()` 在 build 里抛 `Unsupported operation`。
  // 调用方传的是 `MediaQuery.sizeOf` 派生值，对话框/零约束布局里可以是 NaN。
  if (!displayWidth.isFinite || displayWidth <= 0) return 0;
  final dpr =
      (devicePixelRatio.isFinite && devicePixelRatio > 0) ? devicePixelRatio : 1.0;
  final px = ceilDim(displayWidth * dpr, fallback: 1);
  final capped = maxWidth > 0 && px > maxWidth ? maxWidth : px;
  return capped < 1 ? 1 : capped;
}

/// 作品卡封面统一解码宽度（全站唯一，卡片渲染与预热都必须用它）。
int workCardDecodeWidth(double devicePixelRatio) => decodeWidthForDisplay(
      kWorkCardDisplayWidth,
      devicePixelRatio,
      maxWidth: kWorkCardMaxDecodeWidth,
    );

/// 库 / 单元库卡片封面统一解码宽度（卡片渲染与预热都必须用它）。
int libCardDecodeWidth(double devicePixelRatio) => decodeWidthForDisplay(
      kLibCardDisplayWidth,
      devicePixelRatio,
      maxWidth: kLibCardMaxDecodeWidth,
    );

/// 缩略图预取/解码的有界并发。
///
/// 常规上限 [limit]（首屏预热用，默认 4）；滚动/惯性期间收紧到
/// [scrollLimit]（默认保守的 2，常量可调），停下后恢复。
/// 正在跑的请求不打断，只是不再放新的进来。
class DecodeBudget {
  DecodeBudget({
    int limit = 4,
    int scrollLimit = 2,
  })  : _limit = limit < 1 ? 1 : limit,
        _scrollLimit = scrollLimit < 1 ? 1 : scrollLimit;

  int _limit;
  int _scrollLimit;
  bool _scrolling = false;
  int _active = 0;

  final List<void Function()> _waiters = <void Function()>[];

  /// 常规并发上限。
  int get limit => _limit;

  /// 滚动期间的并发上限。
  int get scrollLimit => _scrollLimit;

  /// 是否处于滚动/惯性状态。
  bool get scrolling => _scrolling;

  /// 当前实际生效的并发上限。
  int get effectiveLimit {
    if (!_scrolling) return _limit;
    return _scrollLimit < _limit ? _scrollLimit : _limit;
  }

  /// 正在执行的任务数。
  int get active => _active;

  /// 排队等待的任务数。
  int get waiting => _waiters.length;

  set limit(int v) {
    _limit = v < 1 ? 1 : v;
    _pump();
  }

  set scrollLimit(int v) {
    _scrollLimit = v < 1 ? 1 : v;
    _pump();
  }

  /// 切换滚动状态；滚动开始时排队中的任务会按新上限重新评估。
  void setScrolling(bool value) {
    if (_scrolling == value) return;
    _scrolling = value;
    _pump();
  }

  /// 在预算内执行 [task]，超出并发时排队等待。
  Future<T> run<T>(Future<T> Function() task) async {
    await _acquire();
    try {
      return await task();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_active < effectiveLimit) {
      _active++;
      return Future<void>.value();
    }
    final done = Completer<void>();
    _waiters.add(done.complete);
    return done.future;
  }

  void _release() {
    _active--;
    _pump();
  }

  void _pump() {
    while (_waiters.isNotEmpty && _active < effectiveLimit) {
      final wake = _waiters.removeAt(0);
      _active++;
      wake();
    }
  }
}
