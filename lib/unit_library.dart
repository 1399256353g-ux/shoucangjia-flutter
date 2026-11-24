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
import 'lib_id.dart';
import 'library_badge.dart';
import 'library_tree.dart';
import 'lib_cover.dart';
import 'rel_path.dart';
import 'top_node.dart';

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
  int get works =>
      basics.fold(0, (n, b) => n + b.works) +
      children.fold(0, (n, c) => n + c.works);

  /// 整棵子树的作者数（基础库作者直接相加，不跨库去重）。
  int get authors =>
      basics.fold(0, (n, b) => n + b.authors) +
      children.fold(0, (n, c) => n + c.authors);

  /// 整棵子树的基础库数量。
  int get basicCount =>
      basics.length + children.fold(0, (n, c) => n + c.basicCount);

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

  // 1. 节点去重：同一 rel 只保留一个（多连接聚合时取最先出现者，保留其来源）。
  final byRel = <String, LibNode>{};
  for (final n in nodes) {
    final key = splitRel(n.rel).join('/');
    if (key.isEmpty) continue;
    byRel.putIfAbsent(key, () => n);
  }

  // 2. 从深到浅分配基础库：每个基础库只归最深命中的节点（收敛规则 1）。
  final ordered = byRel.values.toList()
    ..sort((a, b) => b.segments.length.compareTo(a.segments.length));

  final owned = <String, List<BasicLib>>{};
  final orphans = <BasicLib>[];
  for (final b in basics) {
    final segs = splitRel(b.rel);
    LibNode? hit;
    for (final n in ordered) {
      if (isPrefixOf(n.segments, segs) && n.segments.length < segs.length) {
        hit = n;
        break;
      }
      // 基础库目录本身与节点同路径时也算直属（基础库就是节点）。
      if (isPrefixOf(n.segments, segs) && n.segments.length == segs.length) {
        hit = n;
        break;
      }
    }
    if (hit == null) {
      orphans.add(b);
    } else {
      owned.putIfAbsent(splitRel(hit.rel).join('/'), () => []).add(b);
    }
  }

  // 3. 建立节点树（父子按前缀关系）。
  final childrenOf = <String, List<LibNode>>{};
  final sortedNodes = byRel.values.toList()
    ..sort((a, b) => a.segments.length.compareTo(b.segments.length));
  final present = <String, LibNode>{};
  for (final n in sortedNodes) {
    final key = n.segments.join('/');
    LibNode? parent;
    for (var i = n.segments.length - 1; i > 0; i--) {
      final pk = n.segments.take(i).join('/');
      final cand = present[pk];
      if (cand != null) {
        parent = cand;
        break;
      }
    }
    present[key] = n;
    if (parent != null) {
      childrenOf.putIfAbsent(parent.segments.join('/'), () => []).add(n);
    }
  }

  // 4. 递归装配，并按收敛规则 2 剪掉空子树。
  UnitLibrary? build(LibNode n, {int depth = 0}) {
    final key = n.segments.join('/');
    final kids = <UnitLibrary>[];
    for (final k in childrenOf[key] ?? const <LibNode>[]) {
      final sub = build(k, depth: depth + 1);
      if (sub != null) kids.add(sub);
    }
    final own = owned[key] ?? const <BasicLib>[];
    if (own.isEmpty && kids.isEmpty) return null;
    kids.sort((a, b) => a.name.compareTo(b.name));
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

  // 6. 没有归属的基础库 → 默认顶级单元库（收敛规则 3）。
  if (orphans.isNotEmpty) {
    rootUnits.add(UnitLibrary(
      node: LibNode(id: topId, rel: '', name: top),
      basics: orphans,
      children: const [],
    ));
  }
  if (rootUnits.isEmpty) return null;
  rootUnits.sort((a, b) => a.name.compareTo(b.name));

  // 首页要显示的是「媒体库」本身（顶级单元库），而不是库下的第一层目录。
  // 第一次序：按连接（serverId）归组，每个连接一个顶级单元库；
  // 没有 serverId 的树（单连接/离线）保持原样，把第一层目录视为下级。
  final byServer = <String, List<UnitLibrary>>{};
  final noServer = <UnitLibrary>[];
  for (final u in rootUnits) {
    final sid = u.node.serverId.trim();
    if (sid.isEmpty) {
      noServer.add(u);
    } else {
      _collectServerBasics(u, byServer.putIfAbsent(sid, () => <UnitLibrary>[]));
    }
  }

  List<UnitLibrary> mediaLibraries = <UnitLibrary>[];
  for (final e in byServer.entries) {
    final subs = e.value;
    if (subs.isEmpty) continue;
    final label = subs.first.node.serverLabel.trim();
    mediaLibraries.add(UnitLibrary(
      node: LibNode(
        id: 'media:${e.key}',
        rel: '',
        name: label.isEmpty ? top : label,
        serverId: e.key,
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
  mediaLibraries.sort((a, b) => a.name.compareTo(b.name));
  return UnitLibrary(
    node: LibNode(id: topId, rel: '', name: top),
    basics: const [],
    children: mediaLibraries,
  );
}

/// 把一个连接下的根单元库整理成「该媒体库的下级单元库」列表。
///
/// owner 2026-11-24：「媒体库下面的单元库都拆散开了，没有按照文件结构
/// 设置里的层级」。
///
/// 原实现把根节点和它的直接子节点**平铺**成同一层（`root.children` 逐个
/// 塞进 `out`），于是 `/api/nodes` 下发的三层结构（深度 1:5 / 2:24 / 3:2）
/// 在首页被压成一层，层级关系丢失。
///
/// 现在：
/// - 根节点自己挂了基础库（节点就是库根）→ 它本身作为下级，**连同其子树**；
/// - 根节点没挂基础库（纯容器）→ 它的 children 按原父子关系保留，不拆平。
void _collectServerBasics(UnitLibrary root, List<UnitLibrary> out) {
  if (root.basics.isNotEmpty) {
    // 节点就是库根：整个子树照原样保留，不能只取直接子节点。
    out.add(root);
    return;
  }
  // 纯容器节点：children 原样输出（各自带着自己的 children），层级不丢。
  for (final c in root.children) {
    out.add(c);
  }
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
        final at = segs.lastIndexWhere(
            (s) => s.toLowerCase() == 'secret');
        if (at >= 0 && at + 1 < segs.length) {
          rel = segs.skip(at + 1).join('/');
        }
      }
    }
    if (rel.isEmpty) return;
    final name = '${raw['name'] ?? ''}'.trim();
    out.add(LibNode(
      id: '${raw['id'] ?? rel}'.trim(),
      rel: rel,
      // 显示名以磁盘目录名为准；name 只在 rel 为空时兜底。
      name: diskNameOf(rel, name, where: 'nodesFromV2'),
      coverVersion: coverPointerOf(raw['cover']).version,
      coverExt: coverPointerOf(raw['cover']).ext,
      coverUrl: coverUrlOf(raw['cover']),
      serverId: '${raw['_serverId'] ?? ''}'.trim(),
      serverBase: '${raw['_serverBase'] ?? ''}'.trim(),
      serverLabel: '${raw['_serverLabel'] ?? ''}'.trim(),
    ));
  }

  // 手动模式（服务端 `nodesMode: manual`）：节点文件夹只认 owner 在「文件结构」
  // 里勾选的目录（/api/nodes）；空数组＝只有顶级 SECRET，绝不回退自动节点。
  final manual =
      '${json['nodesMode'] ?? ''}'.trim().toLowerCase() == 'manual';
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
      final rel = '${x['rel'] ?? ''}'.trim().replaceAll('\\', '/');
      if (rel.isEmpty) continue;
      add(x);
      used = true;
    }
    if (used) return out;
  }

  for (final x in (json['bigLibraries'] as List? ?? const [])) {
    add(x);
  }
  for (final x in (json['groups'] as List? ?? const [])) {
    add(x);
  }
  return out;
}

