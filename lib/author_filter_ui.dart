/// J10：作者筛选工具的统一底部面板。
///
/// 供作者总览与排行榜复用：多选大库/基础库、等级、作品类型，
/// 实时显示命中数量，并支持一键清空。
library;

import 'package:flutter/material.dart';

import 'author_filter.dart';
import 'work_forms.dart';

/// 打开筛选面板；返回 null 表示取消（保持原筛选）。
Future<AuthorFilterState?> showAuthorFilterSheet({
  required BuildContext context,
  required AuthorFilterState initial,
  required List<AuthorLibNode> basics,
  required List<AuthorBigNode> bigs,
  List<AuthorLibNode> units = const [],
  List<AuthorLibNode> tops = const [],
  required List<String> grades,
  required int Function(AuthorFilterState) count,
}) {
  return showModalBottomSheet<AuthorFilterState>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AuthorFilterSheet(
      initial: initial.copy(),
      basics: basics,
      bigs: bigs,
      units: units,
      tops: tops,
      grades: grades,
      count: count,
    ),
  );
}

class _AuthorFilterSheet extends StatefulWidget {
  final AuthorFilterState initial;
  final List<AuthorLibNode> basics;
  final List<AuthorBigNode> bigs;
  final List<AuthorLibNode> units;

  /// P3：顶级节点（＝媒体库根）选项；作为一级筛选维度。
  final List<AuthorLibNode> tops;
  final List<String> grades;
  final int Function(AuthorFilterState) count;

  const _AuthorFilterSheet({
    required this.initial,
    required this.basics,
    required this.bigs,
    required this.units,
    this.tops = const [],
    required this.grades,
    required this.count,
  });

  @override
  State<_AuthorFilterSheet> createState() => _AuthorFilterSheetState();
}

class _AuthorFilterSheetState extends State<_AuthorFilterSheet> {
  late AuthorFilterState f = _migrateLegacyBigs(widget.initial);

  /// 把旧的「大库」选择并进「单元库」维度（0.9.313）。
  ///
  /// 背景：`bigs` 是单库时代的维度（服务端 `big_id`），而它的 id 就是第一层
  /// 单元库 id——同一个节点在两个下拉里各出现一次，名字还一个叫「媒体库
  /// （旧分组）」、一个叫「单元库」。用户看到两个都能选，选了其中一个另一个
  /// 仍是未选，以为是两件事。
  ///
  /// 现在只有一个维度：面板打开时把仍然有效的旧选择搬进 [units]，
  /// 搬不动的（节点已从树里消失）留在 `bigs` 里照旧生效——不能因为改名
  /// 就让一个看不见的条件继续过滤列表。
  AuthorFilterState _migrateLegacyBigs(AuthorFilterState initial) {
    final state = initial.copy();
    if (state.bigs.isEmpty) return state;
    final knownUnits = {for (final u in widget.units) u.id};
    final moved = <String>[];
    for (final id in state.bigs.toList()) {
      if (!knownUnits.contains(id)) continue;
      moved.add(id);
    }
    for (final id in moved) {
      state.bigs.remove(id);
      state.units.add(id);
    }
    return state;
  }

  void _toggle(void Function() fn) => setState(fn);

  Widget _section(String title, List<Widget> chips) {
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Text(title,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _toggle(onTap),
      visualDensity: VisualDensity.compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxH = MediaQuery.of(context).size.height * 0.82;
    final matched = widget.count(f);

    // P3：顶级节点作为一级筛选（在单元库之前），点它即收敛整棵子树。
    final topChips = [
      for (final t in widget.tops)
        _chip(t.name, f.tops.contains(t.id), () => f.toggleTop(t.id)),
    ];
    final unitChips = [
      for (final u in widget.units)
        _chip(u.name, f.units.contains(u.id), () => f.toggleUnit(u.id)),
    ];
    final bigChips = [
      for (final b in widget.bigs)
        // 已被单元库维度接管的大库不再画一次（同一个节点两个词条）。
        if (!{for (final u in widget.units) u.id}.contains(b.id))
          _chip(b.name, f.bigs.contains(b.id), () => f.toggleBig(b.id)),
    ];
    final basicChips = [
      for (final b in widget.basics)
        _chip(b.name, f.basics.contains(b.id), () => f.toggleBasic(b.id)),
    ];
    final gradeChips = [
      for (final g in widget.grades)
        _chip(g, f.grades.contains(g), () => f.toggleGrade(g)),
    ];
    final typeChips = [
      for (final t in workFilterOrder)
        _chip(workFilterLabel(t), f.types.contains(t), () => f.toggleType(t)),
    ];

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(children: [
              const Expanded(
                  child: Text('作者筛选',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold))),
              TextButton.icon(
                onPressed: f.isActive ? () => _toggle(f.clear) : null,
                icon: const Icon(Icons.filter_alt_off, size: 16),
                label: const Text('一键清空'),
              ),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // owner 2026-11-27：「不要使用出现这种不名所以让用户迷惑的
                  // 文字描述」。旧名「顶级节点（媒体库）」与「媒体库（旧分组）」
                  // 说的是同一棵树上的两个不同层级，用户无从分辨：
                  //   一级 = 每个连接的库根 → 「媒体库」
                  //   二级往下 = 节点文件夹   → 「单元库」
                  _section('媒体库', topChips),
                  _section('单元库', unitChips),
                  // 旧 `big_id` 分组已并入单元库维度；只有搬不动的历史选择
                  // （节点已不在树里）还会出现在这里，标题写明它是什么。
                  _section('其他历史筛选', bigChips),
                  _section('基础库', basicChips),
                  _section('作者等级', gradeChips),
                  _section('作品类型', typeChips),
                  if (widget.basics.isEmpty &&
                      widget.bigs.isEmpty &&
                      widget.units.isEmpty &&
                      widget.tops.isEmpty)
                    Text('暂无可筛选的库信息',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
            ),
            child: Row(children: [
              Expanded(
                child: Text(
                  f.isActive ? '命中 $matched 项' : '共 $matched 项',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('取消')),
              const SizedBox(width: 6),
              FilledButton(
                  onPressed: () => Navigator.of(context).pop(f.copy()),
                  child: const Text('应用')),
            ]),
          ),
        ]),
      ),
    );
  }
}
