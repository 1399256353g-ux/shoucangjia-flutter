/// 全角 ASCII 折叠（**唯一实现**）。
///
/// 中文输入法下，冒号、数字、字母、括号常常是**全角**的：`nas：8090`、
/// `１９２.１６８.２.４:8090`、`（１）名称`、`ＡＢ`。它们看起来就是那个符号，
/// 但所有按 ASCII 写的规则都不认——于是「用户输对了、程序说不行」。
///
/// 实测（本轮）三处真实后果：
///
/// | 输入 | 折叠前 | 后果 |
/// |---|---|---|
/// | `http://nas：8090` | host = `nas%EF%BC%9A8090` | 语法合法、永远连不上，界面只说「连接失败」 |
/// | `http://nas:８０９０` | `normalizeBase` 返回空串 | 直接判「地址不能为空」，用户看不出哪里错 |
/// | `（１）名称` | `stripIndexPrefix` 不剥前缀 | 词条上带着「（１）」，与半角目录不一致 |
/// | `ＡＢ` | `authorIndexLetter` 归到 `#` | 全角字母作者掉进符号分组，A 组里找不到 |
///
/// 折叠只做两件事，且**严格一对一**（一个码点换一个码点，长度不变）：
///  - U+FF01–U+FF5E → 减 0xFEE0 得到对应 ASCII；
///  - U+3000（全角空格）→ 半角空格。
///
/// 长度不变这一点是刻意的：调用方（如 `stripIndexPrefix`）会先用折叠后的
/// 副本做正则匹配，再按匹配到的**下标**去原串上切片——索引必须对得上。
///
/// 不折叠其它全角标点（U+3001「、」、U+3002「。」、U+FF5F/U+FF60 等）：
/// 它们没有 ASCII 对应物，硬折只会把名称改坏。也不碰路径段——文件名的
/// 全角字符是内容本身，不能替用户改写。
library;

/// 全角 ASCII / 全角空格 → 半角；其余字符原样保留（长度不变）。
String foldFullWidthAscii(String s) {
  if (s.isEmpty) return s;
  StringBuffer? out;
  for (var i = 0; i < s.length; i++) {
    final u = s.codeUnitAt(i);
    int? r;
    if (u >= 0xFF01 && u <= 0xFF5E) {
      r = u - 0xFEE0;
    } else if (u == 0x3000) {
      r = 0x20;
    }
    if (r == null) {
      out?.writeCharCode(u);
      continue;
    }
    // 只有真的遇到全角字符时才复制前缀：纯 ASCII 输入不产生任何分配。
    out ??= StringBuffer(s.substring(0, i));
    out.writeCharCode(r);
  }
  return out?.toString() ?? s;
}

/// 「人眼看着一样就该命中」的比较键：全角折叠 + 小写。
///
/// 存在的意义是**避免每个搜索入口各写一遍**。此前作者筛选做了折叠、
/// 分类树筛选和搜索页没做，于是同一个名字在三个输入框里表现不同：
/// 搜「ＡＢ」在作者列表能命中、在分类树里不能。
///
/// 只用于比较，绝不用于落盘或回写名称（名称是内容，不能被改写）。
String foldForMatch(String s) => foldFullWidthAscii(s).toLowerCase();

/// 去掉名称前的作者目录前缀 `@`（可能不止一个）并 trim 首尾空白。
///
/// 0.9.350：这个「while 剥 `@`」的小循环此前在四个文件里各写一遍
/// （`author_index.stripAuthorAt`、`index_prefix.bareNameOf`、
/// `work_author._bareAuthor`、`main.dart` 的作者页标签），四份都是
/// `trim → while startsWith('@') substring(1).trim()`。它们必须完全一致：
/// 全角 `＠` 折叠后也会落到这里，任何一份少剥一层，同一个作者在
/// 「索引字母 / 显示名 / 索引查询」三处就是三个不同的键——A 组里找不到人，
/// 作者页点进去空白，而两边都返回了一个「看着对」的字符串。
///
/// 只剥前缀，不做其它归一（序号前缀由 `index_prefix` 负责、全角折叠由
/// [foldFullWidthAscii] 负责）；调用方按自己的顺序组合它们。
String stripAtPrefixes(String s) {
  var t = s.trim();
  while (t.startsWith('@')) {
    t = t.substring(1).trim();
  }
  return t;
}
