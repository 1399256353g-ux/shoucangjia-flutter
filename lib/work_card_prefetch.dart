/// 作品卡首屏封面预热（**唯一实现**）。
///
/// 为什么要有这个文件（0.9.288）：
///
/// 同一段「按网格规格算张数 → 取作品封面 → 加 `w=` → 按显示宽度解码 →
/// 交给 `ThumbPrefetch`」在**两个页面各写一遍**：
///
/// ```
/// basic_lib_page._prefetchFirstScreen   filtered.take(n) + 单库鉴权头
/// main.WorkGrid._prefetchFirstScreen    works.take(n)    + 按作品各自库取鉴权头
/// ```
///
/// 两处「各自都算对了」，所以不会报错、也没有第二份实现可对比。但它们是
/// **同一个判定的两个副本**：预热哪几张、用多大宽度解码、地址怎么带参。
/// 只要一处改成「多预热一屏」或「按 1080 解码」，同一个作品卡在两个页面
/// 就会有两个缓存键——网格里已解码的图，换页后要重新下载并重新解码。
///
/// 现在这里只有一条链：
///  - 张数只由 [LibGridSpec.prefetchCount] 算；
///  - 解码宽度只由 `decode_plan.workCardDecodeWidth` 算（与 `WorkCard` 同一个值）；
///  - 地址变换只有 `media_resize.withImageWidth(cover, kWorkImageWidth)` 一处；
///  - 去重/限量由 `thumb_prefetch.prefetchThumbItems` 做一次。
///
/// 调用方只决定「预热哪些作品」与「每张图带什么鉴权头」——那两件事本来
/// 就与页面数据源有关，不是可以统一的规则。
library;

import 'package:flutter/widgets.dart';

import 'decode_plan.dart';
import 'grid_spec.dart';
import 'media_resize.dart';
import 'thumb_prefetch.dart';

/// 一张待预热的作品封面：已解析的封面相对/绝对路径 + 它自己的鉴权头。
///
/// 鉴权头必须**随图走**：收藏夹/搜索/推荐列表可能跨库，同一批预热里
/// 两张图要带两种 `Authorization`。
typedef WorkCoverItem = ({String cover, Map<String, String> headers});

/// 预热首屏可见作品卡的封面，返回实际入队张数。
///
/// - [viewport]：页面可用尺寸（`MediaQuery.sizeOf`）；
/// - [grid]：作品网格规格，必须与页面 delegate 同源（[LibGridSpec.delegate]）；
/// - [padding]：页面 `GridView.padding`，与 delegate 拿到的约束一致；
/// - [devicePixelRatio]：用于算解码宽度，必须与 `WorkCard` 用同一个入口；
/// - [items]：按网格显示顺序的作品封面，超出首屏的部分不会进请求；
/// - [maxItems]：覆盖 [LibGridSpec.maxPrefetch]。
int prefetchWorkCovers({
  required Size viewport,
  required LibGridSpec grid,
  required EdgeInsets padding,
  required double devicePixelRatio,
  required Iterable<WorkCoverItem> items,
  int? maxItems,
}) {
  final n = grid.prefetchCount(viewport, padding: padding, maxItems: maxItems);
  if (n <= 0) return 0;
  // 与 `WorkCard.memCacheWidth` 同一个数（`workCardDecodeWidth`），
  // 缓存键一致才能命中。
  final px = workCardDecodeWidth(devicePixelRatio);
  return prefetchThumbItems(
    [
      for (final it in items)
        (
          // 空封面留给 `prefetchThumbItems` 排掉：`cfg.mediaUrl('')` 返回的是
          // base 本身（不是空串），到这里已经是纯字符串，`withImageWidth('')`
          // 仍是空串。
          url: withImageWidth(it.cover, kWorkImageWidth),
          headers: it.headers,
        ),
    ],
    limit: n,
    decodeWidth: px,
  );
}
