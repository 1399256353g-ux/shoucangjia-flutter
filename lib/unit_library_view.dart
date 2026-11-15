import 'package:flutter/material.dart';

import 'library_badge.dart';
import 'library_tree.dart';
import 'unit_library.dart';

/// L5-C：卡片封面（空串表示用默认图）。由调用方解析 `_cover/` 与播放量。
typedef CoverOf = String Function(BasicLib basic);
typedef UnitCoverOf = String Function(UnitLibrary unit);

/// 封面缩略图：有图显示图片，无图显示默认图标。
class _CoverThumb extends StatelessWidget {
  final String url;
  final double size;
  final IconData fallbackIcon;
  final Color fallbackColor;

  const _CoverThumb({
    required this.url,
    required this.size,
    required this.fallbackIcon,
    required this.fallbackColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final box = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fallbackColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: url.isEmpty
          ? Icon(fallbackIcon, color: fallbackColor, size: size * 0.44)
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(fallbackIcon,
                  color: fallbackColor, size: size * 0.44),
            ),
    );
    return Semantics(
      label: url.isEmpty ? '默认封面' : '封面',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.5), width: 0.6),
        ),
        child: box,
      ),
    );
  }
}

/// L5 卡片体系：单元库卡片 > 基础库卡片 > 作品卡片（尺寸递减）。
///
/// 主页只铺「单元库」卡片 + 一个「星标基础库」入口；
/// 点进单元库才看到它的下级单元库与基础库卡片。
class UnitLibraryHomeView extends StatelessWidget {
  final UnitLibrary tree;
  final Set<String> stars;
  final void Function(UnitLibrary unit) onOpenUnit;
  final void Function(BasicLib b) onToggleStar;
  final void Function(BasicLib b) onTapBasic;
  final VoidCallback onOpenStars;
  final UnitCoverOf? unitCoverOf;

  const UnitLibraryHomeView({
    super.key,
    required this.tree,
    required this.stars,
    required this.onOpenUnit,
    required this.onToggleStar,
    required this.onTapBasic,
    required this.onOpenStars,
    this.unitCoverOf,
  });

