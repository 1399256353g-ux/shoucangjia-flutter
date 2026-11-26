import 'dart:ui';

import 'grid_geometry.dart';
import 'grid_spec.dart';
import 'layout_metric.dart';

/// 推荐页每次展示多少个作品：按窗口大小铺满一屏（最少 [minCount]）。
///
/// 几何与页面里的 `GridView` delegate 同源：默认值读 `grid_spec.kWorkGrid`
/// （180 / 3:4 / 间距 2）。此前这三个数字在本文件与 `WorkGrid._buildGrid`
/// 各写一遍。
int recommendVisibleCount(
  Size size, {
  double? maxCrossAxisExtent,
  double? aspect,
  double? spacing,
  double chromeHeight = 110,
  int minCount = 40,
}) {
  final maxExtent = maxCrossAxisExtent ?? kWorkGrid.maxCrossAxisExtent;
  final ratio = aspect ?? kWorkGrid.aspectRatio;
  final gap = spacing ?? kWorkGrid.spacing;
  // 必须用 [finiteOr] 判，不能写 `<= 0`：`NaN <= 0` 与 `infinity <= 0`
  // 都是 **false**，那套守卫拦不住任何一种，后面的 `.ceil()` 直接抛
  // `Unsupported operation: Infinity or NaN toInt`，整页推荐在 build 里崩。
  // 实测：`recommendVisibleCount(Size(360, double.infinity))` 抛异常。
  final w = finiteOr(size.width, 0);
  final h = finiteOr(size.height, 0);
  if (w <= 0 || h <= 0) return minCount;
  // 参数为 0/负数时不能进除法：`x / 0` 得到 infinity，`infinity.ceil()` 直接抛
  // `Unsupported operation`，整页推荐在 build 里崩掉。
  if (!maxExtent.isFinite ||
      maxExtent <= 0 ||
      !ratio.isFinite ||
      ratio <= 0) {
    return minCount;
  }
  // 列数与 Flutter delegate 同一规则（grid_geometry 唯一实现）。此前写成
  // `ceil(宽 / 最大列宽)`，完全没算间距：真实网格是
  // `ceil(宽 / (最大列宽 + 间距))`，宽 1440、间距 2 时这里是 8 列、网格是 7 列，
  // 首屏多铺一整列却永远看不到（多拉的作品列表也是白拉）。
  final cols = gridColumnCount(
    crossAxisExtent: w,
    maxCrossAxisExtent: maxExtent,
    spacing: gap,
  ).clamp(1, 40);
  // 卡片高度按**真实列宽**算（delegate 是 `列宽 / childAspectRatio`），
  // 不是按最大列宽：宽 3600 时最大列宽 180 会低估行高，反之多算行。
  final tileW = gridTileWidth(
    crossAxisExtent: w,
    columns: cols,
    spacing: gap,
  );
  final cardH = tileW > 0
      ? gridTileHeight(tileWidth: tileW, aspectRatio: ratio)
      : maxExtent / ratio;
  if (cardH <= 0) return minCount;
  // 不能写 `.clamp(120.0, size.height)`：Windows 端窗口可以被拖到很矮（
  // 分屏、正被最小化前的中间态），此时下界 120 > 上界 size.height，
  // `num.clamp` 抛 `Invalid argument(s): 120.0` —— 推荐页在 build 阶段
  // 崩成灰屏。这里只保证「至少按一行高估算」，不再用下界反压上界。
  final usable = h - finiteOr(chromeHeight, 0);
  final band = usable < 120.0 ? 120.0 : usable;
  // 行数同样不能裸 `.ceil()`：`band` 有限但 `cardH + spacing` 可能被外部
  // 传成 0（spacing 传负值抵消掉行高），除出 infinity 后再 ceil 就抛。
  final stride = cardH + gap;
  final rows = stride.isFinite && stride > 0
      ? ceilDim(band / stride, fallback: 1) + 1
      : 2;
  final n = cols * rows;
  return n < minCount ? minCount : n;
}
