/// 「这块内容在**当前可见区域**里有多大」（纯几何，无状态、无计时器）。
///
/// 背景（0.9.314 第八十批）：首页的媒体库网格是整页 `ListView` 里的一块
/// `shrinkWrap` 网格。它的 `LayoutBuilder` 拿到的高度是 **infinity**（滚动
/// 方向不受约束），而 `prefetchCount` 对非有限高度只能按「一行」收手——
/// 「按窗口算」会多预热一行屏幕外的封面，「按布局算」又会少预热一整屏。
/// 两个数都算得出来，所以哪一种都不会报错。
///
/// 真正要回答的问题是：**从这块内容自己的左上角往下，还有多少像素在屏幕
/// 里**。这个数只能从渲染树读：外层 `Scrollable` 的视口高度，减去本块在
/// 视口坐标系里的纵向偏移，再用本块自身高度收顶。
///
/// 布局阶段不写状态、不 `setState`：调用方在帧后回调里读一次即可（与
/// `_gridViewport` 系列同一条规矩）。
library;

import 'package:flutter/widgets.dart';

/// 返回 [key] 所指渲染对象的「可见尺寸」；读不到几何时返回 null。
///
/// - 宽：该对象自身的宽度；
/// - 高：`min(自身高度, 视口高度 − 该对象在视口内的纵向偏移)`，小于 0 收成 0。
///
/// 不在任何 `Scrollable` 里时按「自身尺寸」返回——那种情况下它就是整块
/// 可见区域，没有可扣的部分。
Size? visibleViewportOf(GlobalKey key) {
  final ctx = key.currentContext;
  if (ctx == null) return null;
  final box = ctx.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  final w = box.size.width;
  final h = box.size.height;
  if (!w.isFinite || !h.isFinite) return null;

  final scrollable = Scrollable.maybeOf(ctx);
  final viewportCtx = scrollable?.context;
  final viewportBox = viewportCtx?.findRenderObject();
  if (scrollable == null || viewportBox is! RenderBox || !viewportBox.hasSize) {
    return Size(w, h);
  }
  // 该对象左上角在视口坐标系里的纵向位置（滚到上面时会是负数）。
  final dy = viewportBox.globalToLocal(box.localToGlobal(Offset.zero)).dy;
  final visible = scrollable.position.viewportDimension - dy;
  if (!visible.isFinite) return Size(w, h);
  return Size(w, visible <= 0 ? 0 : (visible < h ? visible : h));
}
