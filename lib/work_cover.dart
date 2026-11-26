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

import 'media_path.dart';

/// 服务端按需抽帧 URL 的版本参数。
///
/// 旧版本把目录级 `thumb.jpg` 当作任意作品的首帧返回，客户端磁盘缓存里可能
/// 留下了「多作品同封面」的错误结果；URL 带 `v=2` 可以让旧缓存整体失效。
const String kWorkThumbVersion = '2';

/// 一个库的「媒体地址 / 接口地址」两个解析入口（页面注入或全局 `cfg`）。
typedef MediaUrlOf = String Function(String path, {String? lib});
typedef RawUrlOf = Uri Function(String path, {String? lib});

/// 某个库的作品封面地址拼装（**唯一入口**）。
///
/// `WorkCoverUrls.standard(mediaUrl: ..., rawUrl: ...)` 这段「把两个闭包
/// 各自绑到同一个 lib 上」的写法，此前在四个地方逐字重复：
///
/// ```
/// basic_lib_page._coverOf           widget.mediaUrlOf / widget.urlOf
/// main._posterCoverUrl              cfg.mediaUrl / cfg.u
/// main.WorkGrid._prefetchFirstScreen cfg.mediaUrl / cfg.u
/// main.WorkGrid 卡片构建            cfg.mediaUrl / cfg.u
/// ```
///
/// 四份里三份长得完全一样，第四份只是注入源不同。少写一个 `lib:` 就会让
/// 跨库列表里的封面跑到当前库去取（→ 401 白图），而它们「各自都算对了」。
WorkCoverUrls standardCoverUrls({
  required String lib,
  required MediaUrlOf mediaUrlOf,
  required RawUrlOf urlOf,
}) =>
    WorkCoverUrls.standard(
      mediaUrl: (path) => mediaUrlOf(path, lib: lib),
      rawUrl: (path) => urlOf(path, lib: lib).toString(),
    );

/// 把路径解析成可访问地址的两个回调（便于单测，不依赖全局配置）。
class WorkCoverUrls {
  /// 相对路径 → 绝对地址（媒体已带鉴权/服务器前缀）。
  final String Function(String path) mediaUrl;

  /// 服务端接口路径 → 绝对地址（只补服务器前缀，不加 `/media/<lib>/`）。
  /// 用于 `th` 已被扫描器写成 `/api/thumb/...` 的作品。
  final String Function(String path) rawUrl;

  /// (lib, workId) → 抽帧接口地址。
  final String Function(String lib, String workId) thumbUrl;

  const WorkCoverUrls({
    required this.mediaUrl,
    required this.rawUrl,
    required this.thumbUrl,
  });

  /// 默认实现：`/api/thumb/<lib>/<id>?v=<版本>`。
  factory WorkCoverUrls.standard({
    required String Function(String path) mediaUrl,
    required String Function(String path) rawUrl,
  }) =>
      WorkCoverUrls(
        mediaUrl: mediaUrl,
        rawUrl: rawUrl,
        thumbUrl: (lib, id) => rawUrl('/api/thumb/$lib/$id?v=$kWorkThumbVersion'),
      );
}

/// 作品类型是视频？（服务端 `t` 字段，`v`=视频，`p`=图文）
bool isVideoWork(dynamic work) =>
    work is Map && '${work['t'] ?? ''}' == 'v';

/// 视频扩展名判断（用于 `m` 里混着视频文件的场景）。
///
/// 规则本体在 `media_path.isVideoMediaPath`：`work_forms.chapterIsImage`
/// 此前自己列了一份更短的清单（缺 mkv/avi），同一个 `.mkv` 在封面判定里
/// 是视频、在合集排序里是图片——两套清单必须收敛成一条。这里保留旧名字。
bool isVideoPath(String p) => isVideoMediaPath(p);

/// 这个封面路径是**服务端接口**（`/api/thumb/...`）而不是媒体文件？
///
/// 2026-11-23 实测（只统计结构、不看任何名称）：libidx 里有 2288 条图文作品的
/// `th` 已经被写成 `/api/thumb/<lib>/<id>` 这种**接口地址**（lib-005 454 条、
/// lib-019 229 条、lib-021 1602 条等，正是「comics / AI 单图无封面」的那几个库）。
/// 旧解析把它当相对媒体路径交给 `mediaUrl`，拼出
/// `http://host/media/<lib>/api/thumb/...` —— 服务端把 `api` 当库内子目录，
/// 必然 404，卡片就永远只有底色。
///
/// 接口地址必须原样走 `rawUrl`（只补服务器前缀），不能再加 `/media/<lib>/`。
///
/// 规则本体在 `media_path.isApiMediaPath`（媒体地址拼接与封面解析必须同一条
/// 判据，否则一处认为是接口、另一处认为是媒体文件）。这里保留旧名字，
/// 因为调用点与测试都用它。
bool isApiThumbPath(String p) => isApiMediaPath(p);

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

/// 播放页海报层是否要建：只看**解析后的封面地址**，不看作品有没有 `th`。
///
/// 0.9.148 根因：播放页海报的显示条件写成 `it['th']` 非空，而视频作品大量
/// 没有 `th`（封面走 `/api/thumb` 抽帧）→ 整层海报根本不建，首帧之前只有
/// 黑色，就是「有声黑屏」。判定收敛到这个函数后，有封面就一定先铺海报。
bool posterLayerVisible(String coverUrl) => coverUrl.trim().isNotEmpty;

/// 作品封面最终地址（空串表示无封面）。
String workCoverUrl(
  dynamic work, {
  required String lib,
  required WorkCoverUrls urls,
}) {
  final path = workCoverPath(work);
  if (path.isNotEmpty) {
    // 服务端已把 `th` 落成 `/api/thumb/...`：它是接口不是媒体文件，
    // 直接补服务器前缀（再套 `/media/<lib>/` 会 404）。
    if (isApiThumbPath(path)) return urls.rawUrl(path);
    return urls.mediaUrl(path);
  }
  if (!workNeedsFrameThumb(work)) return '';
  final id = '${(work as Map)['id'] ?? ''}'.trim();
  return urls.thumbUrl(lib, id);
}
