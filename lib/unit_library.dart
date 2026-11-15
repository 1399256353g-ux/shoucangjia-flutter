// L5「单元库」模型（纯函数，便于单测）。
//
// 术语（owner 设计）：
//  - 节点文件夹（含自身与下级全部结构）＝「单元库」
//  - SECRET 为固定顶级单元库；第一层目录即下级单元库（原「大库」）
//  - 单元库之下可以继续嵌套单元库（原「大库分组」），叶子仍是基础库
//  - 卡片层级：单元库卡片 > 基础库卡片 > 作品卡片（尺寸递减）
//
// 收敛规则（L5）：
//  1. 同一路径多节点取最下级，上级不重复认领（父节点只认领直属基础库）
//  2. 单元库（含整棵子树）内没有基础库 → 在选择页消失
//  3. 没有命中任何节点的下级基础库 → 归入默认顶级单元库（SECRET）
//
// 数据来源：/api/libraries.json v2 的 bigLibraries / groups（节点）与
// basicLibraries（基础库，带 rel 相对路径）。

import 'library_tree.dart';
import 'lib_cover.dart';

/// 一个节点文件夹（单元库候选）。
class LibNode {
  final String id;
  final String rel;
  final String name;
  /// L5-C：自定义封面版本（`_cover/<version>.<ext>`）；空串表示无自定义封面。
  final String coverVersion;
  final String coverExt;
  final String serverId;
  final String serverBase;
  final String serverLabel;

  const LibNode({
    required this.id,
    required this.rel,
    required this.name,
    this.coverVersion = '',
    this.coverExt = 'jpg',
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

  String get subtitle =>
      '${basicCount} 个基础库 · ${formatCount(works)} 作品 · ${formatCount(authors)} 作者';

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

/// 路径分段（统一分隔符，去掉空段与 `.`）。
List<String> splitRel(String rel) {
  final out = <String>[];
  for (final raw in rel.split(RegExp(r'[\\/]+'))) {
    final s = raw.trim();
    if (s.isEmpty || s == '.') continue;
    out.add(s);
  }
  return out;
}

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
/// [topName] 顶级单元库名称（默认 `SECRET`），顶级 id 为 [topId]。
/// 返回顶级单元库；没有基础库时返回 null（整棵树在选择页消失）。
UnitLibrary? buildUnitTree({
  required List<LibNode> nodes,
  required List<BasicLib> basics,
  String topId = 'secret',
  String topName = 'SECRET',
}) {
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

  // 5. 顶级节点＝第一层路径段（没有节点声明时用默认 SECRET）。
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
      node: LibNode(id: topId, rel: '', name: topName),
      basics: orphans,
      children: const [],
    ));
  }
  if (rootUnits.isEmpty) return null;
  rootUnits.sort((a, b) => a.name.compareTo(b.name));

  return UnitLibrary(
    node: LibNode(id: topId, rel: '', name: topName),
    basics: const [],
    children: rootUnits,
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
      name: name.isEmpty ? splitRel(rel).last : name,
      coverVersion: coverPointerOf(raw['cover']).version,
      coverExt: coverPointerOf(raw['cover']).ext,
      serverId: '${raw['_serverId'] ?? ''}'.trim(),
      serverBase: '${raw['_serverBase'] ?? ''}'.trim(),
      serverLabel: '${raw['_serverLabel'] ?? ''}'.trim(),
    ));
  }

  // J14：优先用服务端扫出的「通用分类节点」（任意层级上级目录）。
  final rawNodes = json['nodes'];
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
