/// 作品 → 作者名（全 App 唯一回退口径）。
///
/// 爬虫索引里少数作品没有 `a` 字段；它们的媒体路径仍然按
/// `<库>/@<作者>/VID|PIC/...` 组织，且服务端下发的路径经过 URL 编码
/// （`@作者` 会变成 `%40%E4%BD%9C%E8%80%85`）。
///
/// 之前播放页只判断路径段是否以 `@` 开头，编码后的 `%40...` 永远匹配不到，
/// 于是「没头像、点头像也进不去作者页」。这里统一先解码再匹配，
/// 并同时兼容 `m` 为字符串/数组以及 `media`/`path` 等旧字段。
library;

const List<String> _authorKeys = <String>['a', 'author', 'authorName'];

const List<String> _mediaKeys = <String>[
  'm',
  'media',
  'path',
  'file',
  'mp',
  'video',
  'images',
];

String _decodeSegment(String seg) {
  if (seg.isEmpty || !seg.contains('%')) return seg;
  try {
    return Uri.decodeComponent(seg);
  } catch (_) {
    return seg;
  }
}

String? _authorFromMediaValue(dynamic raw) {
  Iterable<String> paths = const <String>[];
  if (raw is String) {
    if (raw.trim().isEmpty) return null;
    paths = <String>[raw];
  } else if (raw is List) {
    paths = raw.whereType<String>();
  } else if (raw is Map) {
    // 少数作品把媒体写成 {url/path: ...}。
    for (final key in const ['url', 'path', 'src', 'm']) {
      final v = raw[key];
      if (v is String && v.trim().isNotEmpty) {
        paths = <String>[v];
        break;
      }
    }
  }
  for (final p0 in paths) {
    for (final rawSeg in p0.split('/')) {
      final seg = _decodeSegment(rawSeg.trim());
      if (seg.startsWith('@') && seg.length > 1) {
        final name = seg.substring(1).trim();
        if (name.isNotEmpty) return name;
      }
    }
  }
  return null;
}

/// 从作品元数据里取作者名；字段缺失时回退到媒体路径里的 `@作者`。
///
/// 返回空串表示作品里没有任何可用作者信息（调用方据此禁用跳转）。
String authorNameFromWork(Map work) {
  for (final key in _authorKeys) {
    final v = '${work[key] ?? ''}'.trim();
    if (v.isNotEmpty) return v;
  }
  for (final key in _mediaKeys) {
    final hit = _authorFromMediaValue(work[key]);
    if (hit != null && hit.isNotEmpty) return hit;
  }
  return '';
}

/// 用于 UI 展示的作者名：去掉作者名前面可能带的 `@`。
String authorDisplayNameFromWork(Map work) {
  final name = authorNameFromWork(work);
  return name.startsWith('@') ? name.substring(1).trim() : name;
}

String _bareAuthor(String name) {
  var s = name.trim();
  while (s.startsWith('@')) {
    s = s.substring(1).trim();
  }
  return s;
}

/// 在 `/api/authors.json` 的索引里按作者名取记录。
///
/// 服务端历史数据里同一作者可能出现 `作者` 与 `@作者` 两种键（目录名带不带 `@`
/// 都出现过）。作者页如果只做一次 `idx[name]`，从媒体路径回退出来的名字
/// 就会因为少了/多了 `@` 而查不到，表现为「点进去了但页面空白」。
Map? authorInfoFromIndex(Map index, String name) {
  Map? asMap(Object? v) => v is Map ? v : null;
  final direct = asMap(index[name]);
  if (direct != null) return direct;
  final bare = _bareAuthor(name);
  if (bare.isEmpty) return null;
  final prefixed = asMap(index['@$bare']);
  if (prefixed != null) return prefixed;
  final plain = asMap(index[bare]);
  if (plain != null) return plain;
  for (final e in index.entries) {
    if (_bareAuthor('${e.key}') == bare) return asMap(e.value);
  }
  return null;
}
