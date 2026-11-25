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

import 'text_fold.dart';

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
///
/// 匹配跑在**全角折叠后的副本**上（[foldFullWidthAscii] 严格一对一、长度不变），
/// 切片仍旧切原串：中文输入法打出的 `（１）名称` 与半角目录名是同一个编号前缀，
/// 但 `\d` 不认全角数字，此前它会被原样显示成「（１）名称」。
String stripIndexPrefix(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return s;
  // 折叠串只用于定位前缀结束位置；`s` 本身一个字符都不改写。
  String stripOne(RegExp re) {
    final m = re.firstMatch(foldFullWidthAscii(s));
    if (m == null) return s;
    final out = s.substring(m.end).trim();
    return (out.isEmpty || out == s) ? s : out;
  }

  while (true) {
    final out = stripOne(_bracketPrefix);
    if (out == s) break;
    s = out;
  }
  for (final re in [_dotPrefix, _dunPrefix]) {
    s = stripOne(re);
  }
  return s;
}

/// 名称归一：折叠全角、剥 `@`、剥序号前缀，三者**交错**剥到稳定。
///
/// 顺序不能写死。「先剥 `@` 再剥序号」漏掉 `@(1)名字`（序号在 `@` 后面），
/// 「先剥序号」漏掉 `＠（１）名字`（`＠` 挡在序号前面）——两种真实目录名都有。
/// 只有反复剥到不再变化才是完备的，且循环有上限，坏输入不会造成死循环。
String bareNameOf(String raw) {
  var s = foldFullWidthAscii(raw.trim());
  for (var i = 0; i < 8; i++) {
    var t = s;
    while (t.startsWith('@')) {
      t = t.substring(1).trim();
    }
    t = stripIndexPrefix(t).trim();
    if (t == s) break;
    s = t;
  }
  return s;
}
