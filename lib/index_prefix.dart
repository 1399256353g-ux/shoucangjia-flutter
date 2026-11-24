/// 名称序号前缀的唯一实现（第十四批，owner 2026-11-24）。
///
/// 目录名里的 `(1) ` / `（02）` / `[3] ` / `01. ` 只是磁盘排序用的编号，
/// 显示与匹配都不该带上它。此前这件事被写了三份、规则还各不相同：
///
/// | 位置 | 支持的写法 | 用途 |
/// |---|---|---|
/// | `LibraryBadge.stripIndex` | `(1)` `（1）` `[1]` `【1】` `01.` `01、` | 词条显示 |
/// | `collection_sync.syncUnitKey` | 去 `@` + 同上 | 同步源匹配 |
/// | `source_lib.normalizeLibLabel` | **只有 `(1)` 半角圆括号** | 基础库匹配 |
///
/// 第三份的缺口是真实故障面：同一个单元库在不同页面上「算不算同一个名字」
/// 取决于调用的是哪个函数——`[3] 名称` 在词条上已经去掉序号，在同步源匹配里
/// 却还带着，于是「有同步记录但匹配不上」。
///
/// 现在只在这里判断一次；三处调用点都转调本文件。
library;

final RegExp _bracketPrefix =
    RegExp(r'^[(（\[【]\s*\d{1,4}\s*[)）\]】]\s*[._\-·]?\s*');

/// 点号式前缀：`01. 名称`——点号后必须有空白。
///
/// 这个空白不是吹毛求疵：`2026.11.24 相册` 里的 `2026.` 与序号形状相同，
/// 宽松写法（`\d{1,4}\s*[.]`）会把它剥成 `11.24 相册`——日期被拆碎。
final RegExp _dotPrefix = RegExp(r'^\d{1,4}\.\s+');

/// 顿号式前缀：`01、名称` / `02 、名称`。顿号只作索引分隔，可无空白。
final RegExp _dunPrefix = RegExp(r'^\d{1,4}\s*、\s*');

/// 去掉名称前的序号前缀；没有前缀时原样返回（只去掉首尾空白）。
///
/// * 括号式前缀可以叠加（`(1)(2) 名称` → `名称`）；
/// * 点号/顿号式只剥一层：`2026.11.24 相册` 不能被拆成日期碎片；
/// * 剥完为空（名字只有一个序号）时返回原串，避免词条变成空白。
String stripIndexPrefix(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return s;
  while (true) {
    final out = s.replaceFirst(_bracketPrefix, '').trim();
    if (out == s || out.isEmpty) break;
    s = out;
  }
  for (final re in [_dotPrefix, _dunPrefix]) {
    final out = s.replaceFirst(re, '').trim();
    if (out != s && out.isNotEmpty) s = out;
  }
  return s;
}

/// 上述规则的反向判断：这个名字是否带了序号前缀。
bool hasIndexPrefix(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return false;
  return _bracketPrefix.hasMatch(s) ||
      _dotPrefix.hasMatch(s) ||
      _dunPrefix.hasMatch(s);
}
