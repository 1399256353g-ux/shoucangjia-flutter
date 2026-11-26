// L5「单元库」模型（纯函数，便于单测）。
//
// 术语（owner 设计）：
//  - 节点文件夹（含自身与下级全部结构）＝「单元库」
//  - 顶级单元库＝**当前连接的媒体库根**（名称取根目录名，见 top_node.dart）；
//    第一层目录即下级单元库（原「大库」）
//  - 单元库之下可以继续嵌套单元库（原「大库分组」），叶子仍是基础库
//  - 卡片层级：单元库卡片 > 基础库卡片 > 作品卡片（尺寸递减）
//
// 收敛规则（L5）：
//  1. 同一路径多节点取最下级，上级不重复认领（父节点只认领直属基础库）
//  2. 单元库（含整棵子树）内没有基础库 → 在选择页消失
//  3. 没有命中任何节点的下级基础库 → 归入顶级单元库（媒体库根）
//
// 数据来源：/api/libraries.json v2 的 bigLibraries / groups（节点）与
// basicLibraries（基础库，带 rel 相对路径）。

import 'disk_name.dart';
import 'http_json.dart';
import 'json_num.dart';
import 'lib_id.dart';
import 'library_badge.dart';
import 'library_tree.dart';
import 'lib_cover.dart';
import 'media_path.dart';
import 'node_key.dart';
import 'server_origin.dart';
import 'stable_order.dart';
import 'rel_path.dart';
import 'top_node.dart';
// 计数文案的**唯一定义**在 `count_label.dart`（它不只服务单元库：基础库卡片、
// 设置页、文件结构页、作者挂载面板都在用）。这里 re-export，既有
// `import 'unit_library.dart'` 的调用点与测试不必改。
export 'count_label.dart' show formatCount;


/// 一个节点文件夹（单元库候选）。
class LibNode {
  final String id;
  final String rel;
  final String name;

  /// L5-C：自定义封面版本（`_cover/<version>.<ext>`）；空串表示无自定义封面。
  final String coverVersion;
  final String coverExt;

  /// 0.9.35：单元库自定义封面（服务端 `unit-covers.json` 下发的 `cover.u`，
  /// 形如 `/media/<基础库>/<库内相对路径>`）；空串表示没设过。
  final String coverUrl;
  final String serverId;
  final String serverBase;
  final String serverLabel;

  const LibNode({
    required this.id,
    required this.rel,
    required this.name,
    this.coverVersion = '',
    this.coverExt = 'jpg',
    this.coverUrl = '',
    this.serverId = '',
    this.serverBase = '',
    this.serverLabel = '',
  });

  List<String> get segments => splitRel(rel);
}

/// 单元库节点（已挂上直属基础库与下级单元库）。
class UnitLibrary {
  final LibNode node;
  final List<BasicLib> basics;
  final List<UnitLibrary> children;

  const UnitLibrary({
    required this.node,
    required this.basics,
    required this.children,
  });

  String get id => node.id;
  String get name => node.name;
  String get rel => node.rel;

  /// 整棵子树的作品数（含下级单元库）。
  ///
  /// **饱和求和**（[sumSat]）：服务端把某个基础库的 `works` 写成 int 上限
  /// 9223372036854775807（坏数据/占位值的常见形态）时，两个这样的基础库
  /// 相加实测得 **-2**——单元库卡片走 `formatCount(n <= 0) → '0'`，于是
  /// 一张有几千个作品的单元库显示成「0 作品」，是最难发现的那种错
  /// （界面看起来只是「这个库是空的」）。等级（`AuthorGrade.score`）与
  /// 排行（`libraryTotals`）早就是饱和求和，这里当时漏了。
  int get works => sumSat(<int>[
        for (final b in basics) b.works,
        for (final c in children) c.works,
      ]);

  /// 整棵子树的作者数（基础库作者直接相加，不跨库去重）。同上走饱和求和。
  int get authors => sumSat(<int>[
        for (final b in basics) b.authors,
        for (final c in children) c.authors,
      ]);

