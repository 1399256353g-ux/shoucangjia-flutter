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
  // 参数为 0/负数时不能进除法：`x / 0` 得到 infinity，`infinity.ceil()` 直接抛
  // `Unsupported operation`，整页推荐在 build 里崩掉。
  if (maxCrossAxisExtent <= 0 || aspect <= 0) return minCount;
  final cols = (size.width / maxCrossAxisExtent).ceil().clamp(1, 40);
  final cardH = maxCrossAxisExtent / aspect;
  // 不能写 `.clamp(120.0, size.height)`：Windows 端窗口可以被拖到很矮（
  // 分屏、正被最小化前的中间态），此时下界 120 > 上界 size.height，
  // `num.clamp` 抛 `Invalid argument(s): 120.0` —— 推荐页在 build 阶段
  // 崩成灰屏。这里只保证「至少按一行高估算」，不再用下界反压上界。
  final usable = size.height - chromeHeight;
  final band = usable < 120.0 ? 120.0 : usable;
  final rows = (band / (cardH + spacing)).ceil() + 1;
  final n = cols * rows;
  return n < minCount ? minCount : n;
}
