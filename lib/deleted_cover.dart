/// 已删除作品列表的预览图选择（H3）。
///
/// 已删除作品的本地媒体通常已被清理，服务端下发的记录里也就没有
/// `th`/`cv`；此时退回作者头像，保证列表里仍有一张可辨认的预览图。
/// 返回空串表示没有任何可用图片，由调用方显示占位图标。
String deletedCoverPath(Map work, Map<String, dynamic> authorsIndex) {
  for (final k in const ['th', 'cv', 'cover']) {
    final v = (work[k] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
  }
  final info = authorsIndex['${work['a'] ?? ''}'];
  if (info is Map) {
    final av = (info['av'] ?? '').toString().trim();
    if (av.isNotEmpty) return av;
  }
  return '';
}
