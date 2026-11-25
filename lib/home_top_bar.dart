// 主页顶部任务栏排布（owner 2026-11-22）。
//
// 手机宽度放不下全部图标，按频率分组：
//  - 常驻：总刷新；
//  - 次常驻：搜索；
//  - 其余（文件结构 / 推荐 / 作者 / 排行榜 / 设置）收进「⋯」菜单。
//
// 硬约束：
//  - 屏幕上直接可见的按钮**不超过 4 个**；
//  - 每个按钮触达区 ≥40dp（这里显式给 44dp）；
//  - 窄屏不换行、不重叠（可见数量由可用宽度算出，不靠 Wrap 硬换行）。
//
// 本文件只做排布与渲染；总刷新的业务编排在 `refresh_all.dart`。
library;

import 'package:flutter/material.dart';

/// 顶部单个动作。
class TopBarAction {
  final String id;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  const TopBarAction({
    required this.id,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });
}

/// 触达区边长（≥40dp 要求，取 44 留余量）。
const double kTopBarTouchSize = 44;

/// 每个按钮占用的横向格宽（44dp 触达 + 8dp 间距）。
const double kTopBarSlot = 52;

/// 「⋯」按钮实际占宽（触达区 44dp，与其它按钮同高）。
///
/// 排布必须把这一格算进去：旧公式只数按钮数、不算总宽，于是窄屏上
/// 「保留的按钮 + ⋯ + 设置」三段加起来会超过可用宽度，Row 直接溢出
/// （实测 170dp 宽需要 200dp）。
const double kTopBarMoreWidth = kTopBarTouchSize;

/// 屏幕上直接可见的按钮上限（含「⋯」）。
const int kTopBarMaxVisible = 4;

/// 排布结果：实际直接渲染的动作 + 收进「⋯」的动作。
class TopBarLayout {
  /// 直接渲染的动作（保持传入顺序）。
  final List<TopBarAction> visible;

  /// 收进「⋯」菜单的动作。
  final List<TopBarAction> overflow;

  const TopBarLayout(this.visible, this.overflow);

  bool get hasOverflow => overflow.isNotEmpty;
}

/// 计算排布。
///
/// 至少保留「1 个常驻 + ⋯」两格，最多 [kTopBarMaxVisible] 个可见按钮。
/// 数量按格宽向下取整，保证窄屏不会挤成溢出。
TopBarLayout topBarLayout({
  required double width,
  required List<TopBarAction> actions,
}) {
  if (actions.isEmpty) {
    return const TopBarLayout(<TopBarAction>[], <TopBarAction>[]);
  }
  // owner 2026-11-24：设置永远直接可见（尾位），不参与溢出竞争。
  final pinIndex = actions.indexWhere((a) => a.id == 'settings');
  final pinned = pinIndex >= 0 ? actions[pinIndex] : null;
  final rest = <TopBarAction>[
    for (var i = 0; i < actions.length; i++)
      if (i != pinIndex) actions[i],
  ];
  if (rest.isEmpty) {
    return TopBarLayout(<TopBarAction>[if (pinned != null) pinned], const []);
  }

  // 给固定尾位预留一格。
  final budget = pinned == null ? kTopBarMaxVisible : kTopBarMaxVisible - 1;
  final slots = (width / kTopBarSlot).floor().clamp(2, budget);
  final direct = slots >= rest.length ? rest.length : slots - 1;
  var keep = direct.clamp(1, rest.length);
  // 宽度也要满足：`keep` 个按钮 + （有溢出时的）「⋯」+ 常驻尾位，
  // 实际总宽不能超过 [width]，否则 Row 会溢出（而不是换行）。
  // 逐个退让到放得下为止；至少保留一格常驻（没有主按钮的顶部栏不可用），
  // 这一格的溢出交给外层（窄屏上「⋯」本身也会被裁，但不会再出现
  // 越过边界的黑黄条纹）。
  double needOf(int k) =>
      k * kTopBarSlot +
      (pinned == null ? 0 : kTopBarSlot) +
      (k < rest.length ? kTopBarMoreWidth : 0);
  if (width.isFinite && width > 0) {
    while (keep > 1 && needOf(keep) > width) {
      keep--;
    }
  }
  return TopBarLayout(
    <TopBarAction>[...rest.take(keep), if (pinned != null) pinned],
    rest.skip(keep).toList(),
  );
}

