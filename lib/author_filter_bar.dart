/// J11：所有混合展示作者的页面共用的筛选条。
///
/// 左侧按钮打开统一筛选面板，右侧显示当前筛选摘要与命中数量，
/// 激活时提供一键清空。样式与 J10 在作者总览/排行榜上的入口一致。
library;

import 'package:flutter/material.dart';

import 'author_filter.dart';
import 'horizontal_chip_bar.dart';
import 'library_badge.dart';

/// 作者总览 / 排行榜共用的库快捷条。
///
/// 只做「单选收敛」：点某个库 = 只筛这个库，点「全部」= 清空该维度。
/// 状态直接读写共享的 [AuthorFilterState]，因此与筛选面板永远一致，
/// 不再各页维护 sel / unitSel 这样的第二份真相。
class AuthorQuickChips extends StatelessWidget {
  /// 「全部 …」按钮文案，例如「全部基础库」「全部单元库」。
  final String allLabel;
  final List<AuthorLibNode> items;
  /// 当前该维度的选中集合（通常来自 filter.bigs / filter.units）。
  final Set<String> selected;
  /// 传入库 id；空串表示清空该维度。
  final ValueChanged<String> onPick;
  final double height;

  const AuthorQuickChips({
    super.key,
    required this.allLabel,
    required this.items,
    required this.selected,
    required this.onPick,
    this.height = 42,
  });

  @override
  Widget build(BuildContext context) {
    final only = selected.length == 1 ? selected.first : '';
    return HorizontalChipBar(
      height: height,
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            key: const ValueKey('quick-chip-all'),
            label: Text(allLabel),
            selected: selected.isEmpty,
            onSelected: (_) {
              if (selected.isEmpty) return;
              onPick('');
            },
          ),
        ),
        for (final n in items)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              key: ValueKey('quick-chip-${n.id}'),
              label: Text(LibraryBadge.labelWithEmoji(
                  LibraryBadge.stripIndex(n.name), n.id)),
              selected: only == n.id,
              onSelected: (_) {
                if (only == n.id) return;
                onPick(n.id);
              },
            ),
          ),
      ],
    );
  }
}

class AuthorFilterBar extends StatelessWidget {
  final AuthorFilterState filter;
  final bool loading;
  final String hint;
  /// 已激活时的摘要；为空时用 [AuthorFilterState.summary] 的默认文案。
  final String? summary;
  final VoidCallback onOpen;
  final VoidCallback onClear;

  const AuthorFilterBar({
    super.key,
    required this.filter,
    required this.onOpen,
    required this.onClear,
    this.loading = false,
    this.hint = '按媒体库/基础库、等级、作品类型叠加筛选',
    this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 6, 4),
      child: Row(children: [
        OutlinedButton.icon(
          onPressed: onOpen,
          icon: loading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.filter_alt_outlined, size: 16),
          label: Text(filter.isActive ? '筛选 ${filter.activeCount}' : '筛选'),
          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            filter.isActive ? (summary ?? filter.summary()) : hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ),
        if (filter.isActive)
          IconButton(
            tooltip: '清空筛选',
            visualDensity: VisualDensity.compact,
            onPressed: onClear,
            icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
          ),
      ]),
    );
  }
}
