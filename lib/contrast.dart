/// 颜色对比：给定底色 ARGB，返回其上文字/图案应使用的颜色。
///
/// 单一来源（owner 2026-11-24 第九批）：此前 `LibraryBadge.textColorOn` 与
/// `library_corner_badge.dart` 的私有 `_pickForeground` 各写了一份完全相同的
/// 亮度公式。角标与词条必须同色才不割裂，所以判定只能有一处。
///
/// 权重取 ITU-R BT.601 亮度（0.299/0.587/0.114）；阈值 0.62 是既有观感，
/// 改动它会同时改变词条与角标的可读性，不要单独调。
int foregroundArgbOn(int argb) {
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  final lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
  return lum > 0.62 ? 0xFF111827 : 0xFFFFFFFF;
}