/// 主页顶部动作条：总刷新常驻，其余按宽度自动收进「⋯」。
///
/// owner 2026-11-24：「主页右上角设置点开没东西不好用」——
/// 设置原本和文件结构/推荐/作者/排行榜一起被塞进「⋯」菜单，
/// 用户点右上角看到的是菜单列表，容易以为「设置坏了」。
///
/// 现在把 `id == 'settings'` 视为**常驻尾位**：它永远直接可见、
/// 固定在最右侧（「⋯」在它左边），与总刷新共同构成两端锚点。
class HomeTopBar extends StatelessWidget {
  /// 动作列表：第一个必须是「总刷新」，第二个建议是「搜索」。
  final List<TopBarAction> actions;

  /// 总刷新是否正在进行（转圈并禁用重复点击）。
  final bool refreshing;

  /// 本动作条可用宽度；为空时按屏幕宽度减去左侧预留估算。
  ///
  /// 不用 `LayoutBuilder`：放在 `AppBar.actions` 里拿到的是被压缩的内禀
  /// 宽度，窄屏判断会失真；调用方（或默认估算）给一个明确数值更可靠。
  final double? availableWidth;

  const HomeTopBar({
    super.key,
    required this.actions,
    this.refreshing = false,
    this.availableWidth,
  });

  @override
  Widget build(BuildContext context) {
    final width = availableWidth ?? (MediaQuery.sizeOf(context).width - 150);
    final layout = topBarLayout(width: width, actions: actions);
    // owner 2026-11-24：设置固定最右，「⋯」放它左边，不把设置再挤进菜单。
    final pinned = layout.visible.where((a) => a.id == 'settings').toList();
    final normal = layout.visible.where((a) => a.id != 'settings').toList();
    final children = <Widget>[];
    Widget buttonOf(TopBarAction a) {
      final busy = refreshing && a.id == 'refresh';
      return IconButton(
        key: ValueKey('topbar-${a.id}'),
        tooltip: a.tooltip,
        iconSize: 24,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(
            width: kTopBarTouchSize, height: kTopBarTouchSize),
        onPressed: busy ? null : a.onPressed,
        icon: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(a.icon),
      );
    }

    for (final a in normal) {
      children.add(buttonOf(a));
    }
    if (layout.hasOverflow) {
      children.add(PopupMenuButton<TopBarAction>(
        key: const ValueKey('topbar-more'),
        tooltip: '更多',
        padding: EdgeInsets.zero,
        // owner 2026-11-25：「主页的三点省略号点开还是 bug，不显示」。
        //
        // 根因：这里原来写了 `constraints: tightFor(44, 44)`。PopupMenuButton
        // 的 constraints 作用于**按钮自身**，但 Flutter 会把它作为菜单的宽度
        // 上限传给弹出的 menu——整个菜单被压成 44dp 宽，菜单项里的文字被挤到
        // 20×20 几乎不可见。真机实测：点开后 UI 树里只剩一个 77×77 的遮罩，
        // 没有任何菜单项。删掉这条约束，按钮尺寸由 IconButton 默认的 48dp
        // 触达区保证，菜单恢复自适应文字宽度。
        icon: const Icon(Icons.more_horiz, size: 24),
        onSelected: (a) => a.onPressed?.call(),
        itemBuilder: (_) => <PopupMenuEntry<TopBarAction>>[
          for (final a in layout.overflow)
            PopupMenuItem<TopBarAction>(
              key: ValueKey('topbar-menu-${a.id}'),
              value: a,
              // 只放文字：菜单项自带 InkWells 与内边距，图标容易把
              // 菜单撑到屏幕外（窄屏实测溢出），文字够用。
              child: Text(a.tooltip, overflow: TextOverflow.ellipsis),
            ),
        ],
      ));
    }
    // 设置固定尾位。
    for (final a in pinned) {
      children.add(buttonOf(a));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}
