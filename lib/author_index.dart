/// 作者列表的首字母索引（owner 2026-11-22）。
///
/// 规则：
///  - 名称首字符是拉丁字母 → 该字母的大写；其他（中文/数字/符号）→ `#`；
///  - 索引条顺序固定为 A–Z，最后是 `#`（与通讯录惯例一致）；
///  - 过滤/搜索结果变化后，索引条按结果重建（只显示存在的分组）。
///
/// 这里只放纯逻辑，便于单测；排序与分页留给页面层。
library;

/// 名称 → 索引字母（`A`–`Z` 或 `#`）。
String authorIndexLetter(String name) {
  final s = name.trim().replaceFirst(RegExp(r'^@+'), '');
  if (s.isEmpty) return '#';
  final c = s[0];
  final u = c.toUpperCase();
  final code = u.codeUnitAt(0);
  if (code >= 65 && code <= 90) return u;
  return '#';
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
