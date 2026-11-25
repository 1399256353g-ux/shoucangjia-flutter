import 'package:flutter/painting.dart';

/// F33：判断单行文本在给定宽度下是否会被截断。
///
/// 之前的实现按字符数（>24）猜测是否显示展开按钮，中文/英文/emoji 宽度
/// 差异很大，窄屏会漏按钮、宽屏会多按钮。这里改用 [TextPainter] 按实际
/// 字体与文本缩放测量，只有真正截断时才显示展开入口。
bool willOverflowText(
  String text,
  TextStyle style,
  double maxWidth, {
  int maxLines = 1,
  TextScaler textScaler = TextScaler.noScaling,
  Locale? locale,
}) {
  // 可用宽度必须先过有限性：`TextPainter.layout(maxWidth:)` 对 **NaN** 直接
  // 断言失败（`!maxWidth.isNaN`），对**负数**断言失败（`dart:ui/math`）。
  // 调用方算的是 `c.maxWidth - expandWidth`——`LayoutBuilder` 在无界约束下
  // 给 infinity（减完仍是 infinity，可接受），而容器窄于展开按钮宽度时
  // 直接给出**负数**；这两条都发生在 build 里，断言失败 = 整页灰屏。
  //
  // 宽度不可用时唯一安全的答案是「不显示展开按钮」：没有可靠可用宽度就
  // 无法证明文本被截断，宁可不给入口，也不要为了显示入口而崩掉信息区。
  if (text.isEmpty || !maxWidth.isFinite || maxWidth <= 0) return false;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: maxLines,
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
    locale: locale,
  )..layout(maxWidth: maxWidth);
  final exceeded = painter.didExceedMaxLines;
  painter.dispose();
  return exceeded;
}
