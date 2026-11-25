/// 网格几何（**唯一实现**）：列数 / 列宽 / 行高偏移。
///
/// 这件事此前被写了三份，而且**写法各不相同**：
///
/// | 位置 | 列数写法 | 缺口 |
/// |---|---|---|
/// | `author_index.authorGridOffsetForIndex` | `ceil((avail + gap) / (max + gap))` | 分子多加了一个 gap，列数偏大 |
/// | `thumb_prefetch.firstScreenThumbCount` | `ceil((usableW + crossSpacing) / stride)` | 同上 |
/// | `recommend_grid.recommendVisibleCount` | `ceil(width / maxExtent)` | 完全没算间距 |
///
/// 左上第一份的缺口是**真的错行**：Flutter 的
/// `SliverGridDelegateWithMaxCrossAxisExtent` 在
/// `rendering/sliver_grid.dart` 里算的是
///
/// ```dart
/// crossAxisCount = ceil(crossAxisExtent / (maxCrossAxisExtent + crossAxisSpacing));
/// ```
///
/// 先除后向上取整，**不是** `(extent + spacing) / (max + spacing)`。
/// 两者在「可用宽除以步长恰好落在 (k, k+1) 的尾部」时分叉：宽 400、两侧
/// 内边距各 12、max 180、间距 10 → 可用 376，正确列数 `ceil(376/190) = 2`，
/// 旧写法 `ceil(386/190) = 3`。列数多算一列，行号就少算一行——点一个字母
/// 滚到的位置整行偏上，越往下差得越多（实测宽 400 时索引 3 应到 234.8，
/// 旧算法给 160.0）。
///
/// 所以这里只留一条规则；页面里的 `SliverGridDelegateWithMaxCrossAxisExtent`
/// 参数必须与传给本文件的参数同源（同一常量），否则依然会分叉。
library;

/// 严格按 `SliverGridDelegateWithMaxCrossAxisExtent` 计算列数。
///
/// [crossAxisExtent] 是**扣除左右内边距之后**的可用宽度（即网格实际拿到的
/// 交叉轴约束），[maxCrossAxisExtent] 与 [spacing] 必须与 delegate 上的
/// 同名参数一致。[crossAxisExtent] ≤ 0 时返回 1（delegate 自身也用
/// `math.max(1, ...)` 兜住 0 宽，避免后续除零）。
int gridColumnCount({
  required double crossAxisExtent,
  required double maxCrossAxisExtent,
  double spacing = 0,
}) {
  if (!crossAxisExtent.isFinite || crossAxisExtent <= 0) return 1;
  if (!maxCrossAxisExtent.isFinite || maxCrossAxisExtent <= 0) return 1;
  final gap = spacing.isFinite && spacing > 0 ? spacing : 0.0;
  final n = (crossAxisExtent / (maxCrossAxisExtent + gap)).ceil();
  return n < 1 ? 1 : n;
}

/// 列宽：可用宽扣掉 `(列数-1)` 条间距后均分（与 delegate 的
/// `usableCrossAxisExtent / crossAxisCount` 一致）。
double gridTileWidth({
  required double crossAxisExtent,
  required int columns,
  double spacing = 0,
}) {
  if (!crossAxisExtent.isFinite || crossAxisExtent <= 0) return 0;
  final n = columns < 1 ? 1 : columns;
  final gap = spacing.isFinite && spacing > 0 ? spacing : 0.0;
  final usable = crossAxisExtent - gap * (n - 1);
  if (usable <= 0) return 0;
  return usable / n;
}

/// 行高：列宽 / 宽高比（delegate 的 `childCrossAxisExtent / childAspectRatio`）。
double gridTileHeight({
  required double tileWidth,
  double aspectRatio = 1,
}) {
  if (!tileWidth.isFinite || tileWidth <= 0) return 0;
  if (!aspectRatio.isFinite || aspectRatio <= 0) return 0;
  return tileWidth / aspectRatio;
}
