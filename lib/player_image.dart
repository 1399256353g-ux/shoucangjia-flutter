/// 播放页「大图」的唯一参数出口（0.9.293）。
///
/// 播放页有四类大图，它们的**取图口径本该完全一致**：
///
/// | 位置 | 用途 |
/// |---|---|
/// | `_prefetchNeighborCovers` | 邻页预载（±3 条） |
/// | `_NeighborPage` | 滑动中的相邻页底图 |
/// | `_picPreview` | 图文落页的零等待底图 |
/// | 舞台海报 `CachedNetworkImage` | 起播前的封面 |
/// | `_cropAndApplyCover` | 裁切框的预览图 |
///
/// 这五处此前各自展开成同一段三元组：
///
/// ```
/// imageUrl      withImageWidth(cover, kPlayerImageWidth)
/// httpHeaders   cfg.headersFor(lib)
/// memCacheWidth _posterDecodeWidth(context)   // = screenDecodeWidth(...)
/// ```
///
/// 三元组里任何一项写错，缓存键就分叉——预载拉回来的图在真正渲染时
/// 「没命中」，再下一次、再解码一次。这类错误不会报错、也没有第二份实现
/// 可对比（第七十批已经修过一次 `maxWidth` vs `memCacheWidth` 的键不一致）。
///
/// 现在只有 [PlayerImage] 一处产出这三项：宽度常量只在这里引用，
/// 空封面统一产出空地址（`withImageWidth('')` 在别处曾是「拼出服务器根地址」
/// 的入口）。
library;

import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'media_resize.dart' show kPlayerImageWidth, kWorkImageWidth, withImageWidth;
import 'decode_plan.dart' show workCardDecodeWidth;
import 'thumb_image.dart';

/// 作品卡尺寸的缩略图 [ImageProvider]（**唯一入口**）。
///
/// 与 [PlayerImage] 同一张图，但按**作品卡**的尺寸取（`kWorkImageWidth` +
/// `workCardDecodeWidth`）——播放页的「零等待底图」用它。
///
/// 为什么需要第二个入口：播放页有两档大图，一档是「海报尺寸」
/// （[PlayerImage]，`w=kPlayerImageWidth` + 屏幕宽 × DPR），一档是「作品卡尺寸」
/// （网格里已经解码过的那张，命中就零等待）。它们必须是两个不同的地址，
/// 否则底图就会顶掉高清图（同一个缓存键 → 海报永远停在 440px）。
///
/// 但**如何从 cover 得到作品卡 provider** 此前在 `_prefetchNeighborCovers`、
/// `_posterPreview`、`_picPreview` 三处各展开一遍（各写一遍
/// `withImageWidth(cover, kWorkImageWidth)` + `workCardDecodeWidth(dpr)` +
/// 各自的 headers 来源），任何一处写错就是「预载一个键、渲染另一个键」。
/// 现在只有这一个函数。
ImageProvider gridImageProvider({
  required String cover,
  required Map<String, String> headers,
  required double devicePixelRatio,
  CacheManager? cacheManager,
}) =>
    thumbImageProvider(
      cover.isEmpty ? '' : withImageWidth(cover, kWorkImageWidth),
      decodeWidth: workCardDecodeWidth(devicePixelRatio),
      headers: headers,
      cacheManager: cacheManager,
    );

/// 播放页一张大图的**请求参数**：地址（已带 `w=`）、鉴权头、解码宽度。
///
/// 构造后不可变；相同参数的两个实例 `==`（见 [operator ==]），因为它同时
/// 被当作图片缓存键与邻页 widget 缓存的键来比较。
class PlayerImage {
  /// 原始封面相对/绝对路径（尚未加 `w=`）；空串表示这条作品没有可用封面。
  final String cover;

  /// 该图所属库 id（鉴权头按库取）。
  final String lib;

  /// 鉴权头（已按 [lib] 解析）。
  final Map<String, String> headers;

  /// 解码宽度（`decode_plan.screenDecodeWidth` 的结果）。
  final int decodeWidth;

  const PlayerImage({
    required this.cover,
    required this.lib,
    required this.headers,
    required this.decodeWidth,
  });

  /// 实际请求地址：`w=kPlayerImageWidth`；无封面时为空串。
  String get url => cover.isEmpty ? '' : withImageWidth(cover, kPlayerImageWidth);

  /// 是否有可用封面（没有时调用方应画纯黑/空占位，不要发请求）。
  bool get isEmpty => cover.isEmpty;

  /// 与渲染同键的 [ImageProvider]（预载、探比例、底图共用）。
  ImageProvider provider({CacheManager? cacheManager}) => thumbImageProvider(
        url,
        decodeWidth: decodeWidth,
        headers: headers,
        cacheManager: cacheManager,
      );

  @override
  bool operator ==(Object other) =>
      other is PlayerImage &&
      other.url == url &&
      other.decodeWidth == decodeWidth &&
      other.lib == lib;

  @override
  int get hashCode => Object.hash(url, decodeWidth, lib);

  @override
  String toString() => 'PlayerImage($lib, $decodeWidth, ${url.isEmpty ? '-' : 'url'})';
}