/// 计数显示：1234 → 1.2k，12345 → 1.2万。
String formatCount(int n) {
  if (n < 1000) return '$n';
  if (n < 10000) {
    final s = (n / 1000).toStringAsFixed(1);
    return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}k';
  }
  final s = (n / 10000).toStringAsFixed(1);
  return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}万';
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
      coverUrl: u.startsWith('/media/') ? u : '',
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
  static final Map<String, bool> leaf = <String, bool>{};
  /// 单元库配色顺序（不含顶级 SECRET）：作者词条与基础库卡片共用。
  static final List<String> order = <String>[];

  /// P1：单元库 id → 所属顶级单元库 id（顶级单元库＝媒体库根）。
  /// 只由结构关系算出，不看任何目录名文本。
  static final Map<String, String> topOf = <String, String>{};

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
    topOf
      ..clear()
      ..addAll(topOfUnitIds(root));
    leaf
      ..clear()
      ..addAll(leafUnitIds(root));
    // 词条继承表同步给 LibraryBadge，配色/分发判定只查这一处。
    LibraryBadge.topOfUnit
      ..clear()
      ..addAll(topOf);
    LibraryBadge.leafUnits
      ..clear()
      ..addAll(leaf);
  }

  static String labelFor(String basicId) => labels[basicId] ?? '';
}
