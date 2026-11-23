import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'cover_cache.dart';
import 'cover_menu.dart';
import 'cover_upload.dart';
import 'decode_plan.dart';
import 'library_badge.dart';
import 'library_corner_badge.dart';
import 'library_tree.dart';
import 'lib_cover.dart';
import 'media_resize.dart';
import 'home_action.dart';
import 'lib_refresh_button.dart';
import 'scroll_decode.dart';
import 'star_store.dart';
import 'thumb_image.dart';
import 'thumb_prefetch.dart';
import 'unit_library.dart';
import 'work_plays.dart';

/// L5-C：卡片封面（空串表示用默认图）。由调用方解析 `_cover/` 与播放量。
typedef CoverOf = String Function(BasicLib basic);
typedef UnitCoverOf = String Function(UnitLibrary unit);

/// owner 2026-11-23：按「基础库 id + 单元库 rel」生成卡片封面菜单动作。
/// 返回 null 表示该卡片没有封面入口（例如缺少基础库 id）。
typedef CoverMenuOf = CoverMenuActions? Function(String libId, String unitRel);

/// owner 2026-11-22：卡片「快速刷新」。返回一句话结果用于提示；
/// 返回 null 表示不提示（例如被防抖拦下）。
typedef LibRefreshOf = Future<String?> Function(String libId, String unitRel);

// ---------------------------------------------------------------------------
// 库卡片统一规格（单元库卡片 / 基础库卡片共用）
//
// 两类卡片只允许在「面积」上不同：圆角、底部渐变、信息层级（名称 → 作者/
// 作品 → 服务器）与文字比例必须一致。外层间距由调用方网格
// （padding 12 / spacing 10）统一控制，卡片本身不再自带外边距。
// ---------------------------------------------------------------------------

/// 库卡片圆角（单元库与基础库必须一致）。
const double kLibCardRadius = 12;

/// 库卡片网格外边距与卡片间距（主页 / 单元库页 / 星标页统一）。
const EdgeInsets kLibGridPadding = EdgeInsets.symmetric(horizontal: 12);
const double kLibGridSpacing = 10;

/// 库卡片底部信息层的统一渐变。
const LinearGradient kLibCardGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0x00000000), Color(0xC7000000)],
);

/// 单元库卡片的显示宽度（网格 `maxCrossAxisExtent: 260`）。
const double kUnitCardDisplayWidth = 260;

/// 单元库卡片解码宽度上限（260dp × 3x）。
const int kUnitCardMaxDecodeWidth = 780;

/// 单元库卡片封面解码宽度（卡片渲染与首屏预热必须共用）。
///
/// 基础库卡片是 220dp、单元库卡片是 260dp；两者共用 `_UnitCoverFill`，
/// 以前统一按 220dp 解码，260dp 的单元库卡片在高 DPI 下被放大 ~18%。
int unitCardDecodeWidth(double devicePixelRatio) => decodeWidthForDisplay(
      kUnitCardDisplayWidth,
      devicePixelRatio,
      maxWidth: kUnitCardMaxDecodeWidth,
    );

/// 库卡片底部信息层：词条（基础库才有）→ 名称 → 统计 → 服务器。
///
/// [dense] 用于网格更小的基础库卡片（字号/内边距各缩一档），层级与
/// 相对字重保持一致，避免两套卡片各写一份排版。
class LibCardInfo extends StatelessWidget {
  final Widget? badge;
  final String title;
  final String stats;
  final String server;
  final bool dense;

  /// 所属单元库 id（`rel` 或 `node:rel`）；给出时标题追加该库 emoji 后缀。
  /// 与作者词条共用同一套 emoji 规则，保证「词条看到什么，卡片标题就是什么」。
  final String unitId;

  const LibCardInfo({
    super.key,
    this.badge,
    required this.title,
    required this.stats,
    this.server = '',
    this.dense = false,
    this.unitId = '',
  });

  @override
  Widget build(BuildContext context) {
    // D2：所有库卡片标题统一去掉目录名前的排序序号（受「省略编号」开关控制）；
    // 再追加所属单元库的 emoji 后缀（与作者卡片词条同一套规则）。
    final titleText =
        LibraryBadge.labelWithEmoji(LibraryBadge.stripIndex(title), unitId);
    return Container(
      padding: dense
          ? const EdgeInsets.fromLTRB(10, 22, 10, 8)
          : const EdgeInsets.fromLTRB(12, 26, 12, 10),
      decoration: const BoxDecoration(gradient: kLibCardGradient),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge != null) ...[
            badge!,
            const SizedBox(height: 4),
          ],
          Text(titleText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: dense ? 13 : 15,
                  height: 1.2,
                  color: Colors.white,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(stats,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, color: Colors.white70)),
          if (server.isNotEmpty)
            Text(server,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Colors.white54)),
        ],
      ),
    );
  }
}

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