  /// 整棵子树的基础库数量。
  int get basicCount =>
      basics.length + children.fold(0, (n, c) => n + c.basicCount);

  /// 这张卡片的「代表基础库」——封面文件、鉴权头、索引重建都挂在它身上。
  ///
  /// 判定只有这一处：「子树里第一个基础库」。此前同一个表达式写了六遍
  /// （`unit_library_view` 5 处 + `main` 1 处），其中三处只取 `.id`、三处
  /// 要整个对象；只要有一处改成「取有封面的那个」，同一张卡就会出现
  /// 「封面来自 A 库、鉴权用 B 库」——请求打到另一台服务器，必然 404。
  ///
  /// 空子树返回 null，由调用方决定显不显示封面按钮。
  BasicLib? get coverLib {
    if (basics.isNotEmpty) return basics.first;
    for (final c in children) {
      final hit = c.coverLib;
      if (hit != null) return hit;
    }
    return null;
  }

  bool get isEmpty => basicCount == 0;

  /// P1：末梢单元库——没有下级单元库。
  ///
  /// 只有末梢单元库的词条可以「向下分发」给它的基础库/作品/作者：
  /// 作品归属由基础库反查得到，非末梢单元库下的作品都落在更深的单元库里，
  /// 所以非末梢单元的样式只作用于自己这一层，分发出去也会被覆盖。
  bool get isLeaf => children.isEmpty;

  /// 深度优先展开全部基础库（保持层级顺序）。
  List<BasicLib> get allBasics => [
        ...basics,
        for (final c in children) ...c.allBasics,
      ];

  /// 子树里**第一个**带爬虫封面（`cv`）的基础库所给的封面路径；没有则空串。
  ///
  /// 「子树里第一个非空 `cv`」这条扫描此前写了三遍：`main._unitCoverUrl` 里的
  /// `crawlerOfUnit()`、`unit_library_view.unitCoverUrl` 里的同名闭包、以及
  /// 测试各自搭的一套。三份里任何一份先被改动，同一张单元库卡在首页与
  /// 单元库页就会拿到不同的爬虫封面（或一份有、一份灰）。现在只有这一处。
  String get firstCrawlerCover {
    for (final b in allBasics) {
      final cv = b.crawlerCover.trim();
      if (cv.isNotEmpty) return cv;
    }
    return '';
  }

  /// 子树里**第一个**带首张作品封面（`fc`）的基础库：基础库 id + 封面路径。
  ///
  /// 与 [firstCrawlerCover] 同一条「第一个非空」规则；`main._firstFcOfUnit`
  /// 目前是它的第二份拷贝（还额外承担「这张图该按哪个库路由」的返回值）。
  ({String lib, String path})? get firstWorkCover {
    for (final b in allBasics) {
      final fc = b.firstCover.trim();
      if (fc.isNotEmpty) return (lib: b.id, path: fc);
    }
    return null;
  }

  /// 查找子树里的单元库（按 id）。
  UnitLibrary? findById(String id) {
    if (node.id == id) return this;
    for (final c in children) {
      final hit = c.findById(id);
      if (hit != null) return hit;
    }
    return null;
  }
}

/// 路径分段交给唯一实现（见 `rel_path.dart`），不在本文件再写一份。
List<String> splitRel(String rel) => relSegments(rel);

/// 去掉库根前缀，得到相对路径。root 为空时按原样返回。
String relFromPath(String path, String root) {
  final p = splitRel(path);
  final r = splitRel(root);
  if (r.isNotEmpty && p.length >= r.length) {
    var same = true;
    for (var i = 0; i < r.length; i++) {
      if (p[i] != r[i]) {
        same = false;
        break;
      }
    }
    if (same) return p.skip(r.length).join('/');
  }
  return p.join('/');
}

