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

/// 把一批库卡片解析成预热请求（纯逻辑：不排队、不联网，便于单测）。
///
/// 配额 [limit] 数的是**真正入队的张数**，与 [prefetchThumbItems] /
/// `prefetchWorkCovers` 同一个语义：
///  1. 先排掉空封面（未生成封面的新库）；
///  2. 再按地址去重（同一张自定义封面 / 同名库出现在两处）；
///  3. 只有真正要拉的那张才占用一个配额。
///
/// 此前这里是「每看一张卡片就 seen++」再与 n 比：首屏若有两张卡没封面，
/// 预热就少拉两张**可见**封面，末尾那两张仍然逐张请求、先露底色。
List<ThumbPrefetchItem> libCoverPrefetchRequests(
  Iterable<LibCoverItem> items, {
  required int limit,
}) {
  if (limit <= 0) return const <ThumbPrefetchItem>[];
  final out = <ThumbPrefetchItem>[];
  final enqueued = <String>{};
  for (final it in items) {
    if (out.length >= limit) break;
    final cover = it.cover.trim();
    if (cover.isEmpty) continue;
    final url = withImageWidth(cover, kCardImageWidth);
    if (!enqueued.add(url)) continue;
    out.add((url: url, headers: it.headers));
  }
  return out;
}

/// 预热首屏可见的库卡片封面，返回实际排队的张数。
///
/// - [viewport]：页面可用尺寸（`MediaQuery.sizeOf`）；
/// - [grid]：卡片网格规格，必须与页面 delegate 同源（[LibGridSpec.delegate]）；
/// - [padding]：页面 `GridView.padding`，左右/上下各自取一半作为可用空间扣除；
/// - [decodeWidth]：卡片渲染用的解码宽度，必须由 `decode_plan.libCardDecodeWidthOf`
///   按卡片真实显示宽度算出（单元库 260 / 基础库 220），否则缓存键不匹配、
///   预热白做；
/// - [items]：按网格显示顺序的卡片，超出首屏的部分不会进请求。传**惰性**
///   `Iterable`（`units.map(...)`）时只求值到配额用完为止——主页面有几百个
///   基础库时，`basicCoverUrl` 每次都要跑一遍封面优先级链，先物化成 List
///   等于给全部卡片算一次，再只用前 8 张的结果。
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
  final requests = libCoverPrefetchRequests(items, limit: n);
  if (requests.isEmpty) return 0;
  final urls = [for (final r in requests) r.url];
  final headers = {for (final r in requests) r.url: r.headers};
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
