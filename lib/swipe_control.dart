/// G15：移动端上下滑手势（抖音式）——左侧调亮度、右侧调音量。
///
/// 手势只覆盖屏幕左右两侧的窄条，中间区域仍然保留上下滑翻页（G3），
/// 避免调亮度/音量时误切作品。换算逻辑保持纯函数，便于单元测试。
library;

/// 上下滑作用区。
enum SwipeZone { brightness, volume }

/// 仅移动端启用；桌面端继续使用鼠标/滚轮/键盘。
bool swipeEnabledFor({
  required bool isAndroid,
  required bool isIOS,
  bool isWeb = false,
}) =>
    !isWeb && (isAndroid || isIOS);

/// 边缘手势条宽度：屏宽的 18%，限制在 48–96 之间。
double swipeEdgeWidth(double screenWidth) {
  if (screenWidth <= 0) return 48;
  return (screenWidth * 0.18).clamp(48.0, 96.0);
}

/// 根据横向位置返回作用区；中间区域返回 null（交给翻页手势）。
SwipeZone? swipeZoneAt(double x, double screenWidth) {
  if (screenWidth <= 0) return null;
  final edge = swipeEdgeWidth(screenWidth);
  if (x <= edge) return SwipeZone.brightness;
  if (x >= screenWidth - edge) return SwipeZone.volume;
  return null;
}

/// 竖向拖动换算：向上（dy < 0）增大。满屏高度对应整个区间。
double swipeValueFromDrag({
  required double start,
  required double dy,
  required double height,
  double min = 0,
  double max = 100,
}) {
  if (height <= 0 || max <= min) return start.clamp(min, max);
  final value = start - dy / height * (max - min);
  return value.clamp(min, max);
}

/// 提示文案。
String swipeLabel(SwipeZone zone) =>
    zone == SwipeZone.brightness ? '亮度' : '音量';

/// 亮度（0–100）换算成压暗遮罩的不透明度；100 时完全不遮。
double dimOpacityForBrightness(double brightness) {
  final b = brightness.clamp(0.0, 100.0);
  return (100.0 - b) / 100.0 * 0.78;
}

/// 按 10% 一档返回档位，用于拖动时的轻震动反馈。
int swipeHapticStep(double value) => (value / 10).floor();
