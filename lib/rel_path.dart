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

/// 归一化相对路径：`\` 与 `/` 等价、压掉空段与 `.`、统一用 `/` 连接。
///
/// **唯一实现**。此前这条规则在四个地方各写了一遍：
///  - `folder_structure_page._normalizeRel`（`replaceAll('\\','/').split('/')…`）；
///  - `collection_sync._unitKeys` 与 `syncCollectionsForUnit`（同一段代码抄两遍）；
///  - `top_node.nameFromRoot`（同样的链，但**不过滤 `.`**）；
///  - `author_mount_sheet` 的 `unit.split('/').last`（连 `\` 都不认）。
///
/// 四份写法一旦分叉，同一条服务端路径在不同页面就是不同的 key：
/// 实测 `nameFromRoot('/vol1/SECRET/.')` 返回 **`.`**（顶级节点名字变成「.」）、
/// `SyncRun(unit: 'A\\B').unitLabel` 返回 **`A\B`**（同步日志里整个路径挤在一行，
/// 而不是最后一段）、`unit.split('/').last` 对这种 rel 直接返回原串。
String normalizeRelPath(String rel) => relJoin(relSegments(rel));

/// 相对路径的最后一段（没有则空串）。
///
/// 与 [normalizeRelPath] 同一条拆分规则：`A\B/C` → `C`。用于「只显示最后一层」
/// 的所有位置（同步日志的单元库列、作者挂载面板的分组标题）。
String lastRelName(String rel) {
  final segs = relSegments(rel);
  return segs.isEmpty ? '' : segs.last;
}

/// [path] 是否在 [base] 之下；是则返回相对 [base] 的路径（`/` 连接），否则空串。
///
/// 判等与判前缀都跑在**归一化后的段列表**上，所以 `E:\media` / `E:/media/` /
/// `E:/media//` 是同一个根；`E:\media\A` 与 `/vol1/m/A` 也不会因为分隔符不同
/// 被判成「不在根下」。
///
/// 旧实现（`source_lib.relUnderBase`）手写「掐尾部斜杠 + `startsWith('$b/')`」，
/// 只认 `/`：实测 `relUnderBase('/vol1/m', r'/vol1/m\A')` 返回 **空串**——
/// Windows 路径的服务端下发一条基础库，客户端算不出 rel 就直接 `continue`，
/// 那个基础库**整条从首页消失**（不报错、不提示，看起来像「服务端没这个库」）。
/// `'/vol1/m/./A'` 返回 `'./A'`、`'/vol1/m//A'` 返回 `'/A'` 同理：rel 带着
/// 点段/前导斜杠去匹配媒体路径，永远匹配不上。
String relUnder(String base, String path) {
  final b = relSegments(base);
  final p = relSegments(path);
  if (b.isEmpty || p.length <= b.length) return '';
  for (var i = 0; i < b.length; i++) {
    if (b[i] != p[i]) return '';
  }
  return relJoin(p.sublist(b.length));
}
