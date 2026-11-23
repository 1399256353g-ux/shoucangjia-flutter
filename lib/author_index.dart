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

import 'package:pinyin/pinyin.dart';

/// 名称 → 索引字母（`A`–`Z` 或 `#`）。
String authorIndexLetter(String name) {
  final s = name.trim().replaceFirst(RegExp(r'^@+'), '');
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
  final q = query.trim().toLowerCase().replaceFirst(RegExp(r'^@+'), '');
  if (q.isEmpty) return true;
  final n = name.trim().toLowerCase().replaceFirst(RegExp(r'^@+'), '');
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

/// 滑动字母条命中测试：按手指纵向位移落在第几个字母上。
///
/// 字母条是等高的竖排（每格 [itemExtent]），所以命中只和 dy 有关：
/// `floor(dy / itemExtent)`，上下边缘夹在 [0, count-1]。越界返回 -1
/// 只在 count<=0 或 itemExtent<=0 时出现（调用方此时不应显示索引条）。
int authorLetterHitIndex({
  required double dy,
  required double itemExtent,
  required int count,
}) {
  if (count <= 0 || itemExtent <= 0) return -1;
  final i = (dy < 0 ? 0.0 : dy / itemExtent).floor();
  if (i < 0) return 0;
  if (i > count - 1) return count - 1;
  return i;
}

/// 作者网格中第 [index] 项对应的滚动偏移。
///
/// 与 `SliverGridDelegateWithMaxCrossAxisExtent` 的算法一致：
/// 列数 = ceil((可用宽 + 间距) / (最大列宽 + 间距))，
/// 列宽 = (可用宽 - 间距 × (列数-1)) / 列数，行高 = 列宽 / 宽高比。
/// 结果夹在 [0, maxScrollExtent]，避免索引条把列表拖到超界再回弹。
double authorGridOffsetForIndex({
  required int index,
  required double viewportWidth,
  required double maxScrollExtent,
  double padding = 12,
  double maxCrossAxisExtent = 180,
  double spacing = 10,
  double aspectRatio = 0.86,
}) {
  if (index <= 0) return 0;
  final pad = padding < 0 ? 0.0 : padding;
  final avail = viewportWidth - pad * 2;
  if (avail <= 0 || maxCrossAxisExtent <= 0 || aspectRatio <= 0) return 0;
  final gap = spacing < 0 ? 0.0 : spacing;
  var columns = ((avail + gap) / (maxCrossAxisExtent + gap)).ceil();
  if (columns < 1) columns = 1;
  final childWidth = (avail - gap * (columns - 1)) / columns;
  if (childWidth <= 0) return 0;
  final childHeight = childWidth / aspectRatio;
  final row = index ~/ columns;
  final offset = pad + row * (childHeight + gap);
  if (maxScrollExtent > 0 && offset > maxScrollExtent) {
    return maxScrollExtent;
  }
  return offset < 0 ? 0 : offset;
}
