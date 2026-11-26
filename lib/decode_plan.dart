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

/// 作品卡解码宽度上限（220dp × 3x）。
const int kWorkCardMaxDecodeWidth = 660;

/// 库卡片解码宽度的兜底上限（按 220dp × 3x；正常走「显示宽度 × 3」）。
///
/// 「显示宽度」本身不在这里：它就是网格规格的 `maxCrossAxisExtent`
/// （`grid_spec.LibGridSpec.displayWidth`），同一个数字不再另立名字。
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

/// 「按屏幕宽度解码」的唯一公式（播放页海报 / 图文原图 / 邻页预载）。
///
/// 0.9.292：同一件事此前在本文件之外写了两遍——
///
/// ```
/// main._posterDecodeWidth   roundDim(size.width * dpr, fallback: 360)
///                           .clamp(360, 2160)
/// main.picView              roundDim(size.width * dpr, fallback: 1080)   ← 无上限
/// ```
///
/// 两者都是「一张原图按屏幕宽度解码」，只是兜底值和上限各写了一遍。
/// 后果是可测量的：窗口宽度 × dpr > 2160 时，同一张图在播放页海报与图文页
/// 得到两个不同的解码宽度；窗口尺寸取到 NaN（最小化/零约束）时一个兜到 360、
/// 一个兜到 1080，缓存里又各存一份。
///
/// 上限 2160 是「4K 宽屏也不超过一张 2160px 宽的位图」——原图常见 2400×3600，
/// 整张进内存约 30MB，滑动会卡顿甚至闪退（0.9.25 真机结论）。
int screenDecodeWidth({
  required double viewportWidth,
  required double devicePixelRatio,
  int minWidth = 360,
  int maxWidth = 2160,
}) {
  final dpr =
      (devicePixelRatio.isFinite && devicePixelRatio > 0) ? devicePixelRatio : 1.0;
  final px = roundDim(viewportWidth * dpr, fallback: minWidth);
  // `clamp` 对 NaN 返回 NaN 的取整会抛异常，所以先兜到 minWidth 再夹。
  return px < minWidth ? minWidth : (px > maxWidth ? maxWidth : px);
}

/// 库卡片封面的解码宽度：按卡片**真实显示宽度**算（0.9.286）。
///
/// 卡片（`_UnitCoverFill.memCacheWidth`）与首屏预热（`lib_card_prefetch`）
/// 必须得到同一个数，否则缓存键不同、预热白拉一次再解码一次。此前两边各写
/// 一份：卡片内联 `decodeWidthForDisplay(displayWidth, dpr, maxWidth:
/// ceilDim(displayWidth*3, fallback: kLibCardMaxDecodeWidth))`，预热调
/// `unitCardDecodeWidth` / `libCardDecodeWidth`——三份公式一致只是巧合，
/// 改一处就分叉。
int libCardDecodeWidthOf(double displayWidth, double devicePixelRatio) =>
    decodeWidthForDisplay(
      displayWidth,
      devicePixelRatio,
      maxWidth: ceilDim(displayWidth * 3, fallback: kLibCardMaxDecodeWidth),
    );

/// 小方图（列表里的 56dp 缩略图这类）解码宽度：显示边长 × dpr，上限 3 倍。
///
/// 0.9.292：删除记录列表的缩略图以前把尺寸 56 写三遍、解码宽度内联成
/// `memCacheWidth: 160`——160 既不是 56 × 2 也不是 56 × 3，而是在 2x 屏上
/// 偏大、3x 屏上偏小的“中间数”。这类图没有卡片/头像语义，也不该借用
/// `avatarDecodeWidth`（那个上限是 384，与边长无关）。
int squareThumbDecodeWidth(double displaySize, double devicePixelRatio) =>
    decodeWidthForDisplay(
      displaySize,
      devicePixelRatio,
      maxWidth: ceilDim(displaySize * 3, fallback: 1),
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
