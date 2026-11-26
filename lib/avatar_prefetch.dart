/// 作者头像首屏预热（**唯一实现**）。
///
/// 为什么要有这个文件（0.9.289 · 第六十六批）：
///
/// 「空路径排掉 → `cfg.mediaUrl` → `w=` → 按显示尺寸算解码宽度 → 带该库的
/// 鉴权头 → 交给 `prefetchThumbItems`」这一段，在 `main.dart` 里有两份：
///
/// ```
/// _RankPageState._prefetchRankAvatars   avatar 键 + 榜单筛选后的行库
/// _AuthorGridPageState._prefetchAvatars av 键 + 每行自带 _lib
/// ```
///
/// 两份「各自都算对了」，所以不报错也没有第二份实现可对比；但空路径的排法
/// （`cfg.mediaUrl('')` 返回的是 base 本身）、`w=` 的宽度、解码宽度公式都是
/// 同一个判定。任一处改成「多预热一行」或「按 200 解码」，同一张头像在两个
/// 列表里就有两个缓存键——首屏白拉一次，进另一个列表再解码一次。
///
/// 这里只收「一张头像怎么变成一次预热请求」；**预热多少张**由调用方按自己
/// 的列表/网格几何算（排行榜按行数与行高，作者网格按 `LibGridSpec`）。
library;

import 'author_grid.dart' show avatarDecodeWidth;
import 'media_resize.dart';
import 'thumb_prefetch.dart';

/// 一张待预热的头像：媒体路径 + 它所属的库（决定鉴权与地址前缀）。
typedef AvatarPrefetchItem = ({String path, String lib});

/// 把一批头像解析成预热请求（纯逻辑：不排队、不联网，便于单测）。
///
/// 顺序与语义：
///  1. 空路径（含纯空白）**先排掉**——`cfg.mediaUrl('')` 返回的是服务器根
///     地址而不是空串，不去就会把 `/` 当图片请求一次；
///  2. 再按 [limit] 截断（limit 指的是「最多预热几张非空头像」）；
///  3. 地址加 `w=`（`media_resize.kAvatarImageWidth`，与头像控件同值）；
///  4. 鉴权头随图走，由 [headersOf] 给出。
List<ThumbPrefetchItem> avatarPrefetchRequests(
  Iterable<AvatarPrefetchItem> items, {
  required int limit,
  required String Function(String path, String lib) urlOf,
  required Map<String, String> Function(String lib) headersOf,
}) {
  if (limit <= 0) return const <ThumbPrefetchItem>[];
  final out = <ThumbPrefetchItem>[];
  for (final it in items) {
    if (out.length >= limit) break;
    final path = it.path.trim();
    if (path.isEmpty) continue;
    out.add((
      url: withImageWidth(urlOf(path, it.lib), kAvatarImageWidth),
      headers: headersOf(it.lib),
    ));
  }
  return out;
}

/// 预热一批作者头像，返回实际入队张数。
///
/// - [limit]：最多预热几张，由调用方的几何算出来；
/// - [displaySize]：头像控件的逻辑边长（`AuthorAvatar.rankSize` / `gridSize`）；
/// - [devicePixelRatio]：与卡片渲染同一个值；
/// - [urlOf] / [headersOf]：地址与鉴权头的解析入口，必须与头像控件用的是
///   同一套（页面上是全局 `cfg.mediaUrl` / `cfg.headersFor`，基础库页是
///   页面注入的绑定表）。这里只注入、不自己拼 base。
int prefetchAvatarItems(
  Iterable<AvatarPrefetchItem> items, {
  required int limit,
  required double displaySize,
  required double devicePixelRatio,
  required String Function(String path, String lib) urlOf,
  required Map<String, String> Function(String lib) headersOf,
}) {
  final requests = avatarPrefetchRequests(
    items,
    limit: limit,
    urlOf: urlOf,
    headersOf: headersOf,
  );
  if (requests.isEmpty) return 0;
  final px = avatarDecodeWidth(
    displaySize: displaySize,
    devicePixelRatio: devicePixelRatio,
  );
  return prefetchThumbItems(
    requests,
    limit: requests.length,
    decodeWidth: px,
  );
}
