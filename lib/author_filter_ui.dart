/// J10：作者筛选工具的统一底部面板。
///
/// 供作者总览与排行榜复用：多选媒体库/单元库/基础库、等级、作品类型，
/// 实时显示命中数量，并支持一键清空。
library;

import 'package:flutter/material.dart';

import 'author_filter.dart';
import 'level_names.dart';
import 'library_badge.dart' show LibEntryKind;
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
  /// 已被「单元库」维度接管的旧分组 id 集合。
  ///
  /// 0.9.348：同一句「这个 `big_id` 已经被单元库维度接管」此前在这个文件里
  /// 写了两遍——[_migrateLegacyBigs] 里算一份 `knownUnits`，`build` 里又在每个 chip 的
  /// `if` 条件里内联重建一次 `{for (final u in widget.units) u.id}`。两处只要
  /// 有一处漏掉某个单元库 id，同一个节点就会同时出现在「单元库」与「其他历史
  /// 筛选」两段（选了一段、另一段看起来仍是未选）；第二处还在循环条件里建
  /// 集合，O(n²)。
  ///
  /// 不能写成 `late final`：面板开着时 `widget.units` 仍会变（跨连接聚合
  /// 逐个到达），那时必须重算——见 [didUpdateWidget]。
  Set<String> _takenOver = const <String>{};

  late AuthorFilterState f = _migrateLegacyBigs(widget.initial);

  @override
  void initState() {
    super.initState();
    _takenOver = _unitIds();
  }

  Set<String> _unitIds() => {for (final u in widget.units) u.id};

  /// 面板开着时 `widget.units` 才拿到那些节点：迁移与接管判定都要**跟着重算**。
  ///
  /// 0.9.348：迁移原先只在 `late f = _migrateLegacyBigs(widget.initial)` 那一帧
  /// 跑一次。推荐页/搜索页的面板是等类型索引回来后打开的，但「单元库」列表
  /// 本身可能晚一帧才齐：面板已经开着、`units` 才多了几个 id 时，那几个节点会
  /// 同时出现在「单元库」与「其他历史筛选」两段。迁移是幂等的（搬不动的不动），
  /// 所以这里重跑一次即可。
  @override
  void didUpdateWidget(covariant _AuthorFilterSheet old) {
    super.didUpdateWidget(old);
    _takenOver = _unitIds();
    // 这一帧紧接着会 rebuild，不需要 setState。
    f = _migrateLegacyBigs(f);
  }

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
    final moved = <String>[];
    for (final id in state.bigs.toList()) {
      if (!_takenOver.contains(id)) continue;
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
        if (!_takenOver.contains(b.id))
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
                  _section(levelName(LibEntryKind.top), topChips),
                  _section(levelName(LibEntryKind.unit), unitChips),
                  // 旧 `big_id` 分组已并入单元库维度；只有搬不动的历史选择
                  // （节点已不在树里）还会出现在这里，标题写明它是什么。
                  _section(kLegacyFilterLabel, bigChips),
                  _section(levelName(LibEntryKind.basic), basicChips),
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
