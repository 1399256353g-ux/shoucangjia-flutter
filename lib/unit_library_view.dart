import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'api_url.dart';
import 'cover_cache.dart';
import 'cover_menu.dart';
import 'cover_upload.dart';
import 'card_metrics.dart';
import 'grid_spec.dart';
import 'lib_card_prefetch.dart';
import 'library_badge.dart';
import 'library_corner_badge.dart';
import 'library_tree.dart';
import 'lib_cover.dart';
import 'media_resize.dart';
import 'home_action.dart';
import 'json_num.dart' show sumSat;
import 'lib_refresh_button.dart';
import 'scroll_decode.dart';
import 'star_store.dart';
import 'text_clip.dart';
import 'unit_cover_store.dart';
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
///
/// 0.9.288：数字本身收到 `card_metrics.kCardRadius`——作者总览卡、
/// 基础库页作者卡用的是同一个 12，此前三处各写一份。
const double kLibCardRadius = kCardRadius;

/// 库卡片网格外边距（主页 / 单元库页 / 星标页统一）。
///
/// 间距与列上限现在只在本文件的 [kUnitLibGrid] / [kBasicLibGrid] 里出现
/// （`grid_spec.dart`），页面 delegate 与首屏预热读同一份规格：此前这里
/// 还有 `kLibGridSpacing = 10`，与 `gridDelegate` 里的字面量 10 两处各写
/// 一遍，改一处另一处不跟，预热张数与实际列数就对不上。
const EdgeInsets kLibGridPadding = EdgeInsets.symmetric(horizontal: 12);

/// 星标页网格外边距：顶部与左右同主页，底部留 24（滚动到末尾不贴着任务栏）。
///
/// 单独定义是为了让「页面 padding」与「预热用的可用高度」读同一个值：
/// 此前星标页的预热把上下内边距写成 `paddingY: 18`（注释写 (12+24)/2），
/// 而网格自己是 `fromLTRB(12, 12, 12, 24)`——一处改成 one 个数字时
/// 另一处不会跟，预热张数就默默偏离。
const EdgeInsets kStarredGridPadding = EdgeInsets.fromLTRB(12, 12, 12, 24);

/// 卡片底部在线/离线圆点色（owner 2026-11-25：绿点在线、红点离线，简约）。
const Color kCardOnlineColor = Color(0xFF4CAF50);
const Color kCardOfflineColor = Color(0xFFE53935);

/// 库卡片底部信息层的统一渐变。
const LinearGradient kLibCardGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0x00000000), Color(0xC7000000)],
);

/// P3：首页顶级单元库卡片上的词条色块边长（逻辑像素）。
///
/// 尺寸固定、不随层级变化——「形状与尺寸一致」是词条体系的硬约束，
/// 四种词条只在边框/底纹/图案上区分。
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

  /// owner 2026-11-25：连接状态改成绿/红圆点，不再写字。
  /// null = 不显示圆点（非媒体库卡片）。
  final bool? online;

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
    this.online,
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
          if (server.isNotEmpty || online != null)
            Row(children: [
              // owner 2026-11-25：在线绿点 / 离线红点，简约不占字。
              if (online != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: online! ? kCardOnlineColor : kCardOfflineColor,
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Expanded(
                child: Text(server,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 10, color: Colors.white54)),
              ),
            ]),
        ],
      ),
    );
  }
}

/// 子树里**本机播放量最高**的基础库（按该库全部作品次数之和，饱和求和）。
///
/// 「哪个基础库播得最多」此前有两份实现且**结论不同**：
///  - `main._topPlayedBasic` 用 `sumSat(次数)`（整库累计）；
///  - `unit_library_view.topPlayedInUnit` 只取**单条作品**的最大次数。
///
/// 两者在「A 库两条各 5 次、B 库一条 7 次」时给出不同答案，于是同一张
/// 单元库卡片在首页（走 main）与单元库页（走 view）显示两张不同的封面——
/// 而两边都“算对了”，只是用了两个问题。
///
/// 口径按 `media_priority.dart` 文件头写的那条：单元库取**播放量最高的基础库**，
/// 再取该基础库的封面。全部为 0（或没有记录）时返回 null，由调用方决定兜底。
BasicLib? topPlayedBasicOf(UnitLibrary unit) {
  BasicLib? best;
  var bestPlays = 0;
  for (final b in unit.allBasics) {
    // 饱和求和：prefs 里一条写成 int 上限的记录会让 `max+max` 回绕成负数，
    // 该基础库被当成「没播过」——封面从「最高播放」退化成首张图。
    final plays =
        sumSat(WorkPlaysStore.countsFor(b.id).values.map((p) => p.count));
    if (plays > bestPlays) {
      bestPlays = plays;
      best = b;
    }
  }
  return best;
}

