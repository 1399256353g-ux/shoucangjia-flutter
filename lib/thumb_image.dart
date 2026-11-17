/// 缩略图 `ImageProvider` 的唯一构造入口。
///
/// `CachedNetworkImage` 内部把 `memCacheWidth` 包成
/// `ResizeImage.resizeIfNeeded(width, null, CachedNetworkImageProvider(...))`，
/// 预取也必须用完全相同的包装，缓存键才会一致（否则预取白拉一次，卡片渲染
/// 时再解码一次 —— 「已缓存图二次解码」的根因）。
///
/// 这里把这件事收敛到一个函数：卡片渲染与首屏预热都调用它，宽度来自
/// `decode_plan.dart` 的统一常量。
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// 构造缩略图 [ImageProvider]。
///
/// [decodeWidth] <= 0 时不缩放（原尺寸）；[headers] 与 [cacheManager] 必须与
/// 对应的 `CachedNetworkImage` 完全一致，否则仍会各存一份。
ImageProvider thumbImageProvider(
  String url, {
  required int decodeWidth,
  Map<String, String> headers = const <String, String>{},
  CacheManager? cacheManager,
}) {
  final provider = CachedNetworkImageProvider(
    url,
    headers: headers,
    cacheManager: cacheManager,
  );
  if (decodeWidth <= 0) return provider;
  return ResizeImage.resizeIfNeeded(decodeWidth, null, provider);
}
