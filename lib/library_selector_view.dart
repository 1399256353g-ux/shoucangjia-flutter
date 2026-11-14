import 'package:flutter/material.dart';

import 'library_tree.dart';

/// 大库 / 基础库选择列表（J2/J3）。
///
/// 首屏只出现「大库」一行行折叠项和（可选的）星标基础库：
///  - 基础库默认不展开，点大库才显示；
///  - 旧的「已注册媒体库」注册表默认收起在「管理」入口里。
/// 这样默认主页的长度只与「大库数量」有关，而不是 39 个基础库 + 11 个注册库。
class LibrarySelectorView extends StatelessWidget {
  final LibraryTree tree;
  final Set<String> expanded;
  final Set<String> stars;
  final int legacyCount;
  final bool legacyOpen;
  final void Function(String id) onToggleSection;
  final void Function(BasicLib b) onToggleStar;
  final void Function(BasicLib b) onTapBasic;
  final VoidCallback onToggleLegacy;
  final WidgetBuilder legacyBuilder;

  const LibrarySelectorView({
    super.key,
    required this.tree,
    required this.expanded,
    required this.stars,
    required this.legacyCount,
    required this.legacyOpen,
    required this.onToggleSection,
    required this.onToggleStar,
    required this.onTapBasic,
    required this.onToggleLegacy,
    required this.legacyBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final t = tree;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            const Icon(Icons.account_tree_outlined, size: 18),
            const SizedBox(width: 6),
            const Text('大库 / 基础库',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${t.bigs.length} 大库 · ${t.totalBasics} 基础库',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ]),
        ),
        if (t.starred.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 2),
            child: Text('★ 星标基础库（置顶）',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.amber)),
          ),
          for (final b in t.starred) _basicTile(context, b, pinned: true),
        ],
        for (final big in t.bigs) ...[
          _bigTile(context, big),
          if (expanded.contains(big.id))
            if (t.visibleBasics(big).isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(48, 2, 16, 8),
                child: Text('该大库的基础库已全部星标置顶',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              )
            else
              for (final b in t.visibleBasics(big))
                _basicTile(context, b, pinned: false),
        ],
        if (t.unassigned.isNotEmpty) ...[
          _sectionTile(
            'tree-unassigned',
            '未归属基础库',
            '${t.unassigned.length} 个',
            icon: Icons.folder_special_outlined,
          ),
          if (expanded.contains('unassigned'))
            for (final b in t.unassigned)
              _basicTile(context, b, pinned: stars.contains(b.id)),
        ],
        const Divider(height: 24),
        // 旧的注册表是「管理」功能，不是日常切换入口：默认收起。
        ListTile(
          key: const ValueKey('legacy-toggle'),
          dense: true,
          leading: const Icon(Icons.tune, size: 18),
          title: const Text('已注册媒体库（管理）',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: Text('$legacyCount 个 · 默认库 / 爬虫 / 维护',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          trailing: AnimatedRotation(
            turns: legacyOpen ? 0.25 : 0,
            duration: const Duration(milliseconds: 150),
            child: const Icon(Icons.chevron_right),
          ),
          onTap: onToggleLegacy,
        ),
        if (legacyOpen) legacyBuilder(context),
      ],
    );
  }

  Widget _bigTile(BuildContext context, BigLib big) {
    final open = expanded.contains(big.id);
    return ListTile(
      key: ValueKey('big-${big.id}'),
      leading: Icon(
          open ? Icons.folder_open : Icons.folder_outlined,
          color: Theme.of(context).colorScheme.primary),
      title: Text(big.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(big.subtitle, style: const TextStyle(fontSize: 11)),
      trailing: AnimatedRotation(
        turns: open ? 0.25 : 0,
        duration: const Duration(milliseconds: 150),
        child: const Icon(Icons.chevron_right),
      ),
      onTap: () => onToggleSection(big.id),
    );
  }

  Widget _sectionTile(String id, String title, String sub,
      {required IconData icon}) {
    final open = expanded.contains(id);
    return ListTile(
      key: ValueKey(id),
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(sub, style: const TextStyle(fontSize: 11)),
      trailing: AnimatedRotation(
        turns: open ? 0.25 : 0,
        duration: const Duration(milliseconds: 150),
        child: const Icon(Icons.chevron_right),
      ),
      onTap: () => onToggleSection(id),
    );
  }

  Widget _basicTile(BuildContext context, BasicLib b, {required bool pinned}) {
    return ListTile(
      key: ValueKey('basic-${b.id}'),
      dense: true,
      contentPadding: const EdgeInsets.only(left: 40, right: 8),
      leading: const Icon(Icons.subdirectory_arrow_right, size: 18),
      title: Text(b.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('${b.authors} 作者 · ${b.works} 作品',
          style: const TextStyle(fontSize: 11)),
      trailing: IconButton(
        key: ValueKey('star-${b.id}'),
        tooltip: pinned ? '取消星标' : '星标并置顶',
        icon: Icon(pinned ? Icons.star : Icons.star_border,
            color: pinned ? Colors.amber : null),
        onPressed: () => onToggleStar(b),
      ),
      onTap: () => onTapBasic(b),
    );
  }
}