/// 单元库封面 URL（优先级高 → 低）：
///  1. 调用方解析好的 [customUrl]（主页/单元库页的完整封面链）；
///  2. owner 手动设置且已解析到当前服务器的封面（零散调用处只能拿相对
///     媒体路径时，用节点自带 serverBase 拼）；
///  3. 自定义 `_cover/<version>.<ext>`；
///  4. 子树内「App 播放量最高」作品的封面（含下级单元库）；
///  5. 空串 → 卡片回退默认图标。
String unitCoverUrl(
  UnitLibrary unit, {
  String customUrl = '',
  String Function(BasicLib basic, String thumb)? thumbUrlOf,
  String firstThumb = '',
  bool ignoreManual = false,
}) {
  final preset = customUrl.trim();
  // 调用方已解析好的地址（自定义封面，鉴权/路由由调用方掌握）优先。
  if (!ignoreManual && preset.isNotEmpty) return preset;
  // 0.9.35：owner 手动设的单元库封面（服务端 `cover.u`）。
  final manual = ignoreManual ? '' : unit.node.coverUrl.trim();
  if (manual.isNotEmpty) {
    final base = unit.node.serverBase.trim();
    if (base.isNotEmpty) {
      return '${base.replaceFirst(RegExp(r'/+$'), '')}$manual';
    }
  }
  final top = topPlayedInUnit(unit);
  final pick = pickUnitCover(
    rel: unit.rel,
    version: ignoreManual ? '' : unit.node.coverVersion,
    ext: unit.node.coverExt,
    bestThumb: top?.thumb ?? '',
    // 首张作品封面始终作为「最后一级」传入：有播放记录但那张记录的缩略图
    // 不可用（视频路径/空）时，仍能落到库内第一张作品的图上，而不是空白卡片。
    firstThumb: firstThumb,
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
///  1. [preset]：调用方已解析好的地址（手动 `_cover/` 等）；
///  2. 爬虫脚本抓到的封面（服务端索引 `cv`）；
///  3. 本库「App 播放量最高」作品的封面（有图文作品时优先图文图片）；
///  4. 服务端下发的首张作品封面 `fc`（[BasicLib.firstCover]）；
///  5. 空串 → 卡片回退默认图标。
String basicCoverUrl(BasicLib basic,
    {String preset = '', String firstThumb = '', bool ignoreCustom = false}) {
  final p = ignoreCustom ? '' : preset.trim();
  if (p.isNotEmpty) return p;
  final top = topPlayed(WorkPlaysStore.countsFor(basic.id));
  // `fc` 只在调用方没指定时兜底用，保证「库 → 封面」只有一套取値口径。
  final fb = firstThumb.trim().isNotEmpty ? firstThumb : basic.firstCover;
  // 服务端把自定义封面写在「库根/_cover/」，而 `/media/<库id>/` 已指向库根；
  // 再拼 rel 会变成 `<rel>/_cover/...` → 404（实测 2026-11-21）。
  final pick = pickBasicCover(
    rel: '',
    version: ignoreCustom ? '' : basic.coverVersion,
    ext: basic.coverExt,
    crawlerThumb: basic.crawlerCover,
    bestThumb: top?.thumb ?? '',
    firstThumb: fb,
  );
  if (pick.isEmpty) return '';
  return absoluteMediaUrl(basic.serverBase, lib: basic.id, path: pick.path);
}

/// L5 卡片体系：单元库卡片 > 基础库卡片 > 作品卡片（尺寸递减）。
///
/// 主页只铺「单元库」卡片 + 一个「星标基础库」入口；
/// 点进单元库才看到它的下级单元库与基础库卡片。
class UnitLibraryHomeView extends StatefulWidget {
  final UnitLibrary tree;
  final Set<String> stars;
  final void Function(UnitLibrary unit) onOpenUnit;
  final void Function(UnitLibrary unit) onToggleUnitStar;
  final void Function(BasicLib b) onTapBasic;
  final VoidCallback onOpenStars;
  final UnitCoverOf? unitCoverOf;

  /// 鉴权头（按基础库 id）；为空时封面请求不带头（公开媒体）。
  final Map<String, String> Function([String? lib])? headersOf;

  /// C2：本地选图上传封面；为空时不显示卡片上的封面按钮。
  final CoverUploader? coverUploader;

  /// owner 2026-11-23：封面入口（本地选图 / 过往封面 / 恢复自动 / 清除）。
  /// 为空时回退到只有「本地选图」的旧入口。
  final CoverMenuOf? coverMenuOf;

  /// P3：顶级单元库卡片的连接状态文案（如「已连接」「已断连」）；空串不显示。
  final String Function(UnitLibrary unit)? statusOf;

  /// P3：顶级单元库卡片只用 owner 设过的封面（自定义 `_cover/` 或服务端
  /// `cover.u`）；空串表示未设封面 → 卡片用词条色块占位，**不取自动封面**。
  final UnitCoverOf? topCoverOf;

  /// owner 2026-11-22：卡片快速刷新；为空不显示刷新按钮。
  final LibRefreshOf? refreshOf;

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
    this.coverUploader,
    this.coverMenuOf,
    this.statusOf,
    this.topCoverOf,
    this.refreshOf,
  });

  @override
  State<UnitLibraryHomeView> createState() => _UnitLibraryHomeViewState();
}

class _UnitLibraryHomeViewState extends State<UnitLibraryHomeView> {
  @override
  void initState() {
    super.initState();
    _schedulePrefetch();
  }