/// 单元库子树里「本机播放量最高且有缩略图」的作品：所属基础库 + 次数 + 缩略图。
///
/// 基础库的选择走 [topPlayedBasicOf]（与 `main._unitCoverUrl` 同一个答案），
/// 缩略图取该库里 `topPlayed` 选出的那一张（图文优先、同分更新）。
/// 该缩略图不可用（空/非图片）时返回 null，调用方继续走下一级。
({BasicLib basic, int count, String thumb})? topPlayedInUnit(UnitLibrary unit) {
  final basic = topPlayedBasicOf(unit);
  if (basic == null) return null;
  final counts = WorkPlaysStore.countsFor(basic.id);
  final best = topPlayed(counts);
  final th = best?.thumb.trim() ?? '';
  if (th.isEmpty) return null;
  return (basic: basic, count: best!.count, thumb: th);
}

/// 从服务端 base 里取出可读的主机标注（`192.168.2.4:8090`）。
///
/// owner 2026-11-25：「媒体库卡片最下面补上 ip 地址标注，在线标识搞个
/// 绿色原点就可以了，不在线就变红色就行，简约一点」。
/// 卡片底部不再写「已连接」这类文字，只留一个圆点 + 地址。
/// 解析失败时返回原串（不清空，至少能看到配了什么）。
///
/// 补协议走 `api_url.baseForJoin`（= `multi_server.normalizeBase`），
/// **不自己判 `contains('://')`**：那条判定是「这个串有没有协议」的第二份
/// 实现，而且比连接配置层窄——实测
///
/// ```
/// hostLabelOf('nas：8090')        -> 'nas%EF%BC%9A8090'  ← 全角冒号被当成主机名
/// hostLabelOf('http://NAS:８０９０') -> 'http://NAS:８０９０'  ← 全角数字整串回落
/// ```
///
/// 卡片底部是 owner 用来认「这张卡是哪个 NAS」的唯一线索，露出
/// `nas%EF%BC%9A8090` 等于没有标注。归一后全角会被折叠，与连接实际能连上
/// 的地址是同一个（`normalizeBase` 成功就说明这条连接存得下、请求打得通）。
String hostLabelOf(String serverBase) {
  final raw = serverBase.trim();
  if (raw.isEmpty) return '';
  // 归一后为空 = 这条串本来就不是可连接地址（`http://`、`//nas:8090`）：
  // 原样返回，别把用户配的串吞成空白。
  final base = baseForJoin(raw);
  if (base.isEmpty) return raw;
  try {
    final u = Uri.parse(base);
    if (u.host.isEmpty) return raw;
    return u.hasPort ? '${u.host}:${u.port}' : u.host;
  } catch (_) {
    return raw;
  }
}

