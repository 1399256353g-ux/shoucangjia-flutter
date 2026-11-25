/// 字符串按 UTF-16 单元截断（**唯一实现**）。
///
/// 同一件事此前在 5 处各写一遍 `s.substring(0, N)`：基础库词条标签（10）、
/// 保存到本机的文件名（80）、爬虫备注（200）、错误文案（600）、
/// 崩溃日志摘要（600）。每一处都按 **code unit** 切片，而 emoji 与增补平面
/// 汉字（如 𠀀）在 Dart 里占两个单元：
///
///  - `'🎬🎬🎬🎬🎬'.substring(0, 5)` 切在第二个 emoji 的高位代理上 →
///    得到一个孤立 `\uD83C`，画出来是替换方块（`⌷`）；
///  - 同一个孤立代理写进文件名 → 文件系统里是一个不能正常显示的名字。
///
/// 词条那条最明显：`lib/unit_library_view.dart` 先取 10 个单元再加 `…`，
/// 而标签本身还带库 emoji 后缀（`labelWithEmoji`），切点正好落在 emoji 上时
/// 卡片上就是一个方块。`emoji_text.dart` 已经把「孤立代理」当成非法输入来
/// 清洗，所以这里不能生产它。
///
/// 规则只有一条：**截断点落在代理对中间时，把那个高位代理一起丢掉**。
/// 结果长度可能比上限少 1，这是正确的取舍——少一个字符好过显示一个坏字符。
library;

/// 把 [s] 截到最多 [maxUnits] 个 UTF-16 单元，绝不切开代理对。
///
/// [maxUnits] <= 0 返回空串；字符串本身不超长时原样返回（不复制）。
String clipToUnits(String s, int maxUnits) {
  if (maxUnits <= 0) return '';
  if (s.length <= maxUnits) return s;
  var end = maxUnits;
  final last = s.codeUnitAt(end - 1);
  // 0xD800–0xDBFF 是高位代理：它的低位代理在 end 位置，已被切掉。
  if (last >= 0xD800 && last <= 0xDBFF) end -= 1;
  return s.substring(0, end);
}

/// 截断并加省略号（`…`）。未超长时原样返回，不加省略号。
String clipWithEllipsis(String s, int maxUnits, {String ellipsis = '…'}) {
  if (maxUnits <= 0) return '';
  if (s.length <= maxUnits) return s;
  return '${clipToUnits(s, maxUnits)}$ellipsis';
}