  /// C2：选本地图上传单元库封面，结果用 SnackBar 提示。
  Future<void> _pickCover(String libId, String unitRel) async {
    final up = widget.coverUploader;
    if (up == null) return;
    final r = await up(libId: libId, unitRel: unitRel);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(r.message)));
  }

  @override
  void didUpdateWidget(covariant UnitLibraryHomeView old) {
    super.didUpdateWidget(old);
    if (!identical(old.tree, widget.tree) ||
        old.unitCoverOf != widget.unitCoverOf) {
      _schedulePrefetch();
    }
  }

  void _schedulePrefetch() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchCovers());
  }

  /// 0.9.30：主页单元库首屏封面预热。
  ///
  /// 卡片封面按 480px 取图（服务端已预热），但首屏仍是逐张请求，卡片会先露
  /// 底色/图标。数据一到就按网格几何预热首页可见的几张，provider 与
  /// `_UnitCoverFill` 完全一致，失败交给卡片自己重试。
  void _prefetchCovers() {
    if (!mounted) return;
    final units = widget.tree.children;
    if (units.isEmpty) return;
    final mq = MediaQuery.maybeOf(context);
    if (mq == null) return;
    final n = firstScreenThumbCount(
      viewportWidth: mq.size.width,
      viewportHeight: mq.size.height,
      maxCrossAxisExtent: 260,
      padding: kLibGridPadding.left,
      crossSpacing: kLibGridSpacing,
      mainSpacing: kLibGridSpacing,
      aspectRatio: 1.02,
      screens: 1,
      maxItems: 8,
    );
    if (n <= 0) return;
    final urls = <String>[];
    final headers = <String, Map<String, String>>{};
    for (final u in units.take(n)) {
      final cover = widget.unitCoverOf?.call(u) ?? '';
      if (cover.isEmpty) continue;
      final url = withImageWidth(cover, kCardImageWidth);
      urls.add(url);
      headers[url] = unitHeadersOf(u, widget.headersOf);
    }
    if (urls.isEmpty) return;
    // 与 `_UnitCoverFill` 共用同一个解码宽度（单元库卡片 260dp），缓存键一致才命中。
    final px = unitCardDecodeWidth(mq.devicePixelRatio);
    ThumbPrefetch.instance.run(
      urls,
      limit: n,
      provider: (u) => thumbImageProvider(
        u,
        decodeWidth: px,
        headers: headers[u] ?? const <String, String>{},
        cacheManager: DiziCache.manager,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 0.9.6：星标数量/点亮状态与 StarStore 保持一致。
    return AnimatedBuilder(
      animation: StarStore.instance,
      builder: (context, _) => _buildView(context),
    );
  }

  Widget _buildView(BuildContext context) {
    final liveStars = StarStore.instance.ready ? StarStore.instance.ids : widget.stars;
    final units = widget.tree.children;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(children: [
            const Icon(Icons.layers_outlined, size: 18),
            const SizedBox(width: 6),
            // P3：首页只列顶级单元库（＝各连接的媒体库根）。
            const Text('媒体库',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${units.length} 个媒体库',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ]),
        ),
        StarredEntryCard(count: liveStars.length, onTap: widget.onOpenStars),
        if (units.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 24),
            child: Text('当前连接下没有可显示的媒体库',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
        // 与其他卡片一样铺成网格，单元库卡片尺寸更大。
        if (units.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: kLibGridPadding,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 260,
              mainAxisSpacing: kLibGridSpacing,
              crossAxisSpacing: kLibGridSpacing,
              childAspectRatio: 1.02,
            ),
            itemCount: units.length,
            itemBuilder: (_, i) {
              final u = units[i];
              final coverLib =
                  u.allBasics.isNotEmpty ? u.allBasics.first.id : '';
              // P3：首页卡片＝顶级单元库卡片。只用 owner 设过的封面，
              // 未设则用该顶级单元库的词条色块占位，不再拿作品图冒充库封面。
              final tint = LibraryBadge.topColorFor(u.id) ??
                  LibraryBadge.colorForUnit(u.id,
                      order: UnitBadgeRegistry.order);
              return UnitLibraryCard(
                unit: u,
                topCard: true,
                fallbackTint: tint,
                connectionStatus: widget.statusOf?.call(u) ?? '',
                coverUrl: (widget.topCoverOf ?? widget.unitCoverOf)?.call(u) ?? '',
                coverUrlOf: widget.topCoverOf ?? widget.unitCoverOf,
                headers: unitHeadersOf(u, widget.headersOf),
                starred: liveStars.contains(u.id),
                onToggleStar: () => widget.onToggleUnitStar(u),
                onTap: () => widget.onOpenUnit(u),
                coverMenu: widget.coverMenuOf?.call(coverLib, u.rel),
                onQuickRefresh: widget.refreshOf == null || coverLib.isEmpty
                    ? null
                    : () => widget.refreshOf!(coverLib, u.rel),
                onSetCover: widget.coverMenuOf != null
                    ? null
                    : (widget.coverUploader == null || coverLib.isEmpty
                        ? null
                        : () => _pickCover(coverLib, u.rel)),
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

  const StarredEntryCard({super.key, required this.count, required this.onTap});

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
class StarredUnitsPage extends StatefulWidget {
  final List<UnitLibrary> units;
  final void Function(UnitLibrary unit) onOpenUnit;
  final void Function(UnitLibrary unit) onToggleUnitStar;
  final UnitCoverOf? unitCoverOf;

  /// 鉴权头（按基础库 id）；为空时封面请求不带头（公开媒体）。
  final Map<String, String> Function([String? lib])? headersOf;

  /// C2：本地选图上传封面；为空时不显示卡片上的封面按钮。
  final CoverUploader? coverUploader;

  /// owner 2026-11-23：卡片封面合并入口。
  final CoverMenuOf? coverMenuOf;

  /// 右上角爬虫配置入口（与主页/详情页单元库卡片一致；非顶级才显示）。
  final void Function(UnitLibrary unit)? onConfigureUnit;

  /// owner 2026-11-22：卡片快速刷新。
  final LibRefreshOf? refreshOf;

  const StarredUnitsPage({
    super.key,
    required this.units,
    required this.onOpenUnit,
    required this.onToggleUnitStar,
    this.unitCoverOf,
    this.headersOf,
    this.coverUploader,
    this.coverMenuOf,
    this.onConfigureUnit,
    this.refreshOf,
  });

  @override
  State<StarredUnitsPage> createState() => _StarredUnitsPageState();
}

class _StarredUnitsPageState extends State<StarredUnitsPage> {
  late List<UnitLibrary> units = List<UnitLibrary>.from(widget.units);

  @override
  void initState() {
    super.initState();
    // 0.9.32：星标页首屏封面预热。网格几何与主页单元库卡片一致，
    // 只预热一屏，provider/鉴权头与 `UnitLibraryCard` 完全相同。
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchCovers());
  }

  /// C2：选本地图上传封面（单元库或基础库），结果用 SnackBar 提示。
  Future<void> _pickCover(String libId, String unitRel) async {
    final up = widget.coverUploader;
    if (up == null) return;
    final r = await up(libId: libId, unitRel: unitRel);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(r.message)));
  }

  void _prefetchCovers() {
    if (!mounted || units.isEmpty) return;
    final mq = MediaQuery.maybeOf(context);
    if (mq == null) return;
    final n = firstScreenThumbCount(
      viewportWidth: mq.size.width,
      viewportHeight: mq.size.height,
      maxCrossAxisExtent: 260,
      padding: 12,
      crossSpacing: kLibGridSpacing,
      mainSpacing: kLibGridSpacing,
      aspectRatio: 1.02,
      screens: 1,
      maxItems: 8,
    );
    if (n <= 0) return;
    final urls = <String>[];
    final headers = <String, Map<String, String>>{};
    for (final u in units.take(n)) {
      final cover = widget.unitCoverOf?.call(u) ?? '';
      if (cover.isEmpty) continue;
      final url = withImageWidth(cover, kCardImageWidth);
      if (urls.contains(url)) continue;
      urls.add(url);
      headers[url] = unitHeadersOf(u, widget.headersOf);
    }
    if (urls.isEmpty) return;
    // 与 `_UnitCoverFill` 共用同一个解码宽度（单元库卡片 260dp），缓存键一致才命中。
    final px = unitCardDecodeWidth(mq.devicePixelRatio);
    ThumbPrefetch.instance.run(
      urls,
      limit: n,
      provider: (u) => thumbImageProvider(
        u,
        decodeWidth: px,
        headers: headers[u] ?? const <String, String>{},
        cacheManager: DiziCache.manager,
      ),
    );
  }

  void _toggle(UnitLibrary u) {
    setState(() => units.removeWhere((e) => e.id == u.id));
    widget.onToggleUnitStar(u);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('星标单元库'), actions: const [HomeAction()]),
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
          : ScrollDecodeScope(
              child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260,
                mainAxisSpacing: kLibGridSpacing,
                crossAxisSpacing: kLibGridSpacing,
                childAspectRatio: 1.02,
              ),
              itemCount: units.length,
              itemBuilder: (_, i) {
                final u = units[i];
                final coverLib =
                    u.allBasics.isNotEmpty ? u.allBasics.first.id : '';
                return UnitLibraryCard(
                  unit: u,
                  coverUrl: widget.unitCoverOf?.call(u) ?? '',
                  coverUrlOf: widget.unitCoverOf,
                  headers: unitHeadersOf(u, widget.headersOf),
                  starred: true,
                  onToggleStar: () => _toggle(u),
                  onTap: () => widget.onOpenUnit(u),
                  coverMenu: widget.coverMenuOf?.call(coverLib, u.rel),
                  onQuickRefresh: widget.refreshOf == null || coverLib.isEmpty
                      ? null
                      : () => widget.refreshOf!(coverLib, u.rel),
                  onSetCover: widget.coverMenuOf != null
                      ? null
                      : (widget.coverUploader == null || coverLib.isEmpty
                          ? null
                          : () => _pickCover(coverLib, u.rel)),
                  onConfigure: (widget.onConfigureUnit == null ||
                          !UnitLibraryCard.canConfigure(u))
                      ? null
                      : () => widget.onConfigureUnit!(u),
                );
              },
              ),
            ),
    );
  }
}

/// 单元库卡片（大）：与基础库卡片同一形状/排版（圆角 [kLibCardRadius]、
/// 满幅封面 + 底部渐变信息层），只比基础库卡片面积更大。
class UnitLibraryCard extends StatefulWidget {
  /// 卡片高度（略大于基础库卡片）。
  static const double height = 150;

  /// 封面缩略尺寸（略大于基础库卡片）。
  static const double coverSize = 72;

  /// 与基础库卡片统一的圆角。
  static const double radius = kLibCardRadius;

  final UnitLibrary unit;

  /// 为空表示纯展示卡片（单元库详情页顶部的自身卡片），不显示进入箭头。
  final VoidCallback? onTap;
  final String coverUrl;

  /// 0.9.75：封面地址按需计算（优先级见 [unitCoverUrl]）。
  ///
  /// 传入时优先于 [coverUrl]，并在卡片自己的播放量监听里重新求值——
  /// 播放某个库后只有这张卡重算封面，不必让整页 `setState` 重建网格。
  final String Function(UnitLibrary unit)? coverUrlOf;

  /// 封面请求的鉴权头（媒体接口需要 Basic 认证）。
  final Map<String, String> headers;

  /// 星标标记的是「单元库」，不是基础库。
  final bool starred;
  final VoidCallback? onToggleStar;

  /// 右上角爬虫配置入口：只有非顶级单元库才显示。
  final VoidCallback? onConfigure;

  /// C2：本地选图上传封面（为空不显示按钮）。
  final VoidCallback? onSetCover;

  /// owner 2026-11-23：封面合并入口。非空时右上角只留一个「封面设置」，
  /// 点击弹出四项菜单；为空时回退到 [onSetCover] 直连选图。
  final CoverMenuActions? coverMenu;

  /// P3：首页顶级单元库卡片。为 true 时**不使用自动封面**，
  /// 未设置封面就用词条色块占位（[fallbackTint]），避免首页拿作品图充当库封面。
  final bool topCard;

  /// 无封面时的占位底色（顶级单元库＝词条色）；为空则回退通用灰。
  final int? fallbackTint;

  /// 连接状态文案（如「已连接」「已断连」）；空串不显示。
  final String connectionStatus;

  /// 快速刷新（该单元库子树里第一个基础库 id 由调用方关入）；
  /// 为空时不显示刷新按钮。
  final Future<String?> Function()? onQuickRefresh;

  const UnitLibraryCard({
    super.key,
    required this.unit,
    this.onTap,
    this.coverUrl = '',
    this.coverUrlOf,
    this.headers = const <String, String>{},
    this.starred = false,
    this.onToggleStar,
    this.onConfigure,
    this.onSetCover,
    this.coverMenu,
    this.topCard = false,
    this.fallbackTint,
    this.connectionStatus = '',
    this.onQuickRefresh,
  });

  /// 顶级单元库（SECRET，rel 为空）没有独立爬虫配置；只有下级单元库才有。
  static bool canConfigure(UnitLibrary unit) => unit.rel.trim().isNotEmpty;

  @override
  State<UnitLibraryCard> createState() => _UnitLibraryCardState();
}

class _UnitLibraryCardState extends State<UnitLibraryCard> {
  /// 菜单操作成功后的临时覆盖：非空直接使用；[_coverAuto] 为 true 时
  /// 按自动封面链重新求值（不读服务端自定义指针）。
  String? _coverOverride;
  bool _coverAuto = false;

  @override
  void didUpdateWidget(covariant UnitLibraryCard old) {
    super.didUpdateWidget(old);
    if (old.coverUrl != widget.coverUrl ||
        !identical(old.coverUrlOf, widget.coverUrlOf)) {
      _coverOverride = null;
      _coverAuto = false;
    }
  }

  String _coverUrlNow() {
    if (_coverOverride != null) return _coverOverride!;
    if (_coverAuto) {
      if (widget.topCard) return '';
      return unitCoverUrl(widget.unit, ignoreManual: true);
    }
    return widget.topCard
        ? (widget.coverUrlOf?.call(widget.unit) ?? widget.coverUrl)
        : unitCoverUrl(
            widget.unit,
            customUrl: widget.coverUrlOf?.call(widget.unit) ?? widget.coverUrl,
          );
  }

  Future<void> _openCoverMenu() async {
    final menu = widget.coverMenu;
    if (menu == null) {
      widget.onSetCover?.call();
      return;
    }
    final out = await showCoverMenu(context, menu);
    if (!mounted || out == null) return;
    setState(() {
      _coverAuto = out.auto;
      _coverOverride = out.auto || out.url.isEmpty ? null : out.url;
    });
  }

  @override
  Widget build(BuildContext context) =>
      // 0.9.55：每张卡片单独一层重绘边界——网格滚动、悬停涟漪、
      // 播放次数变化（WorkPlaysStore）只重绘当前卡片，不带动整块网格。
      RepaintBoundary(child: _buildCard(context));

  Widget _buildCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unit = widget.unit;
    final server = unit.node.serverLabel;
    final showCrawler =
        widget.onConfigure != null && UnitLibraryCard.canConfigure(unit);
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(UnitLibraryCard.radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey(widget.onTap == null
            ? 'unit-head-${unit.id}'
            : 'unit-${unit.id}'),
        borderRadius: BorderRadius.circular(UnitLibraryCard.radius),
        onTap: widget.onTap,
        // 封面铺满整张卡片；不贴来源词条；名称与统计压在底部渐变上。
        child: SizedBox.expand(
          key: ValueKey('unit-card-${unit.id}'),
          child: Stack(children: [
            // 封面铺满（自定义封面优先，其次自动获取）。
            Positioned.fill(
              child: ValueListenableBuilder<int>(
                // 0.9.74：只监听本单元库子树内的库，播放别的库不再重建这张卡。
                valueListenable:
                    WorkPlaysStore.libsListenable(unit.allBasics.map((b) => b.id)),
                builder: (_, __, ___) => _UnitCoverFill(
                  key: ValueKey('unit-cover-${unit.id}'),
                  displayWidth: kUnitCardDisplayWidth,
                  url: _coverUrlNow(),
                  headers: widget.headers,
                  fallbackIcon: Icons.folder_copy_outlined,
                  tint: widget.topCard ? widget.fallbackTint : null,
                  libId: unit.allBasics.isNotEmpty
                      ? unit.allBasics.first.id
                      : '',
                ),
              ),
            ),
            // 底部渐变：与基础库卡片共用同一信息层排版。
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LibCardInfo(
                title: unit.name,
                unitId: unit.id,
                stats: '${formatCount(unit.authors)} 作者 · '
                    '${formatCount(unit.works)} 作品',
                server: [widget.connectionStatus, server]
                    .where((e) => e.isNotEmpty)
                    .join(' · '),
              ),
            ),
            // P4：左上角种类角标（形状尺寸统一，仅图案不同）。
            Positioned(
              left: kCornerBadgeInset,
              top: kCornerBadgeInset,
              child: LibCornerBadge(
                kind: LibraryCornerBadge.kindOf(
                    isTop: unit.rel.trim().isEmpty, isUnit: true),
              ),
            ),
            // 与基础库卡片一致的右上角操作区（封面 / 爬虫配置 / 星标）。
            Positioned(
              top: 6,
              right: 6,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (widget.onQuickRefresh != null)
                  LibQuickRefreshButton(
                    libId: unit.allBasics.isNotEmpty
                        ? unit.allBasics.first.id
                        : unit.id,
                    onRefresh: widget.onQuickRefresh,
                  ),
                if (widget.coverMenu != null)
                  IconButton(
                    key: ValueKey('unit-cover-btn-${unit.id}'),
                    tooltip: '封面设置',
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints.tightFor(width: 30, height: 30),
                    icon: const Icon(Icons.image_outlined),
                    onPressed: _openCoverMenu,
                  )
                else if (widget.onSetCover != null)
                  IconButton(
                    key: ValueKey('unit-cover-btn-${unit.id}'),
                    tooltip: '本地选图作封面',
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints.tightFor(width: 30, height: 30),
                    icon: const Icon(Icons.image_outlined),
                    onPressed: widget.onSetCover,
                  ),
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
                    onPressed: widget.onConfigure,
                  ),
                if (widget.onToggleStar != null)
                  _StarButton(
                    key: ValueKey('unit-star-${unit.id}'),
                    starred: widget.starred,
                    onTap: widget.onToggleStar!,
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// 单元库封面：铺满整张卡片；无图时显示默认图标。
class _UnitCoverFill extends StatelessWidget {
  final String url;
  final Map<String, String> headers;
  final IconData fallbackIcon;

  /// 卡片的逻辑显示宽度（单元库 260 / 基础库 220），决定解码宽度。
  final double displayWidth;

  /// P3：无封面时的占位底色（顶级单元库用词条色块，不用自动封面）。
  final int? tint;

  /// 该封面属于哪个库：用于「卡片快速刷新」按库精确淘汰缓存。
  final String libId;

  const _UnitCoverFill({
    super.key,
    required this.url,
    required this.headers,
    required this.fallbackIcon,
    this.displayWidth = 220,
    this.tint,
    this.libId = '',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = tint;
    final fallback = Container(
      key: t == null ? null : const ValueKey('unit-cover-tint'),
      color: t == null ? scheme.surfaceContainerHighest : Color(t).withValues(alpha: 0.55),
      alignment: Alignment.center,
      child: Icon(fallbackIcon,
          size: 34,
          color: t == null
              ? scheme.primary
              : Color(LibraryBadge.textColorOn(t)).withValues(alpha: 0.75)),
    );
    if (url.isEmpty) return fallback;
    // 登记「URL → 库」，刷新该库时才能精确删掉它的封面缓存。
    DiziCache.noteUrl(libId, withImageWidth(url, kCardImageWidth));
    return CachedNetworkImage(
      cacheManager: DiziCache.manager,
      // 0.9.24：卡片封面按 480px 取图（服务端 `w=` 缩放并缓存），
      // 避免把爬虫/自定义封面的原始大图整张传给客户端。
      imageUrl: withImageWidth(url, kCardImageWidth),
      httpHeaders: headers,
      // 0.9.119：按卡片真实显示宽度解码（单元库 260dp / 基础库 220dp），
      // 与首屏预热用同一个函数，同一张封面不会因解码宽度不同而二次解码。
      memCacheWidth: decodeWidthForDisplay(
        displayWidth,
        MediaQuery.devicePixelRatioOf(context),
        maxWidth: (displayWidth * 3).ceil(),
      ),
      fit: BoxFit.cover,
      fadeInDuration: Duration.zero,
      errorWidget: (_, __, ___) => fallback,
    );
  }
}

/// 星标按钮：本地状态立即反馈（点亮/取消），再回调保存。
class _StarButton extends StatefulWidget {
  final bool starred;
  final VoidCallback onTap;

  const _StarButton({super.key, required this.starred, required this.onTap});

  @override
  State<_StarButton> createState() => _StarButtonState();
}

class _StarButtonState extends State<_StarButton> {
  late bool _on = widget.starred;

  @override
  void didUpdateWidget(covariant _StarButton old) {
    super.didUpdateWidget(old);
    if (old.starred != widget.starred) _on = widget.starred;
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _on ? '取消星标' : '星标单元库',
      iconSize: 22,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      icon: Icon(_on ? Icons.star : Icons.star_border,
          color: _on ? Colors.amber : Colors.white70),
      onPressed: () {
        setState(() => _on = !_on);
        widget.onTap();
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
            duration: const Duration(milliseconds: 900),
            content: Text(_on ? '已加入星标单元库' : '已取消星标')));
      },
    );
  }
}

/// 单元库详情：下级单元库卡片 + 基础库卡片网格。
class UnitLibraryPage extends StatefulWidget {
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

  /// C2：本地选图上传封面；为空时不显示卡片上的封面按钮。
  final CoverUploader? coverUploader;

  /// owner 2026-11-23：卡片封面合并入口。
  final CoverMenuOf? coverMenuOf;

  /// owner 2026-11-22：卡片快速刷新。
  final LibRefreshOf? refreshOf;

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
    this.coverUploader,
    this.coverMenuOf,
    this.refreshOf,
  });

  @override
  State<UnitLibraryPage> createState() => _UnitLibraryPageState();
}

class _UnitLibraryPageState extends State<UnitLibraryPage> {
  @override
  void initState() {
    super.initState();
    _schedulePrefetch();
  }

  /// C2：选本地图上传封面（单元库/基础库），结果用 SnackBar 提示。
  Future<void> _pickCover(String libId, String unitRel) async {
    final up = widget.coverUploader;
    if (up == null) return;
    final r = await up(libId: libId, unitRel: unitRel);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(r.message)));
  }

  @override
  void didUpdateWidget(covariant UnitLibraryPage old) {
    super.didUpdateWidget(old);
    if (!identical(old.unit, widget.unit) ||
        old.coverOf != widget.coverOf ||
        old.unitCoverOf != widget.unitCoverOf) {
      _schedulePrefetch();
    }
  }

  void _schedulePrefetch() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchCovers());
  }

  /// 0.9.31：单元库页首屏封面预热。
  ///
  /// 进单元库后第一屏是下级单元库卡片与基础库卡片，两者此前都是逐张请求，
  /// 会先露底色再出图。这里按两个网格各自的真实几何算张数，URL 与卡片
  /// 用的是同一套解析（`unitCoverUrl` / `basicCoverUrl`），provider 与
  /// `_UnitCoverFill` 完全一致（同 `w=480` + 同鉴权头 + 同 `DiziCache`），
  /// 卡片渲染时直接命中缓存。失败交给卡片自己重试。
  void _prefetchCovers() {
    if (!mounted) return;
    final unit = widget.unit;
    final mq = MediaQuery.maybeOf(context);
    if (mq == null) return;
    final subUrls = <String>[];
    final subHeaders = <String, Map<String, String>>{};
    final basicUrls = <String>[];
    final basicHeaders = <String, Map<String, String>>{};

    void add(List<String> urls, Map<String, Map<String, String>> headers,
        String raw, Map<String, String> h) {
      final cover = raw.trim();
      if (cover.isEmpty) return;
      final url = withImageWidth(cover, kCardImageWidth);
      if (headers.containsKey(url)) return;
      urls.add(url);
      headers[url] = h;
    }

    // 下级单元库卡片：260 / 1.02，一屏、上限 6。
    final subN = firstScreenThumbCount(
      viewportWidth: mq.size.width,
      viewportHeight: mq.size.height,
      maxCrossAxisExtent: 260,
      padding: kLibGridPadding.left,
      crossSpacing: kLibGridSpacing,
      mainSpacing: kLibGridSpacing,
      aspectRatio: 1.02,
      screens: 1,
      maxItems: 6,
    );
    if (subN > 0) {
      for (final sub in unit.children.take(subN)) {
        final cover = widget.unitCoverOf?.call(sub) ?? '';
        add(subUrls, subHeaders, cover, unitHeadersOf(sub, widget.headersOf));
      }
    }

    // 基础库卡片：220 / 0.92，一屏、上限 8（与 `BasicLibCard` 同一封面解析）。
    final basicN = firstScreenThumbCount(
      viewportWidth: mq.size.width,
      viewportHeight: mq.size.height,
      maxCrossAxisExtent: 220,
      padding: kLibGridPadding.left,
      crossSpacing: kLibGridSpacing,
      mainSpacing: kLibGridSpacing,
      aspectRatio: 0.92,
      screens: 1,
      maxItems: 8,
    );
    if (basicN > 0) {
      for (final b in unit.basics.take(basicN)) {
        final cover = basicCoverUrl(b,
            preset: widget.coverOf?.call(b) ?? '', firstThumb: b.firstCover);
        add(basicUrls, basicHeaders, cover,
            widget.headersOf?.call(b.id) ?? const <String, String>{});
      }
    }
    // 两类卡片显示宽度不同（260 / 220），各自用自己的解码宽度预热，
    // 与 `_UnitCoverFill` 传入的 `displayWidth` 一致，缓存键才对得上。
    void prefetch(List<String> urls,
        Map<String, Map<String, String>> headers, int px) {
      if (urls.isEmpty) return;
      ThumbPrefetch.instance.run(
        urls,
        limit: urls.length,
        provider: (u) => thumbImageProvider(
          u,
          decodeWidth: px,
          headers: headers[u] ?? const <String, String>{},
          cacheManager: DiziCache.manager,
        ),
      );
    }

    prefetch(subUrls, subHeaders, unitCardDecodeWidth(mq.devicePixelRatio));
    prefetch(basicUrls, basicHeaders, libCardDecodeWidth(mq.devicePixelRatio));
  }

  @override
  Widget build(BuildContext context) {
    // 0.9.6：星标走 StarStore，入栈后其它页面改动也能即时反映。
    return AnimatedBuilder(
      animation: StarStore.instance,
      builder: (context, _) => _buildPage(context),
    );
  }

  Widget _buildPage(BuildContext context) {
    // 原 `StatelessWidget` 字段在这里落地成局部变量，保持下面的构建代码不动。
    final unit = widget.unit;
    final stars = widget.stars;
    final coverOf = widget.coverOf;
    final unitCoverOf = widget.unitCoverOf;
    final headersOf = widget.headersOf;
    final onOpenUnit = widget.onOpenUnit;
    final onToggleUnitStar = widget.onToggleUnitStar;
    final onTapBasic = widget.onTapBasic;
    final onConfigureUnit = widget.onConfigureUnit;
    final liveStars = StarStore.instance.ready ? StarStore.instance.ids : stars;
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
      appBar: AppBar(
          title: Text(LibraryBadge.labelWithEmoji(
              LibraryBadge.stripIndex(unit.name), unit.id)),
          actions: [
        const HomeAction(),
        if (onConfigureUnit != null && UnitLibraryCard.canConfigure(unit))
          IconButton(
            key: ValueKey('unit-crawler-${unit.id}'),
            tooltip: '爬虫配置',
            icon: const Icon(Icons.settings_ethernet),
            onPressed: () => onConfigureUnit(unit),
          ),
      ]),
      body: ScrollDecodeScope(
        child: ListView(
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
              padding: kLibGridPadding,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260,
                mainAxisSpacing: kLibGridSpacing,
                crossAxisSpacing: kLibGridSpacing,
                childAspectRatio: 1.02,
              ),
              itemCount: unit.children.length,
              itemBuilder: (c, i) {
                final sub = unit.children[i];
                final coverLib =
                    sub.allBasics.isNotEmpty ? sub.allBasics.first.id : '';
                return UnitLibraryCard(
                  unit: sub,
                  coverUrl: unitCoverOf?.call(sub) ?? '',
                  coverUrlOf: unitCoverOf,
                  headers: unitHeadersOf(sub, headersOf),
                  starred: liveStars.contains(sub.id),
                  onToggleStar: () => onToggleUnitStar(sub),
                  onTap: () => onOpenUnit(sub),
                  onConfigure: onConfigureUnit == null
                      ? null
                      : () => onConfigureUnit(sub),
                  coverMenu: widget.coverMenuOf?.call(coverLib, sub.rel),
                  onQuickRefresh: widget.refreshOf == null || coverLib.isEmpty
                      ? null
                      : () => widget.refreshOf!(coverLib, sub.rel),
                  onSetCover: widget.coverMenuOf != null
                      ? null
                      : (widget.coverUploader == null || coverLib.isEmpty
                          ? null
                          : () => _pickCover(coverLib, sub.rel)),
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
              padding: kLibGridPadding,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: kLibGridSpacing,
                crossAxisSpacing: kLibGridSpacing,
                childAspectRatio: 0.92,
              ),
              itemCount: sorted.length,
              itemBuilder: (c, i) => BasicLibCard(
                basic: sorted[i],
                coverUrl: coverOf?.call(sorted[i]) ?? '',
                coverUrlOf: coverOf,
                headers: headersOf?.call(sorted[i].id) ?? const {},
                unitLabel: unit.name,
                unitKey: unit.id,
                onTap: () => onTapBasic(sorted[i]),
                coverMenu: widget.coverMenuOf == null
                    ? null
                    : widget.coverMenuOf!.call(
                        sorted[i].id, ownerKey[sorted[i].id] ?? ''),
                onQuickRefresh: widget.refreshOf == null
                    ? null
                    : () => widget.refreshOf!(
                        sorted[i].id, ownerKey[sorted[i].id] ?? ''),
                onSetCover: widget.coverMenuOf != null
                    ? null
                    : (widget.coverUploader == null
                        ? null
                        : () => _pickCover(
                            sorted[i].id, ownerKey[sorted[i].id] ?? '')),
              ),
            ),
          ],
        ],
        ),
      ),
    );
  }
}

