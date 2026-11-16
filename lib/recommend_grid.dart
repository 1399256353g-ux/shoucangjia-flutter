import 'dart:ui';

/// 推荐页每次展示多少个作品：按窗口大小铺满一屏（最少 [minCount]）。
///
/// 间距与卡片比例与页面里的 SliverGridDelegateWithMaxCrossAxisExtent 一致：
/// maxCrossAxisExtent=180、childAspectRatio=3/4、间距 2。
int recommendVisibleCount(
  Size size, {
  double maxCrossAxisExtent = 180,
  double aspect = 3 / 4,
  double spacing = 2,
  double chromeHeight = 110,
  int minCount = 40,
}) {
  if (size.width <= 0 || size.height <= 0) return minCount;
  final cols = (size.width / maxCrossAxisExtent).ceil().clamp(1, 40);
  final cardH = maxCrossAxisExtent / aspect;
  final usable = (size.height - chromeHeight).clamp(120.0, size.height);
  final rows = (usable / (cardH + spacing)).ceil() + 1;
  final n = cols * rows;
  return n < minCount ? minCount : n;
}
