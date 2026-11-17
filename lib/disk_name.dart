import 'package:flutter/foundation.dart' show debugPrint;

/// 基础库/节点显示名以磁盘真实目录名为准（`rel` 最后一段）。
///
/// 服务端 `name` 只作为兜底（`rel` 为空时）；两者不一致时采用 `rel` 末段，
/// 并在本机打印一条 warn（只写 debug 日志，不联网、不上报）。
String diskNameOf(String rel, String rawName, {String where = ''}) {
  final segs = rel
      .replaceAll('\\', '/')
      .split('/')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  final last = segs.isEmpty ? '' : segs.last;
  final name = rawName.trim();
  if (last.isEmpty) return name;
  if (name.isNotEmpty && name != last && where.isNotEmpty) {
    debugPrint('[name-mismatch] $where: name="$name" rel="$rel" -> "$last"');
  }
  return last;
}
