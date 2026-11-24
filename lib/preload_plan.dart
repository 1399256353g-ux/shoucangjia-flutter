/// G18：自动连播时预缓冲下一条。
///
/// 播放页在播放器 B 中提前打开下一条媒体（静音、暂停），
/// 切条时直接把 B 切为活动播放器，避免每次起播都从零缓冲。
/// 这里集中放可单测的纯逻辑：是否需要预缓冲、取哪条媒体、键是否匹配。
library;

import 'work_safety.dart';

/// 预缓冲用的媒体路径：视频取第一个视频文件，图文取背景音频；
/// 纯图片作品没有可缓冲的媒体，返回 null。
String? preloadMediaPath(dynamic w) {
  if (w is! Map) return null;
  if ('${w['t'] ?? ''}' == 'v') {
    // `m` 为单图字符串时同样是「有媒体」：预载拿不到源就等于每条都要
    // 现开现缓冲，切条会明显变慢。取数只走 workMediaPaths。
    final paths = workMediaPaths(w);
    return paths.isEmpty ? null : paths.first;
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
