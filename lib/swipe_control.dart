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

/// 手机竖屏边缘热区宽度：左右各 1/4 屏宽（抖音式边缘手势已收窄）。
double edgeHotZoneWidth(double screenWidth) =>
    screenWidth <= 0 ? 0 : screenWidth * 0.25;

/// 边缘竖滑的接管意图。
enum EdgeGestureIntent { none, brightness, volume }

/// 判定这次拖动是否应由边缘竖滑接管；返回 [EdgeGestureIntent.none] 时
/// 必须把整个手势让给 PageView 翻页。
///
/// 规则（O1）：
/// - 只在小屏竖屏启用（桌面/横屏不启用）；
/// - 起点落在左右各 1/4 屏宽内（左=亮度，右=音量）；
/// - 竖向位移必须大于 [minVertical]，且横向位移小于竖向位移的
///   [horizontalRatio]；斜向拖动交给翻页。
EdgeGestureIntent edgeGestureIntent({
  required double dx,
  required double dy,
  required double width,
  required double startX,
  bool portrait = true,
  double minVertical = 12,
  double horizontalRatio = 0.6,
}) {
  if (!portrait || width <= 0) return EdgeGestureIntent.none;
  final adx = dx.abs();
  final ady = dy.abs();
  if (ady <= minVertical) return EdgeGestureIntent.none;
  if (adx >= ady * horizontalRatio) return EdgeGestureIntent.none;
  if (startX <= width * 0.25) return EdgeGestureIntent.brightness;
  if (startX >= width * 0.75) return EdgeGestureIntent.volume;
  return EdgeGestureIntent.none;
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
