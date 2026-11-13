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
  if (text.isEmpty || maxWidth <= 0) return false;
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
