import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'library_badge.dart';
import 'library_tree.dart';
import 'lib_cover.dart';
import 'home_action.dart';
import 'unit_library.dart';
import 'work_plays.dart';

/// L5-C：卡片封面（空串表示用默认图）。由调用方解析 `_cover/` 与播放量。
typedef CoverOf = String Function(BasicLib basic);
typedef UnitCoverOf = String Function(UnitLibrary unit);

/// 单元库子树里「本机播放量最高且有缩略图」的作品：所属基础库 + 次数 + 缩略图。
/// 同分按缩略图路径升序，结果稳定；没有则 null。
({BasicLib basic, int count, String thumb})? topPlayedInUnit(UnitLibrary unit) {
  ({BasicLib basic, int count, String thumb})? best;
  for (final b in unit.allBasics) {
    for (final v in WorkPlaysStore.countsFor(b.id).values) {
      final th = v.thumb.trim();
      if (th.isEmpty || v.count <= 0) continue;
      if (best == null ||
          v.count > best.count ||
          (v.count == best.count && th.compareTo(best.thumb) < 0)) {
        best = (basic: b, count: v.count, thumb: th);
      }
    }
  }
  return best;
}

/// 单元库封面 URL（优先级高 → 低，交给 [pickUnitCover] 判定）：
///  1. 自定义 `_cover/<version>.<ext>`（节点带版本指针时自行拼；否则用
///     调用方解析好的 [customUrl]）；
///  2. 子树内「App 播放量最高」作品的封面（含下级单元库）；
///  3. 空串 → 卡片回退默认图标。
String unitCoverUrl(
  UnitLibrary unit, {
  String customUrl = '',
  String Function(BasicLib basic, String thumb)? thumbUrlOf,
}) {
  final preset = customUrl.trim();
  // 调用方已解析好的地址（自定义封面，鉴权/路由由调用方掌握）优先。
  if (preset.isNotEmpty) return preset;
  final top = topPlayedInUnit(unit);
  final pick = pickUnitCover(
    rel: unit.rel,
    version: unit.node.coverVersion,
    ext: unit.node.coverExt,
    bestThumb: top?.thumb ?? '',
  );
  if (pick.isEmpty) return '';
  final basics = unit.allBasics;
  final basic = top?.basic ?? (basics.isEmpty ? null : basics.first);
  if (basic == null) return '';
  if (thumbUrlOf != null) return thumbUrlOf(basic, pick.path);
  final base = basic.serverBase.trim().isNotEmpty
      ? basic.serverBase
      : unit.node.serverBase;
  return absoluteMediaUrl(base, lib: basic.id, path: pick.path);
}

/// 单元库卡片的鉴权头：媒体按基础库路由，用子树第一个基础库的连接。
Map<String, String> unitHeadersOf(
  UnitLibrary unit,
  Map<String, String> Function([String? lib])? headersOf,
) {
  if (headersOf == null) return const <String, String>{};
  final basics = unit.allBasics;
  return basics.isEmpty ? headersOf(null) : headersOf(basics.first.id);
}

/// 基础库卡片/基础库页的封面 URL（优先级高 → 低）：
///  1. [preset]：调用方已解析好的地址（自定义封面等）；
///  2. 本库「App 播放量最高」作品的封面；
///  3. 空串 → 卡片回退默认图标。
String basicCoverUrl(BasicLib basic, {String preset = ''}) {
  final p = preset.trim();
  if (p.isNotEmpty) return p;
  final top = topPlayed(WorkPlaysStore.countsFor(basic.id));
  final pick = pickBasicCover(
    rel: basic.rel,
    version: basic.coverVersion,
    ext: basic.coverExt,
    bestThumb: top?.thumb ?? '',
  );
  if (pick.isEmpty) return '';
  return absoluteMediaUrl(basic.serverBase, lib: basic.id, path: pick.path);
}

