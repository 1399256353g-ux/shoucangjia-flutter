/// 库卡片右上角操作按钮（封面 / 爬虫配置等）的**统一规格**。
///
/// 为什么要有这个文件（0.9.303 · 第七十五批）：
///
/// 「图标 18 + 点击框 30 + `VisualDensity.compact` + `padding: zero`」这四项
/// 在 `unit_library_view` 里写了**四遍**：
///
/// ```
/// UnitLibraryCard  封面设置   IconButton(iconSize: 18, tightFor(30,30))
/// UnitLibraryCard  本地选图   同上
/// UnitLibraryCard  爬虫配置   同上
/// BasicLibCard     封面设置   同上
/// ```
///
/// 四处「看起来一样」纯属巧合：没有第二个实现可供对比，也没有任何断言会
/// 在它们分叉时失败。改一处漏三处的结果不是报错，而是同一排按钮里有一个
/// 更小/更大——点击热区跟着变，用户点了没反应却看不出为什么。
///
/// 这里只收「一个卡片操作按钮长什么样」；图标、提示、回调由调用方给。
/// `Positioned(top/right)` 的 6dp 内缩同理收在 [kCardActionInset]。
library;

import 'package:flutter/material.dart'
    show
        BoxConstraints,
        EdgeInsets,
        Icon,
        IconButton,
        IconData,
        Key,
        VisualDensity,
        VoidCallback,
        Widget;

/// 操作区距卡片上/右边缘的内缩（`Positioned(top/right)`）。
///
/// 与左上角角标的 [kCornerBadgeInset] 不是同一个数：那一个是角标方块到
/// 边缘的距离，这一个是按钮点击框到边缘的距离，两者独立可调，所以不合并。
const double kCardActionInset = 6;

/// 按钮图标边长。
const double kCardActionIconSize = 18;

/// 按钮的**点击框**边长。
///
/// 图标 18 只是画出来的尺寸；真正决定「按不按得到」的是这 30dp 的方框，
/// 它同时决定这一排按钮占多宽（长标题会不会把按钮挤到卡片外）。
const double kCardActionHitSize = 30;

/// 库卡片右上角的一个操作按钮。
///
/// 需要换图标 / 提示 / 回调时只传这三个参数，**规格不参与讨论**。
Widget cardActionButton({
  required Key buttonKey,
  required String tooltip,
  required IconData icon,
  required VoidCallback? onPressed,
}) =>
    IconButton(
      key: buttonKey,
      tooltip: tooltip,
      iconSize: kCardActionIconSize,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
          width: kCardActionHitSize, height: kCardActionHitSize),
      icon: Icon(icon),
      onPressed: onPressed,
    );