/// a 是否是 b 的上级（或同一路径）。
bool isPrefixOf(List<String> a, List<String> b) {
  if (a.length > b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 节点在「去重/父子/归属」三张表里的键：**连接 + rel**。
///
/// 只写 rel 会让两台服务端的同名目录互相顶掉（见 [buildUnitTree] 步骤 1 的
/// 实测），只写连接更不行。
///
/// 拼装本体在 [nodeKey]（唯一实现）：这个字符串同时是封面表的键
/// （`multi_server.unitCoverKey`），两处各写一份时只要有一处改了分隔符或
/// trim 口径，封面就查不到节点、卡片退回默认图，而两边各自都「算对了」。
String _nodeKeyOf(String serverId, String rel) => nodeKey(serverId, rel);

/// 节点所属连接（trim 后）；空串表示旧格式/离线快照。
String _sidOf(LibNode n) => n.serverId.trim();

/// 构造单元库树。
///
/// [nodes] 节点文件夹（可以是 bigLibraries + groups 的合集）。
/// [basics] 基础库，`rel` 为相对库根的路径。
/// [topName] 顶级单元库名称（默认取当前媒体库根目录名），顶级 id 为 [topId]。
/// 返回顶级单元库；没有基础库时返回 null（整棵树在选择页消失）。
UnitLibrary? buildUnitTree({
  required List<LibNode> nodes,
  required List<BasicLib> basics,
  String topId = 'secret',
  String? topName,
}) {
  final top = (topName == null || topName.trim().isEmpty)
      ? TopNodeName.current
      : topName;
  if (basics.isEmpty) return null;

  // 1. 节点去重：同一**连接内**的同一 rel 只保留一个。
  //
  // 键必须带连接标识。此前只用 rel：两台服务端都有 `A` 时后者被整条丢掉，
  // 而 B 服务端的 `A/y` 基础库会命中 A(s1) 的节点——A 卡片里出现 B 的库，
  // 封面/鉴权按 A 的连接去请求，必然 404。实测：
  //   nodes[A@s1] + nodes[A@s2] + basics[a1@s1, b1@s2(rel=A/y)]
  //   → media:s1 → A 的 basics = [a1, b1]（b1 来自另一台机器）
  //   → media:s2 整组消失
  final byKey = <String, LibNode>{};
  for (final n in nodes) {
    final rel = splitRel(n.rel).join('/');
    if (rel.isEmpty) continue;
    byKey.putIfAbsent(_nodeKeyOf(n.serverId, rel), () => n);
  }

  // 2. 从深到浅分配基础库：每个基础库只归**本连接**最深命中的节点（收敛规则 1）。
  //
  // 跨连接归属不存在「更深优先」的余地：不同服务端的同名目录是两份独立数据。
  //
  // `serverId` 为空的基础库＝来源未知（旧格式、单连接、测试构造），按旧行为
  // 参与「最深命中」不限连接；它归属到哪个节点就随那个节点走同一连接。
  // 只有**明确写了** serverId 的基础库才受连接约束——否则单连接场景会因为
  // 节点带连接、基础库不带而全部落进孤儿组，首页一行都显示不出来。
  // 深度降序；同深度按输入顺序（稳定）。同深度节点之间本来没有次序依据，
  // 而 `List.sort` 不稳定：一台服务端上多一个节点就能让「基础库归到哪一层」
  // 里的同深度候选顺序变化，未声明连接的旧格式基础库于是可能改挂到另一台
  // 服务端的同名目录上（词条/封面随之换源）。稳定排序消除这一层偶然性。
  final ordered = stableSort(
      byKey.values.toList(),
      (a, b) => b.segments.length.compareTo(a.segments.length));

  final owned = <String, List<BasicLib>>{};
  final orphanGroups = <String, List<BasicLib>>{};
  for (final b in basics) {
    final segs = splitRel(b.rel);
    final sid = b.serverId.trim();
    LibNode? hit;
    for (final n in ordered) {
      if (sid.isNotEmpty && _sidOf(n) != sid) continue;
      // 基础库目录本身与节点同路径时也算直属（基础库就是节点）。
      if (isPrefixOf(n.segments, segs) && n.segments.length <= segs.length) {
        hit = n;
        break;
      }
    }
    if (hit == null) {
      // 孤儿按**自己声明的**连接归组；没声明就进「未知来源」那组。
      orphanGroups.putIfAbsent(sid, () => <BasicLib>[]).add(b);
    } else {
      owned.putIfAbsent(_nodeKeyOf(hit.serverId, splitRel(hit.rel).join('/')),
          () => <BasicLib>[]).add(b);
    }
  }

  // 3. 建立节点树（父子按前缀关系）。
  final childrenOf = <String, List<LibNode>>{};
  final sortedNodes = stableSort(
      byKey.values.toList(),
      (a, b) => a.segments.length.compareTo(b.segments.length));
  final present = <String, LibNode>{};
  for (final n in sortedNodes) {
    final key = _nodeKeyOf(n.serverId, n.segments.join('/'));
    LibNode? parent;
    for (var i = n.segments.length - 1; i > 0; i--) {
      final pk = n.segments.take(i).join('/');
      final cand = present[_nodeKeyOf(n.serverId, pk)];
      if (cand != null) {
        parent = cand;
        break;
      }
    }
    present[key] = n;
    if (parent != null) {
      childrenOf
          .putIfAbsent(
              _nodeKeyOf(parent.serverId, parent.segments.join('/')), () => [])
          .add(n);
    }
  }

  // 4. 递归装配，并按收敛规则 2 剪掉空子树。
  UnitLibrary? build(LibNode n, {int depth = 0}) {
    final key = _nodeKeyOf(n.serverId, n.segments.join('/'));
    final kids = <UnitLibrary>[];
    for (final k in childrenOf[key] ?? const <LibNode>[]) {
      final sub = build(k, depth: depth + 1);
      if (sub != null) kids.add(sub);
    }
    final own = owned[key] ?? const <BasicLib>[];
    if (own.isEmpty && kids.isEmpty) return null;
    // 同名单元库（不同 rel）之间没有次序依据；普通 sort 不稳定，
    // 同一层每次重建都可能换位置 → 走 stableSort 保持输入顺序。
    stableSortByName(kids, (u) => u.name);
    return UnitLibrary(node: n, basics: own, children: kids);
  }

  // 5. 顶级单元库＝第一层路径段（没有节点声明时用默认 SECRET）。
  final roots = <LibNode>[];
  for (final n in sortedNodes) {
    if (n.segments.length == 1) roots.add(n);
  }
  final rootUnits = <UnitLibrary>[];
  for (final r in roots) {
    final u = build(r);
    if (u != null) rootUnits.add(u);
  }

  // 6. 没有归属的基础库 → 默认顶级单元库（收敛规则 3），**按连接分组**。
  //
  // 此前所有孤儿（不分连接）塞进同一个根，而且那个根的 `serverId` 为空：
  // 只要有一台服务端存在节点，首页就走「每连接一个媒体库」分支，这个空
  // serverId 的根被丢进 `noServer` 后再也没被用到——孤儿库整批消失。
  // 实测：nodes[A@s1] + basics[a1@s1, orphan@s1] → 只有 a1 能上屏。
  //
  // 现在每个连接各得一个根：名称取该连接标签，取不到用库根名。
  // id 不能再用 [topId]——那与树根同 id，`flattenUnits` 会出现两个 `secret`，
  // 星标/词条按 id 索引时互相顶掉。改成 `top:<连接>`。
  final groupKeys = orphanGroups.keys.toList()..sort();
  for (final sid in groupKeys) {
    final group = orphanGroups[sid] ?? const <BasicLib>[];
    if (group.isEmpty) continue;
    final label = group.first.serverLabel.trim();
    rootUnits.add(UnitLibrary(
      node: LibNode(
        id: 'top:${sid.isEmpty ? 'local' : sid}',
        rel: '',
        name: label.isEmpty ? top : label,
        serverId: sid,
        serverBase: group.first.serverBase,
        serverLabel: label,
      ),
      basics: group,
      children: const [],
    ));
  }
  if (rootUnits.isEmpty) return null;
  stableSortByName(rootUnits, (u) => u.name);

  // 单连接 / 无连接信息（旧格式、离线快照）→ 保持旧形态：根即容器，
  // children 就是第一层单元库。此时不存在「哪个媒体库连不连得上」的问题，
  // 多插一层 `media:local` 只会让首页平白多一张没有连接信息的卡片。
  final anyServer =
      rootUnits.any((u) => u.node.serverId.trim().isNotEmpty);
  if (!anyServer) {
    return UnitLibrary(
      node: LibNode(id: topId, rel: '', name: top),
      basics: const [],
      children: rootUnits,
    );
  }

  // 首页要显示的是「媒体库」本身（顶级单元库），而不是库下的第一层目录。
  // 第一次序：按连接（serverId）归组，每个连接一个顶级单元库；
  // 少量没有 serverId 的根（旧格式混进多连接）单独成一张卡片，不丢弃。
  final byServer = <String, List<UnitLibrary>>{};
  for (final u in rootUnits) {
    final sid = u.node.serverId.trim();
    // 空 sid 也保留：它是一条真实存在的库（旧格式/离线快照），
    // 只要有别的连接存在就整组消失，等于「换个网络库就不见了」。
    byServer.putIfAbsent(sid, () => <UnitLibrary>[]).add(u);
  }

  List<UnitLibrary> mediaLibraries = <UnitLibrary>[];
  final mediaKeys = byServer.keys.toList()..sort();
  for (final sid in mediaKeys) {
    final subs = byServer[sid] ?? const <UnitLibrary>[];
    if (subs.isEmpty) continue;
    final label = subs.first.node.serverLabel.trim();
    mediaLibraries.add(UnitLibrary(
      node: LibNode(
        id: 'media:${sid.isEmpty ? 'local' : sid}',
        rel: '',
        name: label.isEmpty ? top : label,
        serverId: sid,
        serverBase: subs.first.node.serverBase,
        serverLabel: label,
      ),
      basics: const [],
      children: subs,
    ));
  }

  if (mediaLibraries.isEmpty) {
    // 退回到旧形态（单连接/无连接信息）：根即为容器，children 是下级单元库。
    return UnitLibrary(
      node: LibNode(id: topId, rel: '', name: top),
      basics: const [],
      children: rootUnits,
    );
  }
  stableSortByName(mediaLibraries, (u) => u.name);
  return UnitLibrary(
    node: LibNode(id: topId, rel: '', name: top),
    basics: const [],
    children: mediaLibraries,
  );
}

/// 从 v2 的 bigLibraries / groups 提取节点。
List<LibNode> nodesFromV2(Map<String, dynamic> json, {String root = ''}) {
  final out = <LibNode>[];
  void add(dynamic raw) {
    if (raw is! Map) return;
    final path = '${raw['path'] ?? ''}'.trim();
    final relRaw = '${raw['rel'] ?? ''}'.trim();
    var rel = relRaw;
    if (rel.isEmpty) {
      rel = relFromPath(path, root);
      // 未给 root 或 root 不匹配时，退化为「最后一个库根段之后」：
      // /vol1/.../Secret/(1) A → (1) A，保证与基础库的 rel 同一坐标系。
      if (splitRel(path).length == splitRel(rel).length) {
        final segs = splitRel(path);
        final at = segs.lastIndexWhere((s) => s.toLowerCase() == 'secret');
        if (at >= 0 && at + 1 < segs.length) {
          rel = segs.skip(at + 1).join('/');
        }
      }
    }
    if (rel.isEmpty) return;
    final name = '${raw['name'] ?? ''}'.trim();
    final origin = serverOriginOf(raw);
    out.add(LibNode(
      id: '${raw['id'] ?? rel}'.trim(),
      rel: rel,
      // 显示名以磁盘目录名为准；name 只在 rel 为空时兜底。
      name: diskNameOf(rel, name, where: 'nodesFromV2'),
      coverVersion: coverPointerOf(raw['cover']).version,
      coverExt: coverPointerOf(raw['cover']).ext,
      coverUrl: coverUrlOf(raw['cover']),
      serverId: origin.id,
      serverBase: origin.base,
      serverLabel: origin.label,
    ));
  }

  // 手动模式（服务端 `nodesMode: manual`）：节点文件夹只认 owner 在「文件结构」
  // 里勾选的目录（/api/nodes）；空数组＝只有顶级 SECRET，绝不回退自动节点。
  final manual = '${json['nodesMode'] ?? ''}'.trim().toLowerCase() == 'manual';
  final rawNodes = json['nodes'];
  if (manual) {
    if (rawNodes is List) {
      for (final x in rawNodes) {
        if (x is! Map) continue;
        if ('${x['rel'] ?? ''}'.trim().isEmpty) continue;
        add(x);
      }
    }
    return out;
  }

  // J14：优先用服务端扫出的「通用分类节点」（任意层级上级目录）。
  if (rawNodes is List && rawNodes.isNotEmpty) {
    var used = false;
    for (final x in rawNodes) {
      if (x is! Map) continue;
      // 归一走 `rel_path.dart` 唯一实现：此前这里是手写链条的第五份拷贝。
      final rel = normalizeRelPath('${x['rel'] ?? ''}');
      if (rel.isEmpty) continue;
      add(x);
      used = true;
    }
    if (used) return out;
  }

  for (final x in listOf(json['bigLibraries'])) {
    add(x);
  }
  for (final x in listOf(json['groups'])) {
    add(x);
  }
  return out;
}

/// `/api/nodes` 载荷的解析结果（唯一实现）。
///
/// 此前 `main.dart` 里**两处**各写了一遍「把 nodes 列表与 covers 映射读出来」
/// 的代码（主页 `_fetchMarkedNodes` 与文件结构页），两处都只做 `trim()`：
/// 服务端把 rel 写成 `A\B` 或 `A//B` 时，键与 `splitRel` 归一后的形式不一致，
/// 同一个目录会在「节点 id / 封面指针」两边归一不同——写进去、读不回来；
/// 封面指针还会被另一个同 rel 目录认领。归一化只在 [parseNodesPayload] 做一次。
class NodesPayload {
  final List<String> rels;

  /// 归一化 rel → `/media/<lib>/...` 封面指针。
  final Map<String, String> covers;

  const NodesPayload(this.rels, this.covers);

  static const NodesPayload empty = NodesPayload(<String>[], <String, String>{});
}

/// 解析 `/api/nodes`：`nodes` 既可能是字符串也可能是 `{id,rel,name}` 对象。
/// 非媒体路径的封面指针不收（避免半截路径被当封面去请求）。
NodesPayload parseNodesPayload(Object? json) {
  if (json is! Map) return NodesPayload.empty;
  final rels = <String>[];
  final seen = <String>{};
  final list = json['nodes'];
  if (list is List) {
    for (final e in list) {
      final raw = e is Map
          ? '${e['rel'] ?? e['path'] ?? e['name'] ?? ''}'
          : '$e';
      final rel = splitRel(raw).join('/');
      if (rel.isEmpty || !seen.add(rel)) continue;
      rels.add(rel);
    }
  }
  final covers = <String, String>{};
  final cm = json['covers'];
  if (cm is Map) {
    for (final e in cm.entries) {
      final k = splitRel('${e.key}').join('/');
      final v = '${e.value ?? ''}'.trim();
      if (k.isEmpty || v.isEmpty) continue;
      if (!isMediaPath(v)) continue;
      covers.putIfAbsent(k, () => v);
    }
  }
  return NodesPayload(rels, covers);
}

/// 手动模式的节点列表：`/api/nodes` 的相对路径 → 单元库节点。
/// 空数组表示只有顶级 SECRET（不生成任何下级节点）。
///
/// 0.9.36：`/api/nodes` 现在同时下发 `covers: {rel: "/media/..."}`（owner 设过的
/// 单元库封面指针）。手动节点模式下单元库节点原本是纯字符串，拿不到 `cover.u`，
/// 自定义封面在该模式下不显示；这里把指针带进节点，`serverBase` 用于零散调用处
/// 自行拼绝对地址（主页/单元库页仍走调用方解析好的封面链）。
List<LibNode> nodesFromMarks(
  Iterable<String> marks, {
  Map<String, String> covers = const <String, String>{},
  String serverBase = '',
  String serverId = '',
  String serverLabel = '',
}) {
  final out = <LibNode>[];
  final seen = <String>{};
  final base = serverBase.trim();
  final sid = serverId.trim();
  final slabel = serverLabel.trim();
  for (final raw in marks) {
    final rel = splitRel(raw).join('/');
    if (rel.isEmpty || !seen.add(rel)) continue;
    final u = '${covers[rel] ?? covers[raw] ?? ''}'.trim();
    out.add(LibNode(
      id: rel,
      rel: rel,
      name: splitRel(rel).last,
      coverUrl: isMediaPath(u) ? u : '',
      serverBase: base,
      // owner 2026-11-24：节点必须带连接标识，否则 buildUnitTree 退回
      // 「第一层目录当卡片」的旧形态，把下级单元库错标成「媒体库」。
      serverId: sid,
      serverLabel: slabel,
    ));
  }
  return out;
}

/// 基础库 id → 所属单元库 id。
///
/// 每个基础库在 [buildUnitTree] 里只会归属一个单元库；
/// 没有归属的基础库挂在顶级单元库（SECRET）下。
Map<String, String> unitOfBasics(UnitLibrary root) {
  final out = <String, String>{};
  void walk(UnitLibrary u) {
    for (final c in u.children) {
      walk(c);
    }
    for (final b in u.basics) {
      out[b.id] = u.id;
    }
  }

  walk(root);
  return out;
}

/// 筛选用单元库列表：只保留含基础库的单元库，深度优先，SECRET 放最后。
List<UnitLibrary> flattenUnits(UnitLibrary root) {
  final out = <UnitLibrary>[];
  void walk(UnitLibrary u) {
    if (u.basics.isNotEmpty) out.add(u);
    for (final c in u.children) {
      walk(c);
    }
  }

  walk(root);
  // 顶级 SECRET 固定放最后，避免它排在小库前面。
  final secret = out.where((u) => u.node.id == root.node.id).toList();
  if (secret.isNotEmpty) {
    out.removeWhere((u) => u.node.id == root.node.id);
    out.addAll(secret);
  }
  return out;
}

/// 基础库所属的单元库节点；没有归属时返回 null。
///
/// 作者来源词条＝作者所属基础库的单元库名/配色，用它反查。
UnitLibrary? unitForBasic(UnitLibrary root, String basicId) {
  if (basicId.isEmpty) return null;
  UnitLibrary? hit;
  void walk(UnitLibrary u) {
    if (hit != null) return;
    for (final b in u.basics) {
      if (b.id == basicId) {
        hit = u;
        return;
      }
    }
    for (final c in u.children) {
      walk(c);
    }
  }

  walk(root);
  return hit;
}

/// 基础库 → 直接上级单元库名称（位置词条唯一来源）。
Map<String, String> unitLabelByBasic(UnitLibrary root) {
  final out = <String, String>{};
  void walk(UnitLibrary u) {
    for (final b in u.basics) {
      out[b.id] = u.name;
    }
    for (final c in u.children) {
      walk(c);
    }
  }

  walk(root);
  return out;
}

/// 基础库 → 直接上级单元库 id（配色唯一来源）。
Map<String, String> unitKeyByBasic(UnitLibrary root) {
  final out = <String, String>{};
  void walk(UnitLibrary u) {
    for (final b in u.basics) {
      out[b.id] = u.id;
    }
    for (final c in u.children) {
      walk(c);
    }
  }

  walk(root);
  return out;
}

/// 基础库 → 直接上级单元库的映射（词条唯一来源）。
///
/// 作者卡、基础库卡、播放页信息行都必须从这里取词条，禁止各自解析，
/// 否则会出现「作者词条是基础库、基础库词条是单元库」的不一致。
/// P1：单元库 id → 顶级单元库 id（顶级单元库＝媒体库根，向下继承词条色）。
///
/// 判定只看树结构：根的直接子节点就是各连接的媒体库根；SECRET 自身没有
/// 上级，按空串处理（它只承载「无归属基础库」兜底）。同名/`node:` 前缀的
/// 两种 id 形式都登记，配色查询无需再做归一。
Map<String, String> topOfUnitIds(UnitLibrary root) {
  final out = <String, String>{};
  void walk(UnitLibrary u, String top) {
    if (top.isNotEmpty) {
      // 两种 id 形式都登记，查询端统一走 lookupByLibId，不必自己归一。
      for (final f in idFormsOf(u.id)) {
        out[f] = top;
      }
      out['node:${u.rel}'] = top;
    }
    for (final c in u.children) {
      walk(c, top);
    }
  }

  for (final c in root.children) {
    walk(c, c.id);
  }
  return out;
}

/// P1：单元库 id → 是否末梢（没有下级单元库）。
///
/// 只由树结构算出，不看任何目录名文本；`rel` 与 `node:rel` 两种 id 形式
/// 都登记，查询端不必自己归一。
Map<String, bool> leafUnitIds(UnitLibrary root) {
  final out = <String, bool>{};
  void walk(UnitLibrary u) {
    final leaf = u.isLeaf;
    // 与 topOfUnitIds 同一份等价键规则（含裸 rel 与带前缀形式）。
    for (final f in idFormsOf(u.id)) {
      out[f] = leaf;
    }
    out['node:${u.rel}'] = leaf;
    for (final c in u.children) {
      walk(c);
    }
  }

  for (final c in root.children) {
    walk(c);
  }
  return out;
}

class UnitBadgeRegistry {
  static final Map<String, String> labels = <String, String>{};
  static final Map<String, String> keys = <String, String>{};

  /// P1：单元库 id → 是否末梢单元库（只有末梢可向下分发词条）。
  ///
  /// **不是独立的一份表**：读取端统一回落到 `LibraryBadge.leafUnits`。
  /// 两份同名表并存时，任一处只填其一时「设置页说可分发给下级、实际不分发」
  /// 这种两边都自洽的矛盾就会重新出现，所以这里只暴露同一份数据的视图。
  static Map<String, bool> get leaf => LibraryBadge.leafUnits;

  /// 单元库配色顺序（不含顶级 SECRET）：作者词条与基础库卡片共用。
  static final List<String> order = <String>[];

  /// 配色顺序的**唯一**入口：全局注册表优先，结构未加载时才用调用方的兜底。
  ///
  /// 此前 `main.dart` 两处各写一遍 `order.isNotEmpty ? order : 本地顺序`，
  /// 而设置页的「本地顺序」来自 `LibMeta.unitOrder`（只含带基础库的单元库），
  /// 与注册表的 `flattenUnits` 顺序并不同——同一单元库可能在设置页预览里
  /// 是一种自动色、在卡片上是另一种，两边都自洽却不同。
  static List<String> orderOr(List<String> fallback) =>
      order.isNotEmpty ? order : fallback;

  /// P1：单元库 id → 所属顶级单元库 id（顶级单元库＝媒体库根）。
  /// 只由结构关系算出，不看任何目录名文本；与 [leaf] 同样只是
  /// `LibraryBadge.topOfUnit` 的视图，不另存一份。
  static Map<String, String> get topOf => LibraryBadge.topOfUnit;

  static void setFrom(UnitLibrary root) {
    labels
      ..clear()
      ..addAll(unitLabelByBasic(root));
    keys
      ..clear()
      ..addAll(unitKeyByBasic(root));
    order
      ..clear()
      ..addAll([
        for (final u in flattenUnits(root))
          if (u.node.id != root.node.id) u.id,
      ]);
    // 词条继承/分发判定只有一处：LibraryBadge 的两张表。
    // 这里不再写第二份副本，`topOf` / `leaf` 都是它的视图。
    LibraryBadge.topOfUnit
      ..clear()
      ..addAll(topOfUnitIds(root));
    LibraryBadge.leafUnits
      ..clear()
      ..addAll(leafUnitIds(root));
  }

  static String labelFor(String basicId) => labels[basicId] ?? '';
}