/// 基础库卡片（中）：来源词条、名称、作者/作品数。
class BasicLibCard extends StatefulWidget {
  final BasicLib basic;
  final VoidCallback onTap;
  final String coverUrl;

  /// 0.9.75：封面地址按需计算（优先级见 [basicCoverUrl]）。
  ///
  /// 传入时优先于 [coverUrl]；卡片在自己的播放量监听里重新求值，
  /// 播放某个基础库后只有这张卡重算封面，网格其余卡片不重建。
  final String Function(BasicLib basic)? coverUrlOf;

  /// 封面请求的鉴权头（媒体接口需要 Basic 认证）。
  final Map<String, String> headers;

  /// 所属单元库（节点文件夹）。只有单元库有资格生成位置词条；
  /// 为空表示该卡片不在单元库语境下，不显示词条。
  final String unitLabel;
  final String unitKey;

  /// C2：本地选图上传封面（为空不显示按钮）。
  final VoidCallback? onSetCover;

  /// owner 2026-11-23：封面合并入口（非空时右上角只留一个「封面设置」）。
  final CoverMenuActions? coverMenu;

  /// owner 2026-11-22：快速刷新（重建索引 → 重拉快照 → 清本库封面缓存）。
  /// 为空时不显示刷新按钮。
  final Future<String?> Function()? onQuickRefresh;

