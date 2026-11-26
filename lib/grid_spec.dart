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

/// 一类库卡片的网格规格。
class LibGridSpec {
  /// 与 `SliverGridDelegateWithMaxCrossAxisExtent.maxCrossAxisExtent` 同义。
  final double maxCrossAxisExtent;

  /// 主轴/交叉轴间距（页面上两者同值）。
  final double spacing;

  /// 与 delegate 的 `childAspectRatio` 同义：卡片宽 / 高。
  final double aspectRatio;

  /// 首屏预热的张数上限（默认值；调用方可按页面覆盖）。
  final int maxPrefetch;

  const LibGridSpec({
    required this.maxCrossAxisExtent,
    required this.spacing,
    required this.aspectRatio,
    required this.maxPrefetch,
  });

  /// 页面上真实使用的 delegate（参数与 [prefetchCount] 同源）。
  SliverGridDelegateWithMaxCrossAxisExtent get delegate =>
      SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxCrossAxisExtent,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        childAspectRatio: aspectRatio,
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
    int screens = 1,
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
        screens: screens,
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
