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
import 'stable_order.dart';

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

/// 按 [metric] 降序排序，同分时按 [works] 降序，再按 [name] 升序。
///
/// **同分同名必须保持输入顺序**（走 [stableSort]，原下标作次排序键）。
///
/// 旧实现只用 `list.sort(...)`：Dart 的 `List.sort` 是内省排序，**不保证稳定**。
/// 实测 40 位「同名同分」作者（跨库同名合并后很常见）排出来是
/// `13,1,2,…,12,0,14,…`——输入顺序被彻底打乱；更麻烦的是，数据里**增一位
/// 无关作者**（例如别的基础库多了一位）后重新排序，原有作者的前后顺序也跟着变
/// （`0` 从第 14 位换到第 15 位）。用户看到的是「刷新一下就有一批作者换位置」，
/// 而播放/作品数一个都没变。
///
/// 这不是「需要一个更细的排序键」——同分同名本来就没有次序依据，
/// 正确做法是让相等元素保持输入顺序（输入顺序来自服务端 JSON，是确定的）。
/// 与 `unit_library` / `category_tree` / `author_big_nodes` 同一条规则
/// （见 `stable_order.dart` 文件头），作者总览此前漏了这一个调用点。
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
  stableSort<T>(list, (a, b) {
    final c = metric(b).compareTo(metric(a));
    if (c != 0) return c;
    final w = works(b).compareTo(works(a));
    if (w != 0) return w;
    return name(a).compareTo(name(b));
  });
  return list;
}
