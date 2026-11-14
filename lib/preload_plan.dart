/// G18：自动连播时预缓冲下一条。
///
/// 播放页在播放器 B 中提前打开下一条媒体（静音、暂停），
/// 切条时直接把 B 切为活动播放器，避免每次起播都从零缓冲。
/// 这里集中放可单测的纯逻辑：是否需要预缓冲、取哪条媒体、键是否匹配。
library;

/// 预缓冲用的媒体路径：视频取第一个视频文件，图文取背景音频；
/// 纯图片作品没有可缓冲的媒体，返回 null。
String? preloadMediaPath(dynamic w) {
  if (w is! Map) return null;
  if ('${w['t'] ?? ''}' == 'v') {
    final m = w['m'];
    if (m is List && m.isNotEmpty) {
      final p = '${m.first ?? ''}';
      return p.isEmpty ? null : p;
    }
    return null;
  }
  final au = '${w['au'] ?? ''}';
  return au.isEmpty ? null : au;
}

/// 预缓冲条目的身份：库 + 作品 id + 媒体路径，任一项变化都不能复用。
String preloadKeyFor(dynamic w, String lib) {
  final id = '${(w is Map ? w['id'] : null) ?? ''}';
  final path = preloadMediaPath(w) ?? '';
  return '$lib|$id|$path';
}

/// 是否应该预缓冲下一条：仅连播开启、未开单条循环、确有下一条且下一条
/// 存在可缓冲媒体时进行。
bool shouldPreloadNext({
  required bool autoplay,
  required bool loopOne,
  required int index,
  required int count,
  required bool hasMedia,
}) {
  if (!autoplay || loopOne) return false;
  if (index < 0 || index >= count) return false;
  return hasMedia;
}

/// 已预缓冲的条目能否直接用于当前目标。
bool preloadMatches({
  required int? preloadedIndex,
  required String? preloadedKey,
  required int index,
  required String key,
}) =>
    preloadedIndex == index && preloadedKey == key && key.isNotEmpty;