/// 单元库封面 URL（优先级高 → 低）：
///  1. 调用方解析好的 [customUrl]（主页/单元库页的完整封面链）；
///  2. owner 手动设置且已解析到当前服务器的封面（零散调用处只能拿相对
///     媒体路径时，用节点自带 serverBase 拼）；
///  3–5. 自定义 `_cover/<version>` → **爬虫封面 `cv`** → 最高播放作品 → 首张作品
///     （顺序本体在 `lib_cover.kCoverSourceOrder`，本函数不再自己排）。
///
/// 0.9.281：这里此前**漏了爬虫一级**——`main._unitCoverUrl` 自己写了一版
/// `crawlerOfUnit()`，而卡片直连的 `unitCoverUrl` 没有，于是同一张单元库卡
/// 在首页（走 main）有封面、在单元库页（走本函数）是灰的。两级现在共用
/// `resolveCover`。
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
  // 解析（trim / 确认媒体路径 / 取库段）只有 `lib_cover.manualCoverUrl` 一处；
  // 本函数只负责拿所在连接拼绝对地址。
  if (!ignoreManual) {
    final base = unit.node.serverBase.trim();
    if (base.isNotEmpty) {
      final manual = manualCoverUrl(unit.node.coverUrl,
          build: (path, _) => '${baseForJoin(base)}$path');
      if (manual.isNotEmpty) return manual;
    }
  }
  final top = topPlayedInUnit(unit);
  final hit = resolveUnitCover(
    unitRel: unit.rel,
    version: ignoreManual ? '' : unit.node.coverVersion,
    ext: unit.node.coverExt,
    // 爬虫封面：子树里第一个有 `cv` 的基础库。扫描本体在
    // `UnitLibrary.firstCrawlerCover`（与 `main._unitCoverUrl` 同一处）。
    crawlerThumb: unit.firstCrawlerCover,
    bestThumb: top?.thumb ?? '',
    // 首张作品封面始终作为「最后一级」传入：有播放记录但那张记录的缩略图
    // 不可用（视频路径/空）时，仍能落到库内第一张作品的图上，而不是空白卡片。
    firstThumb: firstThumb,
  );
  if (hit.path.isEmpty) return '';
  final basics = unit.allBasics;
  final basic = top?.basic ?? (basics.isEmpty ? null : basics.first);
  if (basic == null) return '';
  if (thumbUrlOf != null) return thumbUrlOf(basic, hit.path);
  final base = basic.serverBase.trim().isNotEmpty
      ? basic.serverBase
      : unit.node.serverBase;
  return absoluteMediaUrl(base, lib: basic.id, path: hit.path);
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
  // 基础库的 `_cover/` 在库根（`resolveBasicCover` 里写死空 rel），
  // 与单元库的 `<rel>/_cover/` 语义分开。
  // 顺序本体在 `lib_cover.kCoverSourceOrder`（`main._basicCoverUrl` 同一条）。
  final hit = resolveBasicCover(
    version: ignoreCustom ? '' : basic.coverVersion,
    ext: basic.coverExt,
    crawlerThumb: basic.crawlerCover,
    bestThumb: top?.thumb ?? '',
    firstThumb: fb,
  );
  if (hit.path.isEmpty) return '';
  return absoluteMediaUrl(basic.serverBase, lib: basic.id, path: hit.path);
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

  /// P3：顶级单元库卡片的连接状态（三态）。
  ///
  /// 返回 `null` = 未知（不画圆点）、`true` = 在线（绿点）、
  /// `false` = 已断连（红点）。
  ///
  /// 这里以前传的是文案串「已连接/已断连」，卡片再拿 `== '已连接'` 反推
  /// 布尔——文案一改（本地化、加粗、加空格）圆点就永远是红的，而两条
  /// 「同一个事实」的写法还会各自漂移。现在只传布尔，判定只有一处。
  final bool? Function(UnitLibrary unit)? statusOf;

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
  /// 底色/图标。数据一到就按网格几何预热首页可见的几张。
  ///
  /// 0.9.286：几何/去重/张数上限全部交给 `lib_card_prefetch`（唯一实现）。
  /// 这里此前自己算了一遍 `firstScreenThumbCount`、自己排 URL、不去重，
  /// 与星标页/单元库页各一份，三份的上下内边距还不一样。
  void _prefetchCovers() {
    if (!mounted) return;
    final units = widget.tree.children;
    if (units.isEmpty) return;
    final mq = MediaQuery.maybeOf(context);
    if (mq == null) return;
    prefetchLibCovers(
      viewport: mq.size,
      grid: kUnitLibGrid,
      padding: kLibGridPadding,
      decodeWidth: kUnitLibGrid.decodeWidth(mq.devicePixelRatio),
      items: [
        for (final u in units)
          (
            cover: widget.unitCoverOf?.call(u) ?? '',
            headers: unitHeadersOf(u, widget.headersOf),
          ),
      ],
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
            gridDelegate: kUnitLibGrid.delegate,
            itemCount: units.length,
            itemBuilder: (_, i) {
              final u = units[i];
              // 「代表基础库」只有 `UnitLibrary.coverLib` 一处判定。
              final coverLib = u.coverLib?.id ?? '';
              // P3：首页卡片＝顶级单元库卡片。只用 owner 设过的封面，
              // 未设则用该顶级单元库的词条色块占位，不再拿作品图冒充库封面。
              // 顶级卡片色块：与设置页/词条同一条链（colorForUnit 已内含
              // 顶级自定义色）。这里再写 `topColorFor(...) ??` 是第二处口径，
              // 顶级选「自动分配」时会继续拿到残留 topCustom 旧色。
              final tint = LibraryBadge.colorForUnit(u.id,
                  order: UnitBadgeRegistry.order);
              return UnitLibraryCard(
                unit: u,
                topCard: true,
                fallbackTint: tint,
                online: widget.statusOf?.call(u),
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
        borderRadius: BorderRadius.circular(kCardRadius),
        child: InkWell(
          key: const ValueKey('starred-entry'),
          borderRadius: BorderRadius.circular(kCardRadius),
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
    prefetchLibCovers(
      viewport: mq.size,
      grid: kUnitLibGrid,
      padding: kStarredGridPadding,
      decodeWidth: kUnitLibGrid.decodeWidth(mq.devicePixelRatio),
      items: [
        for (final u in units)
          (
            cover: widget.unitCoverOf?.call(u) ?? '',
            headers: unitHeadersOf(u, widget.headersOf),
          ),
      ],
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
              padding: kStarredGridPadding,
              gridDelegate: kUnitLibGrid.delegate,
              itemCount: units.length,
              itemBuilder: (_, i) {
                final u = units[i];
                final coverLib = u.coverLib?.id ?? '';
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

  /// 连接状态（三态）：`null` 不画圆点，`true` 绿点，`false` 红点。
  final bool? online;

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
    this.online,
    this.onQuickRefresh,
  });

  /// 顶级单元库（SECRET，rel 为空）没有独立爬虫配置；只有下级单元库才有。
  static bool canConfigure(UnitLibrary unit) => unit.rel.trim().isNotEmpty;

  @override
  State<UnitLibraryCard> createState() => _UnitLibraryCardState();
}

class _UnitLibraryCardState extends State<UnitLibraryCard> {
  /// owner 2026-11-25：封面状态收归 [UnitCoverStore]。
  ///
  /// 原来这里有一份私有 `_coverOverride` / `_coverAuto`，`didUpdateWidget`
  /// 发现 `coverUrl` 变了就把它清空——页面一重建，刚选好的封面就回落成
  /// 树快照里的旧值（「返回界面就恢复原样」）。现在卡片不再自己存一份，
  /// 直接问 store；store 变了由 [UnitCoverStore.revision] 通知所有卡片。
  ///
  /// 键带连接标识：两台服务端的同名目录 rel 一样，只按 rel 存会串封面。
  String get _coverKey =>
      UnitCoverStore.unitKey(widget.unit.rel, serverId: widget.unit.node.serverId);

  /// 服务端下发 / 调用方解析出来的「没有本地意见时」的封面地址。
  String _serverCoverUrl() => widget.topCard
      ? (widget.coverUrlOf?.call(widget.unit) ?? widget.coverUrl)
      : unitCoverUrl(
          widget.unit,
          customUrl: widget.coverUrlOf?.call(widget.unit) ?? widget.coverUrl,
        );

  String _coverUrlNow() {
    final local = UnitCoverStore.rawOf(_coverKey);
    if (local != null) {
      // 显式「恢复自动」：忽略服务端自定义指针，走自动链。
      if (local.isEmpty) {
        if (widget.topCard) return '';
        return unitCoverUrl(widget.unit, ignoreManual: true);
      }
      return local;
    }
    return _serverCoverUrl();
  }

  Future<void> _openCoverMenu() async {
    final menu = widget.coverMenu;
    if (menu == null) {
      widget.onSetCover?.call();
      return;
    }
    final out = await showCoverMenu(context, menu);
    if (!mounted || out == null) return;
    // 空串＝恢复自动；非空＝用这张图。写入 store 即触发重建，
    // 不再依赖本卡片的 setState（那样页面一重建就丢）。
    UnitCoverStore.set(_coverKey, out.auto || out.url.isEmpty ? '' : out.url);
  }

  @override
  Widget build(BuildContext context) =>
      // 0.9.55：每张卡片单独一层重绘边界——网格滚动、悬停涟漪、
      // 播放次数变化（WorkPlaysStore）只重绘当前卡片，不带动整块网格。
      RepaintBoundary(child: _buildCard(context));

  /// P3：顶级单元库词条色块（无文字，避免与标题重复）。
  ///
  /// 底色取该库生效的顶级词条色，边框/底纹取 [LibEntryKind.top] 的外观，
  /// 图案与左上角角标同源（[paintCornerGlyph]），三层信息不打架：
  /// 角标说「这是顶级库」，色块说「属于哪个顶级库、什么颜色」。
  /// 媒体库卡片上的词条。
  ///
  /// owner 2026-11-26（第三次提同一件事）：
  /// > 「媒体库词条弄得个星图标就只贴在个首页媒体库卡上，这块不知道在搞
  /// >   什么东西，有点蠢」「词条还是没下发，还是没粘贴」
  ///
  /// 旧实现只画了一个**没有文字**的图案块（注释说「名字就在下方标题里，
  /// 重复是噪声」）。可词条的作用是「这是哪个媒体库、什么颜色、什么后缀」，
  /// 一个色点根本承载不了——用户看到的就是一个星图标，等于没贴词条。
  ///
  /// 现在贴真正的文字词条（与单元库页标题、基础库卡片同一套
  /// `LibBadgeChip`：去序号名称 + emoji 后缀 + 该层级真实外观）。
  Widget _topEntrySwatch(UnitLibrary unit) {
    return ValueListenableBuilder<int>(
      valueListenable: LibraryBadge.revision,
      builder: (_, __, ___) {
        final argb =
            LibraryBadge.colorForUnit(unit.id, order: UnitBadgeRegistry.order);
        return Align(
          alignment: Alignment.centerLeft,
          child: LibBadgeChip(
            key: ValueKey('unit-top-entry-${unit.id}'),
            label: LibraryBadge.stripIndex(unit.name),
            color: argb,
            unitId: unit.id,
            kind: LibEntryKind.top,
          ),
        );
      },
    );
  }

  Widget _buildCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unit = widget.unit;
    // owner 2026-11-25：卡片底部改为「圆点 + IP 地址」，不再用 serverLabel。
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
                // owner 2026-11-25：封面改动也走通知，不再靠卡片自己的
                // setState——那份状态在页面重建时会丢。
                builder: (_, __, ___) => ValueListenableBuilder<int>(
                  valueListenable: UnitCoverStore.revision,
                  builder: (_, __, ___) => _UnitCoverFill(
                    key: ValueKey('unit-cover-${unit.id}'),
                    grid: kUnitLibGrid,
                    url: _coverUrlNow(),
                    headers: widget.headers,
                    fallbackIcon: Icons.folder_copy_outlined,
                    tint: widget.topCard ? widget.fallbackTint : null,
                    libId: unit.coverLib?.id ?? '',
                  ),
                ),
              ),
            ),
            // 底部渐变：与基础库卡片共用同一信息层排版。
            //
            // 0.9.191：这里曾试过给单元库卡也加一条本级词条，结果词条文字与
            // 下方标题完全重复（同一张卡上同一个名字出现两次），属于为「四层级
            // 差异化」硬凑的表现。层级已经由左上角图案角标（P4）与卡片在图里的
            // 位置（首页＝顶级、单元库页＝下级）表达，不再重复；词条仍只在
            // 作者/基础库卡上表示「属于哪个单元库」。
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LibCardInfo(
                // owner 2026-11-26：媒体库卡片要贴**带文字**的词条
                // （含 emoji 后缀），不再是只有图案的色点。
                badge: widget.topCard ? _topEntrySwatch(unit) : null,
                title: unit.name,
                unitId: unit.id,
                stats: '${formatCount(unit.authors)} 作者 · '
                    '${formatCount(unit.works)} 作品',
                // owner 2026-11-25：底部只留「绿/红圆点 + IP 地址」，
                // 不再写「已连接」这类文字（简约）。
                server: hostLabelOf(unit.node.serverBase),
                // 只有顶级卡片表达「这个媒体库连不连得上」；下级卡片
                // 与连接表无关，一律不画。
                online: widget.topCard ? widget.online : null,
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
                    libId: unit.coverLib?.id ?? unit.id,
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

  /// 卡片所属的网格规格（单元库 260 / 基础库 220）：显示宽度与解码宽度
  /// 都从它取，不再自己存一个数字。
  final LibGridSpec grid;

  /// P3：无封面时的占位底色（顶级单元库用词条色块，不用自动封面）。
  final int? tint;

  /// 该封面属于哪个库：用于「卡片快速刷新」按库精确淘汰缓存。
  final String libId;

  const _UnitCoverFill({
    super.key,
    required this.url,
    required this.headers,
    required this.fallbackIcon,
    this.grid = kBasicLibGrid,
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
      // 0.9.288：公式与显示宽度都收到网格规格（`LibGridSpec.decodeWidth`），
      // 页面不再自己挑 220/260。
      memCacheWidth: grid.decodeWidth(MediaQuery.devicePixelRatioOf(context)),
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

  /// A1：作者文件夹挂载（合并同名作者 / 拆分 / 新建作者目录）。
  /// 顶级单元库（rel 为空）不显示入口——它没有可挂载的作者目录。
  final void Function(UnitLibrary unit)? onMountAuthors;

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
    this.onMountAuthors,
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
  /// 会先露底色再出图。
  ///
  /// 0.9.286：两类卡片各走一次 `prefetchLibCovers`（唯一实现）。这里原来自已
  /// 算两遍张数、写一个局部 `add()` 做去重，与另两个页面又各一份。
  void _prefetchCovers() {
    if (!mounted) return;
    final unit = widget.unit;
    final mq = MediaQuery.maybeOf(context);
    if (mq == null) return;

    // 下级单元库卡片（260 / 1.02）。
    prefetchLibCovers(
      viewport: mq.size,
      grid: kUnitLibGrid,
      padding: kLibGridPadding,
      decodeWidth: kUnitLibGrid.decodeWidth(mq.devicePixelRatio),
      maxItems: 6,
      items: [
        for (final sub in unit.children)
          (
            cover: widget.unitCoverOf?.call(sub) ?? '',
            headers: unitHeadersOf(sub, widget.headersOf),
          ),
      ],
    );

    // 基础库卡片（220 / 0.92，与 `BasicLibCard` 同一条封面解析）。
    prefetchLibCovers(
      viewport: mq.size,
      grid: kBasicLibGrid,
      padding: kLibGridPadding,
      decodeWidth: kBasicLibGrid.decodeWidth(mq.devicePixelRatio),
      items: [
        for (final b in unit.basics)
          (
            cover: basicCoverUrl(b,
                preset: widget.coverOf?.call(b) ?? '',
                firstThumb: b.firstCover),
            headers: widget.headersOf?.call(b.id) ?? const <String, String>{},
          ),
      ],
    );
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
    final onMountAuthors = widget.onMountAuthors;
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
        if (onMountAuthors != null && unit.rel.trim().isNotEmpty)
          IconButton(
            key: ValueKey('unit-author-mount-${unit.id}'),
            tooltip: '作者文件夹挂载',
            icon: const Icon(Icons.folder_shared_outlined),
            onPressed: () => onMountAuthors(unit),
          ),
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
              gridDelegate: kUnitLibGrid.delegate,
              itemCount: unit.children.length,
              itemBuilder: (c, i) {
                final sub = unit.children[i];
                final coverLib = sub.coverLib?.id ?? '';
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
              gridDelegate: kBasicLibGrid.delegate,
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
  /// owner 2026-11-25：与单元库卡片同一处状态（[UnitCoverStore]）。
  /// 原来这里也有一份私有覆盖，页面重建即丢——同一个 bug 的第二份拷贝。
  /// 键带连接标识（同 [UnitCoverStore.unitKey] 的理由）。
  String get _coverKey => UnitCoverStore.basicKey(widget.basic.id,
      serverId: widget.basic.serverId);

  String _coverUrlNow() {
    final local = UnitCoverStore.rawOf(_coverKey);
    if (local != null && local.isNotEmpty) return local;
    final auto = local != null; // 空串＝显式恢复自动
    return basicCoverUrl(
      widget.basic,
      preset: auto
          ? ''
          : (widget.coverUrlOf?.call(widget.basic) ?? widget.coverUrl),
      firstThumb: widget.basic.firstCover,
      ignoreCustom: auto,
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
    UnitCoverStore.set(_coverKey, out.auto || out.url.isEmpty ? '' : out.url);
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
      // 截断走 text_clip：按 UTF-16 单元数切会切开 emoji 代理对，
      // 词条本身带库 emoji 后缀（labelWithEmoji），切点正好落在 emoji 上时
      // 卡片上就是一个替换方块。
      label: clipWithEllipsis(text, 10),
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
            // owner 2026-11-25：封面改动同单元库卡片一样走 store 通知。
            builder: (_, __, ___) => ValueListenableBuilder<int>(
              valueListenable: UnitCoverStore.revision,
              builder: (_, __, ___) => _UnitCoverFill(
                key: ValueKey('basic-cover-${basic.id}'),
                url: _coverUrlNow(),
                headers: widget.headers,
                fallbackIcon: Icons.folder_outlined,
                libId: basic.id,
              ),
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
              stats: '${formatCount(basic.authors)} 作者 · '
                  '${formatCount(basic.works)} 作品',
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
