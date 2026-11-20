// 作品封面地址解析（全站唯一入口）。
//
// 背景（owner 2026-11-17）：
//  - 「多作品同封面」：同一目录下多个视频共用一个 `thumb.jpg`，旧服务端把首帧
//    写进目录级文件，目录内其它作品全拿到同一张图。服务端已改为按作品 id 落
//    `thumb.<workId>.jpg`，客户端同时给 URL 加版本参数绕过旧的错误缓存。
//  - 「封面加载慢」：视频缺缩略图时逐张请求 `/api/thumb`，服务端原先是全局
//    串行 ffmpeg；客户端这边要保证「能直接用的封面」绝不走抽帧接口。
//
// 解析顺序（严格按此）：
//  1. `th`（爬虫/扫描器已落盘的缩略图，可能是库内相对路径或 `/media/...`）；
//  2. 非视频作品的 `m` 第一张图片（图文/合集，mp4/mov 等视频文件跳过）；
//  3. 视频且 `id` 非空 → 服务端按需抽帧接口；
//  4. 其余 → 空串（卡片回退底色），不要拼出必然 404 的地址。
library;

/// 服务端按需抽帧 URL 的版本参数。
///
/// 旧版本把目录级 `thumb.jpg` 当作任意作品的首帧返回，客户端磁盘缓存里可能
/// 留下了「多作品同封面」的错误结果；URL 带 `v=2` 可以让旧缓存整体失效。
const String kWorkThumbVersion = '2';

/// 把路径解析成可访问地址的两个回调（便于单测，不依赖全局配置）。
class WorkCoverUrls {
  /// 相对路径 → 绝对地址（媒体已带鉴权/服务器前缀）。
  final String Function(String path) mediaUrl;

  /// (lib, workId) → 抽帧接口地址。
  final String Function(String lib, String workId) thumbUrl;

  const WorkCoverUrls({required this.mediaUrl, required this.thumbUrl});

  /// 默认实现：`/api/thumb/<lib>/<id>?v=<版本>`。
  factory WorkCoverUrls.standard({
    required String Function(String path) mediaUrl,
    required String Function(String path) rawUrl,
  }) =>
      WorkCoverUrls(
        mediaUrl: mediaUrl,
        thumbUrl: (lib, id) => rawUrl('/api/thumb/$lib/$id?v=$kWorkThumbVersion'),
      );
}

/// 作品类型是视频？（服务端 `t` 字段，`v`=视频，`p`=图文）
bool isVideoWork(dynamic work) =>
    work is Map && '${work['t'] ?? ''}' == 'v';

/// 视频扩展名判断（用于 `m` 里混着视频文件的场景）。
bool isVideoPath(String p) {
  final l = p.toLowerCase();
  for (final ext in const ['.mp4', '.mov', '.m4v', '.webm', '.mkv', '.avi']) {
    if (l.endsWith(ext)) return true;
  }
  return false;
}

/// 不经过抽帧接口就能直接用上的封面路径；没有则返回空串。
String workCoverPath(dynamic work) {
  if (work is! Map) return '';
  final th = '${work['th'] ?? ''}'.trim();
  if (th.isNotEmpty) return th;
  if (!isVideoWork(work)) {
    final m = work['m'];
    // 单图作品常见把 `m` 写成字符串而不是数组；两种都要认，
    // 否则这类作品在列表里永远没有封面。
    if (m is String) {
      final one = m.trim();
      if (one.isNotEmpty && !isVideoPath(one)) return one;
    }
    if (m is List) {
      for (final e in m) {
        final one = '$e'.trim();
        if (one.isEmpty) continue;
        if (isVideoPath(one)) continue;
        return one;
      }
    }
    // 兼容只给单图的字段名
    for (final k in const ['img', 'cover', 'p']) {
      final one = '${work[k] ?? ''}'.trim();
      if (one.isNotEmpty && !isVideoPath(one)) return one;
    }
  }
  return '';
}

/// 作品是否需要服务端抽帧（视频且没有现成缩略图）。
bool workNeedsFrameThumb(dynamic work) {
  if (!isVideoWork(work)) return false;
  if (workCoverPath(work).isNotEmpty) return false;
  final id = '${(work as Map)['id'] ?? ''}'.trim();
  return id.isNotEmpty;
}

/// 作品封面最终地址（空串表示无封面）。
String workCoverUrl(
  dynamic work, {
  required String lib,
  required WorkCoverUrls urls,
}) {
  final path = workCoverPath(work);
  if (path.isNotEmpty) return urls.mediaUrl(path);
  if (!workNeedsFrameThumb(work)) return '';
  final id = '${(work as Map)['id'] ?? ''}'.trim();
  return urls.thumbUrl(lib, id);
}
