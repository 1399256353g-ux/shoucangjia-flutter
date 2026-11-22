/// 指针级手势判定（纯逻辑，便于单测）。
///
/// 背景（2026-11-22 设备日志）：`author-tap[pointer-down]` /
/// `author-tap[pointer-up]` 是「指针进到信息层」的取证日志，**不代表发生了
/// 点击**。但只看这两行会误读成「点了没反应」——上一轮就是竖向上滑被读成
/// 点击。这里给按下→抬起的位移与时长一个明确判定，日志里直接写明是滑动还是
/// 点击，不再靠读坐标猜。
library;

import 'dart:ui' show Offset;

/// Flutter 的触摸 slop：位移超过它就说明指针在拖，而不是点。
const double kGestureTapSlop = 18.0;

/// 长按时长门槛（与 Flutter `kLongPressTimeout` 一致）。
const Duration kGestureHoldAfter = Duration(milliseconds: 500);

/// 手势判定结果（作为日志字段使用）。
enum GestureVerdict {
  /// 位移在 slop 内、时长未到长按 → 真点击。
  tap,

  /// 位移超过 slop → 拖动/滑动（手势竞技场会给滑动，不触发 onTap）。
  swipe,

  /// 位移在 slop 内但按住超过 500ms → 长按。
  hold,
}

/// 按下点 [down] → 抬起点 [up]、按住 [held]，判定这一次指针序列是什么手势。
GestureVerdict gestureVerdict({
  required Offset down,
  required Offset up,
  required Duration held,
  double slop = kGestureTapSlop,
}) {
  final dist = (up - down).distance;
  if (dist > slop) return GestureVerdict.swipe;
  if (held >= kGestureHoldAfter) return GestureVerdict.hold;
  return GestureVerdict.tap;
}

/// 日志里用的短名。
String gestureVerdictName(GestureVerdict v) => switch (v) {
      GestureVerdict.tap => 'tap',
      GestureVerdict.swipe => 'swipe',
      GestureVerdict.hold => 'hold',
    };
