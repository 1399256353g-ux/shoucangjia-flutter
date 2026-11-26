/// 卡片网格的**唯一规格**：列上限 / 间距 / 宽高比 / 首屏预热上限。
///
/// 为什么要有这个文件（0.9.286）：
///
/// 同一组几何数字此前在**两个地方各写一遍**——
///
/// ```
/// GridView.builder(gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
///   maxCrossAxisExtent: 260, mainAxisSpacing: 10, crossAxisSpacing: 10,
///   childAspectRatio: 1.02))                       ← 页面实际排布
///
/// firstScreenThumbCount(maxCrossAxisExtent: 260, crossSpacing: 10,
///   mainSpacing: 10, aspectRatio: 1.02)             ← 首屏热身张数
/// ```
///
/// 两边一旦不一致，预热的就是**另一批格子**：张数多算→多拉一列看不见的封面
/// （白花流量），少算→首屏仍然逐张请求（还是先露底色）。而它们「各自都算对了」，
/// 只有把两张截图里的张数对上才会发现。
///
/// 现在两处都读同一个常量：页面用 [LibGridSpec.delegate]，预热用
/// [LibGridSpec.prefetchCount]。数字只在这一张表里出现一次。
library;

import 'package:flutter/widgets.dart';

import 'thumb_prefetch.dart';

/// 一类卡片网格的**唯一规格**。
///
/// 0.9.287（第六十四批）：这张表此前只覆盖库卡片（260/220），作者网格与作品
/// 网格仍各自「页面 delegate 写一遍数字、预热再写一遍」——正是本文件存在的
/// 理由。现在四类网格（库卡片 / 作者卡片 / 作品 / 基础库作品）都进表，
/// 页面 delegate 与首屏预热都读同一份字段。
class LibGridSpec {
  /// 与 `SliverGridDelegateWithMaxCrossAxisExtent.maxCrossAxisExtent` 同义。
  final double maxCrossAxisExtent;

  /// 主轴/交叉轴间距（页面上两者同值）。
  final double spacing;

  /// 与 delegate 的 `childAspectRatio` 同义：卡片宽 / 高。
  /// 给了 [mainAxisExtent] 时被 delegate 忽略（高度固定）。
  final double aspectRatio;

  /// 与 delegate 的 `mainAxisExtent` 同义：固定行高（作者卡片是固定 170）。
  final double? mainAxisExtent;

  /// 首屏预热的张数上限（默认值；调用方可按页面覆盖）。
  final int maxPrefetch;

  /// 预热几屏（默认 1 屏；作品/作者网格历来是 2 屏）。
  ///
  /// 此前这个数只存在于各调用点传给 `firstScreenThumbCount` 的默认值里
  /// （库卡片 1 屏、另两类 2 屏），同一个网格的页面各拿自己的泵。
  final int prefetchScreens;

  const LibGridSpec({
    required this.maxCrossAxisExtent,
    required this.spacing,
    required this.aspectRatio,
    required this.maxPrefetch,
    this.mainAxisExtent,
    this.prefetchScreens = 1,
  });

  /// 页面上真实使用的 delegate（参数与 [prefetchCount] 同源）。
  SliverGridDelegateWithMaxCrossAxisExtent get delegate =>
      SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxCrossAxisExtent,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        childAspectRatio: aspectRatio,
        mainAxisExtent: mainAxisExtent,
      );

  /// 首屏需要预热的张数。
  ///
  /// [padding] 是页面网格自己的 `GridView.padding`：左右与上下各自归一半，
  /// 与 delegate 拿到的交叉轴/主轴约束一致。此前调用方传的是
  /// `padding: kLibGridPadding.left`（一个数同时当左右与上下），上下内边距
  /// 于是在没有纵向留白的页面上也被算进可用高度，预热行数偏少。
  int prefetchCount(
    Size viewport, {
    required EdgeInsets padding,
    int? maxItems,
    int? screens,
  }) =>
      firstScreenThumbCount(
        viewportWidth: viewport.width,
        viewportHeight: viewport.height,
        maxCrossAxisExtent: maxCrossAxisExtent,
        paddingX: padding.horizontal / 2,
        paddingY: padding.vertical / 2,
        crossSpacing: spacing,
        mainSpacing: spacing,
        aspectRatio: aspectRatio,
        mainAxisExtent: mainAxisExtent,
        screens: screens ?? prefetchScreens,
        maxItems: maxItems ?? maxPrefetch,
      );
}

/// 单元库卡片（`UnitLibraryCard`）：`maxCrossAxisExtent: 260` / 间距 10 / 1.02。
const LibGridSpec kUnitLibGrid = LibGridSpec(
  maxCrossAxisExtent: 260,
  spacing: 10,
  aspectRatio: 1.02,
  maxPrefetch: 8,
);

/// 基础库卡片（`BasicLibCard`）：`maxCrossAxisExtent: 220` / 间距 10 / 0.92。
const LibGridSpec kBasicLibGrid = LibGridSpec(
  maxCrossAxisExtent: 220,
  spacing: 10,
  aspectRatio: 0.92,
  maxPrefetch: 8,
);

/// 作者卡片固定行高（逻辑像素）。
///
/// `AuthorGridCard.extent` 转发它、`kAuthorGrid.mainAxisExtent` 读它：此前
/// 「170」这个数字在卡片类与页面 delegate 各写一遍，预热里再写第三遍。
const double kAuthorCardExtent = 170;

/// 作者卡片（`AuthorGridCard`）：`maxCrossAxisExtent: 150` / 间距 10 /
/// 固定行高 [kAuthorCardExtent]（高度与宽度无关）。
///
/// 页面 delegate 与 `_prefetchAvatars` 此前各写一遍这三个数字：数字对齐时
/// 「巧合正确」，任一处改动都会让预热算出屏幕外的另一行。
const LibGridSpec kAuthorGrid = LibGridSpec(
  maxCrossAxisExtent: 150,
  spacing: 10,
  aspectRatio: 1,
  maxPrefetch: 24,
  mainAxisExtent: kAuthorCardExtent,
  prefetchScreens: 2,
);

/// 基础库页作者网格（`basic_lib_page` 的作者 tab）：180 / 间距 10 / 0.86。
///
/// 它与作者总览的 `kAuthorGrid` 是**两个不同的网格**（卡片比例 vs 固定行高），
/// 但 `author_index.authorGridOffsetForIndex` 的默认参数此前也把这组数字写了
/// 一份——字母条跳转与真实排布因此有第二个来源。
const LibGridSpec kBasicAuthorGrid = LibGridSpec(
  maxCrossAxisExtent: 180,
  spacing: 10,
  aspectRatio: 0.86,
  maxPrefetch: 24,
);

/// 作品网格（作者主页 / 收藏夹 / 搜索 / 推荐 / 骨架屏）：180 / 间距 2 / 3:4。
///
/// 三个地方在用它：`WorkGrid._buildGrid`、`WorkGridSkeleton`、
/// `recommendVisibleCount` 的默认几何。
const LibGridSpec kWorkGrid = LibGridSpec(
  maxCrossAxisExtent: 180,
  spacing: 2,
  aspectRatio: 3 / 4,
  maxPrefetch: 24,
  prefetchScreens: 2,
);

/// 基础库页作品网格：150 / 间距 8 / 0.72（页面 `EdgeInsets.all(10)`）。
const LibGridSpec kBasicWorkGrid = LibGridSpec(
  maxCrossAxisExtent: 150,
  spacing: 8,
  aspectRatio: 0.72,
  maxPrefetch: 24,
  prefetchScreens: 2,
);
