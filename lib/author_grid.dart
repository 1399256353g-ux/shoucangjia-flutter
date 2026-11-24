/// I7：作者总览的纯逻辑——头像解码尺寸与排序结果复用。
///
/// 作者总览页数据量大（上千位作者），此前 `sorted` 在每次 build /
/// 滚动回调里都会重新排序，头像也按固定宽度解码；返回作者页还会整页重载。
/// 这里把可测试的解码尺寸与排序抽出来，页面只缓存一次排序结果即可。
///
/// 第六批清理：作者网格几何（按可用宽度算行列、按 itemExtent 复用行）已删除——
/// 真实页面用 `SliverGridDelegateWithMaxCrossAxisExtent(150)` 交给 Flutter 自己
/// 分列，那段算法从未被调用，测试却在断言它。同文件里的卡片外观常量组也一并
/// 删除：9 个常量在 lib 与 test 里零引用，圆角/字号的真实取值写在各页面 widget 里。
library;

import 'decode_plan.dart';

/// 头像解码宽度：按显示尺寸 × 设备像素比，避免把大图整张解码进内存。
///
/// [displaySize] 是控件逻辑尺寸，[devicePixelRatio] 通常来自 MediaQuery；
/// [maxWidth] 兜底上限，避免平板上解码过大。
int avatarDecodeWidth({
  required double displaySize,
  required double devicePixelRatio,
  int maxWidth = 384,
}) =>
    // 与作品卡/库卡片共用同一条「显示尺寸 × 像素比」规则，避免各页各算一套。
    decodeWidthForDisplay(displaySize, devicePixelRatio,
        maxWidth: maxWidth <= 0 ? 1 : maxWidth);

/// 按 [metric] 降序排序，同分时按 [works] 降序，再按 [name] 升序保证稳定。
///
/// 页面只在数据/排序方式变化时调用一次，并把返回值缓存起来，
/// 避免每次 build 都重新排序（I7 卡顿根因之一）。
List<T> sortAuthorEntries<T>(
  List<T> items, {
  required num Function(T) metric,
  required num Function(T) works,
  required String Function(T) name,
}) {
  final list = List<T>.of(items);
  list.sort((a, b) {
    final c = metric(b).compareTo(metric(a));
    if (c != 0) return c;
    final w = works(b).compareTo(works(a));
    if (w != 0) return w;
    return name(a).compareTo(name(b));
  });
  return list;
}
