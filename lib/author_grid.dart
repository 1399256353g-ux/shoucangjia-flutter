/// I7：作者总览网格的纯逻辑——网格几何、头像解码尺寸、排序结果复用。
///
/// 作者总览页数据量大（上千位作者），此前 `sorted` 在每次 build /
/// 滚动回调里都会重新排序，头像也按固定宽度解码；返回作者页还会整页重载。
/// 这里把可测试的几何与排序抽出来，页面只缓存一次排序结果即可。
library;

/// 作者网格的布局几何。
class AuthorGridGeometry {
  /// 每行可放多少个作者卡片（至少 1 个）。
  final int columns;

  /// 单个卡片的宽度（逻辑像素）。
  final double cellWidth;

  /// 单行占用的高度（含行间距），可直接作为 `ListView.itemExtent`。
  final double rowExtent;

  const AuthorGridGeometry({
    required this.columns,
    required this.cellWidth,
    required this.rowExtent,
  });

  /// 给定作者总数需要多少行。
  int rowsFor(int total) {
    if (total <= 0 || columns <= 0) return 0;
    return (total + columns - 1) ~/ columns;
  }
}

/// 按可用宽度计算作者网格的行列与行高。
///
/// 网格使用固定行高（`itemExtent`），滚动时 Flutter 可以直接按偏移量
/// 复用行，不再逐项测量，返回/滚动都更稳定。
AuthorGridGeometry authorGridGeometry({
  required double width,
  double maxCrossAxisExtent = 132,
  double childAspectRatio = 0.80,
  double crossAxisSpacing = 10,
  double mainAxisSpacing = 10,
  double horizontalPadding = 24,
  double minCellWidth = 72,
}) {
  final availableWidth =
      (width - horizontalPadding).clamp(0.0, double.infinity);
  final extent = maxCrossAxisExtent <= 0 ? minCellWidth : maxCrossAxisExtent;
  var columns = availableWidth <= 0
      ? 1
      : ((availableWidth + crossAxisSpacing) / (extent + crossAxisSpacing))
          .ceil();
  if (columns < 1) columns = 1;
  final rawCell = (availableWidth - crossAxisSpacing * (columns - 1)) / columns;
  final cellWidth = rawCell < minCellWidth ? minCellWidth : rawCell;
  final ratio = childAspectRatio <= 0 ? 0.80 : childAspectRatio;
  final rowExtent = cellWidth / ratio + mainAxisSpacing;
  return AuthorGridGeometry(
    columns: columns,
    cellWidth: cellWidth,
    rowExtent: rowExtent,
  );
}

/// 头像解码宽度：按显示尺寸 × 设备像素比，避免把大图整张解码进内存。
///
/// [displaySize] 是控件逻辑尺寸，[devicePixelRatio] 通常来自 MediaQuery；
/// [maxWidth] 兜底上限，避免平板上解码过大。
int avatarDecodeWidth({
  required double displaySize,
  required double devicePixelRatio,
  int maxWidth = 384,
}) {
  if (displaySize <= 0) return 0;
  final dpr = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
  final px = (displaySize * dpr).ceil();
  final cap = maxWidth <= 0 ? 1 : maxWidth;
  return px < 1 ? 1 : (px > cap ? cap : px);
}

/// 按 [metric] 降序排序，同分时按 [works] 降序，再按 [name] 升序保证稳定。
///
/// 页面只在数据/排序方式变化时调用一次，并把返回值缓存起来，
/// 避免每次 build 都重新排序（I7 卡顿根因之一）。
List<T> sortAuthorEntries<T>(
  List<T> items, {
  required num Function(T) metric,
  required num Function(T) works,
  required String Function(T) name,
}) {
  final list = List<T>.of(items);
  list.sort((a, b) {
    final c = metric(b).compareTo(metric(a));
    if (c != 0) return c;
    final w = works(b).compareTo(works(a));
    if (w != 0) return w;
    return name(a).compareTo(name(b));
  });
  return list;
}