/// 封面缩略图：有图显示图片（带鉴权头、按显示尺寸解码），无图显示默认图标。
class _CoverThumb extends StatelessWidget {
  final String url;
  final double size;
  final IconData fallbackIcon;
  final Color fallbackColor;
  final Map<String, String> headers;

  const _CoverThumb({
    super.key,
    required this.url,
    required this.size,
    required this.fallbackIcon,
    required this.fallbackColor,
    this.headers = const <String, String>{},
  });

  Widget _fallback() => Icon(fallbackIcon,
      color: fallbackColor, size: size * 0.44);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 缩略图按「显示尺寸 × 像素比」解码，避免整张大图进内存。
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final px = (size * (dpr <= 0 ? 1.0 : dpr)).round();
    final box = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fallbackColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: url.isEmpty
          ? _fallback()
          : CachedNetworkImage(
              imageUrl: url,
              httpHeaders: headers,
              fit: BoxFit.cover,
              memCacheWidth: px < 1 ? 1 : px,
              fadeInDuration: Duration.zero,
              errorWidget: (_, __, ___) => _fallback(),
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
  final void Function(UnitLibrary unit) onToggleUnitStar;
  final void Function(BasicLib b) onTapBasic;
  final VoidCallback onOpenStars;
  final UnitCoverOf? unitCoverOf;
  /// 鉴权头（按基础库 id）；为空时封面请求不带头（公开媒体）。
  final Map<String, String> Function([String? lib])? headersOf;

  const UnitLibraryHomeView({
    super.key,
    required this.tree,
    required this.stars,
    required this.onOpenUnit,
    required this.onToggleUnitStar,
    required this.onTapBasic,
    required this.onOpenStars,
    this.unitCoverOf,
    this.headersOf,
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
        // 与其他卡片一样铺成网格，单元库卡片尺寸更大。
        if (units.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 260,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.02,
            ),
            itemCount: units.length,
            itemBuilder: (_, i) {
              final u = units[i];
              return UnitLibraryCard(
                unit: u,
                coverUrl: unitCoverOf?.call(u) ?? '',
                headers: unitHeadersOf(u, headersOf),
                starred: stars.contains(u.id),
                onToggleStar: () => onToggleUnitStar(u),
                onTap: () => onOpenUnit(u),
              );
            },
          ),
      ],
    );
  }
}

/// 「星标单元库」入口（单元库才有星标资格）：点进单独的选择页。
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
                child: Text('星标单元库',
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

/// 星标单元库页：星标只属于单元库，基础库不再单独收藏。
class StarredUnitsPage extends StatelessWidget {
  final List<UnitLibrary> units;
  final void Function(UnitLibrary unit) onOpenUnit;
  final void Function(UnitLibrary unit) onToggleUnitStar;
  final UnitCoverOf? unitCoverOf;
  /// 鉴权头（按基础库 id）；为空时封面请求不带头（公开媒体）。
  final Map<String, String> Function([String? lib])? headersOf;

  const StarredUnitsPage({
    super.key,
    required this.units,
    required this.onOpenUnit,
    required this.onToggleUnitStar,
    this.unitCoverOf,
    this.headersOf,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('星标单元库'),
          actions: const [HomeAction()]),
      body: units.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '还没有星标的单元库\n在单元库卡片右侧点星标即可加入',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.02,
              ),
              itemCount: units.length,
              itemBuilder: (_, i) {
                final u = units[i];
                return UnitLibraryCard(
                  unit: u,
                  coverUrl: unitCoverOf?.call(u) ?? '',
                  headers: unitHeadersOf(u, headersOf),
                  starred: true,
                  onToggleStar: () => onToggleUnitStar(u),
                  onTap: () => onOpenUnit(u),
                );
              },
            ),
    );
  }
}

/// 单元库卡片（大）：与基础库卡片同一形状/排版（圆角 12、封面缩略、标题、
/// 作者/作品数），但整体面积略大（高 132、封面 72）。
class UnitLibraryCard extends StatelessWidget {
  /// 卡片高度（略大于基础库卡片）。
  static const double height = 150;

