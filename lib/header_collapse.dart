/// P 修复：作者页头部收起/展开判定（纯逻辑，可单测）。
///
/// 背景：Windows 版作者页作品数刚好卡在可滚动下限时，头部一收起导致
/// `maxScrollExtent` 变成 0，于是再也滚不动、也永远回不到 `pixels <= 8`，
/// 头部永久锁死在收起态。
///
/// 规则（优先级从高到低）：
/// 1. `maxScrollExtent <= 0`：不可滚动，强制展开；
/// 2. `pixels >= maxScrollExtent`：已经到底，强制展开（否则无法回顶触发阈值）；
/// 3. 顶部 overscroll（下拉/回弹）：展开；
/// 4. 未收起：仅当 `maxScrollExtent > minCollapsibleExtent` 且 `pixels > collapseAt` 时收起；
/// 5. 已收起：`pixels <= expandAt` 或中途下滑（delta < 0 且 pixels < midExpandLimit）时展开。
library;

/// 收起所需的最小可滚动距离；不足时保持展开，避免收起后失去滚动能力。
const double minCollapsibleExtent = 48;

/// 上滑超过该像素值才收起。
const double collapseAt = 32;

/// 回顶阈值：不超过它视为“已回顶”。
const double expandAt = 8;

/// 中途下滑展开的下限（pixels 小于它且 delta < 0）。
const double midExpandLimit = 160;

/// 判定结果。
enum HeaderAction { none, collapse, expand }

/// 根据滚动指标与增量计算头部动作。
HeaderAction headerActionFor({
  required bool collapsed,
  required double pixels,
  required double maxScrollExtent,
  double delta = 0,
  bool overscroll = false,
}) {
  // 不可滚动 / 已经到底：必须展开（否则会锁死）。
  if (maxScrollExtent <= 0) return HeaderAction.expand;
  if (pixels >= maxScrollExtent) return HeaderAction.expand;
  if (overscroll && collapsed) return HeaderAction.expand;

  if (!collapsed) {
    if (maxScrollExtent <= minCollapsibleExtent) return HeaderAction.none;
    return pixels > collapseAt ? HeaderAction.collapse : HeaderAction.none;
  }

  if (pixels <= expandAt) return HeaderAction.expand;
  if (delta < 0 && pixels < midExpandLimit) return HeaderAction.expand;
  return HeaderAction.none;
}
