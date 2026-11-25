import 'package:flutter/material.dart';

/// I2：抖音式翻页手感。
///
/// 目标：动画更短、跟手阻尼、松手吸附、无拖沓。
/// - 程序化翻页 180ms → 110ms（easeOutCubic），连按不拖沓
/// - 拖动越界只走 28%，不会拉出大片空白
/// - 松手吸附使用更硬的弹簧（stiffness 420），翻页收尾干脆
/// 纯函数与 Physics 分离，便于单元测试。

/// 程序化翻页（键盘/连播/按钮）的时长。
const Duration pageTurnDuration = Duration(milliseconds: 110);

/// 程序化翻页曲线：起步快、收尾稳，观感更接近抖音。
const Curve pageTurnCurve = Curves.easeOutCubic;

/// 越界拖动阻尼系数（0–1，越小越“拉不动”）。
const double kOverscrollDamping = 0.28;

/// Q：翻页阈值——拖过视口高度的该比例即翻页。
const double kPageSwipeFraction = 0.18;

/// Q：扇动速度阈值（逻辑像素/秒），方向与位移一致才翻页。
const double kPageSwipeVelocity = 120;

/// Q：回弹/落位由 [FastSettleSimulation] 的固定 110ms 保证，不再有
/// “最大回弹时长”这类参数（`kPageSnapMaxDuration = 160ms` 描述的行为从未存在）。

/// 松手后的目标页（唯一实现）。
///
/// [fromPage] 是本次拖动开始时的整页下标（通常为播放器当前索引）。
/// 规则：
/// 1. 相对起点位移 ≥ [fractionThreshold]（默认 18% 页高）→ 按方向翻一页；
/// 2. 否则速度 > [velocityThreshold]（120px/s）且方向一致 → 翻一页；
/// 3. 其余回弹到起点页；目标永远只差最多一页（快扇也不连翻两条）。
double pageSwipeTarget({
  required double page,
  required double fromPage,
  required double velocity,
  double fractionThreshold = kPageSwipeFraction,
  double velocityThreshold = kPageSwipeVelocity,
  double maxPage = double.infinity,
}) {
  final delta = page - fromPage;
  var target = fromPage;
  if (delta.abs() >= fractionThreshold) {
    target = fromPage + delta.sign;
  } else if (velocity.abs() > velocityThreshold &&
      (delta == 0 || velocity.sign == delta.sign)) {
    target = fromPage + velocity.sign;
  }
  if (target < 0) target = 0;
  final max = maxPage.isFinite ? maxPage : double.infinity;
  if (target > max) target = max;
  return target;
}

/// 拖动阻尼：越界时按比例衰减，正常范围内保持 1:1 跟手。
double dampedDragOffset(
  double offset, {
  required bool outOfRange,
  double overscrollFactor = kOverscrollDamping,
}) {
  if (!outOfRange) return offset;
  // 非有限输入必须在这里收手：`offset` 来自滚动指标，在拖动第一帧/尺寸为零
  // 的中间态可以是 NaN；`NaN * f` = NaN 会写进当前滚动物理，页面从此收不回来
  // （表现为整页不再响应滑动）。`overscrollFactor` 同理：`NaN.clamp(0,1)`
  // 实测返回 **1.0**（clamp 对 NaN 走上界），等于悄悄关掉阻尼。
  if (!offset.isFinite) return 0;
  if (!overscrollFactor.isFinite) return offset;
  final f = overscrollFactor.clamp(0.0, 1.0);
  return offset * f;
}

/// 松手后的吸附目标页已由 [pageSwipeTarget]（真实路径）统一回答：
/// `DiziPageScrollPhysics.createBallisticSimulation` 直接调它。历史上这里
/// 还有一份 `snapTargetPage`（惯性加半页再四舍五入），但那套实现从未
/// 被任何渲染路径调用，两套规则同时存在只会让“翻几页”到底以谁为准变成
/// 猜谜——已删除。

/// 竖向翻页物理：跟手阻尼 + 固定时长落位，三端一致且无回弹拖影。
///
/// 历史上这里有 `stiffness` / `dampingRatio` 两个弹簧参数（配 `kSnapStiffness = 620`），
/// 但落位早已改成 [FastSettleSimulation] 的固定 110ms 曲线——弹簧参数不再参与
/// 任何计算，只被一条单测断言“能被 applyTo 保留”，属于为不存在的行为作证。
/// 已连同常量一起删除，现在只留真实用到的 [fromPage]。
class DiziPageScrollPhysics extends ScrollPhysics {
  const DiziPageScrollPhysics({
    super.parent,
    this.fromPage = 0,
  });

  /// Q：拖动开始时的整页位置（播放器当前索引），用于方向与阈值判定。
  final double fromPage;

  @override
  DiziPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return DiziPageScrollPhysics(
      parent: buildParent(ancestor),
      fromPage: fromPage,
    );
  }

  double _page(ScrollMetrics position) {
    if (position is PageMetrics) {
      final p = position.page;
      if (p != null) return p;
    }
    if (position.viewportDimension <= 0) return 0;
    return position.pixels / position.viewportDimension;
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    return dampedDragOffset(offset, outOfRange: position.outOfRange);
  }

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    if (position.viewportDimension <= 0) return null;
    final page = _page(position);
    final maxPage = position.maxScrollExtent / position.viewportDimension;
    final target = pageSwipeTarget(
      page: page,
      fromPage: fromPage,
      velocity: velocity,
      maxPage: maxPage < 0 ? 0 : maxPage,
    );
    final targetPixels = target * position.viewportDimension;
    final atRest = (targetPixels - position.pixels).abs() < 0.5;
    if (atRest && velocity.abs() < kPageSwipeVelocity) return null;
    // owner 2026-11-20：抖音是「固定时长的干脆落位」，不是弹簧。
    // 弹簧的收敛时间随位移变化（甩得远就拖），所以一直显得比抖音长。
    // 这里改成固定 110ms 的曲线动画：不管甩多远，落位时间恒定。
    final distance = (targetPixels - position.pixels).abs();
    if (distance < 0.5) return null;
    return FastSettleSimulation(
      from: position.pixels,
      to: targetPixels,
      duration: const Duration(milliseconds: 110),
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}

/// 固定时长的落位动画。
///
/// 弹簧的收敛时间随位移变化（甩得远就更久），所以观感一直比抖音拖；
/// 这里用固定时长 + easeOutCubic：不管甩多远，110ms 内一定落位。
class FastSettleSimulation extends Simulation {
  FastSettleSimulation({
    required this.from,
    required this.to,
    this.duration = const Duration(milliseconds: 110),
  });

  final double from;
  final double to;
  final Duration duration;

  double get _seconds => duration.inMicroseconds / Duration.microsecondsPerSecond;

  @override
  double x(double time) {
    final t = (time / _seconds).clamp(0.0, 1.0);
    return from + (to - from) * Curves.easeOutCubic.transform(t);
  }

  @override
  double dx(double time) {
    if (time >= _seconds) return 0;
    const dt = 0.001;
    return (x(time + dt) - x(time)) / dt;
  }

  @override
  bool isDone(double time) => time >= _seconds;
}
