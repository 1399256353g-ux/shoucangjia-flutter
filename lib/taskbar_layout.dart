/// 播放页底部任务栏排布（owner 2026-11-22 规格，见 ITERATION_TODO.md）。
///
/// 规格要求（从左到右）：
///   头像+作者（信息区，不在栏内）→ 进度条（贴栏上缘）→
///   播放控制（主按钮，突出）→ 剧集 `1/12` → 播放设置（倍速菜单）→
///   声音 → 显示（全屏/横竖屏）。
/// 平台差异：
///   - 移动端：触达 ≥44dp、图标 24dp、**最多 5 个可见**；空间不足时
///     「播放设置」优先并入「更多」菜单。
///   - 桌面端：全部可见，全屏按钮独立显示。
///
/// 本文件只做**纯排布计算**与一个「更多」按钮控件，不改动任何播放逻辑；
/// 渲染在 `main.dart` 的任务栏 Row 里按 [TaskbarPlan] 展开。
///
/// 与旧实现的关键差别：旧代码用 `FittedBox(scaleDown)` 把放不下的按钮
/// **整体等比缩小**，结果是触达区悄悄掉到 30dp 以下（违反 ≥44dp 的硬
/// 要求，且用户点不中）。这里改为「按真实宽度做取舍」：放得下就原尺寸，
/// 放不下就把低优先级槽位收进「更多」菜单，任何按钮都不缩小。
library;

import 'package:flutter/material.dart';

/// 任务栏里的一个槽位（只描述"是什么"，不含回调与状态）。
enum TaskbarSlot {
  /// 播放/暂停（主按钮，最高优先级，永远不被收进菜单）。
  play,

  /// 剧集 `1/12`，点击弹集数列表。
  episodes,

  /// 播放设置（倍速），显示当前倍速。
  settings,

  /// 自动连播开关（owner 2026-11-24：必须直接可见，不能只藏在菜单里）。
  autoplay,

  /// 单条循环开关。
  loop,

  /// 乱序播放开关。
  shuffle,

  /// 声音（点击静音 / 长按拖动调音量）。
  sound,

  /// 桌面端常驻音量滑杆模块（明显比其他按钮宽）。
  volume,

  /// 送水滴。
  drop,

  /// 显示（移动端=全屏+长按横竖屏；桌面端=独立全屏按钮）。
  display,
}

/// 溢出时的保留优先级：数值越小越先保留。
///
/// 依据 owner 规格的明确要求：
/// - 播放/暂停是主按钮，永不丢失；
/// - 显示（全屏）是桌面端必须独立的按钮；
/// - 播放设置是规格里点名"可以并入更多菜单"的那一个，所以排最后。
const Map<TaskbarSlot, int> kKeepPriority = {
  TaskbarSlot.play: 0,
  // 全屏键固定最右侧，且必须始终可见（owner 2026-11-24：它曾被挤到左端）。
  TaskbarSlot.display: 1,
  // 三个播放开关是日常高频操作，优先级高于选集与声音。
  TaskbarSlot.autoplay: 2,
  TaskbarSlot.loop: 3,
  TaskbarSlot.shuffle: 4,
  TaskbarSlot.episodes: 5,
  TaskbarSlot.sound: 6,
  TaskbarSlot.drop: 7,
  TaskbarSlot.volume: 8,
  TaskbarSlot.settings: 9,
};

/// 「更多」按钮的固定宽度（触达 ≥44dp）。
const double kTaskbarMoreWidth = 44;

/// 排布结果：直接渲染的槽位（保持传入顺序）+ 收进「更多」菜单的槽位。
class TaskbarPlan {
  const TaskbarPlan(this.visible, this.overflow);

  final List<TaskbarSlot> visible;
  final List<TaskbarSlot> overflow;

  bool get hasOverflow => overflow.isNotEmpty;
}

