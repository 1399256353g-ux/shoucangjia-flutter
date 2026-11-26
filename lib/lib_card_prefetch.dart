/// 库卡片首屏封面预热（**唯一实现**）。
///
/// 为什么要有这个文件（0.9.286）：
///
/// 同一段「算张数 → 拼 URL → 去重 → 交给 ThumbPrefetch」的流程此前在
/// `unit_library_view.dart` 里写了**三份**（主页 / 星标页 / 单元库页），
/// 三份之间有三处实质差异，而且都不报错：
///
/// | 页面 | 「张数」的上限 | 去重 | 纵向内边距 |
/// |---|---|---|---|
/// | 主页 | `maxItems: 8` | 不去重 | `kLibGridPadding.left`（12）当上下 |
/// | 星标页 | `maxItems: 8` | `urls.contains` | 12 / 18（真实值） |
/// | 单元库页 | 下级 6、基础库 8 | `headers.containsKey` | 12 当上下 |
///
/// 预热是「首屏几张」的**判定**：三份各写一遍，同一次刷新预热多少张就取决
/// 于当前落在哪个页面；主页还不去重，两个格子指向同一张封面时会重复登记。
/// 纵向内边距用 `padding.left` 顶替，在没有纵向留白的网格上把可用高度算小
/// 一截——行数少算、首屏仍然逐张请求。
///
/// 现在几何只来自 [LibGridSpec]（与页面 delegate 同源），张数只由
/// [LibGridSpec.prefetchCount] 算，URL 去重只在这里做一次。
library;

import 'package:flutter/widgets.dart';

import 'cover_cache.dart';
import 'grid_spec.dart';
import 'media_resize.dart';
import 'thumb_image.dart';
import 'thumb_prefetch.dart';

/// 一张待预热的库卡片：封面原始地址 + 该卡片的鉴权头。
typedef LibCoverItem = ({String cover, Map<String, String> headers});

/// 预热首屏可见的库卡片封面，返回实际排队的张数。
///
/// - [viewport]：页面可用尺寸（`MediaQuery.sizeOf`）；
/// - [grid]：卡片网格规格，必须与页面 delegate 同源（[LibGridSpec.delegate]）；
/// - [padding]：页面 `GridView.padding`，左右/上下各自取一半作为可用空间扣除；
/// - [decodeWidth]：卡片渲染用的解码宽度，必须由 `decode_plan.libCardDecodeWidthOf`
///   按卡片真实显示宽度算出（单元库 260 / 基础库 220），否则缓存键不匹配、
///   预热白做；
/// - [items]：按网格显示顺序的卡片，超出首屏的部分不会进请求；
/// - [maxItems]：覆盖 [LibGridSpec.maxPrefetch]。
int prefetchLibCovers({
  required Size viewport,
  required LibGridSpec grid,
  required EdgeInsets padding,
  required int decodeWidth,
  required Iterable<LibCoverItem> items,
  int? maxItems,
  int screens = 1,
}) {
  final n = grid.prefetchCount(
    viewport,
    padding: padding,
    maxItems: maxItems,
    screens: screens,
  );
  if (n <= 0) return 0;
  final urls = <String>[];
  final headers = <String, Map<String, String>>{};
  for (final it in items) {
    // 配额数的是**真正入队的张数**，与 `prefetchThumbItems` / `prefetchWorkCovers`
    // 同一个语义。此前这里另有一个 `seen` 计数器，把「没有封面的卡片」也
    // 记进 n：主页首屏若有两张卡没有封面（新库、封面还没生成），预热就少拉
    // 两张**可见**封面，末尾那两张仍然逐张请求、先露底色。同一个参数名
    // `limit` 在两处有两种含义，是这一批要收掉的那类分叉。
    if (urls.length >= n) break;
    final cover = it.cover.trim();
    if (cover.isEmpty) continue;
    final url = withImageWidth(cover, kCardImageWidth);
    // 同一个封面地址出现在两张卡片上（同名库、同一张自定义封面）时只拉一次。
    if (headers.containsKey(url)) continue;
    urls.add(url);
    headers[url] = it.headers;
  }
  if (urls.isEmpty) return 0;
  ThumbPrefetch.instance.run(
    urls,
    limit: urls.length,
    provider: (u) => thumbImageProvider(
      u,
      decodeWidth: decodeWidth,
      headers: headers[u] ?? const <String, String>{},
      cacheManager: DiziCache.manager,
    ),
  );
  return urls.length;
}
