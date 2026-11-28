/// J11：所有混合展示作者的页面共用的筛选条。
///
/// 左侧按钮打开统一筛选面板，右侧显示当前筛选摘要与命中数量，
/// 激活时提供一键清空。样式与 J10 在作者总览/排行榜上的入口一致。
library;

import 'package:flutter/material.dart';

import 'author_filter.dart';
import 'loading_view.dart';

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
                  child: InlineSpinner())
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
