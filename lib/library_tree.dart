import 'disk_name.dart';
import 'lib_cover.dart';
import 'source_lib.dart';

// 「大库 / 基础库」两级选择模型（纯函数，便于单测）。
//
// 数据来源：/api/libraries.json（v2，由 NAS `lib_scan.py` 生成）
//  - bigLibraries:   第一层大库（5 个）
//  - basicLibraries: 基础库（39 个，带 big_id 归属）
//
// 规则：
//  - 主页默认只展示大库（全部折叠），点开才看到基础库，减少首屏长度（J3）
//  - 星标标记「基础库」：被标记的基础库收集到顶部「星标」区，按标记时间倒序
//  - 已星标的基础库不再重复出现在大库分组里，避免同一项出现两次
//  - 找不到 big_id 的基础库归入「未归属」分组，不丢数据
//  - 旧版（v1，只有 libraries 注册表）解析返回 null，由页面走原列表兜底

class BasicLib {
  final String id;
  final String name;
  final String rel;
  final String bigId;
  final int authors;
  final int works;
  /// L5-C：自定义封面版本（`_cover/<version>.<ext>`）；空串表示无自定义封面。
  final String coverVersion;
  final String coverExt;
  /// 0.9.9：爬虫脚本抓到的封面（作品目录 `cover.jpg`，服务端索引 `cv` 下发）；
  /// 空串表示没有。优先级介于手动封面与自动封面之间。
  final String crawlerCover;
  /// G：服务端 `/api/libraries.json` 下发的「首张作品封面」（`fc`，已带
  /// `/media/<lib>/` 前缀，且保证是图片）。只在手动/爬虫/播放量都拿不到图时兜底。
  final String firstCover;
  /// J7：来源连接（多 IP 聚合时用于路由与去重展示）。
  final String serverId;
  final String serverBase;
  final String serverLabel;

  const BasicLib({
    required this.id,
    required this.name,
    required this.rel,
    required this.bigId,
    required this.authors,
    required this.works,
    this.coverVersion = '',
    this.coverExt = 'jpg',
    this.crawlerCover = '',
    this.firstCover = '',
    this.serverId = '',
    this.serverBase = '',
    this.serverLabel = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'rel': rel,
        'big_id': bigId,
        'authors': authors,
        'works': works,
        if (coverVersion.isNotEmpty) 'cover': {'v': coverVersion, 'e': coverExt},
        if (crawlerCover.isNotEmpty) 'cv': crawlerCover,
        if (firstCover.isNotEmpty) 'fc': firstCover,
        if (serverId.isNotEmpty) '_serverId': serverId,
        if (serverBase.isNotEmpty) '_serverBase': serverBase,
        if (serverLabel.isNotEmpty) '_serverLabel': serverLabel,
      };
}

/// 把 `BasicLibRef` 转成页面用的 `BasicLib`（单元库树构建时用）。
///
/// 统计字段由调用方补（树构建阶段没有 0 值以外的数据），但封面 `fc` 必须
/// 原样带过来 —— 单元库页基础库卡片只读 `BasicLib.firstCover`。
BasicLib basicLibFromRef(BasicLibRef r, {int authors = 0, int works = 0}) =>
    BasicLib(
      id: r.id,
      name: r.name,
      rel: r.rel,
      bigId: r.bigId,
      authors: authors,
      works: works,
      firstCover: r.firstCover,
    );

class BigLib {
  final String id;
  final String name;
  final String path;
  /// 服务端 v2 索引里的统计字段。仅保留结构，不再生成旧「大库描述」。
  final int authors;
  final int works;
  final List<BasicLib> basics;
  final String serverId;
  final String serverBase;
  final String serverLabel;

  const BigLib({
    required this.id,
    required this.name,
    required this.path,
    required this.authors,
    required this.works,
    required this.basics,
    this.serverId = '',
    this.serverBase = '',
    this.serverLabel = '',
  });
}

class LibraryTree {
  final List<BigLib> bigs;
  final List<BasicLib> starred;
  final List<BasicLib> unassigned;

  const LibraryTree({
    required this.bigs,
    required this.starred,
    required this.unassigned,
  });

