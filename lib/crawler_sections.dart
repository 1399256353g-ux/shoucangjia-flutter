/// 爬虫设置页的「按媒体库分节」纯逻辑（唯一实现）。
///
/// owner 2026-11-25：「设置里也按各个媒体库分类好，哪个媒体库的设置就归到
/// 对应的下面去」；2026-11-27：「各爬虫脚本条目按媒体库分类折叠收纳」。
///
/// 0.9.322（第八十六批）之前，这个页面有两份列表：
///  - 单元库条目：按顶级单元库分节、可折叠（0.9.309），但只吃**一份**
///    `LibMeta`（`LibMeta.load(cfg.lib)`，默认注册库）——第二台服务端的
///    单元库一条都进不了页面；
///  - 注册库条目（爬虫配置 / 维护检查）：一条平铺长列表，与上面的分节
///    互不相干，同一个媒体库的设置被拆成两处。
/// 现在两者都进同一批分节：分节 = 媒体库（＝一个连接的库根），节内先列
/// 该连接的注册库条目，再列该连接的单元库条目。
///
/// 归属判定只看结构（连接 id、rel 前缀），不看任何目录名字文本。
library;

import 'rel_path.dart' show normalizeRelPath;
import 'node_key.dart' show scopedKey;
import 'stable_order.dart';
import 'unit_library.dart';

/// 一个媒体库分节；[top] 为 null 表示「不属于任何媒体库」。
class CrawlerSection {
  final UnitLibrary? top;

  /// 该媒体库下的注册库条目（原始 map，页面直接画）。
  final List<Map<String, dynamic>> libraries;

  /// 该媒体库下的单元库条目（不含媒体库根自身）。
  final List<UnitLibrary> units;

  const CrawlerSection({
    required this.top,
    this.libraries = const <Map<String, dynamic>>[],
    this.units = const <UnitLibrary>[],
  });

  bool get isOther => top == null;

  /// 展开/折叠用的键：带连接，两台服务端同名媒体库不会共用一个开关。
  ///
  /// 空串只出现在「其它」节——那一节不折叠（条目本来就少）。
  String get key => top == null ? '' : unitScopeKey(top!);

  String get title => top?.name ?? '其它（不属于任何媒体库）';

  String get serverId => top?.node.serverId.trim() ?? '';

  bool get isEmpty => libraries.isEmpty && units.isEmpty;
}

/// 单元库的跨连接唯一键：连接 + 归一化 rel；媒体库根（rel 为空）用连接。
///
/// 与 `node_key.nodeKey` 同一套作用域理由：rel 相对各自库根，两台服务端
/// 同名目录的 rel 一模一样，只用 rel 会把两边的条目合成一条。
String unitScopeKey(UnitLibrary u) {
  final sid = u.node.serverId.trim();
  final rel = normalizeRelPath(u.rel);
  if (rel.isEmpty) return 'media:${sid.isEmpty ? 'local' : sid}';
  return 'u:$sid/$rel';
}

/// 一份元数据的单元库视图：顶级节点（媒体库根）与展开后的全部单元库。
typedef CrawlerMetaUnits = ({List<UnitLibrary> tops, List<UnitLibrary> units});

