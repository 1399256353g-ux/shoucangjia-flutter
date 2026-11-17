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

/// 松手吸附弹簧刚度，越高收尾越快。
const double kSnapStiffness = 420;

/// Q：翻页阈值——拖过视口高度的该比例即翻页。
const double kPageSwipeFraction = 0.18;

/// Q：扇动速度阈值（逻辑像素/秒），方向与位移一致才翻页。
const double kPageSwipeVelocity = 120;

/// Q：回弹/落位时长上限（临界阻尼下定 modulus 在 ~120ms 收敛）。
const Duration kPageSnapMaxDuration = Duration(milliseconds: 160);

/// Q：松手时的目标页（纯函数，可单测）。
///
/// [fromPage] 是本次拖动开始时的整页下标（通常传播放器当前索引）。
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

/// 吸附弹簧阻尼比，1.0 为临界阻尼，不过冲。
const double kSnapDampingRatio = 1.0;

/// 拖动阻尼：越界时按比例衰减，正常范围内保持 1:1 跟手。
double dampedDragOffset(
  double offset, {
  required bool outOfRange,
  double overscrollFactor = kOverscrollDamping,
}) {
  if (!outOfRange) return offset;
  final f = overscrollFactor.clamp(0.0, 1.0);
  return offset * f;
}

/// 松手后的目标页：惯性方向先加/减半页，再四舍五入吸附到最近整页。
double snapTargetPage({
  required double page,
  required double velocity,
  double velocityThreshold = 1.0,
  double maxPage = double.infinity,
}) {
  var p = page;
  if (velocity < -velocityThreshold) {
    p -= 0.5;
  } else if (velocity > velocityThreshold) {
    p += 0.5;
  }
  var target = p.roundToDouble();
  if (target < 0) target = 0;
  final max = maxPage.isFinite ? maxPage : double.infinity;
  if (target > max) target = max;
  return target;
}

/// 竖向翻页专用物理：跟手阻尼 + 硬吸附，三端一致且无回弹拖影。
class DiziPageScrollPhysics extends ScrollPhysics {
  const DiziPageScrollPhysics({
    super.parent,
    this.stiffness = kSnapStiffness,
    this.dampingRatio = kSnapDampingRatio,
    this.fromPage = 0,
  });

  final double stiffness;
  final double dampingRatio;

  /// Q：拖动开始时的整页位置（播放器当前索引），用于方向与阈值判定。
  final double fromPage;

  @override
  DiziPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return DiziPageScrollPhysics(
      parent: buildParent(ancestor),
      stiffness: stiffness,
      dampingRatio: dampingRatio,
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
    final tolerance = toleranceFor(position);
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
    return ScrollSpringSimulation(
      SpringDescription.withDampingRatio(
        mass: 0.5,
        stiffness: 800,
        ratio: 1.0,
      ),
      position.pixels,
      targetPixels,
      0, // Q：抬手立即落位，不跟随扇动惯性
      tolerance: tolerance,
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}
