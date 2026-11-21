/// P 修复 + 0.9.153 边缘闪烁修复：作者页头部收起/展开判定（纯逻辑，可单测）。
///
/// 背景 1（P）：Windows 版作者页作品数刚好卡在可滚动下限时，头部一收起导致
/// `maxScrollExtent` 变成 0，于是再也滚不动、也永远回不到 `pixels <= 8`，
/// 头部永久锁死在收起态。
///
/// 背景 2（owner 2026-11-22）：滚到列表最上/最下时信息栏反复闪隐。根因是
/// **判定把 `pixels >= maxScrollExtent` 当成“到底要展开”**，而头部本身的
/// 高度就是视口高度的一部分：展开 → max 变大 → 又“没到底” → 收起 → max 变小
/// → 又“到底” → 展开…… 每帧自激。任何依赖“当前 maxScrollExtent”的展开条件
/// 都会和“收起改变 maxScrollExtent”互相喂回。
///
/// 结构性规则（只依赖滚动几何，不再有任何定时器兜底）：
/// 1. `maxScrollExtent <= 0`：不可滚动，展开（展开只会让 max 变大，天然收敛）；
/// 2. 已收起但剩余范围不足以支撑收起态：展开（同上，单调收敛）；
/// 3. 任一端 overscroll：已到端点，视为稳定态 → 展开（不再只认顶部）；
/// 4. 未收起：只有「上滑超过 collapseAt」且「收起后仍留有 headerExtent +
///    minCollapsibleExtent 的可滚动余量」才收起 —— 这条余量是防自激的关键：
///    收起会让 max 减少约 headerExtent，如果没有这份余量，收起必然把位置顶到
///    新的底部，再触发旧规则里的“到底展开”；
/// 5. 已收起：只在真正回顶（`pixels <= expandAt`）或明确下滑回看
///    （`delta < 0 && pixels < midExpandLimit`）时展开，底部不再强制展开。
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
///
/// [headerExtent]：展开态头部比收起态多出的高度（由调用方测量）。收起会
/// 等量减少 `maxScrollExtent`，所以收起前必须预留这份余量；未知时传 0，
/// 由「已收起且 max 过小则展开」的单向规则兜住收敛。
HeaderAction headerActionFor({
  required bool collapsed,
  required double pixels,
  required double maxScrollExtent,
  double delta = 0,
  bool overscroll = false,
  double headerExtent = 0,
}) {
  // 不可滚动：只能展开（展开让 max 增大，不会来回跳）。
  if (maxScrollExtent <= 0) return HeaderAction.expand;

  // 已收起但可滚动范围已不足以支撑收起态：展开恢复滚动能力。
  if (collapsed && maxScrollExtent < minCollapsibleExtent) {
    return HeaderAction.expand;
  }

  // 任一端越过边界：到达端点，视为稳定态（顶部下拉 / 底部继续下推）。
  if (collapsed && overscroll) return HeaderAction.expand;

  if (!collapsed) {
    if (pixels <= collapseAt) return HeaderAction.none;
    // 收起会等量吃掉 maxScrollExtent，余量不足就保持展开：
    // 这是打断「收起→顶到底→展开→未到底→收起」自激的唯一位置。
    final remaining = maxScrollExtent - pixels;
    if (remaining <= headerExtent + minCollapsibleExtent) {
      return HeaderAction.none;
    }
    return HeaderAction.collapse;
  }

  if (pixels <= expandAt) return HeaderAction.expand;
  if (delta < 0 && pixels < midExpandLimit) return HeaderAction.expand;
  return HeaderAction.none;
}