/// 把各连接的数据合并成「媒体库」分节。
///
/// - [metas]：每个在线连接一份（跨连接时全部传入，不只默认库）；
/// - [librariesByServer]：连接 id → 该连接的注册库条目。
///
/// 规则：
///  - 每个顶级节点一节，顺序按名称稳定排序（同名不换位）；
///  - 注册库按连接归入对应节；该连接没有顶级节点时进「其它」；
///  - 单元库归入**第一个**包含它的顶级节点（含自身）；不属于任何顶级节点
///    的条目进「其它」节，不丢弃；
///  - 同一 (连接, rel) 的单元库只出现一次（先到先得，与库/封面去重口径一致）。
List<CrawlerSection> crawlerSectionsOf({
  Iterable<CrawlerMetaUnits> metas = const <CrawlerMetaUnits>[],
  Map<String, List<Map<String, dynamic>>> librariesByServer =
      const <String, List<Map<String, dynamic>>>{},
}) {
  final tops = <String, UnitLibrary>{};
  final unitsBySection = <String, List<UnitLibrary>>{};
  final seenUnit = <String>{};
  final other = <UnitLibrary>[];

  for (final meta in metas) {
    // 本份元数据里：单元库 → 所属顶级节点。
    final owner = <String, String>{};
    for (final top in meta.tops) {
      final topKey = unitScopeKey(top);
      // 含自身：媒体库根也可能是别的分节的下级（嵌套媒体库），归属取先到。
      for (final u in _walk(top)) {
        owner.putIfAbsent(unitScopeKey(u), () => topKey);
      }
      tops.putIfAbsent(topKey, () => top);
    }
    for (final u in meta.units) {
      final key = unitScopeKey(u);
      if (!seenUnit.add(key)) continue;
      final topKey = owner[key] ?? '';
      if (topKey.isEmpty) {
        other.add(u);
      } else {
        (unitsBySection[topKey] ??= <UnitLibrary>[]).add(u);
      }
    }
  }

  // 连接 → 顶级节点键（一个连接一个媒体库根；多份时先到先得）。
  final topOfServer = <String, String>{};
  for (final e in tops.entries) {
    final sid = e.value.node.serverId.trim();
    if (sid.isEmpty) continue;
    topOfServer.putIfAbsent(sid, () => e.key);
  }

  final libsBySection = <String, List<Map<String, dynamic>>>{};
  final otherLibs = <Map<String, dynamic>>[];
  librariesByServer.forEach((sid, list) {
    final topKey = topOfServer[sid.trim()] ?? '';
    if (topKey.isEmpty) {
      otherLibs.addAll(list);
    } else {
      (libsBySection[topKey] ??= <Map<String, dynamic>>[]).addAll(list);
    }
  });

  final ordered = stableSort<UnitLibrary>(tops.values.toList(growable: false),
      (a, b) => a.name.compareTo(b.name));
  final out = <CrawlerSection>[
    for (final top in ordered)
      CrawlerSection(
        top: top,
        libraries: List<Map<String, dynamic>>.unmodifiable(
            libsBySection[unitScopeKey(top)] ?? const <Map<String, dynamic>>[]),
        units: List<UnitLibrary>.unmodifiable(
            unitsBySection[unitScopeKey(top)] ?? const <UnitLibrary>[]),
      ),
  ];
  if (other.isNotEmpty || otherLibs.isNotEmpty) {
    stableSort<UnitLibrary>(other, (a, b) => a.name.compareTo(b.name));
    out.add(CrawlerSection(
      top: null,
      libraries: List<Map<String, dynamic>>.unmodifiable(otherLibs),
      units: List<UnitLibrary>.unmodifiable(other),
    ));
  }
  return out;
}

/// 跨连接的单元库键：连接 + 归一化 rel（与 [unitScopeKey] 同一套作用域）。
String unitRelKey(String serverId, String rel) =>
    scopedKey(serverId, normalizeRelPath(rel));

/// 注册库爬虫配置的键：连接 + 库 id。
///
/// 只用库 id 会让两台服务端的同名库（`lib-1` 在两边都很常见）共用一条
/// 配置：A 的「不自动抓取」会把 B 的「每 30 分钟」盖掉，而两行标题各自
/// 显示自己的名字，界面上完全看不出一处错。
String crawlerConfigKey(String serverId, String libId) =>
    scopedKey(serverId, libId);

/// 合并各连接的 `/api/nodes` `crawler` 表（键＝连接 + 归一化 rel）。
///
/// 只按 rel 合并会让两台服务端的同名目录互相顶掉：B 的「有脚本」把 A 的
/// 「无脚本」盖掉，A 的条目于是可点、点进去其实没有脚本。
Map<String, bool> mergeCrawlerFlags(
    Map<String, Map<String, bool>> flagsByServer) {
  final out = <String, bool>{};
  flagsByServer.forEach((sid, flags) {
    for (final e in flags.entries) {
      final rel = normalizeRelPath(e.key);
      if (rel.isEmpty) continue;
      out.putIfAbsent(unitRelKey(sid, rel), () => e.value);
    }
  });
  return out;
}

/// 该单元库是否配了可运行爬虫脚本（**唯一判定**）。
///
/// `/api/nodes` 的 `crawler` 表以 rel 为键（服务端 `unitRelKey` 口径），
/// 页面手里却是节点：`id` 可能是 `node:<rel>`、`rel` 可能用 `\` 分隔、
/// 节点还可能没有连接标识（旧树）。这条判定此前在爬虫设置页写了两遍
/// （分节标题的「N 个有脚本」与条目置灰），两处都写
/// `boolOf(flags[u.rel]) || boolOf(flags[u.id.replaceFirst(...)])`——
/// 改一处就会出现「标题说有 3 个有脚本、下面条目全置灰」的两套说法。
///
/// [serverId] 是所在分节的连接：节点自己没带连接标识时用它。
bool unitHasCrawlerScript(
  Map<String, bool> flags,
  UnitLibrary u, {
  String serverId = '',
}) {
  if (flags.isEmpty) return false;
  final rel = normalizeRelPath(u.rel);
  if (rel.isEmpty) return false;
  final sid = u.node.serverId.trim().isNotEmpty ? u.node.serverId : serverId;
  return flags[unitRelKey(sid, rel)] ?? false;
}

/// 深度优先遍历一棵单元库子树（含自身）。
Iterable<UnitLibrary> _walk(UnitLibrary u) sync* {
  yield u;
  for (final c in u.children) {
    yield* _walk(c);
  }
}