  /// 封面缩略尺寸（略大于基础库卡片）。
  static const double coverSize = 72;

  /// 与基础库卡片统一的圆角。
  static const double radius = 12;

  final UnitLibrary unit;

  /// 为空表示纯展示卡片（单元库详情页顶部的自身卡片），不显示进入箭头。
  final VoidCallback? onTap;
  final String coverUrl;
  /// 封面请求的鉴权头（媒体接口需要 Basic 认证）。
  final Map<String, String> headers;

  /// 星标标记的是「单元库」，不是基础库。
  final bool starred;
  final VoidCallback? onToggleStar;

  /// 右上角爬虫配置入口：只有非顶级单元库才显示。
  final VoidCallback? onConfigure;

  const UnitLibraryCard({
    super.key,
    required this.unit,
    this.onTap,
    this.coverUrl = '',
    this.headers = const <String, String>{},
    this.starred = false,
    this.onToggleStar,
    this.onConfigure,
  });

  /// 顶级单元库（SECRET，rel 为空）没有独立爬虫配置；只有下级单元库才有。
  static bool canConfigure(UnitLibrary unit) => unit.rel.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final server = unit.node.serverLabel;
    final showCrawler = onConfigure != null && canConfigure(unit);
    final top = unit.rel.trim().isEmpty || unit.id == 'secret';
    final badgeColor =
        top ? const Color(0xFF6B7280) : Color(LibraryBadge.colorFor(unit.id));
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          key: ValueKey(onTap == null
              ? 'unit-head-${unit.id}'
              : 'unit-${unit.id}'),
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          // 与基础库/作品卡相同的卡片形状：封面在上、词条、名称、统计，
          // 只是整体更大；由外层网格决定宽高，不写死尺寸。
          child: Padding(
            key: ValueKey('unit-card-${unit.id}'),
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 10),
            child: Stack(children: [
              Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ValueListenableBuilder<int>(
                    valueListenable: WorkPlaysStore.revision,
                    builder: (_, __, ___) => _CoverThumb(
                      key: ValueKey('unit-cover-${unit.id}'),
                      url: unitCoverUrl(unit, customUrl: coverUrl),
                      headers: headers,
                      size: coverSize,
                      fallbackIcon: Icons.folder_copy_outlined,
                      fallbackColor: scheme.primary,
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    unit.name.length > 10
                        ? '${unit.name.substring(0, 10)}…'
                        : unit.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      color:
                          Color(LibraryBadge.textColorOn(badgeColor.toARGB32())),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(unit.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15,
                          height: 1.2,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 4),
                Text('${formatCount(unit.authors)} 作者 · '
                    '${formatCount(unit.works)} 作品',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
                // 大库描述：该单元库包含的基础库数量。
                Text('${unit.basicCount} 个基础库',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
                if (server.isNotEmpty)
                  Text(server,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
              // 与基础库卡片一致的右上角操作区（爬虫配置 / 星标）。
              Positioned(
                top: 0,
                right: 0,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (showCrawler)
                    IconButton(
                      key: ValueKey('unit-crawler-${unit.id}'),
                      tooltip: '爬虫配置',
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints.tightFor(width: 30, height: 30),
                      icon: const Icon(Icons.settings_ethernet),
                      onPressed: onConfigure,
                    ),
                  if (onToggleStar != null)
                    IconButton(
                      key: ValueKey('unit-star-${unit.id}'),
                      tooltip: starred ? '取消星标' : '星标单元库',
                      iconSize: 20,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints.tightFor(width: 30, height: 30),
                      icon: Icon(
                        starred ? Icons.star : Icons.star_border,
                        color: starred ? Colors.amber : Colors.grey,
                      ),
                      onPressed: onToggleStar,
                    ),
                ]),
              ),
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
  final void Function(UnitLibrary unit) onToggleUnitStar;
  final void Function(BasicLib b) onTapBasic;
  final CoverOf? coverOf;
  final UnitCoverOf? unitCoverOf;
  /// 鉴权头（按基础库 id）；为空时封面请求不带头（公开媒体）。
  final Map<String, String> Function([String? lib])? headersOf;
  /// L5-D：非顶级单元库可配置独立爬虫（SECRET 顶级不显示入口）。
  final void Function(UnitLibrary unit)? onConfigureUnit;

  const UnitLibraryPage({
    super.key,
    required this.unit,
    required this.stars,
    required this.onOpenUnit,
    required this.onToggleUnitStar,
    required this.onTapBasic,
    this.coverOf,
    this.unitCoverOf,
    this.headersOf,
    this.onConfigureUnit,
  });

  @override
  Widget build(BuildContext context) {
    // 只列直属基础库；下级基础库跟随各自的单元库，避免 SECRET 直通全部。
    final sorted = unit.basics;
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
      appBar: AppBar(title: Text(unit.name), actions: [
        const HomeAction(),
        if (onConfigureUnit != null && UnitLibraryCard.canConfigure(unit))
          IconButton(
            key: ValueKey('unit-crawler-${unit.id}'),
            tooltip: '爬虫配置',
            icon: const Icon(Icons.settings_ethernet),
            onPressed: () => onConfigureUnit!(unit),
          ),
      ]),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // 进入单元库后不再重复显示自身卡片，直接从下级单元库/基础库开始。
          if (unit.children.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 2),
              child: Text('下级单元库',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.02,
              ),
              itemCount: unit.children.length,
              itemBuilder: (c, i) {
                final sub = unit.children[i];
                return UnitLibraryCard(
                  unit: sub,
                  coverUrl: unitCoverOf?.call(sub) ?? '',
                  headers: unitHeadersOf(sub, headersOf),
                  starred: stars.contains(sub.id),
                  onToggleStar: () => onToggleUnitStar(sub),
                  onTap: () => onOpenUnit(sub),
                  onConfigure: onConfigureUnit == null
                      ? null
                      : () => onConfigureUnit!(sub),
                );
              },
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
                coverUrl: coverOf?.call(sorted[i]) ?? '',
                headers: headersOf?.call(sorted[i].id) ?? const {},
                unitLabel: unit.name,
                unitKey: unit.id,
                onTap: () => onTapBasic(sorted[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 基础库卡片（中）：来源词条、名称、作者/作品数。
class BasicLibCard extends StatelessWidget {
  final BasicLib basic;
  final VoidCallback onTap;
  final String coverUrl;
  /// 封面请求的鉴权头（媒体接口需要 Basic 认证）。
  final Map<String, String> headers;
  /// 所属单元库（节点文件夹）。只有单元库有资格生成位置词条；
  /// 为空表示该卡片不在单元库语境下，不显示词条。
  final String unitLabel;
  final String unitKey;

  const BasicLibCard({
    super.key,
    required this.basic,
    required this.onTap,
    this.coverUrl = '',
    this.headers = const <String, String>{},
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
    // K17：有单元库就用单元库词条；没有则回退到「库名」灰色词条。
    final hasUnit = unitLabel.isNotEmpty;
    final text = badgeText(hasUnit ? unitLabel : basic.name);
    // 顶级节点库（SECRET）下发的词条固定灰色；其余按单元库配色。
    final isTop = !hasUnit || unitKey == 'secret';
    final color = isTop
        ? const Color(0xFF6B7280)
        : Color(LibraryBadge.colorFor(unitKey.isEmpty ? unitLabel : unitKey));
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
                ValueListenableBuilder<int>(
                  valueListenable: WorkPlaysStore.revision,
                  builder: (_, __, ___) => _CoverThumb(
                    key: ValueKey('basic-cover-${basic.id}'),
                    url: basicCoverUrl(basic, preset: coverUrl),
                    headers: headers,
                    size: 26,
                    fallbackIcon: Icons.folder_outlined,
                    fallbackColor: scheme.primary,
                  ),
                ),
                const Spacer(),
              ]),
              const SizedBox(height: 5),
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