  /// 解析 v2；不是 v2 或没有大库时返回 null。
  static LibraryTree? parse(
    Map<String, dynamic> json, {
    List<String> stars = const [],
  }) {
    final rawBigs = json['bigLibraries'];
    final rawBasics = json['basicLibraries'];
    if (rawBigs is! List || rawBasics is! List) return null;

    final basics = <BasicLib>[];
    for (final raw in rawBasics) {
      if (raw is! Map) continue;
      final id = '${raw['id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      final relRaw = '${raw['rel'] ?? ''}'.trim();
      basics.add(BasicLib(
        id: id,
        name: diskNameOf(relRaw, '${raw['name'] ?? id}'.trim(), where: 'BasicLib'),
        rel: relRaw,
        bigId: '${raw['big_id'] ?? ''}'.trim(),
        authors: _num(raw['authors']),
        works: _num(raw['works']),
        coverVersion: coverPointerOf(raw['cover']).version,
        coverExt: coverPointerOf(raw['cover']).ext,
        crawlerCover: '${raw['cv'] ?? ''}'.trim(),
        firstCover: '${raw['fc'] ?? ''}'.trim(),
        serverId: '${raw['_serverId'] ?? ''}'.trim(),
        serverBase: '${raw['_serverBase'] ?? ''}'.trim(),
        serverLabel: '${raw['_serverLabel'] ?? ''}'.trim(),
      ));
    }

    final bigs = <BigLib>[];
    for (final raw in rawBigs) {
      if (raw is! Map) continue;
      final id = '${raw['id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      bigs.add(BigLib(
        id: id,
        name: '${raw['name'] ?? id}'.trim(),
        path: '${raw['path'] ?? ''}'.trim(),
        authors: _num(raw['authors']),
        works: _num(raw['works']),
        basics: basics.where((b) => b.bigId == id).toList(growable: false),
        serverId: '${raw['_serverId'] ?? ''}'.trim(),
        serverBase: '${raw['_serverBase'] ?? ''}'.trim(),
        serverLabel: '${raw['_serverLabel'] ?? ''}'.trim(),
      ));
    }
    if (bigs.isEmpty) return null;

    final known = {for (final b in bigs) b.id};
    final unassigned =
        basics.where((b) => !known.contains(b.bigId)).toList(growable: false);

    return LibraryTree(
      bigs: bigs,
      starred: orderStarred(basics, stars),
      unassigned: unassigned,
    );
  }

  /// 全部基础库（含未归属），用于重新排序星标。
  List<BasicLib> get allBasics => [
        for (final b in bigs) ...b.basics,
        ...unassigned,
      ];

  /// 用新的星标顺序重建（其余结构不变）。
  LibraryTree withStars(List<String> stars) => LibraryTree(
        bigs: bigs,
        starred: orderStarred(allBasics, stars),
        unassigned: unassigned,
      );

  BasicLib? basicById(String id) {
    for (final b in bigs) {
      for (final x in b.basics) {
        if (x.id == id) return x;
      }
    }
    for (final x in unassigned) {
      if (x.id == id) return x;
    }
    return null;
  }

  /// 大库里还没被星标的基础库（保持磁盘顺序）。
  List<BasicLib> visibleBasics(BigLib big) => big.basics
      .where((b) => !starred.any((s) => s.id == b.id))
      .toList(growable: false);

  int get totalBasics =>
      bigs.fold(0, (n, b) => n + b.basics.length) + unassigned.length;
}

/// 按星标顺序（最近标记在前）排列基础库；无效/重复 id 自动忽略。
List<BasicLib> orderStarred(List<BasicLib> all, List<String> stars) {
  final byId = {for (final b in all) b.id: b};
  final seen = <String>{};
  final out = <BasicLib>[];
  for (final id in stars) {
    if (!seen.add(id)) continue;
    final b = byId[id];
    if (b != null) out.add(b);
  }
  return out;
}

/// 切换星标：已标记则移除，未标记则插到最前（最近标记优先）。
List<String> toggleStar(List<String> stars, String id, {int max = 20}) {
  final next = List<String>.from(stars);
  if (next.remove(id)) return next;
  next.insert(0, id);
  while (next.length > max) {
    next.removeLast();
  }
  return next;
}

/// 折叠状态：默认全部折叠（J3 只显示大库）；返回新的集合。
Set<String> toggleExpanded(Set<String> expanded, String id) {
  final next = Set<String>.from(expanded);
  if (!next.remove(id)) next.add(id);
  return next;
}

int _num(dynamic v) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? 0);
