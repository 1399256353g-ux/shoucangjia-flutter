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
  });

  final double stiffness;
  final double dampingRatio;

  @override
  DiziPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return DiziPageScrollPhysics(
      parent: buildParent(ancestor),
      stiffness: stiffness,
      dampingRatio: dampingRatio,
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
    final target = snapTargetPage(
      page: page,
      velocity: velocity,
      velocityThreshold: tolerance.velocity,
      maxPage: maxPage < 0 ? 0 : maxPage,
    );
    final targetPixels = target * position.viewportDimension;
    final atRest = (targetPixels - position.pixels).abs() < 0.5;
    if (atRest && velocity.abs() < tolerance.velocity) return null;
    return ScrollSpringSimulation(
      SpringDescription.withDampingRatio(
        mass: 0.5,
        stiffness: stiffness,
        ratio: dampingRatio,
      ),
      position.pixels,
      targetPixels,
      velocity,
      tolerance: tolerance,
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}
