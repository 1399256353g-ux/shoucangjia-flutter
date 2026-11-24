import 'package:flutter/foundation.dart' show debugPrint;

import 'rel_path.dart';

/// 基础库/节点显示名以磁盘真实目录名为准（`rel` 最后一段）。
///
/// 服务端 `name` 只作为兜底（`rel` 为空时）；两者不一致时采用 `rel` 末段，
/// 并在本机打印一条 warn（只写 debug 日志，不联网、不上报）。
///
/// 拆分走 `rel_path.dart` 的唯一实现：此前这里手写了
/// `replaceAll('\\','/').split('/')` 链，与 `splitRel/splitCatRel` 是第三份
/// 同样规则的拷贝，三份必须同时改才不会分叉。
String diskNameOf(String rel, String rawName, {String where = ''}) {
  final segs = relSegments(rel);
  final last = segs.isEmpty ? '' : segs.last;
  final name = rawName.trim();
  if (last.isEmpty) return name;
  if (name.isNotEmpty && name != last && where.isNotEmpty) {
    debugPrint('[name-mismatch] $where: name="$name" rel="$rel" -> "$last"');
  }
  return last;
}
