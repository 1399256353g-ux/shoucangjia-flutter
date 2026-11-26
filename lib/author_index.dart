/// 作者列表的首字母索引（owner 2026-11-22，2026-11-23 补中文拼音）。
///
/// 规则：
///  - 名称首字符是汉字 → 取该字拼音首字母（「海安幼儿园」→ H、「曾」→ Z）；
///  - 拉丁字母 → 该字母的大写；其他（数字/符号/其它文字）→ `#`；
///  - 索引条顺序固定为 A–Z，最后是 `#`（与通讯录惯例一致）；
///  - 过滤/搜索结果变化后，索引条按结果重建（只显示存在的分组）。
///
/// 多音字按词典常用读音处理，不做上下文判断（owner 明确）。
/// 拼音映射表较大，结果按首字符缓存：排序时每个名称只算一次。
///
/// 这里只放纯逻辑，便于单测；排序与分页留给页面层。
library;

import 'package:flutter/painting.dart';
import 'package:pinyin/pinyin.dart';

import 'grid_geometry.dart';
import 'grid_spec.dart';
import 'text_fold.dart';

/// 名称 → 索引字母（`A`–`Z` 或 `#`）。
///
/// 全角字母（`ＡＢ`）先折叠再判断：中文输入法下打出的全角字母是**同一个
/// 字母**，此前 `codeUnitAt` 拿到 0xFF21 落不进 A–Z，整个作者被归到 `#`
/// ——在 A 组里永远找不到。折叠只用于分类，返回值恒为半角。
///
/// 折叠**必须先于**剥 `@`：全角 `＠张三` 在折叠前不匹配 `^@+`，剥不掉前缀，
/// 首字符就成了 `＠`（0xFF20），既不是字母也不是汉字 → 归 `#`。同一份目录里
/// `@张三` 在 Z 组、`＠张三` 在 `#` 组，看起来像「作者漏了」。
String stripAuthorAt(String s) {
  var t = foldFullWidthAscii(s.trim());
  while (t.startsWith('@')) {
    t = t.substring(1).trim();
  }
  return t;
}

/// 比较键：折叠全角 + 小写（**不改原串**，只用于「是不是同一个名字」）。
String authorMatchKey(String s) => stripAuthorAt(s).toLowerCase();

String authorIndexLetter(String name) {
  final s = stripAuthorAt(name);
  if (s.isEmpty) return '#';
  final c = s[0];
  final u = c.toUpperCase();
  final code = u.codeUnitAt(0);
  if (code >= 65 && code <= 90) return u;
  if (isHanChar(c)) {
    final letter = _hanLetter(c);
    if (letter != null) return letter;
  }
  return '#';
}

/// 是否汉字（基本区 + 扩展 A + 兼容区）。
///
/// 只用于「要不要查拼音」，不做任何内容判断。
bool isHanChar(String ch) {
  if (ch.isEmpty) return false;
  final code = ch.runes.first;
  return (code >= 0x4E00 && code <= 0x9FFF) || // 基本区
      (code >= 0x3400 && code <= 0x4DBF) || // 扩展 A
      (code >= 0xF900 && code <= 0xFAFF); // 兼容表意文字
}

/// 姓氏读音覆盖表（owner 2026-11-23：「多音字按常用读音」）。
///
/// 通用词典给的是最常见读音（曾→ceng、解→jie），但作者名首字通常是姓氏，
/// 索引到 C/J 会让人找不到。这里只覆盖「姓氏读音与词典读音首字母不同」的
/// 常见字，未列出的字一律走词典，避免整表维护。
const Map<String, String> kSurnameIndexOverrides = <String, String>{
  '曾': 'Z', // zēng
  '解': 'X', // xiè
  '单': 'S', // shàn
  '仇': 'Q', // qiú
  '区': 'O', // ōu
  '查': 'Z', // zhā
  '朴': 'P', // piáo
  '翟': 'Z', // zhái
  '乐': 'Y', // yuè
  '覃': 'Q', // qín
  '折': 'S', // shé
  '种': 'C', // chóng
  '秘': 'B', // bì
  '员': 'Y', // yùn
  '祭': 'Z', // zhài
  '句': 'G', // gōu
};

/// 单字 → 拼音首字母；无法转换返回 null。
final Map<String, String?> _hanLetterCache = <String, String?>{};