/// 计算任务栏排布。
///
/// [items] 传入顺序即渲染顺序；[widthOf] 给出每个槽位的真实宽度
/// （必须 ≥44dp 触达）；[availableWidth] 是栏内可用宽度；
/// [maxVisible] 是平台上直接可见的按钮上限（移动端 5，桌面端给足够大的值）。
///
/// 规则（不叠兜底，单一取舍路径）：
/// 1. 全部放得下且未超可见上限 → 全部可见，顺序不变；
/// 2. 放不下 → 按 [kKeepPriority] 保留高优先级槽位，其余进「更多」；
/// 3. 保留结果按传入顺序渲染，不重排，避免按钮跳位；
/// 4. 只为「更多」预留宽度时确实预留（不靠事后缩放掩盖溢出）。
TaskbarPlan taskbarPlan({
  required List<TaskbarSlot> items,
  required double availableWidth,
  required double Function(TaskbarSlot) widthOf,
  int maxVisible = 5,
}) {
  if (items.isEmpty) return const TaskbarPlan(<TaskbarSlot>[], <TaskbarSlot>[]);
  final cap = maxVisible < 1 ? 1 : maxVisible;
  final avail =
      availableWidth.isFinite && availableWidth > 0 ? availableWidth : 0.0;

  double totalOf(Iterable<TaskbarSlot> s) =>
      s.fold(0.0, (a, x) => a + widthOf(x));

  if (items.length <= cap && totalOf(items) <= avail) {
    return TaskbarPlan(List<TaskbarSlot>.of(items), const <TaskbarSlot>[]);
  }

  // 需要取舍：按优先级贪心装入，同时不超过宽度与可见数上限。
  final ranked = List<TaskbarSlot>.of(items)
    ..sort((a, b) {
      final pa = kKeepPriority[a] ?? 99;
      final pb = kKeepPriority[b] ?? 99;
      return pa.compareTo(pb);
    });

  final kept = <TaskbarSlot>[];
  var used = 0.0;
  for (final s in ranked) {
    if (kept.length >= cap) break;
    final wNeed = widthOf(s);
    // 最高优先级槽位永远保留：没有主按钮的任务栏不可用。
    if (kept.isEmpty) {
      kept.add(s);
      used += wNeed;
      continue;
    }
    if (used + wNeed > avail) continue;
    kept.add(s);
    used += wNeed;
  }

  // 溢出就必须有「更多」按钮；放不下就把优先级最低的那个让出去
  // （不让「更多」自己被裁掉——那是缩放，不是取舍）。
  while (kept.length > 1 && used + kTaskbarMoreWidth > avail) {
    used -= widthOf(kept.removeLast());
  }

  final visible = <TaskbarSlot>[];
  final overflow = <TaskbarSlot>[];
  final keptSet = kept.toSet();
  for (final s in items) {
    (keptSet.contains(s) ? visible : overflow).add(s);
  }
  return TaskbarPlan(visible, overflow);
}

/// 「更多」按钮：把溢出槽位收进弹出菜单（只放文字，避免窄屏撑破菜单）。
class TaskbarMoreButton extends StatelessWidget {
  const TaskbarMoreButton({
    super.key,
    required this.items,
    required this.labelOf,
    required this.onSelected,
    this.width = kTaskbarMoreWidth,
  });

  /// 溢出槽位，按传入顺序展示。
  final List<TaskbarSlot> items;

  /// 槽位对应的菜单文案。
  final String Function(TaskbarSlot) labelOf;

  /// 选中后的动作。
  final void Function(TaskbarSlot) onSelected;

  final double width;

  @override
  Widget build(BuildContext context) {
    final w = width < 44 ? 44.0 : width;
    return PopupMenuButton<TaskbarSlot>(
      key: const Key('taskbar-more'),
      tooltip: '更多',
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: w, height: 48),
      icon: const Icon(Icons.more_horiz, size: 24, color: Colors.white70),
      onSelected: onSelected,
      itemBuilder: (_) => <PopupMenuEntry<TaskbarSlot>>[
        for (final s in items)
          PopupMenuItem<TaskbarSlot>(
            key: ValueKey('taskbar-more-${s.name}'),
            value: s,
            child: Text(labelOf(s), overflow: TextOverflow.ellipsis),
          ),
      ],
    );
  }
}
