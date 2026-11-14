/// G19：列表渐进渲染（无限滚动）的纯逻辑。
///
/// 接口一次返回整份列表，但一次性构建上千个网格项会造成明显卡顿/白屏，
/// 因此首屏只渲染 [initialGridCount] 个，滚动接近底部时再追加一页。
library;

/// 每页追加数量（与 WorkGrid 的网格密度匹配）。
const int kGridPageSize = 60;

/// 首屏应渲染的数量：空列表为 0，不足一页时全量，否则一页。
int initialGridCount(int total, {int pageSize = kGridPageSize}) {
  if (total <= 0 || pageSize <= 0) return 0;
  return total < pageSize ? total : pageSize;
}

/// 追加一页后的数量，自动夹紧到 [0, total]，不会超过总数。
int nextGridCount(int current, int total, {int pageSize = kGridPageSize}) {
  if (total <= 0 || pageSize <= 0) return 0;
  final c = current <= 0 ? 0 : (current >= total ? total : current);
  if (c >= total) return total;
  final next = c + pageSize;
  return next >= total ? total : next;
}

/// 滚动位置是否接近底部（可触发下一页）。
///
/// [pixels] 当前滚动偏移，[maxScrollExtent] 最大可滚动距离，
/// [viewportDimension] 视口高度；[threshold] 为提前触发的像素距离。
/// 内容不足一屏（maxScrollExtent 为 0）时视为已到底，由调用方决定是否还有下一页。
bool shouldLoadNextPage({
  required double pixels,
  required double maxScrollExtent,
  required double viewportDimension,
  double threshold = 480,
}) {
  if (viewportDimension <= 0 || threshold < 0) return false;
  final remaining = maxScrollExtent - pixels;
  return remaining <= threshold;
}