String? _hanLetter(String ch) {
  final override = kSurnameIndexOverrides[ch];
  if (override != null) return override;
  if (_hanLetterCache.containsKey(ch)) return _hanLetterCache[ch];
  String? out;
  try {
    final py = PinyinHelper.getFirstWordPinyin(ch).trim();
    if (py.isNotEmpty) {
      final first = py[0].toUpperCase();
      final code = first.codeUnitAt(0);
      if (code >= 65 && code <= 90) out = first;
    }
  } catch (_) {
    // 词典缺字不是错误：归到 `#`，不阻断列表构建。
    out = null;
  }
  _hanLetterCache[ch] = out;
  return out;
}

/// 分组顺序：A–Z，最后 `#`。
const List<String> authorIndexOrder = <String>[
  'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
  'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '#',
];

int authorIndexRank(String letter) {
  final i = authorIndexOrder.indexOf(letter);
  return i < 0 ? authorIndexOrder.length : i;
}

/// 名称排序键：先按索引分组，再按名称码点（同一分组内稳定）。
int compareAuthorNames(String a, String b) {
  final ra = authorIndexRank(authorIndexLetter(a));
  final rb = authorIndexRank(authorIndexLetter(b));
  if (ra != rb) return ra.compareTo(rb);
  return a.compareTo(b);
}

/// 过滤：本地即时过滤（大小写不敏感，忽略首部 `@`）。
bool authorMatchesQuery(String name, String query) {
  // 双侧都做全角折叠：用全角字母/括号搜索半角名称（或反过来）应当命中。
  // 折叠在剥 `@` 之前（见 [stripAuthorAt]），否则全角 `＠` 前缀剥不掉。
  final q = authorMatchKey(query);
  if (q.isEmpty) return true;
  final n = authorMatchKey(name);
  return n.contains(q);
}

/// 当前结果里存在的索引字母（按 [authorIndexOrder] 排序）。
List<String> authorIndexLetters(Iterable<String> names) {
  final set = <String>{for (final n in names) authorIndexLetter(n)};
  final out = <String>[
    for (final l in authorIndexOrder)
      if (set.contains(l)) l,
  ];
  return out;
}

/// 每个索引字母在结果列表中的首位下标。
Map<String, int> authorGroupStarts(List<String> names) {
  final out = <String, int>{};
  for (var i = 0; i < names.length; i++) {
    final l = authorIndexLetter(names[i]);
    out.putIfAbsent(l, () => i);
  }
  return out;
}


// 这里原有一份 `authorLetterHitIndex`（按 `height / count` 均分算命中格）。
// 0.9.245 起字母条改成「固定行高 + 整体居中」，真实判定在
// `AuthorLetterBar.hitIndex`；那份均分实现**零调用**，只被测试引用。
// 两条规则同时存在时，「点某个字母定位到哪一格」就有两个答案，而测试只
// 覆盖了没人用的那个——已删除，命中规则只剩 `AuthorLetterBar.hitIndex` 一处。

/// 作者网格内边距（**唯一定义**）：左侧固定，右侧在字母索引条出现时让出
/// 28dp 条带 + 6dp 间隙。网格的实际 `padding` 与「按序号算滚动偏移」必须
/// 用同一组数，否则列数会算错——此前偏移按左右各 12 算，宽 400 时得出 3 列，
/// 而网格实际只排 2 列。
const double kAuthorGridPadLeft = 12;
const double kAuthorGridPadRight = 12;
const double kAuthorIndexBarWidth = 28;
const double kAuthorIndexBarGap = 6;

/// 是否显示右侧首字母索引条：**唯一判定**。
///
/// 只有 1 个字母时索引条没有意义（点了也不移动），所以门槛是「≥2 个不同
/// 字母」。这条判定此前在 `basic_lib_page` 里写了**四遍**：
///
/// ```
/// GridView.padding   basicAuthorGridPadding(hasIndexBar: letters.length > 1)
/// Stack 里的条带     if (letters.length > 1) Positioned(...)
/// 点字母跳转         _jumpToAuthorLetter(..., letters.length > 1)
/// 首屏头像预热       final hasIndexBar = authorIndexLetters(...).length > 1
/// ```
///
/// 四处都「各自算得出同一个答案」，所以不报错也没有第二份实现可对比；
/// 但只要有一处改了门槛（比如改成 `>= 2` 之外的判断，或某处拿未过滤的
/// 全量作者算），就会出现「条带画出来了但网格没让位」（最后一列被压住、
/// 点击被抢）或反过来「网格白让了 34dp」。现在只有一个名字。
bool authorIndexBarVisible(List<String> letters) => letters.length > 1;

