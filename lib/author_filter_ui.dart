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
      grades: grades,
      count: count,
    ),
  );
}

class _AuthorFilterSheet extends StatefulWidget {
  final AuthorFilterState initial;
  final List<AuthorLibNode> basics;
  final List<AuthorBigNode> bigs;
  final List<String> grades;
  final int Function(AuthorFilterState) count;

  const _AuthorFilterSheet({
    required this.initial,
    required this.basics,
    required this.bigs,
    required this.grades,
    required this.count,
  });

  @override
  State<_AuthorFilterSheet> createState() => _AuthorFilterSheetState();
}

class _AuthorFilterSheetState extends State<_AuthorFilterSheet> {
  late AuthorFilterState f = widget.initial;

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
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
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

    final bigChips = [
      for (final b in widget.bigs)
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
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
              TextButton.icon(
                onPressed: f.isActive
                    ? () => _toggle(f.clear)
                    : null,
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
                  _section('大库', bigChips),
                  _section('基础库', basicChips),
                  _section('作者等级', gradeChips),
                  _section('作品类型', typeChips),
                  if (widget.basics.isEmpty && widget.bigs.isEmpty)
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
                  f.isActive ? '匹配 $matched 位作者' : '共 $matched 位作者',
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