  const BasicLibCard({
    super.key,
    required this.basic,
    required this.onTap,
    this.coverUrl = '',
    this.coverUrlOf,
    this.headers = const <String, String>{},
    this.onQuickRefresh,
    this.unitLabel = '',
    this.unitKey = '',
    this.onSetCover,
    this.coverMenu,
  });

  /// 词条文本：与作者词条共用同一套「去序号」规则。
  static String badgeText(String name) => LibraryBadge.stripIndex(name);

  @override
  State<BasicLibCard> createState() => _BasicLibCardState();
}

class _BasicLibCardState extends State<BasicLibCard> {
  String? _coverOverride;
  bool _coverAuto = false;

  @override
  void didUpdateWidget(covariant BasicLibCard old) {
    super.didUpdateWidget(old);
    if (old.coverUrl != widget.coverUrl ||
        !identical(old.coverUrlOf, widget.coverUrlOf)) {
      _coverOverride = null;
      _coverAuto = false;
    }
  }

  String _coverUrlNow() {
    if (_coverOverride != null) return _coverOverride!;
    return basicCoverUrl(
      widget.basic,
      preset: _coverAuto ? '' : (widget.coverUrlOf?.call(widget.basic) ?? widget.coverUrl),
      firstThumb: widget.basic.firstCover,
      ignoreCustom: _coverAuto,
    );
  }