/// 作者网格右侧内边距：[hasIndexBar] 时给字母条让位。
double authorGridPadRight({required bool hasIndexBar}) => hasIndexBar
    ? kAuthorIndexBarWidth + kAuthorIndexBarGap
    : kAuthorGridPadRight;

/// 作者总览页（`main` 作者 tab）网格的内边距。
///
/// 0.9.292：`GridView.padding` 与 `_prefetchAvatars` 的 `prefetchCount(padding:)`
/// 必须拿到同一组数——预热按它算「首屏几列几行」。此前这两处各写一遍
/// `fromLTRB(12, 4, 12, 16)`（外加列表页三处无关的同值），只要有人把网格
/// 上边距从 4 改成 8，预热就会算多一行、去拉屏幕外的头像。
const EdgeInsets kAuthorGridPagePadding =
    EdgeInsets.fromLTRB(kAuthorGridPadLeft, 4, kAuthorGridPadRight, 16);

/// 基础库页作者 tab 的网格内边距（上下各 12，右侧在索引条出现时让位）。
///
/// 同上：页面 `GridView.padding` 与 `_prefetchAuthorAvatars` 的预热几何同源。
EdgeInsets basicAuthorGridPadding({required bool hasIndexBar}) =>
    EdgeInsets.fromLTRB(
        kAuthorGridPadLeft, 12, authorGridPadRight(hasIndexBar: hasIndexBar), 12);

/// 作者网格中第 [index] 项对应的滚动偏移。
///
/// 列数/列宽/行高全部走 `grid_geometry.dart`（与 Flutter delegate 同一规则：
/// `ceil(可用宽 / (最大列宽 + 间距))`）。此前这里写的是
/// `ceil((可用宽 + 间距) / (最大列宽 + 间距))`——分子多算了一个间距，
/// 宽 400 时算出 3 列，网格实际只排 2 列（见 grid_geometry 文件头）。
/// 结果夹在 [0, maxScrollExtent]，避免索引条把列表拖到超界再回弹。
///
/// **左右内边距必须分别传入**：字母索引条只占右边缘，网格的右内边距因此
/// 从 12 变成 34（给索引条让位），左内边距仍是 12。此前这里只有一个 `padding`，
/// 两边都按 12 算，于是宽 400 时算出 3 列、网格实际只排 2 列——点一个字母
/// 滚到的行是错的（差一列就错一整行，而且越往下差得越多）。
/// 两边同值时传两个一样的数，不要再加第二个入口。
///
/// 0.9.287：三个几何默认值改为**引用** `grid_spec.kBasicAuthorGrid`（页面
/// delegate 与预热读同一份表）。此前它们在这里写第二遍
/// （180/10/0.86），字母条跳转与真实排布各有各的数字。
double authorGridOffsetForIndex({
  required int index,
  required double viewportWidth,
  required double maxScrollExtent,
  double paddingLeft = kAuthorGridPadLeft,
  double paddingRight = kAuthorGridPadRight,
  double? maxCrossAxisExtent,
  double? spacing,
  double? aspectRatio,
}) {
  final maxExtent = maxCrossAxisExtent ?? kBasicAuthorGrid.maxCrossAxisExtent;
  final gapArg = spacing ?? kBasicAuthorGrid.spacing;
  final aspect = aspectRatio ?? kBasicAuthorGrid.aspectRatio;
  if (index <= 0) return 0;
  final left = paddingLeft < 0 ? 0.0 : paddingLeft;
  final right = paddingRight < 0 ? 0.0 : paddingRight;
  final avail = viewportWidth - left - right;
  if (avail <= 0 || maxExtent <= 0 || aspect <= 0) return 0;
  final gap = gapArg < 0 ? 0.0 : gapArg;
  final columns = gridColumnCount(
    crossAxisExtent: avail,
    maxCrossAxisExtent: maxExtent,
    spacing: gap,
  );
  final childWidth = gridTileWidth(
    crossAxisExtent: avail,
    columns: columns,
    spacing: gap,
  );
  if (childWidth <= 0) return 0;
  final childHeight = gridTileHeight(
    tileWidth: childWidth,
    aspectRatio: aspect,
  );
  if (childHeight <= 0) return 0;
  final row = index ~/ columns;
  final offset = left + row * (childHeight + gap);
  if (maxScrollExtent > 0 && offset > maxScrollExtent) {
    return maxScrollExtent;
  }
  return offset < 0 ? 0 : offset;
}