  @override
  Widget build(BuildContext context) {
    final units = tree.children;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(children: [
            const Icon(Icons.layers_outlined, size: 18),
            const SizedBox(width: 6),
            const Text('单元库',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${units.length} 个 · ${tree.basicCount} 基础库',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ]),
        ),
        StarredEntryCard(count: stars.length, onTap: onOpenStars),
        if (units.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 24),
            child: Text('当前连接下没有可显示的单元库',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
        // 主页只给「顶级单元库」一张卡；下级单元库在进入后再显示。
        UnitLibraryCard(
          unit: tree,
          coverUrl: unitCoverOf?.call(tree) ?? '',
          onTap: () => onOpenUnit(tree),
        ),
      ],
    );
  }
}

/// 「星标基础库」入口（原「默认收藏夹」）：点进单独的选择页。
class StarredEntryCard extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const StarredEntryCard(
      {super.key, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: Material(
        color: Colors.amber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: const ValueKey('starred-entry'),
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(children: [
              const Icon(Icons.star, color: Colors.amber, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('星标基础库',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              Text(count == 0 ? '未标记' : '$count 个',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 星标基础库选择页：只列出被星标的基础库卡片。
class StarredLibrariesPage extends StatelessWidget {
  final List<BasicLib> basics;
  final void Function(BasicLib b) onToggleStar;
  final void Function(BasicLib b) onTapBasic;
  final CoverOf? coverOf;

  const StarredLibrariesPage({
    super.key,
    required this.basics,
    required this.onToggleStar,
    required this.onTapBasic,
    this.coverOf,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('星标基础库')),
      body: basics.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '还没有星标的基础库\n在单元库内点基础库卡片右上角的星标即可加入',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.92,
              ),
              itemCount: basics.length,
              itemBuilder: (c, i) => BasicLibCard(
                basic: basics[i],
                starred: true,
                coverUrl: coverOf?.call(basics[i]) ?? '',
                onToggleStar: () => onToggleStar(basics[i]),
                onTap: () => onTapBasic(basics[i]),
              ),
            ),
    );
  }
}

/// 单元库卡片（大）：名称、层级摘要、来源连接。
class UnitLibraryCard extends StatelessWidget {
  final UnitLibrary unit;
  final VoidCallback onTap;
  final String coverUrl;

  const UnitLibraryCard({
    super.key,
    required this.unit,
    required this.onTap,
    this.coverUrl = '',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final server = unit.node.serverLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: ValueKey('unit-${unit.id}'),
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            height: 116,
            child: Row(children: [
              const SizedBox(width: 14),
              _CoverThumb(
                url: coverUrl,
                size: 64,
                fallbackIcon: Icons.folder_copy_outlined,
                fallbackColor: scheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(unit.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(unit.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),
                    if (server.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(server,
                          style:
                              const TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
              const SizedBox(width: 10),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 单元库详情：下级单元库卡片 + 基础库卡片网格。
class UnitLibraryPage extends StatelessWidget {
  final UnitLibrary unit;
  final Set<String> stars;
  final void Function(UnitLibrary unit) onOpenUnit;
  final void Function(BasicLib b) onToggleStar;
  final void Function(BasicLib b) onTapBasic;
  final CoverOf? coverOf;
  final UnitCoverOf? unitCoverOf;
  /// L5-D：非顶级单元库可配置独立爬虫（SECRET 顶级不显示入口）。
  final void Function(UnitLibrary unit)? onConfigureUnit;

  const UnitLibraryPage({
    super.key,
    required this.unit,
    required this.stars,
    required this.onOpenUnit,
    required this.onToggleStar,
    required this.onTapBasic,
    this.coverOf,
    this.unitCoverOf,
    this.onConfigureUnit,
  });

  @override
  Widget build(BuildContext context) {
    final basics = unit.allBasics;
    final sorted = [
      ...basics.where((b) => stars.contains(b.id)),
      ...basics.where((b) => !stars.contains(b.id)),
    ];
    // 每张基础库卡片的词条来自「直接上级单元库」。
    final ownerLabel = <String, String>{};
    final ownerKey = <String, String>{};
    void walkOwners(UnitLibrary u) {
      for (final b in u.basics) {
        ownerLabel[b.id] = u.name;
        ownerKey[b.id] = u.id;
      }
      for (final c in u.children) {
        walkOwners(c);
      }
    }

    walkOwners(unit);
    return Scaffold(
      appBar: AppBar(
        title: Text(unit.name),
        actions: [
          if (onConfigureUnit != null && unit.rel.trim().isNotEmpty)
            IconButton(
              key: ValueKey('unit-crawler-${unit.id}'),
              tooltip: '爬虫配置',
              icon: const Icon(Icons.settings_ethernet),
              onPressed: () => onConfigureUnit!(unit),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
            child: Text(unit.subtitle,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ),
          if (unit.children.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 2),
              child: Text('下级单元库',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            for (final c in unit.children)
              UnitLibraryCard(
                unit: c,
                coverUrl: unitCoverOf?.call(c) ?? '',
                onTap: () => onOpenUnit(c),
              ),
          ],
          if (sorted.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text('基础库',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.92,
              ),
              itemCount: sorted.length,
              itemBuilder: (c, i) => BasicLibCard(
                basic: sorted[i],
                starred: stars.contains(sorted[i].id),
                coverUrl: coverOf?.call(sorted[i]) ?? '',
                onToggleStar: () => onToggleStar(sorted[i]),
                onTap: () => onTapBasic(sorted[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 基础库卡片（中）：来源词条、名称、作者/作品数、星标。
class BasicLibCard extends StatelessWidget {
  final BasicLib basic;
  final bool starred;
  final VoidCallback onToggleStar;
  final VoidCallback onTap;
  final String coverUrl;
  /// 所属单元库（节点文件夹）。只有单元库有资格生成位置词条；
  /// 为空表示该卡片不在单元库语境下，不显示词条。
  final String unitLabel;
  final String unitKey;

  const BasicLibCard({
    super.key,
    required this.basic,
    required this.starred,
    required this.onToggleStar,
    required this.onTap,
    this.coverUrl = '',
    this.unitLabel = '',
    this.unitKey = '',
  });

  /// 词条文本：基础库名去掉「(序号) 」前缀。
  static String badgeText(String name) {
    final raw = name.replaceFirst(RegExp(r'^\(\d+\)\s*'), '').trim();
    return raw.isEmpty ? name : raw;
  }

  Widget _badge() {
    // 位置词条只由「单元库」生成：取所属单元库名称与配色，不再用基础库自身。
    final text = badgeText(unitLabel);
    final color = Color(LibraryBadge.colorFor(unitKey.isEmpty ? unitLabel : unitKey));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text.length > 10 ? '${text.substring(0, 10)}…' : text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 9.5,
          color: Color(LibraryBadge.textColorOn(color.toARGB32())),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('basic-card-${basic.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 6, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                _CoverThumb(
                  url: coverUrl,
                  size: 26,
                  fallbackIcon: Icons.folder_outlined,
                  fallbackColor: scheme.primary,
                ),
                const Spacer(),
                InkResponse(
                  key: ValueKey('star-card-${basic.id}'),
                  onTap: onToggleStar,
                  radius: 16,
                  child: Icon(
                    starred ? Icons.star : Icons.star_border,
                    size: 18,
                    color: starred ? Colors.amber : Colors.grey,
                  ),
                ),
              ]),
              const SizedBox(height: 5),
              if (unitLabel.isNotEmpty)
                Align(alignment: Alignment.centerLeft, child: _badge()),
              const SizedBox(height: 4),
              Expanded(
                child: Text(basic.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 4),
              Text('${basic.authors} 作者 · ${basic.works} 作品',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
              if (basic.serverLabel.isNotEmpty)
                Text(basic.serverLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}