  Future<void> _openCoverMenu() async {
    final menu = widget.coverMenu;
    if (menu == null) {
      widget.onSetCover?.call();
      return;
    }
    final out = await showCoverMenu(context, menu);
    if (!mounted || out == null) return;
    setState(() {
      _coverAuto = out.auto;
      _coverOverride = out.auto || out.url.isEmpty ? null : out.url;
    });
  }

  Widget _badge() {
    // 位置词条只由「单元库」生成：取所属单元库名称与配色，不再用基础库自身。
    // K17：有单元库就用单元库词条；没有则回退到「库名」灰色词条。
    //
    // P1：末梢基础库词条颜色优先级＝本库自定义 → 上级单元库自定义 →
    // 顶级单元库继承 → 自动配色；层级外观固定为 basic（形状/尺寸与上层一致，
    // 只改边框/底纹）。
    final hasUnit = widget.unitLabel.isNotEmpty;
    final text = LibraryBadge.labelWithEmoji(
        BasicLibCard.badgeText(hasUnit ? widget.unitLabel : widget.basic.name),
        hasUnit ? widget.unitKey : '');
    final unitId = widget.unitKey.isEmpty ? widget.unitLabel : widget.unitKey;
    final color = Color(LibraryBadge.basicColorFor(widget.basic.id, unitId,
        order: UnitBadgeRegistry.order));
    return LibBadgeChip(
      label: text.length > 10 ? '${text.substring(0, 10)}…' : text,
      color: color.toARGB32(),
      unitId: '',
      kind: LibEntryKind.basic,
    );
  }

