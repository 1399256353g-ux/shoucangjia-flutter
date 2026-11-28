/// 加载占位的唯一出口。
///
/// 此前「转圈」在 `lib/` 里出现 **41 次**，两种形态各写各的：
///
/// | 形态 | 处数 | 典型写法 |
/// |---|---|---|
/// | 整页加载 | 22 | `const Center(child: CircularProgressIndicator())` |
/// | 行内加载 | 19 | `CircularProgressIndicator(strokeWidth: 2)` |
///
/// 两种形态本身没错（整页居中 vs 行内细圈），错在**每个页面都自己写一遍**：
/// 想统一调整转圈大小、加一句「加载中…」、或换成骨架屏，要改 41 处，
/// 改漏的那一处不会报错，只会显得「这一页的转圈跟别处不一样」。
///
/// 这里只立两个名字，外观与既有实现完全一致（默认尺寸 / `strokeWidth: 2`）：
///   - [LoadingView]  整页加载，居中；
///   - [InlineSpinner] 行内/按钮内加载，细圈。
///
/// 尺寸不在这里指定：行内圈的大小一直由外层 `SizedBox` 决定，收进来会把
/// 各处的实际视觉改掉。
library;

import 'package:flutter/material.dart';

/// 行内细圈的线宽。只在这里出现一次。
const double kInlineSpinnerStroke = 2;

/// 整页加载：居中一个默认尺寸的转圈。
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

/// 行内加载：细圈，尺寸由外层约束决定。
class InlineSpinner extends StatelessWidget {
  const InlineSpinner({super.key, this.color});

  /// 少数深色背景处需要白色圈；默认取主题色。
  final Color? color;

  @override
  Widget build(BuildContext context) => CircularProgressIndicator(
        strokeWidth: kInlineSpinnerStroke,
        color: color,
      );
}
