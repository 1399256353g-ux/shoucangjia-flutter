/// 库内相对路径的统一拆分/拼接。
///
/// 单一来源（owner 2026-11-24 第九批）：此前同一套「统一分隔符、去空段、去 `.`」
/// 的规则在三个地方各写了一遍——`category_tree.dart` 的 `splitCatRel`、
/// `unit_library.dart` 的 `splitRel`、以及 `disk_name.dart` 里手写的
/// `replaceAll('\\','/').split('/')` 链。三份实现必须同时改才不会分叉，
/// 一旦分叉，「同名目录判定」与「库归属判定」就会对不上。
///
/// 这里只做纯字符串处理：不碰磁盘、不认绝对路径、不解析 `..`
/// （`..` 原样保留，由调用方的校验层拒绝）。
library;

/// 拆分相对路径：`\` 与 `/` 等价，去空段与当前目录 `.`。
///
/// `..` 保留——它需要被校验层看见并拒绝，而不是在这里被静默吃掉。
List<String> relSegments(String rel) {
  final out = <String>[];
  for (final raw in rel.split(RegExp(r'[\\/]+'))) {
    final s = raw.trim();
    if (s.isEmpty || s == '.') continue;
    out.add(s);
  }
  return out;
}

/// 用 `/` 重新拼接（与 [relSegments] 互为逆运算，用于路径归一化）。
String relJoin(Iterable<String> segs) => segs.join('/');