  @override
  Widget build(BuildContext context) =>
      // 0.9.55：与单元库卡片一致，网格里每张卡各自一层重绘边界。
      RepaintBoundary(child: _buildCard(context));

  Widget _buildCard(BuildContext context) {
    final basic = widget.basic;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(kLibCardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('basic-card-${basic.id}'),
        borderRadius: BorderRadius.circular(kLibCardRadius),
        onTap: widget.onTap,
        // 与单元库卡片一致：封面铺满整张卡片，信息压在底部渐变上。
        child: Stack(fit: StackFit.expand, children: [
          ValueListenableBuilder<int>(
            // 0.9.74：基础库封面只依赖自己的播放量，按库通知即可。
            valueListenable: WorkPlaysStore.libListenable(basic.id),
            builder: (_, __, ___) => _UnitCoverFill(
              key: ValueKey('basic-cover-${basic.id}'),
              url: _coverUrlNow(),
              headers: widget.headers,
              fallbackIcon: Icons.folder_outlined,
              libId: basic.id,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LibCardInfo(
              badge: _badge(),
              title: basic.name,
              unitId: widget.unitKey,
              stats: '${basic.authors} 作者 · ${basic.works} 作品',
              server: basic.serverLabel,
              dense: true,
            ),
          ),
          // P4：基础库（末梢）角标；形状尺寸与上层一致。
          const Positioned(
            left: kCornerBadgeInset,
            top: kCornerBadgeInset,
            child: LibCornerBadge(kind: LibBadgeKind.basic),
          ),
          if (widget.coverMenu != null || widget.onSetCover != null)
            Positioned(
              top: 6,
              right: 6,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (widget.onQuickRefresh != null)
                  LibQuickRefreshButton(
                    libId: basic.id,
                    onRefresh: widget.onQuickRefresh,
                  ),
                if (widget.coverMenu != null || widget.onSetCover != null)
                  IconButton(
                    key: ValueKey('basic-cover-btn-${basic.id}'),
                    tooltip:
                        widget.coverMenu != null ? '封面设置' : '本地选图作封面',
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints.tightFor(width: 30, height: 30),
                    icon: const Icon(Icons.image_outlined),
                    onPressed: _openCoverMenu,
                  ),
              ]),
            )
          else if (widget.onQuickRefresh != null)
            Positioned(
              top: 6,
              right: 6,
              child: LibQuickRefreshButton(
                libId: basic.id,
                onRefresh: widget.onQuickRefresh,
              ),
            ),
        ]),
      ),
    );
  }
}
